// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { MultiproofOracle } from "src/MultiproofOracle.sol";
import { MockProver } from "src/mocks/MockProver.sol";
import { IProver } from "src/interfaces/IProver.sol";
import { IMultiproofOracle } from "src/interfaces/IMultiproofOracle.sol";
import { console } from "forge-std/Test.sol";
import { BaseTest } from "./BaseTest.t.sol";

contract MultiproofOracleTest is BaseTest {
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    // TODO: write tests of e2e withdrawal
    // - propose output root
    // - prove withdrawal
    // - finalize withdrawal fails
    // - wait for output root & finalize on oracle
    // - finalize withdrawal succeed
}
