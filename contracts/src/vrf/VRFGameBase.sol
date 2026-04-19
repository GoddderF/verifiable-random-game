// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/vrf/VRFConsumerBaseV2.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {IVRFGameBase} from "../interfaces/IVRFGameBase.sol";

/// @title VRFGameBase
/// @notice Chainlink VRF v2 async consumer with proof storage, failure marking, and timeout retry.
abstract contract VRFGameBase is IVRFGameBase, VRFConsumerBaseV2, Ownable, ReentrancyGuard {
    uint256 internal constant MAX_VRF_RETRIES = 3;

    bytes32 internal immutable i_keyHash;
    uint64 internal immutable i_subscriptionId;
    uint16 internal immutable i_requestConfirmations;
    uint32 internal immutable i_callbackGasLimit;
    uint32 internal immutable i_numWords;

    VRFCoordinatorV2Interface internal immutable i_vrfCoordinator;

    /// @notice Seconds after which a pending request may be retried.
    uint256 public vrfTimeoutSeconds;

    mapping(uint256 requestId => VRFProofRecord record) internal _recordsByRequestId;
    mapping(bytes32 context => uint256 activeRequestId) internal _activeRequestByContext;

    constructor(
        address vrfCoordinator,
        address initialOwner,
        bytes32 keyHash,
        uint64 subscriptionId,
        uint16 requestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords,
        uint256 timeoutSeconds
    ) VRFConsumerBaseV2(vrfCoordinator) Ownable(initialOwner) {
        if (timeoutSeconds == 0 || numWords == 0 || callbackGasLimit < 50_000) {
            revert InvalidVRFConfig();
        }
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_keyHash = keyHash;
        i_subscriptionId = subscriptionId;
        i_requestConfirmations = requestConfirmations;
        i_callbackGasLimit = callbackGasLimit;
        i_numWords = numWords;
        vrfTimeoutSeconds = timeoutSeconds;
    }

    // --- Views ---

    /// @inheritdoc IVRFGameBase
    function getVRFRecordByContext(bytes32 context) external view returns (VRFProofRecord memory) {
        uint256 requestId = _activeRequestByContext[context];
        if (requestId == 0) {
            return VRFProofRecord({
                requestId: 0,
                context: context,
                randomWords: new uint256[](0),
                status: VRFStatus.None,
                requestedAt: 0,
                fulfilledAt: 0,
                retryCount: 0,
                supersededByRequestId: 0
            });
        }
        return _recordsByRequestId[requestId];
    }

    /// @inheritdoc IVRFGameBase
    function getVRFRecordByRequestId(uint256 requestId) external view returns (VRFProofRecord memory) {
        return _recordsByRequestId[requestId];
    }

    /// @inheritdoc IVRFGameBase
    function getActiveRequestId(bytes32 context) external view returns (uint256) {
        return _activeRequestByContext[context];
    }

    // --- Admin ---

    function setVrfTimeoutSeconds(uint256 newTimeout) external onlyOwner {
        if (newTimeout == 0) revert InvalidVRFConfig();
        vrfTimeoutSeconds = newTimeout;
    }

    // --- Retry ---

    /// @notice Retry a stuck or failed VRF request for the same game context.
    function retryVRF(bytes32 context) external nonReentrant {
        uint256 oldRequestId = _activeRequestByContext[context];
        if (oldRequestId == 0) revert VRFRequestNotRetryable(context);

        VRFProofRecord storage oldRecord = _recordsByRequestId[oldRequestId];
        if (oldRecord.status == VRFStatus.Fulfilled) revert VRFRequestNotRetryable(context);

        // NOTE: block.timestamp is used only for a coarse-grained timeout gate. Small timestamp manipulation
        // by validators is bounded and does not enable bypassing retry limits or breaking correctness.
        // forge-lint: disable-next-line(block-timestamp)
        bool timedOut = block.timestamp > uint256(oldRecord.requestedAt) + vrfTimeoutSeconds;

        if (oldRecord.status == VRFStatus.Pending && !timedOut) {
            revert VRFRequestStillPending(context);
        }
        if (oldRecord.retryCount >= MAX_VRF_RETRIES) revert VRFMaxRetriesExceeded(context);

        oldRecord.status = VRFStatus.Superseded;
        uint256 newRequestId = _requestRandomness(context, oldRecord.retryCount + 1);
        oldRecord.supersededByRequestId = newRequestId;

        emit VRFRetried(context, oldRequestId, newRequestId);
    }

    // --- Internal VRF flow ---

    function _requestRandomness(bytes32 context, uint8 retryCount) internal returns (uint256 requestId) {
        uint256 existing = _activeRequestByContext[context];
        if (existing != 0) {
            VRFStatus status = _recordsByRequestId[existing].status;
            if (status == VRFStatus.Pending) revert VRFContextAlreadyPending(context);
        }

        requestId = i_vrfCoordinator.requestRandomWords(
            i_keyHash, i_subscriptionId, i_requestConfirmations, i_callbackGasLimit, i_numWords
        );

        _recordsByRequestId[requestId] = VRFProofRecord({
            requestId: requestId,
            context: context,
            randomWords: new uint256[](0),
            status: VRFStatus.Pending,
            requestedAt: uint64(block.timestamp),
            fulfilledAt: 0,
            retryCount: retryCount,
            supersededByRequestId: 0
        });
        _activeRequestByContext[context] = requestId;

        emit VRFRequested(context, requestId, retryCount);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        VRFProofRecord storage record = _recordsByRequestId[requestId];
        if (record.status != VRFStatus.Pending) return;

        record.randomWords = randomWords;
        record.status = VRFStatus.Fulfilled;
        record.fulfilledAt = uint64(block.timestamp);

        emit VRFFulfilled(record.context, requestId, randomWords);

        try this.__vrfCallbackTrampoline(record.context, requestId, randomWords) {
            // Game logic executed via external trampoline for safe failure capture.
        } catch Error(string memory reason) {
            record.status = VRFStatus.Failed;
            emit VRFFailed(record.context, requestId, reason);
        } catch {
            record.status = VRFStatus.Failed;
            emit VRFFailed(record.context, requestId, "VRF callback reverted");
        }
    }

    /// @dev External entry used only by `fulfillRandomWords` try/catch; not part of the public API.
    function __vrfCallbackTrampoline(bytes32 context, uint256 requestId, uint256[] memory randomWords) external {
        require(msg.sender == address(this), "VRFGameBase: only self");
        _onRandomWordsFulfilled(context, requestId, randomWords);
    }

    /// @dev Implemented by concrete games; must follow CEI inside implementations.
    function _onRandomWordsFulfilled(bytes32 context, uint256 requestId, uint256[] memory randomWords) internal virtual;
}