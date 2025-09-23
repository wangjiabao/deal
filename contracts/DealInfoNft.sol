// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721}  from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20}  from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Base64}  from "@openzeppelin/contracts/utils/Base64.sol";

interface IFactoryLite {
    function dlToken() external view returns (address);
}
interface IDLBurnable is IERC20 { function burnFrom(address from, uint256 value) external; }

contract DealInfoNFT is ERC721, Ownable {
    /* ========== 基本配置 ========== */
    uint256 public nextId = 1;

    // 主 Factory（仅用于 mintByBurn 时查询 dlToken）；可由 Owner 切换
    address public factory;

    // 允许写入/锁的 Factory 白名单
    mapping(address => bool) public isFactory;

    // 多 Factory 事件
    event FactoryAdded(address indexed factory);
    event FactoryRemoved(address indexed factory);
    event PrimaryFactoryUpdated(address indexed factory);

    uint256 public mintPriceDL;

    /* ========== 地址枚举（可选） ========== */
    mapping(address => uint256[]) private _ownedTokens;
    mapping(uint256 => uint256)  private _ownedIndex1b;

    function tokensOfOwner(address owner) external view returns (uint256[] memory tokens) {
        return _ownedTokens[owner];
    }
    function tokensOfOwnerPaginated(address owner, uint256 offset, uint256 limit)
        external view returns (uint256[] memory tokens, uint256 total)
    {
        uint256[] storage arr = _ownedTokens[owner];
        total = arr.length;
        if (offset >= total) return (new uint256[](0), total);
        uint256 end = offset + limit; if (end > total) end = total;
        uint256 n = end - offset; tokens = new uint256[](n);
        for (uint256 i = 0; i < n; ++i) tokens[i] = arr[offset + i];
    }

    /* ========== 媒体（可选） ========== */
    struct Media { string uri; string mime; bytes data; }
    mapping(uint256 => Media) private _media;
    uint256 public maxImageDataBytes = 256*1024;
    event TokenImageURISet(uint256 indexed tokenId, string uri);
    event TokenImageDataSet(uint256 indexed tokenId, string mime, uint256 size);
    event MaxImageDataBytesUpdated(uint256 newLimit);

    /* ========== 访问控制 ========== */
    modifier onlyOwnerOrApproved(uint256 tokenId) {
        address owner = _ownerOf(tokenId);
        require(owner != address(0), "NONEXISTENT");
        require(
            msg.sender == owner ||
            getApproved(tokenId) == msg.sender ||
            isApprovedForAll(owner, msg.sender),
            "NOT_ALLOWED"
        );
        _;
    }

    modifier onlyFactoryAuth() {
        require(isFactory[msg.sender], "NOT_FACTORY");
        _;
    }

    /* ========== 构造 & 治理 ========== */
    constructor(address f, uint256 p) ERC721("Deal Info NFT", "DINFT") Ownable(msg.sender) {
        require(f != address(0), "ZERO_FACTORY");
        factory = f;                  // 作为主 Factory（仅供 mintByBurn 查询 dlToken）
        isFactory[f] = true;          // 主 Factory 默认授权
        emit FactoryAdded(f);
        mintPriceDL = p;
    }

    // 设置/切换主 Factory（必须先授权）
    function setFactory(address f) external onlyOwner {
        require(f != address(0), "ZERO_FACTORY");
        require(isFactory[f], "NEW_FACTORY_NOT_ADDED");
        factory = f;
        emit PrimaryFactoryUpdated(f);
    }

    // 新增/移除授权 Factory（并行授权以平滑迁移）
    function addFactory(address f) external onlyOwner {
        require(f != address(0), "ZERO_FACTORY");
        require(!isFactory[f], "ALREADY_ADDED");
        isFactory[f] = true;
        emit FactoryAdded(f);
    }
    function removeFactory(address f) external onlyOwner {
        require(isFactory[f], "NOT_ADDED");
        require(f != factory, "CANNOT_REMOVE_PRIMARY");
        isFactory[f] = false;
        emit FactoryRemoved(f);
    }

    function setMintPriceDL(uint256 p) external onlyOwner { mintPriceDL = p; }
    function setMaxImageDataBytes(uint256 newLimit) external onlyOwner {
        require(newLimit <= 256*1024, "LIMIT");
        maxImageDataBytes = newLimit;
        emit MaxImageDataBytesUpdated(newLimit);
    }

    /* ========== 媒体/昵称 ========== */
    function setTokenImageURI(uint256 tokenId, string calldata uri) external onlyOwnerOrApproved(tokenId) {
        require(_ownerOf(tokenId) != address(0), "NONEXISTENT");
        _media[tokenId].uri = uri; emit TokenImageURISet(tokenId, uri);
    }
    function setTokenImageData(uint256 tokenId, string calldata mime, bytes calldata data)
        external onlyOwnerOrApproved(tokenId)
    {
        require(_ownerOf(tokenId) != address(0), "NONEXISTENT");
        require(bytes(mime).length > 0 && data.length <= maxImageDataBytes, "BAD_MEDIA");
        _media[tokenId].mime = mime; _media[tokenId].data = data;
        emit TokenImageDataSet(tokenId, mime, data.length);
    }
    function imageOf(uint256 tokenId) public view returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "NONEXISTENT");
        Media storage m = _media[tokenId];
        if (bytes(m.uri).length != 0) return m.uri;
        if (m.data.length != 0) {
            return string(abi.encodePacked(
                "data:", bytes(m.mime).length != 0 ? m.mime : "application/octet-stream",
                ";base64,", Base64.encode(m.data)
            ));
        }
        string memory svg = string(
            abi.encodePacked(
                "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 350 350'>",
                "<rect fill='#121212' width='100%' height='100%'/>",
                "<text x='50%' y='50%' dominant-baseline='middle' text-anchor='middle' font-size='20' fill='#fff'>DINFT #",
                _toString(tokenId), "</text></svg>"
            )
        );
        return string(abi.encodePacked("data:image/svg+xml;base64,", Base64.encode(bytes(svg))));
    }

    mapping(uint256 => string) public username;
    event TokenUserNameSet(uint256 indexed tokenId, string username);
    function setTokenUserName(uint256 tokenId, string calldata _name) external onlyOwnerOrApproved(tokenId) {
        require(_ownerOf(tokenId) != address(0), "NONEXISTENT");
        username[tokenId] = _name; emit TokenUserNameSet(tokenId, _name);
    }

    /* ========== 统计与伙伴指针（Factory 代理写） ========== */
    mapping(uint256 => uint256) public totalDLMinted;
    event MintedAdded(uint256 indexed tokenId, uint256 amount);
    function totalMintedOf(uint256 tokenId) external view returns (uint256) { return totalDLMinted[tokenId]; }

    mapping(uint256 => uint256) private _maxPartner; // 0 表示自己
    event MaxPartnerUpdated(uint256 indexed tokenId, uint256 indexed newMaxPartner);

    function maxPartnerOf(uint256 tokenId) external view returns (uint256) {
        require(_ownerOf(tokenId) != address(0), "NONEXISTENT");
        uint256 p = _maxPartner[tokenId];
        return p == 0 ? tokenId : p;
    }

    function addMinted(uint256 tokenId, uint256 amount) external onlyFactoryAuth {
        totalDLMinted[tokenId] += amount;
        emit MintedAdded(tokenId, amount);
    }
    function setMaxPartnerOf(uint256 tokenId, uint256 partnerTokenId) external onlyFactoryAuth {
        require(_ownerOf(tokenId) != address(0) && _ownerOf(partnerTokenId) != address(0), "NONEXISTENT");
        _maxPartner[tokenId] = partnerTokenId;
        emit MaxPartnerUpdated(tokenId, partnerTokenId);
    }

    /* ========== 锁：支持多 Deal 并发 ========== */
    // tokenId 当前被多少个 Deal 同时占用
    mapping(uint256 => uint32) public lockCount;
    // 每个 Deal 对该 tokenId 的占用计数（通常为 1，防御性设计）
    mapping(uint256 => mapping(address => uint32)) public lockCountByDeal;

    event TokenLocked(uint256 indexed tokenId, address indexed deal, address indexed owner, uint256 totalLocks);
    event TokenUnlocked(uint256 indexed tokenId, address indexed deal, uint256 remainingLocks);

    /// 仅授权 Factory 代调用；Factory 内部会校验 msg.sender 为 Deal
    function lockByFactory(uint256 tokenId, address deal, address owner) external onlyFactoryAuth {
        require(_ownerOf(tokenId) == owner && owner != address(0), "NOT_OWNER");
        // 防溢出（uint32 最大 4,294,967,295）
        require(lockCount[tokenId] < type(uint32).max, "LOCK_OVERFLOW");
        lockCountByDeal[tokenId][deal] += 1;
        lockCount[tokenId] += 1;
        emit TokenLocked(tokenId, deal, owner, lockCount[tokenId]);
    }

    /// 仅授权 Factory 代调用；按 deal 维度解一把锁
    function unlockByFactory(uint256 tokenId, address deal) external onlyFactoryAuth {
        uint32 cnt = lockCountByDeal[tokenId][deal];
        require(cnt > 0 && lockCount[tokenId] >= cnt, "UNLOCK_BAD_STATE");
        lockCountByDeal[tokenId][deal] = cnt - 1;
        lockCount[tokenId] -= 1;
        emit TokenUnlocked(tokenId, deal, lockCount[tokenId]);
    }

    function isLocked(uint256 tokenId) external view returns (bool) { return lockCount[tokenId] > 0; }

    /* ========== 铸造：通过 DL 燃烧 ========== */
    function mintByBurn() external returns (uint256 tokenId) {
        require(factory != address(0), "NO_FACTORY");
        address dl = IFactoryLite(factory).dlToken();
        require(dl != address(0) && mintPriceDL > 0, "DL/PRICE");
        IDLBurnable(dl).burnFrom(msg.sender, mintPriceDL);

        tokenId = nextId++;
        _mint(msg.sender, tokenId);
        _maxPartner[tokenId] = tokenId; // 默认指向自己
    }

    /* ========== tokenURI ========== */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "NONEXISTENT");
        string memory image = imageOf(tokenId);
        bytes memory json = abi.encodePacked(
            '{',
                '"name":"Deal Info NFT #', _toString(tokenId), '",',
                '"description":"Deal Info NFT - partner & DL stats",',
                '"image":"', image, '",',
                '"attributes":[',
                    '{"trait_type":"Total DL Minted","value":"', _toString(totalDLMinted[tokenId]), '"},',
                    '{"trait_type":"Locked","value":"', lockCount[tokenId] > 0 ? "true" : "false", '"}',
                ']',
            '}'
        );
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(json)));
    }

    /* ========== 转移拦截 + 地址枚举维护 ========== */
    function _update(address to, uint256 tokenId, address auth) internal override returns (address from) {
        // 锁定期间禁止转移（也就禁止间接“销毁再铸造”的类 burn）
        if (lockCount[tokenId] > 0) revert("LOCKED");

        from = super._update(to, tokenId, auth);

        // 维护 from 的枚举
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
        // 维护 to 的枚举
        if (to != address(0)) {
            _ownedTokens[to].push(tokenId);
            _ownedIndex1b[tokenId] = _ownedTokens[to].length;
        }
    }

    /* ========== 辅助 ========== */
    function _toString(uint256 v) internal pure returns (string memory str) {
        if (v == 0) return "0";
        uint256 j = v; uint256 len;
        while (j != 0) { len++; j /= 10; }
        bytes memory b = new bytes(len);
        while (v != 0) { len -= 1; b[len] = bytes1(uint8(48 + v % 10)); v /= 10; }
        str = string(b);
    }
}
