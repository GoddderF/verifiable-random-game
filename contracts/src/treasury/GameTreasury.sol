// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IGameTreasury} from "../interfaces/IGameTreasury.sol";

/// @title GameTreasury
/// @notice Central pool for game bets and atomic winner payouts with configurable house edge.
contract GameTreasury is IGameTreasury, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public constant NATIVE_TOKEN = address(0);

    uint256 public houseEdgeBps;
    uint256 public constant MAX_HOUSE_EDGE_BPS = 500; // 5% cap

    mapping(address game => bool authorized) private _authorizedGames;
    mapping(address token => bool supported) private _supportedTokens;
    mapping(address token => uint256 balance) private _poolBalances;
    mapping(address token => uint256 minBet) private _minBets;
    mapping(address token => uint256 maxBet) private _maxBets;

    constructor(address initialOwner, uint256 initialHouseEdgeBps) Ownable(initialOwner) {
        if (initialHouseEdgeBps > MAX_HOUSE_EDGE_BPS) revert BetAboveMaximum(initialHouseEdgeBps, MAX_HOUSE_EDGE_BPS);
        houseEdgeBps = initialHouseEdgeBps;
        _supportedTokens[NATIVE_TOKEN] = true;
        _minBets[NATIVE_TOKEN] = 0.001 ether;
        _maxBets[NATIVE_TOKEN] = 10 ether;
    }

    modifier onlyAuthorizedGame() {
        if (!_authorizedGames[msg.sender]) revert UnauthorizedGame(msg.sender);
        _;
    }

    // --- Admin ---

    function setHouseEdgeBps(uint256 newBps) external onlyOwner {
        if (newBps > MAX_HOUSE_EDGE_BPS) revert BetAboveMaximum(newBps, MAX_HOUSE_EDGE_BPS);
        houseEdgeBps = newBps;
    }

    function setGameAuthorized(address game, bool authorized) external onlyOwner {
        _authorizedGames[game] = authorized;
        emit GameAuthorized(game, authorized);
    }

    function setTokenSupported(address token, bool supported) external onlyOwner {
        _supportedTokens[token] = supported;
        emit TokenSupported(token, supported);
    }

    function setBetLimits(address token, uint256 minBet_, uint256 maxBet_) external onlyOwner {
        if (minBet_ > maxBet_) revert BetBelowMinimum(maxBet_, minBet_);
        _minBets[token] = minBet_;
        _maxBets[token] = maxBet_;
        emit BetLimitsUpdated(token, minBet_, maxBet_);
    }

    function withdrawFees(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        _transferOut(token, to, amount);
        _poolBalances[token] -= amount;
    }

    // --- Views ---

    function getPoolBalance(address token) external view returns (uint256) {
        return _poolBalances[token];
    }

    function getBetLimits(address token) external view returns (uint256, uint256) {
        return (_minBets[token], _maxBets[token]);
    }

    function isGameAuthorized(address game) external view returns (bool) {
        return _authorizedGames[game];
    }

    function isTokenSupported(address token) external view returns (bool) {
        return _supportedTokens[token];
    }

    // --- Game-facing (CEI: checks → effects → interactions) ---

    /// @inheritdoc IGameTreasury
    function depositBet(address player, address token, uint256 amount)
        external
        payable
        onlyAuthorizedGame
        nonReentrant
    {
        if (!_supportedTokens[token]) revert UnsupportedToken(token);

        uint256 received;
        if (token == NATIVE_TOKEN) {
            received = msg.value;
            if (amount != 0 && received != amount) revert BetBelowMinimum(received, amount);
        } else {
            if (msg.value != 0) revert UnsupportedToken(NATIVE_TOKEN);
            received = amount;
            // Pull from the authorized game contract (funds must be held or approved by the game).
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        _enforceBetLimits(token, received);
        _poolBalances[token] += received;
        emit BetReceived(msg.sender, player, token, received);
    }

    /// @inheritdoc IGameTreasury
    function payoutWinner(address winner, address token, uint256 grossAmount)
        external
        onlyAuthorizedGame
        nonReentrant
    {
        if (!_supportedTokens[token]) revert UnsupportedToken(token);
        if (grossAmount == 0) return;

        uint256 fee = (grossAmount * houseEdgeBps) / 10_000;
        uint256 net = grossAmount - fee;

        if (_poolBalances[token] < grossAmount) {
            revert InsufficientPoolBalance(token, grossAmount, _poolBalances[token]);
        }

        _poolBalances[token] -= grossAmount;
        _transferOut(token, winner, net);
        emit PayoutSent(msg.sender, winner, token, net, fee);
    }

    receive() external payable {
        _poolBalances[NATIVE_TOKEN] += msg.value;
    }

    // --- Internal ---

    function _enforceBetLimits(address token, uint256 amount) internal view {
        uint256 minBet_ = _minBets[token];
        uint256 maxBet_ = _maxBets[token];
        if (amount < minBet_) revert BetBelowMinimum(amount, minBet_);
        if (amount > maxBet_) revert BetAboveMaximum(amount, maxBet_);
    }

    function _transferOut(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        if (token == NATIVE_TOKEN) {
            (bool ok,) = to.call{value: amount}("");
            if (!ok) revert TransferFailed();
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }
}
