// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

import {IMinter} from "./interfaces/IMinter.sol";
import {IZodiac} from "./interfaces/IZodiac.sol";
import {ISnake} from "./interfaces/ISnake.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";
import {IRewardsDistributor} from "./interfaces/IRewardsDistributor.sol";

contract Minter is IMinter {
    uint256 internal constant WEEK = 7 * 24 * 60 * 60; // 1 week
    uint256 internal constant PRECISION = 1000;

    // @dev This is the alternative token for reward distribution
    // IZodiac public immutable zodiac;
    ISnake public immutable snake;
    IVoter public immutable voter;
    IVotingEscrow public immutable votingEscrow;
    IRewardsDistributor[] public rewardsDistributors;

    uint256 public weeklyPerGauge = 2000 * 1e18; // 2000 ZDC
    uint256 public activePeriod;

    address internal initializer;
    address public team;
    address public teamEmissions;
    uint256 public teamRate;

    uint256 public constant MAX_TEAM_RATE = 50; // 5%

    struct Claim {
        address claimant;
        uint256 amount;
        uint256 lockTime;
    }

    /* --------------------------------- EVENTS --------------------------------- */
    event Mint(
        address indexed sender,
        uint256 weekly,
        uint256 circulatingSupply
    );
    event EmissionPerGaugeSet(uint256 newEmissionPerGauge);

    constructor(
        address _voter,
        address _votingEscrow,
        address _rewardsDistributor
    ) {
        initializer = msg.sender;
        team = msg.sender;
        teamRate = 30; // 3%
        // zodiac = IZodiac(IVotingEscrow(_votingEscrow).zodiac()); // Option
        snake = ISnake(IVotingEscrow(_votingEscrow).token());
        voter = IVoter(_voter);
        votingEscrow = IVotingEscrow(_votingEscrow);
        rewardsDistributors.push(IRewardsDistributor(_rewardsDistributor));
        activePeriod = ((block.timestamp + (2 * WEEK)) / WEEK) * WEEK; // 2 weeks from the current week starting
    }

    function startActivePeriod() external {
        require(msg.sender == initializer, "Minter: FORBIDDEN");
        initializer = address(0);
        activePeriod = (block.timestamp / WEEK) * WEEK;
    }

    function setTeam(address _team) external {
        require(msg.sender == team, "Minter: FORBIDDEN");
        team = _team;
    }

    function setTeamRate(uint256 _teamRate) external {
        require(msg.sender == team, "Minter: FORBIDDEN");
        require(_teamRate <= MAX_TEAM_RATE, "Minter: INVALID_RATE");
        teamRate = _teamRate;
    }

    function setTeamEmissionAddress(address _teamEmissions) external {
        require(msg.sender == team, "Minter: FORBIDDEN");
        teamEmissions = _teamEmissions;
    }

    function setWeeklyEmissionPerGauge(uint256 _weeklyPerGauge) external {
        require(msg.sender == team, "Minter: FORBIDDEN");
        weeklyPerGauge = _weeklyPerGauge;
        emit EmissionPerGaugeSet(_weeklyPerGauge);
    }

    function updatePeriod() external override returns (uint256) {
        uint256 _period = activePeriod;
        // new week
        if (block.timestamp >= _period + WEEK && initializer == address(0)) {
            _period = (block.timestamp / WEEK) * WEEK;
            activePeriod = _period;
            uint256 _weeklyEmission = weeklyEmission();
            uint256 _teamEmissions = (teamRate * _weeklyEmission) /
                (PRECISION - teamRate);
            uint256 _required = _weeklyEmission + _teamEmissions;
            uint256 _balanceOf = snake.balanceOf(address(this));
            if (_balanceOf < _required) {
                snake.mint(address(this), _required - _balanceOf);
            }

            require(snake.transfer(teamEmissions, _teamEmissions));
            _checkpointRewardsDistributors();
            snake.approve(address(voter), _weeklyEmission);
            voter.notifyRewardAmount(_weeklyEmission);

            emit Mint(msg.sender, _weeklyEmission, circulatingSupply());
        }
        return _period;
    }

    function addRewardsDistributor(address _rewardsDistributor) external {
        require(msg.sender == team, "Minter: FORBIDDEN");
        rewardsDistributors.push(IRewardsDistributor(_rewardsDistributor));
    }

    function removeRewardsDistributor(uint256 index) external {
        require(msg.sender == team, "Minter: FORBIDDEN");
        rewardsDistributors[index] = rewardsDistributors[
            rewardsDistributors.length - 1
        ];
        rewardsDistributors.pop();
    }

    /* ----------------------------- VIEW FUNCTIONS ----------------------------- */
    function circulatingSupply() public view returns (uint256) {
        return snake.totalSupply() - votingEscrow.totalSupply();
    }

    function weeklyEmission() public view returns (uint256) {
        uint256 numberOfGauges = voter.activeGaugeNumber();
        if (numberOfGauges == 0) {
            return weeklyPerGauge;
        }
        return weeklyPerGauge * numberOfGauges;
    }

    function calculateGrowth(uint256 _minted) public view returns (uint256) {
        return 0;
    }
    /* --------------------------- INTERNAL FUNCTIONS --------------------------- */
    function _checkpointRewardsDistributors() internal {
        for (uint256 i = 0; i < rewardsDistributors.length; i++) {
            rewardsDistributors[i].checkpoint_token();
            rewardsDistributors[i].checkpoint_total_supply();
        }
    }
}
