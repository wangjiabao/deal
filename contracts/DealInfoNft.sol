// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721}  from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20}  from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Base64}  from "@openzeppelin/contracts/utils/Base64.sol";

interface IFactoryLite {
    function isDeal(address) external view returns (bool);
    function dlToken() external view returns (address);
}
interface IDLBurnable is IERC20 { function burnFrom(address from, uint256 value) external; }

contract DealInfoNFT is ERC721, Ownable {
    uint256 public nextId = 1;
    address public factory;
    uint256 public mintPriceDL;

    // 按地址枚举
    mapping(address => uint256[]) private _ownedTokens;
    mapping(uint256 => uint256)  private _ownedIndex1b;

    function tokensOfOwner(address owner) external view returns (uint256[] memory tokens) { return _ownedTokens[owner]; }
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

    // 媒体（可选）
    struct Media { string uri; string mime; bytes data; }
    mapping(uint256 => Media) private _media;
    uint256 public maxImageDataBytes = 256*1024;
    event TokenImageURISet(uint256 indexed tokenId, string uri);
    event TokenImageDataSet(uint256 indexed tokenId, string mime, uint256 size);
    event MaxImageDataBytesUpdated(uint256 newLimit);

    modifier onlyOwnerOrApproved(uint256 tokenId) {
        address owner = _ownerOf(tokenId);
        require(owner != address(0));
        require(msg.sender == owner || getApproved(tokenId) == msg.sender || isApprovedForAll(owner, msg.sender));
        _;
    }

    constructor() ERC721("Deal Info NFT", "DINFT") Ownable(msg.sender) {}

    function setFactory(address f) external onlyOwner { factory = f; }
    function setMintPriceDL(uint256 p) external onlyOwner { mintPriceDL = p; }
    function setMaxImageDataBytes(uint256 newLimit) external onlyOwner { require(newLimit <= 256*1024); maxImageDataBytes=newLimit; emit MaxImageDataBytesUpdated(newLimit); }

    function setTokenImageURI(uint256 tokenId, string calldata uri) external onlyOwnerOrApproved(tokenId) {
        require(_ownerOf(tokenId) != address(0));
        _media[tokenId].uri = uri; emit TokenImageURISet(tokenId, uri);
    }
    function setTokenImageData(uint256 tokenId, string calldata mime, bytes calldata data)
        external onlyOwnerOrApproved(tokenId)
    {
        require(_ownerOf(tokenId) != address(0));
        require(bytes(mime).length > 0 && data.length <= maxImageDataBytes);
        _media[tokenId].mime = mime; _media[tokenId].data = data;
        emit TokenImageDataSet(tokenId, mime, data.length);
    }
    function imageOf(uint256 tokenId) public view returns (string memory) {
        require(_ownerOf(tokenId) != address(0));
        Media storage m = _media[tokenId];
        if (bytes(m.uri).length != 0) return m.uri;
        if (m.data.length != 0) {
            return string(abi.encodePacked("data:", bytes(m.mime).length != 0 ? m.mime : "application/octet-stream", ";base64,", Base64.encode(m.data)));
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
        require(_ownerOf(tokenId) != address(0));
        username[tokenId] = _name; emit TokenUserNameSet(tokenId, _name);
    }

    // 统计累计
    mapping(uint256 => uint256) public totalDLMinted;
    event MintedAdded(uint256 indexed tokenId, uint256 amount);
    function totalMintedOf(uint256 tokenId) external view returns (uint256) {
        return totalDLMinted[tokenId];
    }

    // 单一“最大伙伴”指针（默认指向自己）
    mapping(uint256 => uint256) private _maxPartner;
    event MaxPartnerUpdated(uint256 indexed tokenId, uint256 indexed newMaxPartner);

    function maxPartnerOf(uint256 tokenId) external view returns (uint256) {
        require(_ownerOf(tokenId) != address(0));
        uint256 p = _maxPartner[tokenId]; return p == 0 ? tokenId : p;
    }

    function mintByBurn() external returns (uint256 tokenId) {
        require(factory != address(0));
        address dl = IFactoryLite(factory).dlToken();
        require(dl != address(0) && mintPriceDL > 0);
        IDLBurnable(dl).burnFrom(msg.sender, mintPriceDL);

        tokenId = nextId++; _mint(msg.sender, tokenId);
        _maxPartner[tokenId] = tokenId; // 默认自己
    }

    /* ---------- 仅 Deal 可写 ---------- */
    modifier onlyDeal() { require(factory != address(0) && IFactoryLite(factory).isDeal(msg.sender)); _; }

    function addMinted(uint256 tokenId, uint256 amount) external onlyDeal { totalDLMinted[tokenId] += amount; emit MintedAdded(tokenId, amount); }

    function setMaxPartnerOf(uint256 tokenId, uint256 partnerTokenId) external onlyDeal {
        require(_ownerOf(tokenId) != address(0) && _ownerOf(partnerTokenId) != address(0));
        _maxPartner[tokenId] = partnerTokenId; emit MaxPartnerUpdated(tokenId, partnerTokenId);
    }

    /* ---------- tokenURI ---------- */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0));
        string memory image = imageOf(tokenId);
        bytes memory json = abi.encodePacked(
            '{',
                '"name":"Deal Info NFT #', _toString(tokenId), '",',
                '"description":"Deal Info NFT - partner & DL stats",',
                '"image":"', image, '",',
                '"attributes":[{"trait_type":"Total DL Minted","value":"', _toString(totalDLMinted[tokenId]), '"}]',
            '}'
        );
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(json)));
    }

    /* ---------- 仅按地址枚举维护 ---------- */
    function _update(address to, uint256 tokenId, address auth) internal override returns (address from) {
        from = super._update(to, tokenId, auth);
        if (from != address(0)) {
            uint256 idx1b = _ownedIndex1b[tokenId];
            if (idx1b != 0) {
                uint256 idx = idx1b - 1;
                uint256[] storage arrFrom = _ownedTokens[from];
                uint256 last = arrFrom.length - 1;
                if (idx != last) { uint256 lastId = arrFrom[last]; arrFrom[idx] = lastId; _ownedIndex1b[lastId] = idx + 1; }
                arrFrom.pop(); delete _ownedIndex1b[tokenId];
            }
        }
        if (to != address(0)) { _ownedTokens[to].push(tokenId); _ownedIndex1b[tokenId] = _ownedTokens[to].length; }
    }

    /* ---------- 辅助 ---------- */
    function _toString(uint256 v) internal pure returns (string memory str) {
        if (v == 0) return "0";
        uint256 j=v; uint256 len; while (j!=0){len++; j/=10;}
        bytes memory b=new bytes(len); while (v!=0){len-=1; b[len]=bytes1(uint8(48+v%10)); v/=10;} str=string(b);
    }
}
