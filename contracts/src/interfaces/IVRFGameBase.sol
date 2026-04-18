// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IVRFGameBase
/// @notice Queryable VRF request / proof records for frontends and indexers.
interface IVRFGameBase {
    enum VRFStatus {
        None,
        Pending,
        Fulfilled,
        Failed,
        Superseded
    }

    struct VRFProofRecord {
        uint256 requestId;
        bytes32 context;
        uint256[] randomWords;
        VRFStatus status;
        uint64 requestedAt;
        uint64 fulfilledAt;
        uint8 retryCount;
        uint256 supersededByRequestId;
    }

    event VRFRequested(bytes32 indexed context, uint256 indexed requestId, uint8 retryCount);
    event VRFFulfilled(bytes32 indexed context, uint256 indexed requestId, uint256[] randomWords);
    event VRFFailed(bytes32 indexed context, uint256 indexed requestId, string reason);
    event VRFRetried(bytes32 indexed context, uint256 indexed oldRequestId, uint256 indexed newRequestId);

    error VRFRequestStillPending(bytes32 context);
    error VRFRequestNotRetryable(bytes32 context);
    error VRFMaxRetriesExceeded(bytes32 context);
    error VRFContextAlreadyPending(bytes32 context);
    error InvalidVRFConfig();

    function getVRFRecordByContext(bytes32 context) external view returns (VRFProofRecord memory);

    function getVRFRecordByRequestId(uint256 requestId) external view returns (VRFProofRecord memory);

    function getActiveRequestId(bytes32 context) external view returns (uint256);
}
