// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721}  from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20}  from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Base64}  from "@openzeppelin/contracts/utils/Base64.sol";

/* ---------- 外部最小接口 ---------- */
interface IFactoryLite {
    function isDeal(address) external view returns (bool);
    function dlToken() external view returns (address);
}
interface IDLBurnable is IERC20 { function burnFrom(address from, uint256 value) external; }

contract DealInfoNFT is ERC721, Ownable {
    /* ============================================================
     * 基本配置
     * ============================================================ */
    uint256 public nextId = 1;
    address public factory;      // DealFactory
    uint256 public mintPriceDL;  // 燃烧多少 DL 才能铸造（以 DL 精度计）

    /* ============================================================
     * “仅按地址枚举”：owner => tokenId[]；tokenId => 1基索引
     * ============================================================ */
    mapping(address => uint256[]) private _ownedTokens;
    mapping(uint256 => uint256)  private _ownedIndex1b; // 0 表示不存在

    function tokensOfOwner(address owner) external view returns (uint256[] memory tokens) {
        return _ownedTokens[owner];
    }

    function tokensOfOwnerPaginated(address owner, uint256 offset, uint256 limit)
        external
        view
        returns (uint256[] memory tokens, uint256 total)
    {
        uint256[] storage arr = _ownedTokens[owner];
        total = arr.length;
        if (offset >= total) return (new uint256[](0), total);
        uint256 end = offset + limit; if (end > total) end = total;
        uint256 n = end - offset;
        tokens = new uint256[](n);
        for (uint256 i = 0; i < n; ++i) tokens[i] = arr[offset + i];
    }

    /* ============================================================
     * 头像图片（URL + 链上二进制）
     * ============================================================ */
    struct Media {
        string uri;       // 外链：ipfs:// 或 https://
        string mime;      // 链上二进制的 MIME（例："image/png"）
        bytes  data;      // 链上二进制（建议小图）；生成 data:URI 时 base64 编码
    }
    mapping(uint256 => Media) private _media;
    uint256 public maxImageDataBytes = 48 * 1024; // 默认 48KB，上链存图注意成本

    event TokenImageURISet(uint256 indexed tokenId, string uri);
    event TokenImageDataSet(uint256 indexed tokenId, string mime, uint256 size);
    event MaxImageDataBytesUpdated(uint256 newLimit);

    function setMaxImageDataBytes(uint256 newLimit) external onlyOwner {
        require(newLimit <= 256 * 1024, "too large"); // 安全兜底
        maxImageDataBytes = newLimit;
        emit MaxImageDataBytesUpdated(newLimit);
    }

    // ===== v5 修正：自定义授权判断（替代 _isApprovedOrOwner） =====
    modifier onlyOwnerOrApproved(uint256 tokenId) {
        address owner = _ownerOf(tokenId);
        require(owner != address(0), "NONEXISTENT");
        require(
            msg.sender == owner ||
            getApproved(tokenId) == msg.sender ||
            isApprovedForAll(owner, msg.sender),
            "NOT_AUTH"
        );
        _;
    }

    function setTokenImageURI(uint256 tokenId, string calldata uri) external onlyOwnerOrApproved(tokenId) {
        require(_ownerOf(tokenId) != address(0), "NONEXISTENT"); // v5: 替代 _exists
        _media[tokenId].uri = uri; // 留空可清除
        emit TokenImageURISet(tokenId, uri);
    }

    function setTokenImageData(uint256 tokenId, string calldata mime, bytes calldata data)
        external
        onlyOwnerOrApproved(tokenId)
    {
        require(_ownerOf(tokenId) != address(0), "NONEXISTENT"); // v5: 替代 _exists
        require(bytes(mime).length > 0, "mime=empty");
        require(data.length <= maxImageDataBytes, "image too large");
        _media[tokenId].mime = mime;
        _media[tokenId].data = data; // 置空 data 可清除
        emit TokenImageDataSet(tokenId, mime, data.length);
    }

    // 最终显示用的 image 字段（供前端便捷读取）
    function imageOf(uint256 tokenId) public view returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "NONEXISTENT"); // v5: 替代 _exists
        Media storage m = _media[tokenId];
        if (bytes(m.uri).length != 0) return m.uri;
        if (m.data.length != 0) {
            return string(
                abi.encodePacked(
                    "data:",
                    bytes(m.mime).length != 0 ? m.mime : "application/octet-stream",
                    ";base64,",
                    Base64.encode(m.data)
                )
            );
        }
        // 占位 SVG（内联 data:URI）
        string memory svg = string(
            abi.encodePacked(
                "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 350 350'>",
                "<rect fill='#121212' width='100%' height='100%'/>",
                "<text x='50%' y='50%' dominant-baseline='middle' text-anchor='middle' font-size='20' fill='#fff'>",
                "DINFT #", _toString(tokenId),
                "</text></svg>"
            )
        );
        return string(abi.encodePacked("data:image/svg+xml;base64,", Base64.encode(bytes(svg))));
    }

    /* ============================================================
     * 统计：该 tokenId 自身累计被“完成奖励”铸造的 DL 数
     * ============================================================ */
    mapping(uint256 => uint256) public totalDLMinted; // tokenId => sum
    event MintedAdded(uint256 indexed tokenId, uint256 amount);

    /* ============================================================
     * 伙伴集（最多 50）：O(1) 判重 + 最小值缓存
     * ============================================================ */
    uint256 public constant MAX_PARTNERS = 50;
    mapping(uint256 => uint256[]) private _partners;                    // tokenId => 伙伴列表
    mapping(uint256 => mapping(uint256 => uint8)) private _partnerIndex1b; // tokenId => (partnerId => 1基索引)
    struct MinCache { uint8 index1b; uint256 score; }                   // 最小值下界缓存
    mapping(uint256 => MinCache) private _minCache;

    event PartnerRecorded(uint256 indexed tokenId, uint256 indexed partnerTokenId);

    function partnersOf(uint256 tokenId) external view returns (uint256[] memory) { return _partners[tokenId]; }
    function totalMintedOf(uint256 tokenId) external view returns (uint256) { return totalDLMinted[tokenId]; }
    function minCacheOf(uint256 tokenId) external view returns (uint8 index1b, uint256 score) {
        MinCache memory mc = _minCache[tokenId]; return (mc.index1b, mc.score);
    }

    /* ============================================================
     * 管理与构造
     * ============================================================ */
    event FactoryUpdated(address factory);
    event MintPriceUpdated(uint256 newPrice);
    event Minted(address indexed to, uint256 indexed tokenId, uint256 burnDL);

    constructor() ERC721("Deal Info NFT", "DINFT") Ownable(msg.sender) {}

    function setFactory(address f) external onlyOwner { factory = f; emit FactoryUpdated(f); }
    function setMintPriceDL(uint256 p) external onlyOwner { mintPriceDL = p; emit MintPriceUpdated(p); }

    /* ============================================================
     * 铸造：按 DL 燃烧
     * ============================================================ */
    function mintByBurn() external returns (uint256 tokenId) {
        require(factory != address(0), "factory=0");
        address dl = IFactoryLite(factory).dlToken();
        require(dl != address(0) && mintPriceDL > 0, "cfg");
        // 用户需先对本合约 approve DL
        IDLBurnable(dl).burnFrom(msg.sender, mintPriceDL);

        tokenId = nextId++;
        _mint(msg.sender, tokenId);
        emit Minted(msg.sender, tokenId, mintPriceDL);
    }

    /* ============================================================
     * 仅 Deal 可写（由 Factory 认定）
     * ============================================================ */
    modifier onlyDeal() {
        require(factory != address(0) && IFactoryLite(factory).isDeal(msg.sender), "not deal");
        _;
    }

    function addMinted(uint256 tokenId, uint256 amount) external onlyDeal {
        totalDLMinted[tokenId] += amount;
        emit MintedAdded(tokenId, amount);
        // 不更新 _minCache（它只用作快速拒绝的下界）；当候选 > 缓存最小时，
        // recordPartner 会做一次精确遍历并刷新缓存为真实最小。
    }

    /**
     * 伙伴记录规则：
     * - 若 partnerTokenId 已存在：直接返回；
     * - 未满 50：直接追加；
     * - 已满 50：若 partner 的 totalDLMinted > 当前 50 个里的“最小值”，则替换之；否则忽略。
     */
    function recordPartner(uint256 tokenId, uint256 partnerTokenId) external onlyDeal {
        if (tokenId == partnerTokenId) return;
        if (_partnerIndex1b[tokenId][partnerTokenId] != 0) return; // O(1) 判重

        uint256[] storage arr = _partners[tokenId];
        uint256 len = arr.length;
        uint256 cand = totalDLMinted[partnerTokenId];

        // 未达上限：直接追加
        if (len < MAX_PARTNERS) {
            arr.push(partnerTokenId);
            _partnerIndex1b[tokenId][partnerTokenId] = uint8(len + 1);

            MinCache storage mc = _minCache[tokenId];
            if (len == 0 || mc.index1b == 0 || cand < mc.score) {
                mc.index1b = uint8(len + 1);
                mc.score   = cand;
            }
            emit PartnerRecorded(tokenId, partnerTokenId);
            return;
        }

        // 已满 50：先用缓存快速拒绝
        MinCache storage cache = _minCache[tokenId];
        uint8  minIdx1b;
        uint256 minScore;
        uint8  secondIdx1b;
        uint256 secondScore;

        if (cache.index1b == 0) {
            (minIdx1b, minScore, secondIdx1b, secondScore) = _minAndSecond(arr);
            cache.index1b = minIdx1b;
            cache.score   = minScore;
        }
        if (cand <= cache.score) return; // 不合格，O(1) 直接拒绝

        // 精确计算“最小 & 次小”
        (minIdx1b, minScore, secondIdx1b, secondScore) = _minAndSecond(arr);
        if (cand <= minScore) {
            cache.index1b = minIdx1b;
            cache.score   = minScore;
            return;
        }

        // 合格：替换最小
        uint256 replaceIndex0 = uint256(minIdx1b) - 1;
        uint256 oldPartner    = arr[replaceIndex0];
        arr[replaceIndex0] = partnerTokenId;
        _partnerIndex1b[tokenId][oldPartner]      = 0;
        _partnerIndex1b[tokenId][partnerTokenId]  = uint8(replaceIndex0 + 1);

        // 刷新真实最小：min(secondScore, cand)
        if (secondScore <= cand) {
            cache.index1b = secondIdx1b;
            cache.score   = secondScore;
        } else {
            cache.index1b = uint8(replaceIndex0 + 1);
            cache.score   = cand;
        }

        emit PartnerRecorded(tokenId, partnerTokenId);
    }

    /* ============================================================
     * 元数据：tokenURI（URI 优先；否则 data URI；再否则占位 SVG）
     * ============================================================ */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "NONEXISTENT"); // v5: 替代 _exists

        string memory image = imageOf(tokenId);

        bytes memory json = abi.encodePacked(
            '{',
                '"name":"Deal Info NFT #', _toString(tokenId), '",',
                '"description":"Deal Info NFT - partner & DL stats",',
                '"image":"', image, '",',
                '"attributes":[',
                    '{"trait_type":"Total DL Minted","value":"', _toString(totalDLMinted[tokenId]), '"}',
                ']',
            '}'
        );
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(json)));
    }

    /* ============================================================
     * 内部：一次遍历找“最小 & 次小”
     * ============================================================ */
    function _minAndSecond(uint256[] storage arr)
        internal view
        returns (uint8 minIdx1b, uint256 minScore, uint8 secondIdx1b, uint256 secondScore)
    {
        uint256 len = arr.length; // 调用处保证 len >= 1
        uint256 m1 = type(uint256).max;
        uint256 m2 = type(uint256).max;
        uint256 i1 = 0;
        uint256 i2 = 0;

        unchecked {
            for (uint256 i = 0; i < len; ++i) {
                uint256 pid = arr[i];
                uint256 s = totalDLMinted[pid];
                if (s < m1) {
                    m2 = m1; i2 = i1;
                    m1 = s;  i1 = i + 1; // 1 基
                } else if (s < m2) {
                    m2 = s;  i2 = i + 1;
                }
            }
        }
        return (uint8(i1), m1, uint8(i2), m2);
    }

    /* ============================================================
     * 覆写 _update：维护“仅按地址枚举”的索引
     * ============================================================ */
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address from)
    {
        from = super._update(to, tokenId, auth);

        // 从旧 owner 的列表移除
        if (from != address(0)) {
            uint256 idx1b = _ownedIndex1b[tokenId];
            if (idx1b != 0) {
                uint256 idx = idx1b - 1;
                uint256[] storage arrFrom = _ownedTokens[from];
                uint256 last = arrFrom.length - 1;
                if (idx != last) {
                    uint256 lastId = arrFrom[last];
                    arrFrom[idx] = lastId;
                    _ownedIndex1b[lastId] = idx + 1;
                }
                arrFrom.pop();
                delete _ownedIndex1b[tokenId];
            }
        }

        // 加入新 owner 的列表
        if (to != address(0)) {
            uint256[] storage arrTo = _ownedTokens[to];
            arrTo.push(tokenId);
            _ownedIndex1b[tokenId] = arrTo.length; // 1 基
        }
    }

    /* ============================================================
     * 辅助：uint256 -> string（轻量）
     * ============================================================ */
    function _toString(uint256 v) internal pure returns (string memory str) {
        if (v == 0) return "0";
        uint256 j = v; uint256 len;
        while (j != 0) { len++; j /= 10; }
        bytes memory b = new bytes(len);
        while (v != 0) { len -= 1; b[len] = bytes1(uint8(48 + v % 10)); v /= 10; }
        str = string(b);
    }
}
