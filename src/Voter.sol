// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

import {IVoter} from "./interfaces/IVoter.sol";

contract Voter {
    address public immutable VOTING_ESCROW;

    address public immutable votingEscrowToken;

    // Array of the pair factories consists of the external protocol factories as well
    address[] public factories;
    address[] public gaugeFactories;

    address public bribeFactory;

    constructor(address _ve, address _votingEscrowToken) {
        VOTING_ESCROW = _ve;
        votingEscrowToken = _votingEscrowToken;
    }
}
