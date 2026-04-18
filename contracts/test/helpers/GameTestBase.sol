// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/vrf/mocks/VRFCoordinatorV2Mock.sol";
import {GameTreasury} from "../../src/treasury/GameTreasury.sol";
import {LotteryRaffle} from "../../src/games/LotteryRaffle.sol";
import {DiceGame} from "../../src/games/DiceGame.sol";
import {IVRFGameBase} from "../../src/interfaces/IVRFGameBase.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

abstract contract GameTestBase is Test {
    uint256 internal constant HOUSE_EDGE_BPS = 200;
    uint96 internal constant SUB_FUND = uint96(100 ether);
    bytes32 internal constant KEY_HASH = bytes32(uint256(0x1234));

    VRFCoordinatorV2Mock internal vrfCoordinator;
    GameTreasury internal treasury;
    LotteryRaffle internal lottery;
    DiceGame internal dice;
    MockERC20 internal token;

    uint64 internal subId;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public virtual {
        vrfCoordinator = new VRFCoordinatorV2Mock(0.25 ether, 1e9);
        subId = vrfCoordinator.createSubscription();
        vrfCoordinator.fundSubscription(subId, SUB_FUND);

        treasury = new GameTreasury(address(this), HOUSE_EDGE_BPS);

        lottery = new LotteryRaffle(
            address(vrfCoordinator),
            address(this),
            address(treasury),
            KEY_HASH,
            subId,
            3,
            500_000
        );

        dice = new DiceGame(
            address(vrfCoordinator),
            address(this),
            address(treasury),
            KEY_HASH,
            subId,
            3,
            500_000,
            3
        );

        vrfCoordinator.addConsumer(subId, address(lottery));
        vrfCoordinator.addConsumer(subId, address(dice));

        treasury.setGameAuthorized(address(lottery), true);
        treasury.setGameAuthorized(address(dice), true);
        treasury.setBetLimits(address(0), 0.001 ether, 100 ether);

        token = new MockERC20();
        treasury.setTokenSupported(address(token), true);
        treasury.setBetLimits(address(token), 1e6, 1000e18);

        // Seed treasury pool balance (vm.deal alone does not update internal accounting).
        vm.deal(address(lottery), 50 ether);
        vm.prank(address(lottery));
        treasury.depositBet{value: 50 ether}(address(this), address(0), 50 ether);

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        token.mint(alice, 1000e18);
        token.mint(bob, 1000e18);
    }

    function _fulfillVRF(uint256 requestId, address consumer, uint256[] memory words) internal {
        vrfCoordinator.fulfillRandomWordsWithOverride(requestId, consumer, words);
    }

    function _lotteryContext(uint256 roundId) internal view returns (bytes32) {
        return keccak256(abi.encode("LOTTERY_ROUND", address(lottery), roundId));
    }

    function _diceContext(uint256 betId) internal view returns (bytes32) {
        return keccak256(abi.encode("DICE_BET", address(dice), betId));
    }

    function _openDefaultRound() internal returns (uint256 roundId) {
        uint64 start = uint64(block.timestamp);
        uint64 end = start + 1 days;
        roundId = lottery.openRound(start, end, address(0));
        vm.warp(start);
    }

    function _roundStatus(uint256 roundId) internal view returns (LotteryRaffle.RoundStatus) {
        (,, LotteryRaffle.RoundStatus status,,,,,,,,) = lottery.rounds(roundId);
        return status;
    }

    function _roundWinner(uint256 roundId) internal view returns (address) {
        (,,,,,,,, address winner,,) = lottery.rounds(roundId);
        return winner;
    }

    function _roundWinnerPayout(uint256 roundId) internal view returns (uint256) {
        (,,,,,,,,, uint256 payout,) = lottery.rounds(roundId);
        return payout;
    }

    function _roundTotalWeight(uint256 roundId) internal view returns (uint256) {
        (,,,, uint256 totalWeight,,,,,,) = lottery.rounds(roundId);
        return totalWeight;
    }

    function _roundRolloverIn(uint256 roundId) internal view returns (uint256) {
        (,,,,,, uint256 rolloverIn,,,,) = lottery.rounds(roundId);
        return rolloverIn;
    }
}
