// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IGameTreasury} from "../interfaces/IGameTreasury.sol";
import {VRFGameBase} from "../vrf/VRFGameBase.sol";

/// @title LotteryRaffle
/// @notice Time-windowed weighted lottery with Chainlink VRF draw and rollover when no winner is selected.
contract LotteryRaffle is VRFGameBase {
    using SafeERC20 for IERC20;

    enum RoundStatus {
        Open,
        Closed,
        Drawing,
        Settled
    }

    struct Ticket {
        address player;
        uint96 weight;
    }

    struct Round {
        uint64 startTime;
        uint64 endTime;
        RoundStatus status;
        address paymentToken;
        uint256 totalWeight;
        uint256 poolAmount;
        uint256 rolloverIn;
        uint256 rolloverOut;
        address winner;
        uint256 winnerPayout;
        uint256 vrfRequestId;
    }

    IGameTreasury public immutable treasury;

    uint256 public currentRoundId;
    uint256 public pendingRollover;

    mapping(uint256 roundId => Round round) public rounds;
    mapping(uint256 roundId => Ticket[] tickets) private _tickets;
    mapping(bytes32 vrfContext => uint256 roundId) private _roundIdByContext;

    event RoundOpened(uint256 indexed roundId, uint64 startTime, uint64 endTime, address indexed token, uint256 rolloverIn);
    event TicketPurchased(uint256 indexed roundId, address indexed player, uint256 amount, uint256 totalWeight);
    event RoundClosed(uint256 indexed roundId);
    event DrawRequested(uint256 indexed roundId, bytes32 indexed vrfContext, uint256 requestId);
    event RoundSettled(uint256 indexed roundId, address winner, uint256 payout, uint256 rolloverOut);

    error RoundNotOpen();
    error RoundStillOpen();
    error RoundNotClosed();
    error InvalidRoundTiming();
    error InvalidPayment();
    error RoundNotDrawing();
    error NoActiveRound();
    error AmountTooLarge();

    constructor(
        address vrfCoordinator,
        address initialOwner,
        address treasury_,
        bytes32 keyHash,
        uint256 subscriptionId, // <-- changed from uint64 to uint256 for v2.5
        uint16 requestConfirmations,
        uint32 callbackGasLimit
    )
        VRFGameBase(
            vrfCoordinator,
            initialOwner,
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            1,
            1 hours
        )
    {
        treasury = IGameTreasury(treasury_);
    }

    function openRound(uint64 startTime, uint64 endTime, address paymentToken) external onlyOwner returns (uint256 roundId) {
        if (endTime <= startTime) revert InvalidRoundTiming();

        roundId = ++currentRoundId;
        uint256 rolloverIn = pendingRollover;
        pendingRollover = 0;

        Round storage round = rounds[roundId];
        round.startTime = startTime;
        round.endTime = endTime;
        round.status = RoundStatus.Open;
        round.paymentToken = paymentToken;
        round.rolloverIn = rolloverIn;
        round.poolAmount = rolloverIn;

        emit RoundOpened(roundId, startTime, endTime, paymentToken, rolloverIn);
    }

    function buyTicketsWithETH() external payable {
        _buyTickets(address(0), msg.value);
    }

    function buyTicketsWithERC20(address token, uint256 amount) external {
        _buyTickets(token, amount);
    }

    function closeRound(uint256 roundId) external {
        Round storage round = rounds[roundId];
        if (round.status != RoundStatus.Open) revert RoundNotOpen();

        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp < round.endTime) revert RoundStillOpen();

        round.status = RoundStatus.Closed;
        emit RoundClosed(roundId);
    }

    function requestDraw(uint256 roundId) external {
        Round storage round = rounds[roundId];
        if (round.status != RoundStatus.Closed) revert RoundNotClosed();

        round.status = RoundStatus.Drawing;
        bytes32 context = keccak256(abi.encode("LOTTERY_ROUND", address(this), roundId));
        _roundIdByContext[context] = roundId;

        uint256 requestId = _requestRandomness(context, 0);
        round.vrfRequestId = requestId;

        emit DrawRequested(roundId, context, requestId);
    }

    function ticketCount(uint256 roundId) external view returns (uint256) {
        return _tickets[roundId].length;
    }

    function getTicket(uint256 roundId, uint256 index) external view returns (address player, uint96 weight) {
        Ticket memory t = _tickets[roundId][index];
        return (t.player, t.weight);
    }

    function _buyTickets(address token, uint256 amount) internal {
        uint256 roundId = currentRoundId;
        if (roundId == 0) revert NoActiveRound();

        Round storage round = rounds[roundId];
        if (round.status != RoundStatus.Open) revert RoundNotOpen();

        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp < round.startTime || block.timestamp >= round.endTime) revert InvalidRoundTiming();

        if (round.paymentToken != token || amount == 0) revert InvalidPayment();
        if (amount > type(uint96).max) revert AmountTooLarge();

        round.totalWeight += amount;
        round.poolAmount += amount;

        _tickets[roundId].push(Ticket({player: msg.sender, weight: uint96(amount)}));

        emit TicketPurchased(roundId, msg.sender, amount, round.totalWeight);

        if (token == address(0)) {
            treasury.depositBet{value: amount}(msg.sender, address(0), amount);
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            IERC20(token).forceApprove(address(treasury), amount);
            treasury.depositBet(msg.sender, token, amount);
        }
    }

    function _onRandomWordsFulfilled(bytes32 context, uint256, uint256[] memory randomWords) internal override {
        uint256 roundId = _roundIdByContext[context];
        Round storage round = rounds[roundId];
        if (round.status != RoundStatus.Drawing) revert RoundNotDrawing();

        Ticket[] storage tickets = _tickets[roundId];
        if (tickets.length == 0 || round.totalWeight == 0) {
            _rolloverNoWinner(round, roundId);
            return;
        }

        uint256 winningPoint = randomWords[0] % round.totalWeight;
        address winner;
        uint256 accumulated;

        for (uint256 i = 0; i < tickets.length; i++) {
            accumulated += tickets[i].weight;
            if (winningPoint < accumulated) {
                winner = tickets[i].player;
                break;
            }
        }

        if (winner == address(0)) {
            _rolloverNoWinner(round, roundId);
            return;
        }

        uint256 payout = round.poolAmount;
        round.winner = winner;
        round.winnerPayout = payout;
        round.status = RoundStatus.Settled;

        treasury.payoutWinner(winner, round.paymentToken, payout);

        emit RoundSettled(roundId, winner, payout, 0);
    }

    function _rolloverNoWinner(Round storage round, uint256 roundId) internal {
        uint256 rolled = round.poolAmount;
        round.rolloverOut = rolled;
        round.status = RoundStatus.Settled;
        pendingRollover += rolled;

        emit RoundSettled(roundId, address(0), 0, rolled);
    }
}