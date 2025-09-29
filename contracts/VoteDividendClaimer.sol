// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol"; // 引入时钟接口

contract VoteDividendClaimer is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// 投票资产（你的 D：ERC20Votes 或任意 IVotes）
    IVotes  public immutable votesToken;
    /// EIP-6372 时钟（与 votesToken 为同一地址）
    IERC6372 public immutable votesClock;
    /// 分红资产
    IERC20  public immutable dlc;
    /// 只有该地址可开轮（建议设为 Timelock）
    address public executor;

    struct Round {
        uint48  snapshot;   // 快照 timepoint（与代币时钟一致：区块号或时间戳）
        uint256 total;      // 本轮 dlc 总额
        uint256 claimed;    // 全部地址累计已领取
    }
    Round[] public rounds;

    /// 防重复领取：roundId => account => claimed?
    mapping(uint256 => mapping(address => bool)) public claimed;

    // --------- events ---------
    event ExecutorUpdated(address indexed oldExec, address indexed newExec);
    event RoundCreated(uint256 indexed roundId, uint48 snapshot, uint256 total);
    event Claimed(uint256 indexed roundId, address indexed account, uint256 votes, uint256 payout);

    modifier onlyExecutor() {
        require(msg.sender == executor, "NOT_EXECUTOR");
        _;
    }

    constructor(address _votesToken, address _dlc, address _executor) {
        require(_votesToken != address(0) && _dlc != address(0) && _executor != address(0), "ZERO_ADDR");
        votesToken = IVotes(_votesToken);
        votesClock = IERC6372(_votesToken); // 同地址作为时钟
        dlc = IERC20(_dlc);
        executor = _executor;
        emit ExecutorUpdated(address(0), _executor);
    }

    /// 治理迁移时更新执行者
    function setExecutor(address newExec) external onlyExecutor {
        require(newExec != address(0), "ZERO_ADDR");
        emit ExecutorUpdated(executor, newExec);
        executor = newExec;
    }

    /// DAO：开新一轮（记录“过去”的快照，避免与本交易同一 timepoint）
    function createRound(uint256 total) external onlyExecutor {
        require(total > 0, "total=0");

        uint48 current = votesClock.clock();
        uint48 snapshot = current == 0 ? 0 : current - 1; // 关键：取过去的快照

        rounds.push(Round({ snapshot: snapshot, total: total, claimed: 0 }));
        emit RoundCreated(rounds.length - 1, snapshot, total);
    }

    /// 用户：按快照票权领取（每地址一次）
    function claim(uint256 roundId) external nonReentrant {
        Round storage r = rounds[roundId];
        require(!claimed[roundId][msg.sender], "already claimed");
        require(r.snapshot < votesClock.clock(), "round not active yet"); // 快照必须在过去

        // 分子：快照票权（未委托==0）
        uint256 votes = votesToken.getPastVotes(msg.sender, r.snapshot);
        require(votes > 0, "no votes at snapshot");

        // 分母：快照总投票单位（= 全局 supply 的快照）
        uint256 totalSupplyAt = votesToken.getPastTotalSupply(r.snapshot);
        require(totalSupplyAt > 0, "totalSupply=0");

        // 向下取整
        uint256 payout = Math.mulDiv(votes, r.total, totalSupplyAt);
        require(payout > 0, "payout=0");

        // 防双花 & 不变量护栏
        claimed[roundId][msg.sender] = true;
        r.claimed += payout;
        require(r.claimed <= r.total, "over-claimed");

        dlc.safeTransfer(msg.sender, payout);
        emit Claimed(roundId, msg.sender, votes, payout);
    }

    // --------- 只读 ---------
    function roundsCount() external view returns (uint256) { return rounds.length; }
    function getRound(uint256 roundId) external view returns (Round memory) { return rounds[roundId]; }

    function previewClaim(uint256 roundId, address account)
        external view returns (uint256 votes, uint256 payout)
    {
        Round storage r = rounds[roundId];
        if (r.snapshot >= votesClock.clock()) return (0, 0); // 这轮尚未生效
        votes = votesToken.getPastVotes(account, r.snapshot);
        if (votes == 0) return (0, 0);
        uint256 totalSupplyAt = votesToken.getPastTotalSupply(r.snapshot);
        if (totalSupplyAt == 0) return (votes, 0);
        payout = Math.mulDiv(votes, r.total, totalSupplyAt);
    }
}
