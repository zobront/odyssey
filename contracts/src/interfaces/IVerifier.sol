// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IMultiproofOracle } from "./IMultiproofOracle.sol";

interface IVerifier {
    function encode(IMultiproofOracle.PublicValuesStruct memory publicValues) external pure returns (bytes memory);
    function verify(bytes memory publicValues, bytes memory proof) external view returns (bool);
}
