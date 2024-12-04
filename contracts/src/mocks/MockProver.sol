// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IProver } from "src/interfaces/IProver.sol";
import { IMultiproofOracle } from "src/interfaces/IMultiproofOracle.sol";

contract MockProver is IProver {
    function encode(IMultiproofOracle.PublicValuesStruct memory publicValues) external pure override returns (bytes memory) {
        return abi.encode(publicValues);
    }

    function verify(bytes memory publicValues, bytes memory proof) external view returns (bool) {
        if (proof.length == 0) {
            return false;
        }
        return true;
    }
}
