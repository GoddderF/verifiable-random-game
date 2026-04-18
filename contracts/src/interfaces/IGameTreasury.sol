// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IGameTreasury
/// @notice Central custody and payout interface for authorized game contracts.
interface IGameTreasury {
    event GameAuthorized(address indexed game, bool authorized);
    event TokenSupported(address indexed token, bool supported);
    event BetLimitsUpdated(address indexed token, uint256 minBet, uint256 maxBet);
    event BetReceived(address indexed game, address indexed player, address indexed token, uint256 amount);
    event PayoutSent(address indexed game, address indexed winner, address indexed token, uint256 netAmount, uint256 feeAmount);

    error UnauthorizedGame(address caller);
    error UnsupportedToken(address token);
    error BetBelowMinimum(uint256 amount, uint256 minBet);
    error BetAboveMaximum(uint256 amount, uint256 maxBet);
    error InsufficientPoolBalance(address token, uint256 required, uint256 available);
    error TransferFailed();

    function houseEdgeBps() external view returns (uint256);

    function getPoolBalance(address token) external view returns (uint256);

    function getBetLimits(address token) external view returns (uint256 minBet, uint256 maxBet);

    function isGameAuthorized(address game) external view returns (bool);

    function isTokenSupported(address token) external view returns (bool);

    /// @param token Use address(0) for native ETH.
    function depositBet(address player, address token, uint256 amount) external payable;

    /// @param token Use address(0) for native ETH.
    function payoutWinner(address winner, address token, uint256 grossAmount) external;
}
