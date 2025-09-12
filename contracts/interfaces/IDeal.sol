// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IDeal {
    struct InitParams {
        // 四个数字
        address aSwapToken;   uint256 aSwapAmount;
        address aMarginToken; uint256 aMarginAmount;
        address bSwapToken;   uint256 bSwapAmount;
        address bMarginToken; uint256 bMarginAmount;

        // 进入模式
        uint8   joinMode;     // 0=Open,1=ExactAddress,2=NftGated
        address expectedB;

        // NFT 门禁（NftGated 用）
        address gateNft;      uint256 gateNftId;

        // A 可选 NFT（若非零：本次 A 要质押）
        address aNft;         uint256 aNftId;

        // 基础信息
        string  title;
        uint64  timeoutSeconds;  // 工厂已保证 ≥ 最小值
        string  memo;
    }

    function initialize(
        address factory,
        address initiator,
        address liquidityHook,
        InitParams calldata p
    ) external;
}
