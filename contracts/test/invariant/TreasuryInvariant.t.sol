// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {GameTreasury} from "../../src/treasury/GameTreasury.sol";
import {TreasuryHandler} from "./TreasuryHandler.sol";

contract TreasuryInvariantTest is StdInvariant, Test {
    GameTreasury internal treasury;
    TreasuryHandler internal handler;
    address internal game = makeAddr("game");
    address internal player = makeAddr("player");

    function setUp() public {
        treasury = new GameTreasury(address(this), 200);
        treasury.setGameAuthorized(game, true);

        handler = new TreasuryHandler(treasury, game, player);
        vm.deal(game, 1000 ether);
        vm.deal(player, 0);

        targetContract(address(handler));
        excludeContract(address(treasury));
    }

    function invariant_poolBalanceMatchesAccounting() public view {
        assertEq(treasury.getPoolBalance(address(0)), handler.ghost_deposited() - handler.ghost_paidGross());
    }

    function invariant_poolNeverNegative() public view {
        assertGe(treasury.getPoolBalance(address(0)), 0);
    }
}
