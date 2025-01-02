// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Bribe is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Reward {
        uint256 periodFinish;
        uint256 rewardPerEpoch;
        uint256 updateTime;
    }

    uint256 public constant DURATION = 7 * 24 * 60 * 60; // 1 week
    uint256 public firstBribeTimestamp;

    mapping(address => mapping(uint256 => Reward)) public rewards;
    mapping(address => bool) public isRewardToken;

    address[] public rewardTokens;
    address public voter;
    address public immutable bribeFactory;
    address public minter;
    address public immutable VotingEscrow;
    address public owner;

    string public TYPE;

    // owner -> reward token -> last update time
    mapping(address => mapping(address => uint256))
        public userRewardPerTokenPaid;
    mapping(address => mapping(address => uint256)) public userTimestamp;

    mapping(uint256 => uint256) private _totalSupply;
    // owner -> timestamp -> balance
    mapping(address => mapping(uint256 => uint256)) private _balances;

    constructor(
        address _owner,
        address _voter,
        address _bribeFactory,
        string memory _type
    ) {
        require(
            _bribeFactory != address(0) &&
                _voter != address(0) &&
                _owner != address(0),
            "Bribe: zero address"
        );
        voter = _voter;
        bribeFactory = _bribeFactory;
        owner = _owner;
        TYPE = _type;
    }

    /* -------------------------------------------------------------------------- */
    /*                               VIEW FUNCTIONS                               */
    /* -------------------------------------------------------------------------- */

    // TODO
    // function getEpochStart()

    /* -------------------------------------------------------------------------- */
    /*                             EXTERNAL FUNCTIONS                             */
    /* -------------------------------------------------------------------------- */

    /* -------------------------------------------------------------------------- */
    /*                             INTERNAL FUNCTIONS                             */
    /* -------------------------------------------------------------------------- */
}
