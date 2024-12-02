// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IMultiproofOracle {

    struct ImmutableArgs {
        uint88 proposalBond;
        uint40 challengeTime;
        uint88 proofReward;
        uint40 provingTime;
        uint64 proverFeePctWad;
        uint64 challengedFeePctWad;
        address treasury;
        uint16 emergencyPauseThreshold;
        uint40 emergencyPauseTime;
        bytes32 rollupConfigHash;
        bytes32 vkey;
    }

    struct Challenge {
        bytes32 outputRoot;
        uint256 index;
    }

    enum ProposalState {
        None,
        Unchallenged,
        Challenged,
        Rejected,
        Confirmed
    }

    struct ProposalData {
        address proposer;
        Challenge parent;
        uint40 deadline;
        uint8 version;
        ProposalState state;
        uint40 provenBitmap;
        address challenger;
        uint96 blockNum;
    }

    struct PublicValuesStruct {
        bytes32 l1BlockHash;
        bytes32 l2PreRoot;
        bytes32 claimRoot;
        uint256 l2BlockNum;
        bytes32 rollupConfigHash;
        bytes32 vkey;
    }

    struct PauseData {
        uint40 deadline;
        Challenge[] challenges;
    }

    /// Getters

    function getProposal(bytes32 outputRoot, uint256 index) external view returns (ProposalData memory);
    function isValidProposal(bytes32 outputRoot, uint256 index) external view returns (bool);
}
