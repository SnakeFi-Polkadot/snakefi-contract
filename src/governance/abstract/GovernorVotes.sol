// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

import {Governor} from "./Governor.sol";

abstract contract GovernorVotes is Governor {
    IVotes public immutable token;

    constructor(IVotes _token) {
        token = _token;
    }

    function _getVotes(
        address _account,
        uint256 _blockNumber,
        bytes memory // _params
    ) internal view virtual override returns (uint256) {
        return token.getPastVotes(_account, _blockNumber);
    }
}
