// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GameTreasury} from "../../src/treasury/GameTreasury.sol";

contract TreasuryHandler is Test {
    GameTreasury public treasury;
    address public game;
    address public player;

    uint256 public ghost_deposited;
    uint256 public ghost_paidGross;

    constructor(GameTreasury treasury_, address game_, address player_) {
        treasury = treasury_;
        game = game_;
        player = player_;
    }

    function deposit(uint256 amount) external {
        amount = bound(amount, 0.001 ether, 2 ether);
        vm.deal(game, amount);
        vm.prank(game);
        treasury.depositBet{value: amount}(player, address(0), amount);
        ghost_deposited += amount;
    }

    function payout(uint256 gross) external {
        uint256 pool = treasury.getPoolBalance(address(0));
        if (pool == 0) return;
        gross = bound(gross, 0.001 ether, pool);

        vm.prank(game);
        treasury.payoutWinner(player, address(0), gross);
        ghost_paidGross += gross;
    }
}
