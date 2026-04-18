// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GameTestBase} from "./helpers/GameTestBase.sol";
import {IGameTreasury} from "../src/interfaces/IGameTreasury.sol";

contract GameTreasuryTest is GameTestBase {
    address internal unauthorized = makeAddr("unauthorized");

    receive() external payable {}

    function test_initialConfig() public view {
        assertEq(treasury.houseEdgeBps(), HOUSE_EDGE_BPS);
        assertTrue(treasury.isGameAuthorized(address(lottery)));
        assertTrue(treasury.isTokenSupported(address(0)));
    }

    function test_depositNative_enforcesLimits() public {
        vm.deal(address(lottery), 1 ether);
        vm.prank(address(lottery));
        vm.expectRevert(abi.encodeWithSelector(IGameTreasury.BetBelowMinimum.selector, uint256(0.0001 ether), uint256(0.001 ether)));
        treasury.depositBet{value: 0.0001 ether}(alice, address(0), 0.0001 ether);
    }

    function test_depositNative_success() public {
        uint256 poolBefore = treasury.getPoolBalance(address(0));
        vm.deal(address(lottery), 1 ether);
        vm.prank(address(lottery));
        treasury.depositBet{value: 0.01 ether}(alice, address(0), 0.01 ether);
        assertEq(treasury.getPoolBalance(address(0)), poolBefore + 0.01 ether);
    }

    function test_depositERC20_success() public {
        uint256 poolBefore = treasury.getPoolBalance(address(token));
        vm.prank(alice);
        token.transfer(address(lottery), 5e18);

        vm.prank(address(lottery));
        token.approve(address(treasury), 5e18);
        vm.prank(address(lottery));
        treasury.depositBet(alice, address(token), 5e18);

        assertEq(treasury.getPoolBalance(address(token)), poolBefore + 5e18);
    }

    function test_payout_appliesHouseEdge() public {
        vm.deal(address(lottery), 2 ether);
        vm.prank(address(lottery));
        treasury.depositBet{value: 1 ether}(alice, address(0), 1 ether);

        uint256 bobBefore = bob.balance;
        vm.prank(address(lottery));
        treasury.payoutWinner(bob, address(0), 1 ether);

        uint256 expectedNet = 1 ether - (1 ether * HOUSE_EDGE_BPS / 10_000);
        assertEq(bob.balance - bobBefore, expectedNet);
    }

    function test_unauthorizedDeposit_reverts() public {
        vm.deal(unauthorized, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IGameTreasury.UnauthorizedGame.selector, unauthorized));
        vm.prank(unauthorized);
        treasury.depositBet{value: 0.01 ether}(alice, address(0), 0.01 ether);
    }

    function test_insufficientPool_reverts() public {
        uint256 pool = treasury.getPoolBalance(address(0));
        vm.prank(address(lottery));
        vm.expectRevert(
            abi.encodeWithSelector(
                IGameTreasury.InsufficientPoolBalance.selector, address(0), pool + 1, pool
            )
        );
        treasury.payoutWinner(bob, address(0), pool + 1);
    }

    function test_setHouseEdge_capped() public {
        vm.expectRevert(abi.encodeWithSelector(IGameTreasury.BetAboveMaximum.selector, uint256(600), uint256(500)));
        treasury.setHouseEdgeBps(600);
    }

    function test_withdrawFees() public {
        uint256 poolBefore = treasury.getPoolBalance(address(0));
        vm.deal(address(lottery), 1 ether);
        vm.prank(address(lottery));
        treasury.depositBet{value: 0.5 ether}(alice, address(0), 0.5 ether);

        uint256 ownerBefore = address(this).balance;
        treasury.withdrawFees(address(0), address(this), 0.1 ether);
        assertEq(address(this).balance - ownerBefore, 0.1 ether);
        assertEq(treasury.getPoolBalance(address(0)), poolBefore + 0.5 ether - 0.1 ether);
    }

    function testFuzz_depositWithinLimits(uint256 amount) public {
        amount = bound(amount, 0.001 ether, 10 ether);
        uint256 poolBefore = treasury.getPoolBalance(address(0));
        vm.deal(address(lottery), amount);
        vm.prank(address(lottery));
        treasury.depositBet{value: amount}(alice, address(0), amount);
        assertEq(treasury.getPoolBalance(address(0)), poolBefore + amount);
    }

    function testFuzz_payoutNeverExceedsPool(uint256 depositAmt, uint256 payoutAmt) public {
        depositAmt = bound(depositAmt, 0.001 ether, 10 ether);
        payoutAmt = bound(payoutAmt, 0.001 ether, depositAmt);

        uint256 poolBefore = treasury.getPoolBalance(address(0));
        vm.deal(address(lottery), depositAmt);
        vm.prank(address(lottery));
        treasury.depositBet{value: depositAmt}(alice, address(0), depositAmt);

        vm.prank(address(lottery));
        treasury.payoutWinner(bob, address(0), payoutAmt);
        assertEq(treasury.getPoolBalance(address(0)), poolBefore + depositAmt - payoutAmt);
    }
}
