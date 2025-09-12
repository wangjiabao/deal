
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFactoryLite {
    function isDeal(address) external view returns (bool);
    function dlToken() external view returns (address);
}
interface IDLBurnable is IERC20 { function burnFrom(address from, uint256 value) external; }

contract DealInfoNFT is ERC721, Ownable {
    uint256 public nextId = 1;
    address public factory;      // DealFactory
    uint256 public mintPriceDL;  // 燃烧多少 DL 才能铸造

    mapping(uint256 => uint256) public totalDLMinted; // tokenId => sum

    uint256 public constant MAX_PARTNERS = 50;
    mapping(uint256 => uint256[]) private _partners;  // tokenId => list（去重，尾部为最新）

    event FactoryUpdated(address factory);
    event MintPriceUpdated(uint256 newPrice);
    event Minted(address indexed to, uint256 indexed tokenId, uint256 burnDL);
    event MintedAdded(uint256 indexed tokenId, uint256 amount);
    event PartnerRecorded(uint256 indexed tokenId, uint256 indexed partnerTokenId);

    constructor() ERC721("Deal Info NFT", "DINFT") Ownable(msg.sender) {}

    /* ------------ Admin ------------ */
    function setFactory(address f) external onlyOwner { factory = f; emit FactoryUpdated(f); }
    function setMintPriceDL(uint256 p) external onlyOwner { mintPriceDL = p; emit MintPriceUpdated(p); }

    /* ------------ Mint by burning DL ------------ */
    function mintByBurn() external returns (uint256 tokenId) {
        require(factory != address(0), "factory=0");
        address dl = IFactoryLite(factory).dlToken();
        require(dl != address(0) && mintPriceDL > 0, "cfg");
        IDLBurnable(dl).burnFrom(msg.sender, mintPriceDL); // 用户需先 approve 给本合约
        tokenId = nextId++;
        _mint(msg.sender, tokenId);
        emit Minted(msg.sender, tokenId, mintPriceDL);
    }

    /* ------------ 仅 Deal 可写 ------------ */
    modifier onlyDeal() {
        require(factory != address(0) && IFactoryLite(factory).isDeal(msg.sender), "not deal");
        _;
    }

    function addMinted(uint256 tokenId, uint256 amount) external onlyDeal {
        totalDLMinted[tokenId] += amount;
        emit MintedAdded(tokenId, amount);
    }

    function recordPartner(uint256 tokenId, uint256 partnerTokenId) external onlyDeal {
        if (tokenId == partnerTokenId) return;
        uint256[] storage arr = _partners[tokenId];
        uint256 len = arr.length;

        // 空数组：直接插入
        if (len == 0) {
            arr.push(partnerTokenId);
            emit PartnerRecorded(tokenId, partnerTokenId);
            return;
        }

        // 单次循环：去重 + 找最小值
        uint256 minIndex = 0;
        uint256 minVal = totalDLMinted[arr[0]];
        for (uint256 i = 0; i < len; i++) {
            uint256 v = arr[i];
            if (v == partnerTokenId) {
                return; // 已存在，直接返回
            }
            if (totalDLMinted[v] < minVal) {
                minVal = v;
                minIndex = i;
            }
        }

        // 容量未满：直接加入
        if (len < MAX_PARTNERS) {
            arr.push(partnerTokenId);
            emit PartnerRecorded(tokenId, partnerTokenId);
            return;
        }

        // 容量已满：若当前最小值仍然 > 新值，则忽略；否则替换最小
        if (minVal > totalDLMinted[partnerTokenId]) {
            return;
        }

        arr[minIndex] = partnerTokenId;
        emit PartnerRecorded(tokenId, partnerTokenId);
    }

    /* ------------ 只读 ------------ */
    function partnersOf(uint256 tokenId) external view returns (uint256[] memory) { return _partners[tokenId]; }
    function totalMintedOf(uint256 tokenId) external view returns (uint256) { return totalDLMinted[tokenId]; }
}
