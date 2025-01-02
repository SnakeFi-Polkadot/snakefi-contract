// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

import {IVoter} from "./interfaces/IVoter.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";

contract Bribe is ReentrancyGuard {
    address public immutable voter;
    address public immutable VOTING_ESCROW;

    uint256 public constant DURATION = 7 * 24 * 60 * 60; // 7 days
    uint256 public constant MAX_REWARD_TOKENS = 16;

    uint256 public totalSupply;
    mapping(uint256 => uint256) public balanceOf;
    mapping(address => mapping(uint256 => uint256)) public tokenRewardsPerEpoch;
    mapping(address => uint256) public periodFinish;
    mapping(address => mapping(uint256 => uint256)) public lastEarn;

    address[] public rewardTokens;
    mapping(address => bool) public isRewardToken;

    struct Checkpoint {
        uint256 timestamp;
        uint256 balanceOf;
    }

    struct SupplyCheckpoint {
        uint256 timestamp;
        uint256 supply;
    }

    mapping(uint256 => mapping(uint256 => Checkpoint)) public checkpoints;
    mapping(uint256 => uint256) public numCheckpoints;
    mapping(uint256 => SupplyCheckpoint) public supplyCheckpoints;
    uint256 public supplyNumCheckpoints;

    /* --------------------------------- EVENTS --------------------------------- */
    event Deposit(address indexed from, uint256 tokenId, uint256 amount);
    event Withdraw(address indexed from, uint256 tokenId, uint256 amount);
    event NotifyReward(
        address indexed from,
        address indexed reward,
        uint256 epoch,
        uint256 amount
    );
    event ClaimRewards(
        address indexed from,
        address indexed reward,
        uint256 amount
    );
    event HandleLeftOverRewards(
        address indexed reward,
        uint256 originalEpoch,
        uint256 updatedEpoch,
        uint256 amount
    );

    constructor(address _voter, address[] memory _allowedRewardTokens) {
        voter = _voter;
        VOTING_ESCROW = IVoter(_voter).VOTING_ESCROW();

        for (uint256 i = 0; i < _allowedRewardTokens.length; i++) {
            if (_allowedRewardTokens[i] != address(0)) {
                rewardTokens.push(_allowedRewardTokens[i]);
                isRewardToken[_allowedRewardTokens[i]] = true;
            }
        }
    }

    uint8 internal _unlock = 1;
    modifier lock() {
        require(_unlock == 1, "Bribe: LOCKED");
        _unlock = 2;
        _;
        _unlock = 1;
    }

    /* -------------------------------------------------------------------------- */
    /*                               VIEW FUNCTIONS                               */
    /* -------------------------------------------------------------------------- */

    function getEpochStart(uint256 timestamp) public pure returns (uint256) {
        uint256 bribeStart = _bribeStart(timestamp);
        uint256 bribeEnd = bribeStart + DURATION;

        return timestamp < bribeEnd ? bribeStart : bribeStart + DURATION;
    }

    function getPriorBalanceIndex(
        uint256 tokenId,
        uint256 timestamp
    ) public view returns (uint256) {
        uint256 nCheckpoints = numCheckpoints[tokenId];
        if (nCheckpoints == 0) {
            return 0;
        }
        // First check most recent balance
        if (checkpoints[tokenId][nCheckpoints - 1].timestamp <= timestamp) {
            return (nCheckpoints - 1);
        }
        // Next check implicit zero balance
        if (checkpoints[tokenId][0].timestamp > timestamp) {
            return 0;
        }

        uint256 lower = 0;
        uint256 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[tokenId][center];
            if (cp.timestamp == timestamp) {
                return center;
            } else if (cp.timestamp < timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    function getPriorSupplyIndex(
        uint256 timestamp
    ) public view returns (uint256) {
        uint256 nCheckpoints = supplyNumCheckpoints;
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (supplyCheckpoints[nCheckpoints - 1].timestamp <= timestamp) {
            return (nCheckpoints - 1);
        }

        // Next check implicit zero balance
        if (supplyCheckpoints[0].timestamp > timestamp) {
            return 0;
        }

        uint256 lower = 0;
        uint256 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            SupplyCheckpoint memory cp = supplyCheckpoints[center];
            if (cp.timestamp == timestamp) {
                return center;
            } else if (cp.timestamp < timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    function rewardsListLength() external view returns (uint256) {
        return rewardTokens.length;
    }

    // returns the last time the reward was modified or periodFinish if the reward has ended
    function lastTimeRewardApplicable(
        address token
    ) public view returns (uint256) {
        return FixedPointMathLib.min(block.timestamp, periodFinish[token]);
    }

    function earned(
        address token,
        uint256 tokenId
    ) public view returns (uint256) {
        if (numCheckpoints[tokenId] == 0) {
            return 0;
        }

        uint256 reward = 0;
        uint256 _bal = 0;
        uint256 _supply = 1;
        uint256 _index = 0;
        uint256 _currTs = _bribeStart(lastEarn[token][tokenId]); // take epoch last claimed in as starting point

        _index = getPriorBalanceIndex(tokenId, _currTs);

        // accounts for case where lastEarn is before first checkpoint
        _currTs = FixedPointMathLib.max(
            _currTs,
            _bribeStart(checkpoints[tokenId][_index].timestamp)
        );

        // get epochs between current epoch and first checkpoint in same epoch as last claim
        uint256 numEpochs = (_bribeStart(block.timestamp) - _currTs) / DURATION;

        if (numEpochs > 0) {
            for (uint256 i = 0; i < numEpochs; i++) {
                // get index of last checkpoint in this epoch
                _index = getPriorBalanceIndex(tokenId, _currTs + DURATION);
                // get checkpoint in this epoch
                _bal = checkpoints[tokenId][_index].balanceOf;
                // get supply of last checkpoint in this epoch
                _supply = supplyCheckpoints[
                    getPriorSupplyIndex(_currTs + DURATION)
                ].supply;
                if (_supply != 0) {
                    reward +=
                        (_bal * tokenRewardsPerEpoch[token][_currTs]) /
                        _supply;
                }
                _currTs += DURATION;
            }
        }

        return reward;
    }

    function left(address token) external view returns (uint256) {
        uint256 adjustedTstamp = getEpochStart(block.timestamp);
        return tokenRewardsPerEpoch[token][adjustedTstamp];
    }

    /* -------------------------------------------------------------------------- */
    /*                             EXTERNAL FUNCTIONS                             */
    /* -------------------------------------------------------------------------- */

    // allows a user to claim rewardTokens for a given token
    function getReward(uint256 tokenId, address[] memory tokens) external lock {
        require(
            IVotingEscrow(VOTING_ESCROW).isApprovedOrOwner(msg.sender, tokenId)
        );
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 _reward = earned(tokens[i], tokenId);
            lastEarn[tokens[i]][tokenId] = block.timestamp;
            if (_reward > 0) _safeTransfer(tokens[i], msg.sender, _reward);

            emit ClaimRewards(msg.sender, tokens[i], _reward);
        }
    }

    // used by Voter to allow batched reward claims
    function getRewardForOwner(
        uint256 tokenId,
        address[] memory tokens
    ) external lock {
        require(msg.sender == voter);
        address _owner = IVotingEscrow(VOTING_ESCROW).ownerOf(tokenId);
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 _reward = earned(tokens[i], tokenId);
            lastEarn[tokens[i]][tokenId] = block.timestamp;
            if (_reward > 0) _safeTransfer(tokens[i], _owner, _reward);

            emit ClaimRewards(_owner, tokens[i], _reward);
        }
    }

    function notifyRewardAmount(address token, uint256 amount) external lock {
        require(amount > 0);
        if (!isRewardToken[token]) {
            require(
                IVoter(voter).isWhitelisted(token),
                "bribe tokens must be whitelisted"
            );
            require(
                rewardTokens.length < MAX_REWARD_TOKENS,
                "too many rewardTokens tokens"
            );
        }
        // bribes kick in at the start of next bribe period
        uint256 adjustedTstamp = getEpochStart(block.timestamp);
        uint256 epochRewards = tokenRewardsPerEpoch[token][adjustedTstamp];

        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        _safeTransferFrom(token, msg.sender, address(this), amount);
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));

        amount = balanceAfter - balanceBefore;

        tokenRewardsPerEpoch[token][adjustedTstamp] = epochRewards + amount;

        periodFinish[token] = adjustedTstamp + DURATION;

        if (!isRewardToken[token]) {
            isRewardToken[token] = true;
            rewardTokens.push(token);
        }

        emit NotifyReward(msg.sender, token, adjustedTstamp, amount);
    }

    // This is an external function that can only be called by teams to handle unclaimed rewardTokens due to zero vote
    function handleLeftOverRewards(
        uint256 epochTimestamp,
        address[] memory tokens
    ) external {
        require(msg.sender == IVotingEscrow(VOTING_ESCROW).team(), "only team");

        // require that supply of that epoch to be ZERO
        uint256 epochStart = getEpochStart(epochTimestamp);
        SupplyCheckpoint memory sp0 = supplyCheckpoints[
            getPriorSupplyIndex(epochStart + DURATION)
        ];
        if (epochStart + DURATION > _bribeStart(sp0.timestamp)) {
            require(sp0.supply == 0, "this epoch has votes");
        }

        // do sth like notifyRewardAmount
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; ) {
            // check bribe amount
            uint256 previousEpochRewards = tokenRewardsPerEpoch[tokens[i]][
                epochStart
            ];
            require(previousEpochRewards != 0, "no bribes for this epoch");

            // get timestamp of current epoch
            uint256 adjustedTstamp = getEpochStart(block.timestamp);

            // get notified reward of current epoch
            uint256 currentEpochRewards = tokenRewardsPerEpoch[tokens[i]][
                adjustedTstamp
            ];

            // add previous unclaimed rewardTokens to current epoch
            tokenRewardsPerEpoch[tokens[i]][adjustedTstamp] =
                currentEpochRewards +
                previousEpochRewards;

            // remove token rewardTokens from previous epoch
            tokenRewardsPerEpoch[tokens[i]][epochStart] = 0;

            // amend period finish
            periodFinish[tokens[i]] = adjustedTstamp + DURATION;

            emit HandleLeftOverRewards(
                tokens[i],
                epochStart,
                adjustedTstamp,
                previousEpochRewards
            );

            unchecked {
                ++i;
            }
        }
    }

    function swapOutRewardToken(
        uint256 i,
        address oldToken,
        address newToken
    ) external {
        require(msg.sender == IVotingEscrow(VOTING_ESCROW).team(), "only team");
        require(rewardTokens[i] == oldToken);
        isRewardToken[oldToken] = false;
        isRewardToken[newToken] = true;
        rewardTokens[i] = newToken;
    }

    /* -------------------------------------------------------------------------- */
    /*                             INTERNAL FUNCTIONS                             */
    /* -------------------------------------------------------------------------- */

    function _bribeStart(uint256 timestamp) internal pure returns (uint256) {
        return timestamp - (timestamp % DURATION);
    }

    function _writeCheckpoint(uint256 tokenId, uint256 balance) internal {
        uint256 _timestamp = block.timestamp;
        uint256 _nCheckPoints = numCheckpoints[tokenId];
        if (
            _nCheckPoints > 0 &&
            checkpoints[tokenId][_nCheckPoints - 1].timestamp == _timestamp
        ) {
            checkpoints[tokenId][_nCheckPoints - 1].balanceOf = balance;
        } else {
            checkpoints[tokenId][_nCheckPoints] = Checkpoint(
                _timestamp,
                balance
            );
            numCheckpoints[tokenId] = _nCheckPoints + 1;
        }
    }

    function _writeSupplyCheckpoint() internal {
        uint256 _nCheckPoints = supplyNumCheckpoints;
        uint256 _timestamp = block.timestamp;

        if (
            _nCheckPoints > 0 &&
            supplyCheckpoints[_nCheckPoints - 1].timestamp == _timestamp
        ) {
            supplyCheckpoints[_nCheckPoints - 1].supply = totalSupply;
        } else {
            supplyCheckpoints[_nCheckPoints] = SupplyCheckpoint(
                _timestamp,
                totalSupply
            );
            supplyNumCheckpoints = _nCheckPoints + 1;
        }
    }

    // This is an external function, but internal notation is used since it can only be called "internally" from Gauges
    function _deposit(uint256 amount, uint256 tokenId) external {
        require(msg.sender == voter);

        totalSupply += amount;
        balanceOf[tokenId] += amount;

        _writeCheckpoint(tokenId, balanceOf[tokenId]);
        _writeSupplyCheckpoint();

        emit Deposit(msg.sender, tokenId, amount);
    }

    function _withdraw(uint256 amount, uint256 tokenId) external {
        require(msg.sender == voter);

        totalSupply -= amount;
        balanceOf[tokenId] -= amount;

        _writeCheckpoint(tokenId, balanceOf[tokenId]);
        _writeSupplyCheckpoint();

        emit Withdraw(msg.sender, tokenId, amount);
    }

    function _safeTransfer(address token, address to, uint256 value) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                from,
                to,
                value
            )
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }
}
