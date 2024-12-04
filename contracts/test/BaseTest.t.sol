// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { MultiproofOracle } from "src/MultiproofOracle.sol";
import { MockProver } from "src/mocks/MockProver.sol";
import { IVerifier } from "src/interfaces/IVerifier.sol";
import { IMultiproofOracle } from "src/interfaces/IMultiproofOracle.sol";
import { Test, console } from "forge-std/Test.sol";

contract BaseTest is Test {
    MultiproofOracle public oracle;
    IMultiproofOracle.Challenge public anchor;

    function setUp() public {
        IVerifier[] memory verifiers = new IVerifier[](3);
        for (uint i = 0; i < verifiers.length; i++) {
            verifiers[i] = IVerifier(address(new MockProver()));
        }

        // set based on defaults here:
        // https://docs.google.com/spreadsheets/d/1csqvtQxZNtQxwJ72du3oy5BVA54gGalmNDK0lA6h2Gc/edit?gid=0#gid=0
        IMultiproofOracle.ImmutableArgs memory args = IMultiproofOracle.ImmutableArgs({
            proposalBond: uint88(3 ether),
            challengeTime: uint40(12 hours),
            proofReward: uint88(1 ether),
            provingTime: uint40(1 days),
            proverFeePctWad: uint64(0.5e18),
            challengedFeePctWad: uint64(0.5e18),
            treasury: address(makeAddr("treasury")),
            emergencyPauseThreshold: uint16(200),
            emergencyPauseTime: uint40(10 days),
            rollupConfigHash: bytes32(0),
            vkey: bytes32(0)
        });
        oracle = new MultiproofOracle(verifiers, 0, bytes32(0), args);
        vm.deal(address(oracle), 100 ether);

        anchor = IMultiproofOracle.Challenge({
            outputRoot: bytes32(0),
            index: 0
        });
    }
}
