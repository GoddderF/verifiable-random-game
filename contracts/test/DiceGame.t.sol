// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GameTestBase} from "./helpers/GameTestBase.sol";
import {IVRFGameBase} from "../src/interfaces/IVRFGameBase.sol";
import {DiceGame} from "../src/games/DiceGame.sol";

contract DiceGameTest is GameTestBase {
    receive() external payable {}

    bytes32 internal secret = keccak256("secret");
    uint256 internal nonce = 42;

    function _commitment(DiceGame.BetKind kind, uint8 target) internal view returns (bytes32) {
        return keccak256(abi.encode(alice, kind, target, secret, nonce));
    }

    function _reveal(DiceGame.BetKind kind, uint8 target, uint256 amount) internal returns (uint256 betId) {
        vm.prank(alice);
        dice.commitBet(_commitment(kind, target));
        vm.roll(block.number + 4);
        vm.prank(alice);
        return dice.revealAndBet{value: amount}(secret, nonce, kind, target, address(0), amount);
    }

    function test_commitReveal_exactWin() public {
        uint256 betId = _reveal(DiceGame.BetKind.Exact, 4, 0.1 ether);
        uint256 requestId = dice.getActiveRequestId(_diceContext(betId));

        uint256[] memory words = new uint256[](1);
        words[0] = 3; // roll = (3 % 6) + 1 = 4

        uint256 aliceBefore = alice.balance;
        _fulfillVRF(requestId, address(dice), words);

        (,,,,, bool settled) = dice.bets(betId);
        assertTrue(settled);
        assertGt(alice.balance, aliceBefore);
    }

    function test_exactLose_noPayout() public {
        uint256 betId = _reveal(DiceGame.BetKind.Exact, 4, 0.1 ether);
        uint256 requestId = dice.getActiveRequestId(_diceContext(betId));

        uint256[] memory words = new uint256[](1);
        words[0] = 0; // roll = 1

        uint256 aliceBefore = alice.balance;
        _fulfillVRF(requestId, address(dice), words);
        assertEq(alice.balance, aliceBefore);
    }

    function test_overBet_win() public {
        uint256 betId = _reveal(DiceGame.BetKind.Over, 0, 0.1 ether);
        uint256 requestId = dice.getActiveRequestId(_diceContext(betId));

        uint256[] memory words = new uint256[](1);
        words[0] = 4; // roll = 5

        uint256 aliceBefore = alice.balance;
        _fulfillVRF(requestId, address(dice), words);
        assertGt(alice.balance, aliceBefore);
    }

    function test_underBet_win() public {
        uint256 betId = _reveal(DiceGame.BetKind.Under, 0, 0.1 ether);
        uint256 requestId = dice.getActiveRequestId(_diceContext(betId));

        uint256[] memory words = new uint256[](1);
        words[0] = 1; // roll = 2

        uint256 aliceBefore = alice.balance;
        _fulfillVRF(requestId, address(dice), words);
        assertGt(alice.balance, aliceBefore);
    }

    function test_revealTooEarly_reverts() public {
        vm.prank(alice);
        dice.commitBet(_commitment(DiceGame.BetKind.Exact, 3));
        vm.expectRevert(DiceGame.RevealTooEarly.selector);
        vm.prank(alice);
        dice.revealAndBet{value: 0.1 ether}(secret, nonce, DiceGame.BetKind.Exact, 3, address(0), 0.1 ether);
    }

    function test_invalidCommitment_reverts() public {
        vm.prank(alice);
        dice.commitBet(keccak256("wrong"));
        vm.roll(block.number + 4);
        vm.expectRevert(DiceGame.InvalidCommitment.selector);
        vm.prank(alice);
        dice.revealAndBet{value: 0.1 ether}(secret, nonce, DiceGame.BetKind.Exact, 3, address(0), 0.1 ether);
    }

    function test_revealERC20() public {
        vm.prank(alice);
        dice.commitBet(_commitment(DiceGame.BetKind.Over, 0));
        vm.roll(block.number + 4);

        vm.startPrank(alice);
        token.approve(address(dice), 5e18);
        uint256 betId = dice.revealAndBet(secret, nonce, DiceGame.BetKind.Over, 0, address(token), 5e18);
        vm.stopPrank();

        assertEq(treasury.getPoolBalance(address(token)), 5e18);

        uint256 requestId = dice.getActiveRequestId(_diceContext(betId));
        uint256[] memory words = new uint256[](1);
        words[0] = 10; // roll 5
        _fulfillVRF(requestId, address(dice), words);
    }

    function test_vrfCallbackFailure_marksFailed() public {
        uint256 betId = _reveal(DiceGame.BetKind.Exact, 1, 0.1 ether);
        bytes32 ctx = _diceContext(betId);
        uint256 requestId = dice.getActiveRequestId(ctx);

        // Drain treasury pool so payout reverts inside callback (keep only the latest bet).
        uint256 pool = treasury.getPoolBalance(address(0));
        if (pool > 0.1 ether) {
            treasury.withdrawFees(address(0), address(this), pool - 0.1 ether);
        }

        _fulfillVRF(requestId, address(dice), new uint256[](1));

        IVRFGameBase.VRFProofRecord memory rec = dice.getVRFRecordByRequestId(requestId);
        assertEq(uint256(rec.status), uint256(IVRFGameBase.VRFStatus.Failed));
    }

    function testFuzz_rollMapping(uint256 randomWord) public {
        uint256 betId = _reveal(DiceGame.BetKind.Exact, 3, 0.01 ether);
        uint256 requestId = dice.getActiveRequestId(_diceContext(betId));

        uint256[] memory words = new uint256[](1);
        words[0] = randomWord;
        _fulfillVRF(requestId, address(dice), words);

        uint8 roll = uint8((randomWord % 6) + 1);
        assertGe(roll, 1);
        assertLe(roll, 6);
        (,,,,, bool settledAfter) = dice.bets(betId);
        assertTrue(settledAfter);
    }
}
