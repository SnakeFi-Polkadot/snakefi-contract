// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

import {Governor} from "./Governor.sol";

abstract contract GovernorCountingSimple is Governor {
    enum VoteType {
        Against,
        For,
        Abstain
    }

    struct ProposalVote {
        uint256 againstVotes;
        uint256 forVotes;
        uint256 abstainVotes;
        mapping(address => bool) hasVoted;
    }

    mapping(uint256 => ProposalVote) internal _proposalVotes;

    function COUNTING_MODE()
        public
        pure
        virtual
        override
        returns (string memory)
    {
        return "support=bravo&quorum=for,abstain";
    }

    function hasVoted(
        uint256 _proposalId,
        address _account
    ) public view virtual override returns (bool) {
        return _proposalVotes[_proposalId].hasVoted[_account];
    }

    function proposalVotes(
        uint256 _proposalId
    )
        public
        view
        virtual
        returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes)
    {
        ProposalVote storage proposalVote = _proposalVotes[_proposalId];
        return (
            proposalVote.againstVotes,
            proposalVote.forVotes,
            proposalVote.abstainVotes
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                             INTERNAL FUNCTIONS                             */
    /* -------------------------------------------------------------------------- */
    function _quorumReached(
        uint256 _proposalId
    ) internal view virtual override returns (bool) {
        ProposalVote storage proposalVote = _proposalVotes[_proposalId];
        return
            quorum(proposalSnapshot(_proposalId)) <=
            proposalVote.forVotes + proposalVote.abstainVotes;
    }

    function _voteSucceeded(
        uint256 _proposalId
    ) internal view virtual override returns (bool) {
        ProposalVote storage proposalVote = _proposalVotes[_proposalId];
        return proposalVote.forVotes > proposalVote.againstVotes;
    }

    function _countVote(
        uint256 _proposalId,
        address _account,
        uint8 _support,
        uint256 _weight,
        bytes memory // _params
    ) internal virtual override returns (uint256) {
        ProposalVote storage proposalVote = _proposalVotes[_proposalId];

        require(
            !proposalVote.hasVoted[_account],
            "Governor: account has already voted"
        );
        proposalVote.hasVoted[_account] = true;

        if (_support == uint8(VoteType.Against)) {
            proposalVote.againstVotes += _weight;
        } else if (_support == uint8(VoteType.For)) {
            proposalVote.forVotes += _weight;
        } else if (_support == uint8(VoteType.Abstain)) {
            proposalVote.abstainVotes += _weight;
        } else {
            revert("Governor: invalid vote type");
        }

        return _weight;
    }
}
