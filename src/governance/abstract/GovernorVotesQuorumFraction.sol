// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

import {GovernorVotes} from "./GovernorVotes.sol";

abstract contract GovernorVotesQuorumFraction is GovernorVotes {
    uint256 private _quorumNumerator;

    /* --------------------------------- EVENTS --------------------------------- */
    event QuorumNumeratorUpdated(
        uint256 oldQuorumNumerator,
        uint256 newQuorumNumerator
    );

    constructor(uint256 _quorumNumerator_) {
        _quorumNumerator = _quorumNumerator_;
    }

    function quorumNumerator() public view virtual returns (uint256) {
        return _quorumNumerator;
    }
    function quorumDenominator() public pure virtual returns (uint256) {
        return 100;
    }

    function quorum(
        uint256 blockNumber
    ) public view virtual override returns (uint256) {
        return
            (quorumNumerator() * token.getPastTotalSupply(blockNumber)) /
            quorumDenominator();
    }

    function updateQuorumNumerator(
        uint256 _newQuorumNumerator
    ) external virtual onlyGovernance {
        _updateQuorumNumerator(_newQuorumNumerator);
    }

    /* --------------------------- INTERNAL FUNCTIONS --------------------------- */
    function _updateQuorumNumerator(
        uint256 _newQuorumNumerator
    ) internal virtual {
        require(
            _newQuorumNumerator <= quorumDenominator(),
            "GovernorVotesQuorumFraction: quorumNumerator > quorumDenominator"
        );

        uint256 oldQuorumNumerator = _quorumNumerator;
        _quorumNumerator = _newQuorumNumerator;

        emit QuorumNumeratorUpdated(oldQuorumNumerator, _newQuorumNumerator);
    }
}
