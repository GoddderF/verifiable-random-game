// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/treasury/GameTreasury.sol";
import "../src/games/LotteryRaffle.sol";
import "../src/games/DiceGame.sol";
import "../test/mocks/MockVRFCoordinator.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        // 1. Mock VRF Coordinator（本地 Anvil 专用）
        MockVRFCoordinator vrf = new MockVRFCoordinator();
        console.log("MockVRFCoordinator:", address(vrf));

        // 2. 金库：owner=deployer, houseEdge=200bps(2%)
        GameTreasury treasury = new GameTreasury(deployer, 200);
        console.log("GameTreasury      :", address(treasury));

        // VRF 通用参数
        bytes32 keyHash            = bytes32(0);   // 本地无需真实 keyHash
        uint64  subscriptionId     = 1;
        uint16  requestConfirms    = 1;
        uint32  callbackGasLimit   = 500_000;

        // 3. 乐透合约
        LotteryRaffle lottery = new LotteryRaffle(
            address(vrf),
            deployer,
            address(treasury),
            keyHash,
            subscriptionId,
            requestConfirms,
            callbackGasLimit
        );
        console.log("LotteryRaffle     :", address(lottery));

        // 4. 骰子合约（revealDelayBlocks=1）
        DiceGame dice = new DiceGame(
            address(vrf),
            deployer,
            address(treasury),
            keyHash,
            subscriptionId,
            requestConfirms,
            callbackGasLimit,
            1
        );
        console.log("DiceGame          :", address(dice));

        // 5. 授权游戏合约使用金库
        treasury.setGameAuthorized(address(lottery), true);
        treasury.setGameAuthorized(address(dice), true);
        console.log("Games authorized in treasury");

        vm.stopBroadcast();
    }
}