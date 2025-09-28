// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @dev 可选：若 dl 原生支持 burn(uint256)，这里会优先调用
interface IBurnable {
    function burn(uint256 amount) external;
}

/// @title DividendDistributor
/// @notice 按“轮”分红的分发合约：
///  - 管理者先把 dl 充值到本合约，再创建分红轮（总额 & 截止）
///  - 持 D 的地址在截止前 stake(D) 即时领取按比例的 dl，D 锁定到截止后
///  - 截止后可解押 D；任何人可 finalize 燃烧未领取的 dl
contract DividendDistributor is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable d;          // 股东代币 D（质押代币）
    IERC20 public immutable dl;         // 分红代币 DL（被分发/燃烧）
    IERC20Permit public immutable dPermit; // 用于 stakeWithPermit

    uint256 public constant MAX_DURATION = 20 days;

    /// @dev 已为各轮“预留但尚未发放/燃烧”的 dl 总额
    uint256 public reservedUnclaimed;

    struct Round {
        uint256 total;       // 本轮待分 dl 总额（已在创建时预留）
        uint256 claimed;     // 已发放的 dl
        uint64  deadline;    // 领取/质押截止时间（秒）
        bool    finalized;   // 是否已燃烧剩余
    }
    Round[] public rounds;

    /// @dev 每轮每地址的 D 质押量（用于截止后解押）
    mapping(uint256 => mapping(address => uint256)) public staked;

    event RoundCreated(uint256 indexed roundId, uint256 total, uint64 deadline);
    event Staked(uint256 indexed roundId, address indexed account, uint256 amountD, uint256 payoutDL);
    event Unstaked(uint256 indexed roundId, address indexed account, uint256 amountD);
    event Finalized(uint256 indexed roundId, uint256 burnedLeftover);

    constructor(address dToken, address dlToken, address initialOwner) Ownable(initialOwner) {
        require(dToken != address(0) && dlToken != address(0), "zero addr");
        d = IERC20(dToken);
        dl = IERC20(dlToken);
        dPermit = IERC20Permit(dToken);
    }

    // ------------------------ 管理者接口 ------------------------

    /// @notice 创建一轮分红（需提前把 dl 充到本合约）
    /// @param total    本轮要分的 dl 总额（将被预留）
    /// @param deadline 领取截止时间（block.timestamp 之后，<= 20 天）
    function createRound(uint256 total, uint64 deadline) external onlyOwner {
        require(total > 0, "total=0");
        require(deadline > block.timestamp, "deadline past");
        require(deadline <= block.timestamp + MAX_DURATION, "deadline>20d");

        // 不允许与上轮重叠（避免跨轮逻辑混淆）
        if (rounds.length > 0) {
            Round storage last = rounds[rounds.length - 1];
            require(block.timestamp >= last.deadline, "prev round active");
        }

        // 要求本合约当前“未预留”的 dl 余额足够
        require(availableDL() >= total, "insufficient dl funded");

        rounds.push(Round({
            total: total,
            claimed: 0,
            deadline: deadline,
            finalized: false
        }));
        reservedUnclaimed += total;

        emit RoundCreated(rounds.length - 1, total, deadline);
    }

    // ------------------------ 用户接口 ------------------------

    /// @notice 截止前质押 D 即时领取 dl
    function stake(uint256 roundId, uint256 amountD) public nonReentrant {
        require(amountD > 0, "amountD=0");
        Round storage r = rounds[roundId];
        require(block.timestamp < r.deadline, "round ended");

        // payout = amountD / D.totalSupply * r.total （向下取整）
        uint256 supply = IERC20(address(d)).totalSupply();
        require(supply > 0, "D supply=0");
        uint256 payout = Math.mulDiv(amountD, r.total, supply);
        require(payout > 0, "payout=0");

        // 先改状态（checks-effects），再外部调用
        r.claimed += payout;
        require(r.claimed <= r.total, "overclaim");
        reservedUnclaimed -= payout;
        staked[roundId][msg.sender] += amountD;

        d.safeTransferFrom(msg.sender, address(this), amountD);
        dl.safeTransfer(msg.sender, payout);

        emit Staked(roundId, msg.sender, amountD, payout);
    }

    /// @notice 带 permit 的便捷质押；permit 失败将自动忽略（遵循 OZ 推荐模式）
    function stakeWithPermit(
        uint256 roundId,
        uint256 amountD,
        uint256 permitDeadline,
        uint8 v, bytes32 r, bytes32 s
    ) external {
        // 容忍被抢跑或智能钱包不支持 permit 的情况
        try dPermit.permit(msg.sender, address(this), amountD, permitDeadline, v, r, s) { } catch { }
        stake(roundId, amountD);
    }

    /// @notice 截止后可对该轮解押自己质押的 D
    function unstake(uint256 roundId) external nonReentrant {
        Round storage r = rounds[roundId];
        require(block.timestamp >= r.deadline, "not ended");
        uint256 amt = staked[roundId][msg.sender];
        require(amt > 0, "nothing staked");
        staked[roundId][msg.sender] = 0;
        d.safeTransfer(msg.sender, amt);
        emit Unstaked(roundId, msg.sender, amt);
    }

    /// @notice 截止后任何人可调用：燃烧本轮剩余 dl（或转黑洞地址）
    function finalize(uint256 roundId) external nonReentrant {
        Round storage r = rounds[roundId];
        require(block.timestamp >= r.deadline, "not ended");
        require(!r.finalized, "finalized");
        r.finalized = true;

        uint256 leftover = r.total - r.claimed;
        if (leftover > 0) {
            // 先更新预留，再外部调用
            reservedUnclaimed -= leftover;

            // 优先尝试原生 burn；失败则转到 0x...dead（不会减少总供给）
            try IBurnable(address(dl)).burn(leftover) {
                // burned
            } catch {
                dl.safeTransfer(0x000000000000000000000000000000000000dEaD, leftover);
                // 注意：转到黑洞并不会减少 totalSupply（仅资金不可用）。:contentReference[oaicite:2]{index=2}
            }
        }
        emit Finalized(roundId, leftover);
    }

    // ------------------------ 只读/辅助 ------------------------

    function roundsCount() external view returns (uint256) { return rounds.length; }

    function getRound(uint256 roundId) external view returns (Round memory) { return rounds[roundId]; }

    /// @notice 当前未被“预留”的 dl 可用余额
    function availableDL() public view returns (uint256) {
        return dl.balanceOf(address(this)) - reservedUnclaimed;
    }

    /// @notice 报价：若此刻在 roundId 质押 amountD，将领取多少 dl（只读）
    function quotePayout(uint256 roundId, uint256 amountD) external view returns (uint256) {
        Round storage r = rounds[roundId];
        if (block.timestamp >= r.deadline) return 0;
        uint256 supply = IERC20(address(d)).totalSupply();
        if (supply == 0) return 0;
        return Math.mulDiv(amountD, r.total, supply);
    }
}
