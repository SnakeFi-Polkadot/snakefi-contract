// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

import {Governor} from "./abstract/Governor.sol";
import {GovernorVotes} from "./abstract/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from "./abstract/GovernorVotesQuorumFraction.sol";
import {GovernorCountingSimple} from "./abstract/GovernorCountingSimple.sol";

contract SnakeGovernor is
    Governor,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction
{
    uint256 public constant MAX_NUMERATOR = 100; // max 10%
    uint256 public constant DENOMINATOR = 1000;
    uint256 public constant MAX_PROPOSAL_THRESHOLD = 1000;

    address public setter;
    uint256 public numerator = 3; // 0.03 %

    constructor(
        IVotes _veSnake
    )
        Governor("S_N_A_K_E__G_O_V_E_R_N_O_R")
        GovernorVotes(_veSnake)
        GovernorVotesQuorumFraction(4) // 4%
    {
        setter = msg.sender;
    }

    function votingDelay() public pure override returns (uint256) {
        return 15 * 60; // 15 minutes
    }

    function votingPeriod() public pure override returns (uint256) {
        return 7 * 24 * 60 * 60; // 7 days
    }

    function setSetter(address _setter) external {
        require(msg.sender == setter, "Not Setter");
        setter = _setter;
    }

    function setProposalNumerator(uint256 _numerator) external {
        require(msg.sender == setter, "Not Setter");
        require(numerator <= MAX_NUMERATOR, "Not Exceed max");
        numerator = _numerator;
    }

    function proposalThreshold()
        public
        view
        virtual
        override(Governor)
        returns (uint256)
    {
        return
            (token.getPastTotalSupply(block.timestamp) * numerator) /
            DENOMINATOR;
    }

    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }
}
