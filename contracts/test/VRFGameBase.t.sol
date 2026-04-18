// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GameTestBase} from "./helpers/GameTestBase.sol";
import {IVRFGameBase} from "../src/interfaces/IVRFGameBase.sol";

/// @notice Additional VRF lifecycle tests (retry limits, admin config).
contract VRFGameBaseTest is GameTestBase {
    function test_vrfMaxRetriesExceeded() public {
        uint256 roundId = _openDefaultRound();
        vm.warp(block.timestamp + 1 days);
        lottery.closeRound(roundId);
        lottery.requestDraw(roundId);

        bytes32 ctx = _lotteryContext(roundId);
        vm.warp(block.timestamp + 2 hours);

        lottery.retryVRF(ctx);
        vm.warp(block.timestamp + 2 hours);
        lottery.retryVRF(ctx);
        vm.warp(block.timestamp + 2 hours);
        lottery.retryVRF(ctx);

        vm.warp(block.timestamp + 2 hours);
        vm.expectRevert(abi.encodeWithSelector(IVRFGameBase.VRFMaxRetriesExceeded.selector, ctx));
        lottery.retryVRF(ctx);
    }

    function test_setVrfTimeout_onlyOwner() public {
        lottery.setVrfTimeoutSeconds(2 hours);
        vm.prank(alice);
        vm.expectRevert();
        lottery.setVrfTimeoutSeconds(1 hours);
    }

    function test_getVRFRecord_emptyContext() public view {
        bytes32 emptyCtx = keccak256("missing");
        IVRFGameBase.VRFProofRecord memory rec = lottery.getVRFRecordByContext(emptyCtx);
        assertEq(uint256(rec.status), uint256(IVRFGameBase.VRFStatus.None));
    }
}
