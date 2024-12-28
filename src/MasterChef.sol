// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

import {ISnake} from "./interfaces/ISnake.sol";

/// @title MasterChef
contract MasterChef is Ownable {
    using SafeCast for int256;
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    uint256 public constant DAY = 60 * 60 * 24;
    uint256 public constant WEEK = 7 * DAY;
    uint256 public constant WWND_PRECISION = 1e12;

    struct StakerInfo {
        uint256 amount; // The amount of tokenIds which the user has staked
        int256 rewardDebt;
        uint256[] tokenIds;
        mapping(uint256 => uint256) tokenIndicates;
    }

    struct PoolInfo {
        uint256 accRewardPerShare;
        uint256 lastRewardTime;
    }

    // This is native token
    // ISnake public snake;
    IERC20 public W_WND;

    IERC721 public NFT;

    /* --------------------------------- REWARD --------------------------------- */

    ISnake public snakeToken;

    // IERC404 public snake404;

    PoolInfo public poolInfo;

    mapping(uint256 => address) public tokenOwner;

    mapping(address => StakerInfo) public stakerInfo;

    mapping(address => bool) public isKeeper;

    uint256 public rewardPerSecond;
    uint256 public distributePeriod;
    uint256 public lastDistributedTime;

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    event Deposit(address indexed user, uint256 amount, address indexed to);

    event Withdraw(address indexed user, uint256 amount, address indexed to);

    event Harvest(address indexed user, uint256 amount);

    event PoolUpdated(
        uint256 lastRewardTime,
        uint256 nftSupply,
        uint256 accRewardPerShare
    );

    event RewardPerSecondUpdated(uint256 rewardPerSeconds);

    /* -------------------------------------------------------------------------- */
    /*                                  MODIFIERS                                 */
    /* -------------------------------------------------------------------------- */

    modifier onlyKeeper() {
        require(isKeeper[msg.sender], "MasterChef: FORBIDDEN");
        _;
    }

    constructor(IERC20 _nativeToken, IERC721 _nft) Ownable(msg.sender) {
        W_WND = _nativeToken;
        NFT = _nft;
        distributePeriod = WEEK;
        poolInfo = PoolInfo({
            lastRewardTime: block.timestamp,
            accRewardPerShare: 0
        });
    }

    function addKeeper(address[] memory _keepers) external onlyOwner {
        for (uint256 i = 0; i < _keepers.length; ) {
            address _keeper = _keepers[i];
            if (!isKeeper[_keeper]) {
                isKeeper[_keeper] = true;
            }
            unchecked {
                i++;
            }
        }
    }

    function removeKeeper(address[] memory _keepers) external onlyOwner {
        uint256 i = 0;
        uint256 len = _keepers.length;

        for (i; i < len; ) {
            address _keeper = _keepers[i];
            if (isKeeper[_keeper]) {
                isKeeper[_keeper] = false;
            }
            unchecked {
                i++;
            }
        }
    }

    function setRewardPerSecond(uint256 _rewardPerSecond) public onlyOwner {
        updatePool();
        rewardPerSecond = _rewardPerSecond;

        emit RewardPerSecondUpdated(_rewardPerSecond);
    }

    function setDistributeRate(uint256 amount) public onlyOwner {
        updatePool();
        uint256 currentTime = block.timestamp;
        uint256 notDistributed;
        // Means that currentTime is within the week
        if (lastDistributedTime > 0 && currentTime < lastDistributedTime) {
            uint256 timeLeft;
            unchecked {
                timeLeft = lastDistributedTime - currentTime;
            }
            notDistributed = timeLeft * rewardPerSecond;
        }
        amount = amount + notDistributed;
        uint256 _rewardPerSecond = amount / distributePeriod;
        rewardPerSecond = _rewardPerSecond;
        lastDistributedTime = currentTime + distributePeriod;

        emit RewardPerSecondUpdated(_rewardPerSecond);
    }

    function updatePool() public returns (PoolInfo memory pool) {
        pool = poolInfo;
        if (block.timestamp > pool.lastRewardTime) {
            uint256 nftSupply = NFT.balanceOf(address(this));
            uint256 currentTime = block.timestamp;
            if (nftSupply > 0) {
                uint256 time = currentTime > pool.lastRewardTime
                    ? currentTime - pool.lastRewardTime
                    : 0;
                uint256 reward = time * rewardPerSecond;
                pool.accRewardPerShare += (reward * WWND_PRECISION) / nftSupply;
            }
            pool.lastRewardTime = currentTime;
            poolInfo = pool;

            emit PoolUpdated(
                pool.lastRewardTime,
                nftSupply,
                pool.accRewardPerShare
            );
        }
    }

    /// @notice Deposit NFT token
    /// @dev Following the CEI principle
    function deposit(uint256[] calldata tokenIds) public {
        address sender = msg.sender;
        PoolInfo memory pool = updatePool();
        StakerInfo storage staker = stakerInfo[sender];

        staker.amount = staker.amount + tokenIds.length;
        staker.rewardDebt =
            staker.rewardDebt +
            (
                int256(
                    (tokenIds.length * pool.accRewardPerShare) / WWND_PRECISION
                )
            );

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                NFT.ownerOf(tokenIds[i]) == sender,
                "MasterChef: INVALID_OWNER"
            );

            staker.tokenIndicates[tokenIds[i]] = staker.tokenIds.length;
            staker.tokenIds.push(tokenIds[i]);
            tokenOwner[tokenIds[i]] = sender;

            NFT.transferFrom(msg.sender, address(this), tokenIds[i]);
        }

        emit Deposit(sender, tokenIds.length, msg.sender);
    }

    /// @notice Withdraw the NFT tokens
    /// @dev Following the CEI principle
    function withdraw(uint256[] calldata tokenIds) public {
        address sender = msg.sender;
        PoolInfo memory pool = updatePool();
        StakerInfo storage staker = stakerInfo[sender];

        staker.rewardDebt -= int256(
            (tokenIds.length * pool.accRewardPerShare) / WWND_PRECISION
        );
        staker.amount += tokenIds.length;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                tokenOwner[tokenIds[i]] == sender,
                "MasterChef: INVALID_OWNER"
            );

            NFT.transferFrom(address(this), sender, tokenIds[i]);
            uint256 lastTokenId = staker.tokenIds[staker.tokenIds.length - 1];
            staker.tokenIds[staker.tokenIndicates[tokenIds[i]]] = lastTokenId;
            staker.tokenIndicates[lastTokenId] = staker.tokenIndicates[
                tokenIds[i]
            ];
            staker.tokenIds.pop();

            delete staker.tokenIndicates[tokenIds[i]];
            delete tokenOwner[tokenIds[i]];
        }
        emit Withdraw(sender, tokenIds.length, sender);
    }

    function harvest() public {
        address sender = msg.sender;
        PoolInfo memory pool = updatePool();
        StakerInfo storage staker = stakerInfo[sender];

        int256 accumulatedReward = int256(
            (staker.amount * pool.accRewardPerShare) / WWND_PRECISION
        );
        uint256 _pendingReward = (accumulatedReward - staker.rewardDebt)
            .toUint256();

        staker.rewardDebt = accumulatedReward;

        if (_pendingReward > 0) {
            W_WND.safeTransfer(sender, _pendingReward);
        }

        emit Harvest(sender, _pendingReward);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /* -------------------------------------------------------------------------- */
    /*                               VIEW FUNCTIONS                               */
    /* -------------------------------------------------------------------------- */

    /// @notice View function to help see pending W_WND on UI.
    /// @param _user User's address.
    /// @return pending The amount of pending W_WND reward for a given user;
    function pendingReward(
        address _user
    ) external view returns (uint256 pending) {
        PoolInfo memory pool = poolInfo;
        StakerInfo storage staker = stakerInfo[_user];

        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 nftSupply = NFT.balanceOf(address(this));
        uint256 currentTime = block.timestamp;

        if (currentTime > pool.lastRewardTime && nftSupply != 0) {
            uint256 time;
            unchecked {
                time = currentTime - pool.lastRewardTime;
            }
            uint256 reward = time * rewardPerSecond;
            accRewardPerShare += (reward * WWND_PRECISION) / nftSupply;
        }
        pending = (int256(
            (staker.amount * accRewardPerShare) / WWND_PRECISION
        ) - staker.rewardDebt).toUint256();
    }

    function stakedTokenIds(
        address _user
    ) external view returns (uint256[] memory tokenIds) {
        tokenIds = stakerInfo[_user].tokenIds;
    }
}
