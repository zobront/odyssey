// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IProver } from "./interfaces/IProver.sol";
import { IMultiproofOracle } from "./interfaces/IMultiproofOracle.sol";

contract MultiproofOracle is IMultiproofOracle {

    ///////////////////////////////
    //////// STATE VARIABLES /////
    ///////////////////////////////

    uint8 public constant VERSION = 1;

    uint256 public immutable proposalBond;
    uint256 public immutable challengeTime;

    uint256 public immutable proofReward; // to challenge, we must bond `proofReward * provers.length`
    uint256 public immutable provingTime;

    bytes32 public immutable rollupConfigHash;
    bytes32 public immutable vkey;

    // outputRoot => array of proposals
    mapping(bytes32 => ProposalData[]) proposals;
    IProver[] public provers;

    uint256 public proverFeePctWad;
    uint256 public challengedFeePctWad;
    address public treasury;

    uint256 public immutable emergencyPauseThreshold;
    uint256 public immutable emergencyPauseTime;
    bool public emergencyPaused;
    uint40 public emergencyPauseDeadline;
    Challenge[] emergencyPauseChallenges;

    bool public emergencyShutdown;
    uint256 emergencyShutdownIncentive;

    mapping(bytes32 => bool) public historicBlockhashes;

    ///////////////////////////////
    ///////// CONSTRUCTOR /////////
    ///////////////////////////////

    constructor(IProver[] memory _provers, uint96 _initialBlockNum, bytes32 _initialOutputRoot, ImmutableArgs memory _args) payable {
        require(_provers.length < 40); // proven bitmap has to fit in uint40
        provers = _provers;

        // set params - for details on how to set: https://github.com/zobront/odyssey/blob/multiproof/contracts/spec/params.md
        require(_args.proverFeePctWad < 1e18, "prover fee must be less than 100%");
        require(_args.challengedFeePctWad < 1e18, "challenged fee must be less than 100%");
        proposalBond = _args.proposalBond;
        challengeTime = _args.challengeTime;
        proofReward = _args.proofReward;
        provingTime = _args.provingTime;
        proverFeePctWad = _args.proverFeePctWad;
        challengedFeePctWad = _args.challengedFeePctWad;
        treasury = _args.treasury;
        emergencyPauseThreshold = _args.emergencyPauseThreshold;
        emergencyPauseTime = _args.emergencyPauseTime;
        rollupConfigHash = _args.rollupConfigHash;
        vkey = _args.vkey;

        // initialize anchor state with Confirmed status
        proposals[_initialOutputRoot].push(ProposalData({
            proposer: address(0),
            parent: Challenge({
                outputRoot: bytes32(0),
                index: 0
            }),
            deadline: 0,
            version: VERSION,
            state: ProposalState.Confirmed,
            provenBitmap: 0,
            challenger: address(0),
            blockNum: _initialBlockNum
        }));

        emergencyShutdownIncentive = msg.value;
    }

    ///////////////////////////////
    ////////// LIFECYCLE //////////
    ///////////////////////////////

    function propose(Challenge memory parent, uint96 blockNum, bytes32 outputRoot) public payable {
        require(msg.value == proposalBond, "incorrect bond amount");
        require(!emergencyShutdown, "emergency shutdown");

        proposals[outputRoot].push(ProposalData({
            proposer: msg.sender,
            parent: parent,
            deadline: uint40(block.timestamp + challengeTime),
            version: VERSION,
            state: ProposalState.Unchallenged,
            provenBitmap: 0,
            challenger: address(0),
            blockNum: blockNum
        }));
    }

    function challenge(bytes32 outputRoot, uint256 index) public payable {
        require(!emergencyShutdown, "emergency shutdown");
        require(msg.value == proofReward * provers.length, "incorrect bond amount");

        ProposalData storage proposal = proposals[outputRoot][index];
        require(proposal.state == ProposalState.Unchallenged, "can only challenge unchallenged proposals");
        require(proposal.deadline > block.timestamp, "deadline passed");

        proposals[outputRoot][index].deadline = uint40(block.timestamp + provingTime);
        proposals[outputRoot][index].state = ProposalState.Challenged;
        proposals[outputRoot][index].challenger = msg.sender;
    }

    function prove(bytes32 outputRoot, uint256 index, bytes32 l1BlockHash, bytes[] memory proofs) public {
        require(!emergencyShutdown, "emergency shutdown");
        ProposalData storage proposal = proposals[outputRoot][index];
        require(proposal.state == ProposalState.Challenged, "can only prove challenged proposals");
        require(proposal.deadline > block.timestamp, "deadline passed");
        require(historicBlockhashes[l1BlockHash], "blockhash not checkpointed");

        // verify ZK proofs
        require(proofs.length == provers.length, "incorrect number of proofs");

        uint successfulProofCount;
        for (uint256 i = 0; i < proofs.length; i++) {
            if (proposal.provenBitmap & (1 << i) != 0) {
                continue;
            }

            bytes memory pvs = provers[i].encode(PublicValuesStruct({
                l1BlockHash: l1BlockHash,
                l2PreRoot: proposal.parent.outputRoot,
                claimRoot: outputRoot,
                l2BlockNum: proposal.blockNum,
                rollupConfigHash: rollupConfigHash,
                vkey: vkey
            }));

            // Note: It IS possible to verify valid proofs against invalid parents.
            // Challengers should not challenge proofs of invalid parents, as they will lose their bonds.
            // As long as the parent is rejected, children will be rejected too.
            if (provers[i].verify(abi.encode(pvs), proofs[i])) {
                proposal.provenBitmap |= uint40(1 << i);
                successfulProofCount++;
            }
        }

        if (successfulProofCount > 0) {
            uint rewards = proofReward * successfulProofCount;
            uint treasuryFee = rewards * proverFeePctWad / 1e18;
            payable(treasury).transfer(treasuryFee);
            payable(msg.sender).transfer(rewards - treasuryFee);
        }
    }

    function finalize(bytes32 outputRoot, uint256 index) public {
        require(!emergencyShutdown, "emergency shutdown");
        ProposalData storage proposal = proposals[outputRoot][index];
        require(!isFinalized(proposal.state), "proposal already finalized");

        Challenge memory parent = proposal.parent;
        ProposalData storage parentProposal = proposals[parent.outputRoot][parent.index];
        if (!isFinalized(parentProposal.state)) {
            finalize(parent.outputRoot, parent.index);

            // extra safety check
            require(isFinalized(parentProposal.state), "parent not finalized");
        }

        uint successfulProofCount;
        for (uint i = 0; i < provers.length; i++) {
            if (proposal.provenBitmap & (1 << i) != 0) {
                successfulProofCount++;
            }
        }

        // If the parent was Rejected, the child should be Rejected.
        if (parentProposal.state == ProposalState.Rejected) {
            proposal.state = ProposalState.Rejected;

            if (proposal.challenger != address(0)) {
                payable(proposal.challenger).transfer(proposalBond + proofReward * (provers.length - successfulProofCount));
            } else {
                payable(msg.sender).transfer(proposalBond);
            }

            return;
        }

        // If it was challenged and all proven, we don't need to wait for the deadline.
        if (successfulProofCount == provers.length) {
            proposal.state = ProposalState.Confirmed;
            payable(proposal.proposer).transfer(proposalBond);
            return;
        }

        require(proposal.deadline < block.timestamp, "deadline not passed");

        if (proposal.state == ProposalState.Unchallenged) {
            require(!emergencyPaused, "no confirming while emergency paused");

            proposal.state = ProposalState.Confirmed;
            payable(proposal.proposer).transfer(proposalBond);
            return;
        }

        proposal.state = ProposalState.Rejected;

        uint treasuryFee = proposalBond * challengedFeePctWad / 1e18;
        uint proposalBondRewards = proposalBond - treasuryFee;
        uint challangeBondRefund = proofReward * (provers.length - successfulProofCount);

        payable(treasury).transfer(treasuryFee);
        payable(proposal.challenger).transfer(proposalBondRewards + challangeBondRefund);

        // If any proofs were proven, we have an on chain bug and need to shut down to address it.
        if (proposal.provenBitmap != 0) {
            emergencyShutdown = true;
            payable(msg.sender).transfer(emergencyShutdownIncentive);
        }
    }

    ///////////////////////////////
    /////////// HELPERS ///////////
    ///////////////////////////////

    function checkpointBlockHash(uint256 _blockNumber) external returns (bytes32) {
        bytes32 blockHash = blockhash(_blockNumber);
        require(blockHash != bytes32(0), "block hash not available");
        historicBlockhashes[blockHash] = true;

        return blockHash;
    }

    ///////////////////////////////
    /////////// EMERGENCY /////////
    ///////////////////////////////

    // This function exists to block a Proof of Whale attack.
    // If an attacker is proposing too many false roots, this allows us to emergency pause the contract
    // by showing that at least `emergencyPauseThreshold` roots have already been challenged.
    // An attacker is incentivized not to abuse this because they will pay treasury fees for all their challenges,
    // effectively losing 50% of `emergencyPauseThreshold` bonds to perform the attack.
    function emergencyPause(Challenge[] memory challenges) public payable {
        require(!emergencyPaused, "already in emergency pause");
        require(challenges.length >= emergencyPauseThreshold, "not enough challenges");

        for (uint i = 0; i < challenges.length; i++) {
            Challenge memory c = challenges[i];
            require(proposals[c.outputRoot][c.index].state == ProposalState.Challenged, "proposal not confirmed");
            emergencyPauseChallenges.push(c);
        }

        emergencyPaused = true;
        emergencyPauseDeadline = uint40(block.timestamp + emergencyPauseTime);
    }

    function endPause() public {
        require(emergencyPaused, "not in emergency pause");
        require(block.timestamp > emergencyPauseDeadline);

        emergencyPaused = false;
        delete emergencyPauseDeadline;
        delete emergencyPauseChallenges;
    }

    function triggerEmergencyShutdown(bytes32 outputRoot1, uint index1, bytes32 outputRoot2, uint index2) external {
        require(isValidProposal(outputRoot1, index1), "invalid proposal 1");
        require(isValidProposal(outputRoot2, index2), "invalid proposal 2");
        require(outputRoot1 != outputRoot2, "output roots must be different");

        emergencyShutdown = true;
        payable(msg.sender).transfer(emergencyShutdownIncentive);
    }

    ///////////////////////////////
    //////////// VIEWS ////////////
    ///////////////////////////////

    function getProposal(bytes32 outputRoot, uint256 index) public view returns (ProposalData memory) {
        return proposals[outputRoot][index];
    }

    function isFinalized(ProposalState state) public pure returns (bool) {
        require(state != ProposalState.None, "proposal doesn't exist");
        return state == ProposalState.Confirmed || state == ProposalState.Rejected;
    }

    function isValidProposal(bytes32 outputRoot, uint256 index) public view returns (bool) {
        require(!emergencyShutdown, "emergency shutdown");
        return proposals[outputRoot][index].state == ProposalState.Confirmed;
    }
}
