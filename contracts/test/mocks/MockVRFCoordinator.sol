// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/vrf/VRFConsumerBaseV2.sol";

contract MockVRFCoordinator {
    uint256 private _requestId = 1;

    struct Request {
        address consumer;
        uint32  numWords;
    }
    mapping(uint256 => Request) private _requests;

    event RandomWordsRequested(uint256 indexed requestId, address indexed consumer);

    function requestRandomWords(
        bytes32,
        uint64,
        uint16,
        uint32 callbackGasLimit,
        uint32 numWords
    ) external returns (uint256 requestId) {
        requestId = _requestId++;
        _requests[requestId] = Request(msg.sender, numWords);
        emit RandomWordsRequested(requestId, msg.sender);
    }

    /// 手动触发随机数回调（测试用）
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) external {
        Request memory req = _requests[requestId];
        require(req.consumer != address(0), "unknown request");
        VRFConsumerBaseV2(req.consumer).rawFulfillRandomWords(requestId, randomWords);
    }

    /// 自动用 keccak 生成伪随机数并回调
    function fulfillRandomWordsAuto(uint256 requestId) external {
        Request memory req = _requests[requestId];
        require(req.consumer != address(0), "unknown request");
        uint256[] memory words = new uint256[](req.numWords);
        for (uint32 i = 0; i < req.numWords; i++) {
            words[i] = uint256(keccak256(abi.encodePacked(requestId, i, block.timestamp)));
        }
        VRFConsumerBaseV2(req.consumer).rawFulfillRandomWords(requestId, words);
    }

    // VRFCoordinatorV2 接口兼容（合约内部调用需要）
    function addConsumer(uint64, address) external {}
    function removeConsumer(uint64, address) external {}
    function cancelSubscription(uint64, address) external {}
    function getSubscription(uint64) external pure returns (
        uint96 balance, uint64 reqCount, address owner, address[] memory consumers
    ) {
        consumers = new address[](0);
        return (1 ether, 0, address(0), consumers);
    }
}