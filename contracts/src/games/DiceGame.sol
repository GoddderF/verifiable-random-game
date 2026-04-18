// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IGameTreasury} from "../interfaces/IGameTreasury.sol";
import {VRFGameBase} from "../vrf/VRFGameBase.sol";

/// @title DiceGame
/// @notice Commit-reveal dice betting with Chainlink VRF roll and dynamic payout multipliers.
contract DiceGame is VRFGameBase {
    using SafeERC20 for IERC20;

    enum BetKind {
        Exact, // predict face 1-6
        Over, // roll > 3 (4,5,6)
        Under // roll < 4 (1,2,3)
    }

    struct Commitment {
        bytes32 commitment;
        uint64 commitBlock;
        bool revealed;
    }

    struct ActiveBet {
        address player;
        address token;
        uint256 amount;
        BetKind kind;
        uint8 target; // 1-6 for Exact; ignored for Over/Under
        bool settled;
    }

    IGameTreasury public immutable treasury;

    /// @notice Blocks between commit and reveal to mitigate mempool front-running.
    uint256 public revealDelayBlocks;

    uint256 public nextBetId;
    mapping(address player => Commitment) public commitments;
    mapping(uint256 betId => ActiveBet) public bets;
    mapping(bytes32 vrfContext => uint256 betId) private _betIdByContext;

    /// @dev Net multipliers before treasury house edge (scaled 1e4). Exact: ~5.88x, Over/Under: ~1.96x at 2% edge.
    uint256 public constant MULTIPLIER_EXACT_BPS = 58_800;
    uint256 public constant MULTIPLIER_OVER_UNDER_BPS = 19_600;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    event BetCommitted(address indexed player, bytes32 commitment, uint64 commitBlock);
    event BetRevealed(uint256 indexed betId, address indexed player, BetKind kind, uint8 target, uint256 amount);
    event DiceRollSettled(uint256 indexed betId, uint8 roll, uint256 payout, bool won);

    error InvalidCommitment();
    error CommitmentAlreadyExists();
    error NoCommitment();
    error RevealTooEarly();
    error AlreadyRevealed();
    error InvalidTarget();
    error InvalidAmount();
    error BetNotFound();
    error BetAlreadySettled();

    constructor(
        address vrfCoordinator,
        address initialOwner,
        address treasury_,
        bytes32 keyHash,
        uint64 subscriptionId,
        uint16 requestConfirmations,
        uint32 callbackGasLimit,
        uint256 revealDelayBlocks_
    )
        VRFGameBase(
            vrfCoordinator,
            initialOwner,
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            1,
            30 minutes
        )
    {
        treasury = IGameTreasury(treasury_);
        revealDelayBlocks = revealDelayBlocks_ == 0 ? 3 : revealDelayBlocks_;
    }

    function setRevealDelayBlocks(uint256 blocks_) external onlyOwner {
        revealDelayBlocks = blocks_;
    }

    /// @notice Phase 1: hide prediction from mempool observers.
    function commitBet(bytes32 commitment) external {
        if (commitment == bytes32(0)) revert InvalidCommitment();
        if (commitments[msg.sender].commitment != bytes32(0) && !commitments[msg.sender].revealed) {
            revert CommitmentAlreadyExists();
        }
        commitments[msg.sender] = Commitment({commitment: commitment, commitBlock: uint64(block.number), revealed: false});
        emit BetCommitted(msg.sender, commitment, uint64(block.number));
    }

    /// @notice Phase 2: reveal prediction, deposit bet, and request VRF (after block delay).
    function revealAndBet(
        bytes32 secret,
        uint256 nonce,
        BetKind kind,
        uint8 target,
        address token,
        uint256 amount
    ) external payable returns (uint256 betId) {
        Commitment storage c = commitments[msg.sender];
        if (c.commitment == bytes32(0)) revert NoCommitment();
        if (c.revealed) revert AlreadyRevealed();
        if (block.number < uint256(c.commitBlock) + revealDelayBlocks) revert RevealTooEarly();

        bytes32 expected = keccak256(abi.encode(msg.sender, kind, target, secret, nonce));
        if (expected != c.commitment) revert InvalidCommitment();

        if (kind == BetKind.Exact && (target < 1 || target > 6)) revert InvalidTarget();
        if (amount == 0) revert InvalidAmount();

        c.revealed = true;

        betId = ++nextBetId;
        bets[betId] = ActiveBet({
            player: msg.sender,
            token: token,
            amount: amount,
            kind: kind,
            target: target,
            settled: false
        });

        bytes32 context = keccak256(abi.encode("DICE_BET", address(this), betId));
        _betIdByContext[context] = betId;

        if (token == address(0)) {
            if (msg.value != amount) revert InvalidAmount();
            treasury.depositBet{value: amount}(msg.sender, address(0), amount);
        } else {
            if (msg.value != 0) revert InvalidAmount();
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            IERC20(token).forceApprove(address(treasury), amount);
            treasury.depositBet(msg.sender, token, amount);
        }

        _requestRandomness(context, 0);

        emit BetRevealed(betId, msg.sender, kind, target, amount);
    }

    function _onRandomWordsFulfilled(bytes32 context, uint256, uint256[] memory randomWords) internal override {
        uint256 betId = _betIdByContext[context];
        ActiveBet storage bet = bets[betId];
        if (bet.player == address(0)) revert BetNotFound();
        if (bet.settled) revert BetAlreadySettled();

        uint8 roll = uint8((randomWords[0] % 6) + 1);
        bool won = _isWinner(bet.kind, bet.target, roll);

        bet.settled = true;

        if (!won) {
            emit DiceRollSettled(betId, roll, 0, false);
            return;
        }

        uint256 multiplierBps = bet.kind == BetKind.Exact ? MULTIPLIER_EXACT_BPS : MULTIPLIER_OVER_UNDER_BPS;
        uint256 grossPayout = (bet.amount * multiplierBps) / BPS_DENOMINATOR;

        treasury.payoutWinner(bet.player, bet.token, grossPayout);

        emit DiceRollSettled(betId, roll, grossPayout, true);
    }

    function _isWinner(BetKind kind, uint8 target, uint8 roll) internal pure returns (bool) {
        if (kind == BetKind.Exact) return roll == target;
        if (kind == BetKind.Over) return roll > 3;
        return roll < 4;
    }
}
