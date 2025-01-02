// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ISnakePair} from "./interfaces/ISnakePair.sol";
import {IBribe} from "./interfaces/IBribe.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";

contract Gauge is Ownable, ReentrancyGuard {
    using FixedPointMathLib for uint256;

    uint256 internal constant DURATAION = 7 * 24 * 60 * 60; // 7 days
    uint256 internal constant PRECISION = 10 ** 18;
    uint256 internal constant MAX_REWARD_TOKENS = 6;

    // This lp token is used to stake for rewards
    address public immutable lpToken;
    // The ve token used for gauges
    address public immutable VOTING_ESCROW;
    address public immutable externalBribe;
    address public immutable voter;
    address public immutable snake; // Snake token
    address public immutable gaugeFactory;

    struct Checkpoint {
        uint256 timestamp;
        uint256 balanceOf;
    }

    struct RewardPerTokenCheckpoint {
        uint256 timestamp;
        uint256 rewardPerToken;
    }

    struct SupplyCheckpoint {
        uint256 timestamp;
        uint256 supply;
    }

    // This is the rewarder contract that will be used to distribute rewards
    address public snakeZodiac;

    uint256 public derivedSupply;
    mapping(address => uint256) public derivedBalances;

    bool public isForPair; // Used to track the type of gauge

    uint256 public fees0;
    uint256 public fees1;

    mapping(address => uint256) public rewardRate;
    mapping(address => uint256) public periodFinish;
    mapping(address => uint256) public lastUpdateTime;
    mapping(address => uint256) public rewardPerTokenStored;

    mapping(address => mapping(address => uint256)) public lastEarns;
    mapping(address => mapping(address => uint256))
        public userRewardPerTokenStored;

    mapping(address => uint256) public tokenIds;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public balanceWithLock;
    mapping(address => uint256) public lockEnd;

    address[] public rewardTokens;
    mapping(address => bool) public isReward;
    mapping(address => bool) public isZodiacToken;

    mapping(address => mapping(uint256 => Checkpoint)) public checkpoints;
    mapping(address => uint256) public checkpointsLength;
    mapping(uint256 => SupplyCheckpoint) public supplyCheckpoints;
    uint256 public supplyCheckpointsLength;
    mapping(address => mapping(uint256 => RewardPerTokenCheckpoint))
        public rewardPerTokenCheckpoints;
    mapping(address => uint256) public rewardPerTokenCheckpointsLength;

    /* --------------------------------- EVENTS --------------------------------- */
    event Deposit(address indexed from, uint256 tokenId, uint256 amount);
    event Withdraw(address indexed from, uint256 tokenId, uint256 amount);
    event NotifyReward(
        address indexed from,
        address indexed reward,
        uint256 amount
    );
    event ClaimRewards(
        address indexed from,
        address indexed reward,
        uint256 amount
    );
    event SnakeSet(address indexed _snake);
    event ZodiacTokenAdded(address indexed _zodiac);
    event ZodiacTokenRemoved(address indexed _zodiac);

    constructor(
        address _lpToken,
        address _externalBribe,
        address _ve,
        address _voter,
        address _snakeZodiac,
        address _gaugeFactory,
        bool _isForPair,
        address[] memory _allowedRewardTokens
    ) Ownable(msg.sender) {
        lpToken = _lpToken;
        externalBribe = _externalBribe;
        VOTING_ESCROW = _ve;
        voter = _voter;
        snakeZodiac = _snakeZodiac;
        gaugeFactory = _gaugeFactory;
        isForPair = _isForPair;
        snake = IVotingEscrow(_ve).token();
        _safeApprove(snake, snakeZodiac, type(uint256).max);
        isZodiacToken[snakeZodiac] = true;

        for (uint256 i = 0; i < _allowedRewardTokens.length; i++) {
            if (_allowedRewardTokens[i] != address(0)) {
                isReward[_allowedRewardTokens[i]] = true;
                rewardTokens.push(_allowedRewardTokens[i]);
            }
        }
    }

    // Start with 1 as gas saving
    uint8 internal _unlocked = 1;
    modifier lock() {
        require(_unlocked == 1, "Gauge: LOCKED");
        _unlocked = 2;
        _;
        _unlocked = 1;
    }

    // function claimFees() external lock returns (uint256, uint256) {
    //     return _claimFees();
    // }

    function getReward(address account, address[] memory tokens) external lock {
        require(msg.sender == account || msg.sender == voter);
        _unlocked = 1;
        IVoter(voter).distribute(address(this));
        _unlocked = 2;

        for (uint256 i = 0; i < tokens.length; i++) {
            (
                rewardPerTokenStored[tokens[i]],
                lastUpdateTime[tokens[i]]
            ) = _updateRewardPerToken(tokens[i], type(uint256).max, true);

            uint256 _reward = earned(tokens[i], account);
            lastEarns[tokens[i]][account] = block.timestamp;
            userRewardPerTokenStored[tokens[i]][account] = rewardPerTokenStored[
                tokens[i]
            ];
            if (_reward > 0) _safeTransfer(tokens[i], account, _reward);

            emit ClaimRewards(msg.sender, tokens[i], _reward);
        }

        uint256 _derivedBalance = derivedBalances[account];
        derivedSupply -= _derivedBalance;
        _derivedBalance = derivedBalance(account);
        derivedBalances[account] = _derivedBalance;
        derivedSupply += _derivedBalance;

        _writeCheckpoint(account, derivedBalance(account));
        _writeSupplyCheckpoint();
    }

    function batchRewardPerToken(address token, uint256 maxRuns) external {
        (
            rewardPerTokenStored[token],
            lastUpdateTime[token]
        ) = _batchRewardPerToken(token, maxRuns);
    }

    function batchUpdateRewardPerToken(
        address token,
        uint256 maxRuns
    ) external {
        (
            rewardPerTokenStored[token],
            lastUpdateTime[token]
        ) = _updateRewardPerToken(token, maxRuns, false);
    }

    function depositWithLock(
        address account,
        uint256 amount,
        uint256 lockDuration
    ) external lock {
        // Only allow the self account or zodiac token to deposit with lock
        require(
            msg.sender == account || isZodiacToken[msg.sender],
            "Not allowed to deposit with lock"
        );
        _deposit(account, amount, 0);
        // if (block.timestamp >= lock)
    }

    function depositAll(uint256 tokenId) external {
        deposit(IERC20(lpToken).balanceOf(msg.sender), tokenId);
    }

    function deposit(uint256 amount, uint256 tokenId) public lock {
        _deposit(msg.sender, amount, tokenId);
    }

    function depositFor(address account, uint256 amount) public lock {
        _deposit(account, amount, 0);
    }

    function withdrawAll() external {
        withdraw(balanceOf[msg.sender]);
    }

    function withdraw(uint256 amount) public {
        uint256 tokenId = 0;
        if (amount == balanceOf[msg.sender]) {
            tokenId = tokenIds[msg.sender];
        }
        withdrawToken(amount, tokenId);
    }

    function withdrawToken(uint256 amount, uint256 tokenId) public lock {
        _updateRewardForAllTokens();

        totalSupply -= amount;
        balanceOf[msg.sender] -= amount;
        _safeTransfer(lpToken, msg.sender, amount);

        if (tokenId > 0) {
            require(tokenId == tokenIds[msg.sender]);
            tokenIds[msg.sender] = 0;
            IVoter(voter).detachTokenFromGauge(tokenId, msg.sender);
        } else {
            tokenId = tokenIds[msg.sender];
        }

        uint256 _derivedBalance = derivedBalances[msg.sender];
        derivedSupply -= _derivedBalance;
        _derivedBalance = derivedBalance(msg.sender);
        derivedBalances[msg.sender] = _derivedBalance;
        derivedSupply += _derivedBalance;

        _writeCheckpoint(msg.sender, derivedBalances[msg.sender]);
        _writeSupplyCheckpoint();

        IVoter(voter).emitWithdraw(tokenId, msg.sender, amount);
        emit Withdraw(msg.sender, tokenId, amount);
    }

    function notifyRewardAmount(address token, uint256 amount) external lock {
        require(token != lpToken);
        require(amount > 0);
        if (!isReward[token]) {
            require(
                IVoter(voter).isWhitelisted(token),
                "reward tokens must be whitelisted"
            );
            require(
                rewardTokens.length < MAX_REWARD_TOKENS,
                "reward tokens must be less than 16"
            );
        }

        if (rewardRate[token] == 0) {
            _writeRewardPerTokenCheckpoint(token, 0, block.timestamp);
        }
        (
            rewardPerTokenStored[token],
            lastUpdateTime[token]
        ) = _updateRewardPerToken(token, type(uint256).max, true);
        // _claimFees();

        if (block.timestamp >= periodFinish[token]) {
            _safeTransferFrom(token, msg.sender, address(this), amount);
            rewardRate[token] = amount / DURATAION;
        } else {
            uint256 _remaining = periodFinish[token] - block.timestamp;
            uint256 _left = _remaining * rewardRate[token];
            require(amount > _left);
            _safeTransferFrom(token, msg.sender, address(this), amount);
            rewardRate[token] = (amount + _left) / DURATAION;
        }
        require(rewardRate[token] > 0);
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(
            rewardRate[token] <= balance / DURATAION,
            "Provided reward too high"
        );
        periodFinish[token] = block.timestamp + DURATAION;
        if (!isReward[token]) {
            isReward[token] = true;
            rewardTokens.push(token);
        }

        emit NotifyReward(msg.sender, token, amount);
    }

    function swapOutRewardToken(
        uint256 i,
        address oldToken,
        address newToken
    ) external {
        require(msg.sender == IVotingEscrow(VOTING_ESCROW).team());
        require(rewardTokens[i] == oldToken);
        isReward[oldToken] = false;
        isReward[newToken] = true;
        rewardTokens[i] = newToken;
    }

    /* -------------------------------------------------------------------------- */
    /*                               VIEW FUNCTIONS                               */
    /* -------------------------------------------------------------------------- */

    function getPriorBalanceIndex(
        address account,
        uint256 timestamp
    ) public view returns (uint256) {
        uint256 checkpointsL = checkpointsLength[account];
        if (checkpointsL == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][checkpointsL - 1].timestamp <= timestamp) {
            return checkpointsL - 1;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].timestamp > timestamp) {
            return 0;
        }

        uint256 lower = 0;
        uint256 upper = checkpointsL - 1;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory checkpoint = checkpoints[account][center];
            if (checkpoint.timestamp == timestamp) {
                return center;
            } else if (checkpoint.timestamp < timestamp) {
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
        uint256 checkpointsL = supplyCheckpointsLength;
        if (checkpointsL == 0) {
            return 0;
        }

        // First check most recent balance
        if (supplyCheckpoints[checkpointsL - 1].timestamp <= timestamp) {
            return checkpointsL - 1;
        }

        // Next check implicit zero balance
        if (supplyCheckpoints[0].timestamp > timestamp) {
            return 0;
        }

        uint256 lower = 0;
        uint256 upper = checkpointsL - 1;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            SupplyCheckpoint memory checkpoint = supplyCheckpoints[center];
            if (checkpoint.timestamp == timestamp) {
                return center;
            } else if (checkpoint.timestamp < timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return lower;
    }

    function getPriorRewardPerToken(
        address token,
        uint256 timestamp
    ) public view returns (uint256, uint256) {
        uint256 checkpointsL = rewardPerTokenCheckpointsLength[token];
        if (checkpointsL == 0) {
            return (0, 0);
        }

        // First check most recent balance
        if (
            rewardPerTokenCheckpoints[token][checkpointsL - 1].timestamp <=
            timestamp
        ) {
            return (
                rewardPerTokenCheckpoints[token][checkpointsL - 1]
                    .rewardPerToken,
                rewardPerTokenCheckpoints[token][checkpointsL - 1].timestamp
            );
        }

        // Next check implicit zero balance
        if (rewardPerTokenCheckpoints[token][0].timestamp > timestamp) {
            return (0, 0);
        }

        uint256 lower = 0;
        uint256 upper = checkpointsL - 1;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            RewardPerTokenCheckpoint
                memory checkpoint = rewardPerTokenCheckpoints[token][center];
            if (checkpoint.timestamp == timestamp) {
                return (checkpoint.rewardPerToken, checkpoint.timestamp);
            } else if (checkpoint.timestamp < timestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return (
            rewardPerTokenCheckpoints[token][lower].rewardPerToken,
            rewardPerTokenCheckpoints[token][lower].timestamp
        );
    }

    function rewardsLength() external view returns (uint256) {
        return rewardTokens.length;
    }

    function lastTimeRewardApplicable(
        address token
    ) public view returns (uint256) {
        return FixedPointMathLib.min(block.timestamp, periodFinish[token]);
    }

    function derivedBalance(address account) public view returns (uint256) {
        return balanceOf[account];
    }

    function rewardPerToken(address token) public view returns (uint256) {
        if (derivedSupply == 0) {
            return rewardPerTokenStored[token];
        }
        return
            rewardPerTokenStored[token] +
            (((lastTimeRewardApplicable(token) -
                FixedPointMathLib.min(
                    lastUpdateTime[token],
                    periodFinish[token]
                )) *
                rewardRate[token] *
                PRECISION) / derivedSupply);
    }

    function earned(
        address token,
        address account
    ) public view returns (uint256) {
        uint256 _startTimestamp = FixedPointMathLib.max(
            lastEarns[token][account],
            rewardPerTokenCheckpoints[token][0].timestamp
        );
        if (checkpointsLength[account] == 0) {
            return 0;
        }

        uint256 _startIndex = getPriorBalanceIndex(account, _startTimestamp);
        uint256 _endIndex = checkpointsLength[account] - 1;

        uint256 reward = 0;

        if (_endIndex > 0) {
            for (uint256 i = _startIndex; i <= _endIndex - 1; i++) {
                Checkpoint memory checkpoint0 = checkpoints[account][i];
                Checkpoint memory checkpoint1 = checkpoints[account][i + 1];
                (uint256 _rewardPerTokenStored0, ) = getPriorRewardPerToken(
                    token,
                    checkpoint0.timestamp
                );
                (uint256 _rewardPerTokenStored1, ) = getPriorRewardPerToken(
                    token,
                    checkpoint1.timestamp
                );
                reward +=
                    (checkpoint0.balanceOf *
                        (_rewardPerTokenStored1 - _rewardPerTokenStored0)) /
                    PRECISION;
            }
        }

        Checkpoint memory checkpoint = checkpoints[account][_endIndex];
        (uint256 _rewardPerTokenStored, ) = getPriorRewardPerToken(
            token,
            checkpoint.timestamp
        );
        reward +=
            (checkpoint.balanceOf *
                (rewardPerToken(token) -
                    FixedPointMathLib.max(
                        _rewardPerTokenStored,
                        userRewardPerTokenStored[token][account]
                    ))) /
            PRECISION;

        return reward;
    }

    function left(address token) external view returns (uint256) {
        if (block.timestamp >= periodFinish[token]) {
            return 0;
        }
        uint256 _remaining = periodFinish[token] - block.timestamp;
        return _remaining * rewardRate[token];
    }

    /* -------------------------------------------------------------------------- */
    /*                             INTERNAL FUNCTIONS                             */
    /* -------------------------------------------------------------------------- */

    function _deposit(
        address account,
        uint256 amount,
        uint256 tokenId
    ) internal {
        require(amount > 0);
        _updateRewardForAllTokens();

        _safeTransferFrom(lpToken, msg.sender, address(this), amount);
        totalSupply += amount;
        balanceOf[account] += amount;

        if (tokenId > 0) {
            require(IVotingEscrow(VOTING_ESCROW).ownerOf(tokenId) == account);
            if (tokenIds[account] == 0) {
                tokenIds[account] = tokenId;
                IVoter(voter).attachTokenToGauge(tokenId, account);
            }
            require(tokenIds[account] == tokenId);
        } else {
            tokenId = tokenIds[account];
        }

        uint256 _derivedBalance = derivedBalances[account];
        derivedSupply -= _derivedBalance;
        _derivedBalance = derivedBalance(account);
        derivedBalances[account] = _derivedBalance;
        derivedSupply += _derivedBalance;

        _writeCheckpoint(account, _derivedBalance);
        _writeSupplyCheckpoint();

        IVoter(voter).emitDeposit(tokenId, account, amount);
        emit Deposit(account, tokenId, amount);
    }

    // function _claimFees()
    //     internal
    //     returns (uint256 claimed0, uint256 claimed1)
    // {
    //     if (!isForPair) {
    //         return (0, 0);
    //     }
    //     (claimed0, claimed1) = ISnakePair(lpToken).claimFees();
    //     if (claimed0 > 0 || claimed1 > 0) {
    //         uint256 _fees0 = fees0 + claimed0;
    //         uint256 _fees1 = fees1 + claimed1;
    //         (address _token0, address _token1) = ISnakePair(lpToken).tokens();
    //         if (
    //             _fees0 > IBribe(externalBribe).left(_token0) &&
    //             _fees0 / DURATAION > 0
    //         ) {
    //             _fees0 = 0;
    //             _safeApprove(_token0, externalBribe, _fees0);
    //             IBribe(externalBribe).notifyRewardAmount(_token0, _fees0);
    //         } else {
    //             fees0 = _fees0;
    //         }
    //         if (
    //             _fees1 > IBribe(externalBribe).left(_token1) &&
    //             _fees1 / DURATAION > 0
    //         ) {
    //             _fees1 = 0;
    //             _safeApprove(_token1, externalBribe, _fees1);
    //             IBribe(externalBribe).notifyRewardAmount(_token1, _fees1);
    //         } else {
    //             fees1 = _fees1;
    //         }
    //         emit ClaimFees(msg.sender, claimed0, claimed1);
    //     }
    // }

    function _writeCheckpoint(address account, uint256 balance) internal {
        uint256 _timestamp = block.timestamp;
        uint256 _checkpointsL = checkpointsLength[account];

        if (
            _checkpointsL > 0 &&
            checkpoints[account][_checkpointsL - 1].timestamp == _timestamp
        ) {
            checkpoints[account][_checkpointsL - 1].balanceOf = balance;
        } else {
            checkpoints[account][_checkpointsL - 1] = Checkpoint(
                _timestamp,
                balance
            );
            checkpointsLength[account] = _checkpointsL + 1;
        }
    }

    function _writeRewardPerTokenCheckpoint(
        address token,
        uint256 reward,
        uint256 timestamp
    ) internal {
        uint256 _checkpointsL = rewardPerTokenCheckpointsLength[token];

        if (
            _checkpointsL > 0 &&
            rewardPerTokenCheckpoints[token][_checkpointsL - 1].timestamp ==
            timestamp
        ) {
            rewardPerTokenCheckpoints[token][_checkpointsL - 1]
                .rewardPerToken = reward;
        } else {
            rewardPerTokenCheckpoints[token][
                _checkpointsL
            ] = RewardPerTokenCheckpoint(timestamp, reward);
            rewardPerTokenCheckpointsLength[token] = _checkpointsL + 1;
        }
    }

    function _writeSupplyCheckpoint() internal {
        uint256 _timestamp = block.timestamp;
        uint256 _checkpointsL = supplyCheckpointsLength;

        if (
            _checkpointsL > 0 &&
            supplyCheckpoints[_checkpointsL - 1].timestamp == _timestamp
        ) {
            supplyCheckpoints[_checkpointsL - 1].supply = derivedSupply;
        } else {
            supplyCheckpoints[_checkpointsL] = SupplyCheckpoint(
                _timestamp,
                derivedSupply
            );
            supplyCheckpointsLength = _checkpointsL + 1;
        }
    }

    function _batchRewardPerToken(
        address token,
        uint256 maxRuns
    ) internal returns (uint256, uint256) {
        uint256 _startTimestamp = lastUpdateTime[token];
        uint256 reward = rewardPerTokenStored[token];

        if (supplyCheckpointsLength == 0) {
            return (reward, _startTimestamp);
        }

        if (rewardRate[token] == 0) {
            return (reward, block.timestamp);
        }

        uint256 _startIndex = getPriorSupplyIndex(_startTimestamp);
        uint256 _endIndex = FixedPointMathLib.min(
            supplyCheckpointsLength - 1,
            maxRuns
        );

        for (uint256 i = _startIndex; i < _endIndex; i++) {
            SupplyCheckpoint memory supplyCheckpoint0 = supplyCheckpoints[i];
            if (supplyCheckpoint0.supply > 0) {
                SupplyCheckpoint memory supplyCheckpoint1 = supplyCheckpoints[
                    i + 1
                ];
                (uint256 _reward, uint256 _endTime) = _calcRewardPerToken(
                    token,
                    supplyCheckpoint1.timestamp,
                    supplyCheckpoint0.timestamp,
                    supplyCheckpoint0.supply,
                    _startTimestamp
                );
                reward += _reward;
                _writeRewardPerTokenCheckpoint(token, reward, _endTime);
                _startTimestamp = _endTime;
            }
        }

        return (reward, _startTimestamp);
    }

    function _calcRewardPerToken(
        address token,
        uint256 timestamp1,
        uint256 timestamp0,
        uint256 supply,
        uint256 startTimestamp
    ) internal view returns (uint256, uint256) {
        uint256 endTime = FixedPointMathLib.max(timestamp1, startTimestamp);
        return (
            ((FixedPointMathLib.min(endTime, periodFinish[token]) -
                FixedPointMathLib.min(
                    FixedPointMathLib.max(timestamp0, startTimestamp),
                    periodFinish[token]
                )) *
                rewardRate[token] *
                PRECISION) / supply,
            endTime
        );
    }

    function _updateRewardForAllTokens() internal {
        uint256 length = rewardTokens.length;
        for (uint256 i = 0; i < length; i++) {
            address token = rewardTokens[i];
            (
                rewardPerTokenStored[token],
                lastUpdateTime[token]
            ) = _updateRewardPerToken(token, type(uint256).max, true);
        }
    }

    function _updateRewardPerToken(
        address token,
        uint256 maxRuns,
        bool actualLast
    ) internal returns (uint256, uint256) {
        uint256 _startTimestamp = lastUpdateTime[token];
        uint256 reward = rewardPerTokenStored[token];

        if (supplyCheckpointsLength == 0) {
            return (reward, _startTimestamp);
        }

        if (rewardRate[token] == 0) {
            return (reward, block.timestamp);
        }

        uint256 _startIndex = getPriorSupplyIndex(_startTimestamp);
        uint256 _endIndex = FixedPointMathLib.min(
            supplyCheckpointsLength - 1,
            maxRuns
        );

        if (_endIndex > 0) {
            for (uint256 i = _startIndex; i <= _endIndex - 1; i++) {
                SupplyCheckpoint memory supplyCheckpoint0 = supplyCheckpoints[
                    i
                ];
                if (supplyCheckpoint0.supply > 0) {
                    SupplyCheckpoint
                        memory supplyCheckpoint1 = supplyCheckpoints[i + 1];
                    (uint256 _reward, uint256 _endTime) = _calcRewardPerToken(
                        token,
                        supplyCheckpoint1.timestamp,
                        supplyCheckpoint0.timestamp,
                        supplyCheckpoint0.supply,
                        _startTimestamp
                    );
                    reward += _reward;
                    _writeRewardPerTokenCheckpoint(token, reward, _endTime);
                    _startTimestamp = _endTime;
                }
            }
        }

        // need to override the last value with actual numbers only on deposit/withdraw/claim/notify actions
        if (actualLast) {
            SupplyCheckpoint memory supplyCheckpoint = supplyCheckpoints[
                _endIndex
            ];
            if (supplyCheckpoint.supply > 0) {
                (uint256 _reward, ) = _calcRewardPerToken(
                    token,
                    lastTimeRewardApplicable(token),
                    FixedPointMathLib.max(
                        supplyCheckpoint.timestamp,
                        _startTimestamp
                    ),
                    supplyCheckpoint.supply,
                    _startTimestamp
                );
                reward += _reward;
                _writeRewardPerTokenCheckpoint(token, reward, block.timestamp);
                _startTimestamp = block.timestamp;
            }
        }

        return (reward, _startTimestamp);
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

    function _safeApprove(
        address token,
        address spender,
        uint256 value
    ) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.approve.selector, spender, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }
}
