// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

import {IERC20} from "./interfaces/IERC20.sol";
import {ISnakePair} from "./interfaces/ISnakePair.sol";
import {ISnakeRouter} from "./interfaces/ISnakeRouter.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {IGauge} from "./interfaces/IGauge.sol";
import {IZodiacNotify} from "./interfaces/IZodiacNotify.sol";

contract ZodiacToken is ERC20, AccessControl {
    uint256 public constant MAX_DISCOUNT = 100; // 10%
    uint256 public constant MIN_DISCOUNT = 0; // 0%
    uint256 public constant MAX_TWAP_POINTS = 50; // 25 hours
    uint256 public constant FULL_LOCK = 52 * 7 * 86400; // 52 weeks
    uint256 public constant MAX_FEES = 50; // 50%

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER");

    // This token is used in the exercise progress
    IERC20 public paymentToken;

    IERC20 public immutable underlyingToken; // native protocol token

    // Rewards  Distributor
    // @dev this address is used to receive the rewards
    address public rewardsAddress;

    IVotingEscrow public immutable VOTING_ESCROW;

    IVoter public immutable voter;

    /// @notice the time period required to be waited before we can burn the tokens
    uint256 public immutable expiryCooldownTime;

    /// @dev Dex router
    ISnakeRouter public router;

    /// @notice The pair contract that provides the current TWAP price to purchase
    /// the underlying token while exercising options (the strike price)
    ISnakePair public pair;

    IGauge public gauge;

    /// @notice the discount given during exercising with locking to the LP
    uint256 public maxLPDiscount = 20; //  User pays 20%
    uint256 public minLPDiscount = 80; //  User pays 80%

    /// @notice the discount given during exercising. 30 = user pays 30%
    uint256 public discount = 88; // User pays 88%

    /// @notice the lock duration for max discount to create locked LP
    uint256 public lockDurationForMaxLpDiscount = FULL_LOCK; // 52 weeks

    // @notice the lock duration for max discount to create locked LP
    uint256 public lockDurationForMinLpDiscount = 7 * 86400; // 1 week

    /// @notice controls the duration of the twap used to calculate the strike price
    // each point represents 30 minutes. 4 points = 2 hours
    uint256 public twapPoints = 4;

    bool public isPaused;

    /// @notice expiry time
    uint256 public expiryTime;

    struct TreasuryConfig {
        address treasury;
        uint256 fee;
        bool notify;
    }

    TreasuryConfig[] public treasuries;

    /* --------------------------------- ERRORS --------------------------------- */
    error PastDeadline();
    error NotAdminRole();
    error NotMinterRole();
    error NotPauserRole();
    error NotEnoughBalance();
    error InvalidDiscount();
    error Paused();
    error InvalidTwapPoints();
    error IncorrectPoolToken();
    error InvalidLockDuration();
    /* --------------------------------- EVENTS --------------------------------- */
    event Exercise(
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        uint256 paymentAmount
    );
    event ExerciseLP(
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        uint256 paymentAmount,
        uint256 lpAmount
    );
    event SetPairAndPaymentToken(
        ISnakePair indexed newPair,
        address indexed newPaymentToken
    );
    event SetGauge(address indexed newGauge);
    event AddTreasury(address indexed newTreasury, uint256 fee, bool notify);
    event SetRouter(address indexed newRouter);
    event SetRewardsAddress(address indexed newRewardsAddress);
    event SetDiscount(uint256 discount);
    event SetVeDiscount(uint256 discount);
    event SetMinLPDiscount(uint256 lpMinDiscount);
    event SetMaxLPDiscount(uint256 lpMaxDiscount);
    event SetLockDurationForMaxLpDiscount(uint256 lockDurationForMaxLpDiscount);
    event SetLockDurationForMinLpDiscount(uint256 lockDurationForMinLpDiscount);
    event PauseStateChanged(bool isPaused);
    event SetTwapPoints(uint256 twapPoints);

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "ZodiacToken: Not admin role");
        _;
    }

    modifier onlyMinter() {
        require(
            hasRole(MINTER_ROLE, msg.sender),
            "ZodiacToken: Not minter role"
        );
        _;
    }

    modifier onlyPauser() {
        require(
            hasRole(PAUSER_ROLE, msg.sender),
            "ZodiacToken: Not pauser role"
        );
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        address _admin,
        IERC20 _underlyingToken,
        address _treasury,
        address _voter,
        address _router,
        uint256 _expiryCooldownTime
    ) ERC20(_name, _symbol) {
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(MINTER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(PAUSER_ROLE, ADMIN_ROLE);

        underlyingToken = _underlyingToken;
        voter = IVoter(_voter);
        VOTING_ESCROW = IVotingEscrow(IVoter(_voter).VOTING_ESCROW());
        router = ISnakeRouter(_router);

        treasuries.push(TreasuryConfig(_treasury, 5, false));

        expiryCooldownTime = _expiryCooldownTime;

        emit AddTreasury(_treasury, 5, false);
        emit SetRouter(_router);
    }

    /* -------------------------------------------------------------------------- */
    /*                             EXTERNAL FUNCTIONS                             */
    /* -------------------------------------------------------------------------- */
    // @dev This exercise function is used to redeem the underlying token
    function exercise(
        uint256 _amount,
        uint256 _maxPaymentAmount,
        address _recipient,
        uint256 _deadline
    ) external returns (uint256) {
        if (block.timestamp > _deadline) revert PastDeadline();
        return _exercise(_amount, _maxPaymentAmount, _recipient);
    }

    function exerciseLp(
        uint256 _amount,
        uint256 _maxPaymentAmount,
        address _recipient,
        uint256 _discount,
        uint256 _deadline
    ) external returns (uint256, uint256) {
        if (block.timestamp > _deadline) revert PastDeadline();
        return _exerciseLp(_amount, _maxPaymentAmount, _recipient, _discount);
    }

    function setPairAndPaymentToken(
        ISnakePair _pair,
        address _paymentToken
    ) external onlyAdmin {
        (address token0, address token1) = _pair.tokens();
        if (
            !((token0 == _paymentToken && token1 == address(underlyingToken)) ||
                (token0 == address(underlyingToken) && token1 == _paymentToken))
        ) {
            revert IncorrectPoolToken();
        }
        pair = _pair;
        gauge = IGauge(IVoter(voter).gauges(address(_pair)));
        paymentToken = IERC20(_paymentToken);
        emit SetPairAndPaymentToken(_pair, _paymentToken);
    }

    function updateGauge() external {
        address newGauge = IVoter(voter).gauges(address(pair));
        gauge = IGauge(newGauge);
        emit SetGauge(newGauge);
    }

    function setGauge(address _gauge) external onlyAdmin {
        gauge = IGauge(_gauge);
        emit SetGauge(_gauge);
    }

    function addTreasury(TreasuryConfig calldata _treasury) external onlyAdmin {
        require(
            _treasury.treasury != address(0),
            "ZodiacToken: Invalid treasury address"
        );
        treasuries.push(_treasury);
        emit AddTreasury(_treasury.treasury, _treasury.fee, _treasury.notify);
    }

    function replaceTreasury(
        TreasuryConfig calldata _treasury,
        uint256 _pos
    ) external onlyAdmin {
        require(
            _treasury.treasury != address(0),
            "ZodiacToken: Invalid treasury address"
        );
        require(
            _pos < treasuries.length,
            "ZodiacToken: Invalid treasury position"
        );
        treasuries[_pos] = _treasury;
    }

    function removeTreasury(uint256 _pos) external onlyAdmin {
        require(
            _pos < treasuries.length,
            "ZodiacToken: Invalid treasury position"
        );
        treasuries[_pos] = treasuries[treasuries.length - 1];
        treasuries.pop();
    }

    function setRouter(address _router) external onlyAdmin {
        router = ISnakeRouter(_router);
        emit SetRouter(_router);
    }

    function setRewardsAddress(address _rewardsAddress) external onlyAdmin {
        rewardsAddress = _rewardsAddress;
        emit SetRewardsAddress(_rewardsAddress);
    }

    function setDiscount(uint256 _discount) external onlyAdmin {
        if (_discount > MAX_DISCOUNT || _discount < MIN_DISCOUNT) {
            revert InvalidDiscount();
        }
        discount = _discount;
        emit SetDiscount(_discount);
    }

    function setMinLPDiscount(uint256 _lpMinDiscount) external onlyAdmin {
        if (
            _lpMinDiscount > MAX_DISCOUNT ||
            _lpMinDiscount < MIN_DISCOUNT ||
            maxLPDiscount > _lpMinDiscount
        ) {
            revert InvalidDiscount();
        }
        minLPDiscount = _lpMinDiscount;
        emit SetMinLPDiscount(_lpMinDiscount);
    }

    function setMaxLPDiscount(uint256 _lpMaxDiscount) external onlyAdmin {
        if (
            _lpMaxDiscount > MAX_DISCOUNT ||
            _lpMaxDiscount < MIN_DISCOUNT ||
            minLPDiscount < _lpMaxDiscount
        ) {
            revert InvalidDiscount();
        }
        maxLPDiscount = _lpMaxDiscount;
        emit SetMaxLPDiscount(_lpMaxDiscount);
    }

    function setLockDurationForMaxLpDiscount(
        uint256 _duration
    ) external onlyAdmin {
        if (_duration <= lockDurationForMinLpDiscount) {
            revert InvalidLockDuration();
        }
        lockDurationForMaxLpDiscount = _duration;
        emit SetLockDurationForMaxLpDiscount(_duration);
    }

    function setLockDurationForMinLpDiscount(
        uint256 _duration
    ) external onlyAdmin {
        if (_duration >= lockDurationForMaxLpDiscount) {
            revert InvalidLockDuration();
        }
        lockDurationForMinLpDiscount = _duration;
        emit SetLockDurationForMinLpDiscount(_duration);
    }

    function setTwapPoints(uint256 _twapPoints) external onlyAdmin {
        if (_twapPoints > MAX_TWAP_POINTS) {
            revert InvalidTwapPoints();
        }
        twapPoints = _twapPoints;
        emit SetTwapPoints(_twapPoints);
    }

    function mint(address _to, uint256 _amount) external onlyMinter {
        _safeTransferFrom(
            address(underlyingToken),
            msg.sender,
            address(this),
            _amount
        );
        _mint(_to, _amount);
    }

    function startExpire() external onlyAdmin {
        require(expiryCooldownTime != 0, "no expiry token");
        require(expiryTime == 0, "already started");
        expiryTime = block.timestamp + expiryCooldownTime;
    }

    function expire() external onlyAdmin {
        require(expiryTime != 0, "not started");
        require(block.timestamp > expiryTime, "not expiry time");
        underlyingToken.burn(underlyingToken.balanceOf(address(this)));
    }

    function unPause() external onlyAdmin {
        if (!isPaused) return;
        isPaused = false;
        emit PauseStateChanged(false);
    }

    function pause() external onlyPauser {
        if (isPaused) return;
        isPaused = true;
        emit PauseStateChanged(true);
    }

    function getDiscountedPrice(uint256 amount) public view returns (uint256) {
        return (getTimeWeightedAveragePrice(amount) * discount) / 100;
    }

    function getLpDiscountedPrice(
        uint256 _amount,
        uint256 _discount
    ) public view returns (uint256) {
        return (getTimeWeightedAveragePrice(_amount) * _discount) / 100;
    }

    function getLockDurationForLpDiscount(
        uint256 _discount
    ) public view returns (uint256 duration) {
        (int256 slope, int256 intercept) = getSlopeInterceptForLpDiscount();
        duration = _discount == 0
            ? lockDurationForMaxLpDiscount
            : FixedPointMathLib.abs(slope * int256(_discount) + intercept);
    }

    function getPaymentTokenAmountForExerciseLp(
        uint256 _amount,
        uint256 _discount
    )
        public
        view
        returns (uint256 paymentAmount, uint256 paymentAmountToAddLiquidity)
    {
        paymentAmount = _discount == 0
            ? 0
            : getLpDiscountedPrice(_amount, _discount);
        (uint256 underlyingReserve, uint256 paymentReserve) = router
            .getReserves(
                address(underlyingToken),
                address(paymentToken),
                false
            );
        paymentAmountToAddLiquidity =
            (paymentAmount * underlyingReserve) /
            paymentReserve;
    }

    function getSlopeInterceptForLpDiscount()
        public
        view
        returns (int256 slope, int256 intercept)
    {
        slope =
            int256(
                lockDurationForMaxLpDiscount - lockDurationForMinLpDiscount
            ) /
            (int256(maxLPDiscount) - int256(minLPDiscount));
        intercept =
            int256(lockDurationForMinLpDiscount) -
            (slope * int256(minLPDiscount));
    }

    function getTimeWeightedAveragePrice(
        uint256 amount
    ) public view returns (uint256) {
        uint256[] memory amountsOut = ISnakePair(pair).prices(
            address(underlyingToken),
            amount,
            twapPoints
        );
        uint256 length = amountsOut.length;
        uint256 summedAmount;
        for (uint256 i = 0; i < length; i++) {
            summedAmount += amountsOut[i];
        }
        return summedAmount / twapPoints;
    }

    /* -------------------------------------------------------------------------- */
    /*                             INTERNAL FUNCTIONS                             */
    /* -------------------------------------------------------------------------- */
    function _exercise(
        uint256 _amount,
        uint256 _maxPaymentAmount, // Slippage protection
        address _recipient
    ) internal returns (uint256 paymentAmount) {
        if (isPaused) revert Paused();

        // Burn the zodiac token
        _burn(msg.sender, _amount);
        paymentAmount = getDiscountedPrice(_amount);
        if (paymentAmount > _maxPaymentAmount) {
            revert NotEnoughBalance();
        }
        // transfer the payment token to the treasury
        uint256 gaugeRewardAmount = _takeFees(
            address(paymentToken),
            paymentAmount
        );
        _usePaymentAsGaugeReward(gaugeRewardAmount);

        // send the underlying token to the recipient
        underlyingToken.transfer(_recipient, _amount);

        emit Exercise(msg.sender, _recipient, _amount, _maxPaymentAmount);
    }

    function _exerciseLp(
        uint256 _amount,
        uint256 _maxPaymentAmount,
        address _recipient,
        uint256 _discount
    ) internal returns (uint256 paymentAmount, uint256 lpAmount) {
        if (isPaused) revert Paused();

        if (_discount > minLPDiscount || _discount < maxLPDiscount)
            revert InvalidDiscount();

        _burn(msg.sender, _amount);
        uint256 paymentAmountToAddLiquidity;
        (
            paymentAmount,
            paymentAmountToAddLiquidity
        ) = getPaymentTokenAmountForExerciseLp(_amount, _discount);
        if (paymentAmount > _maxPaymentAmount) revert NotEnoughBalance();

        // Take team fee
        uint256 paymentGaugeRewardAmount = _discount == 0
            ? 0
            : _takeFees(address(paymentToken), paymentAmount);
        _safeTransferFrom(
            address(paymentToken),
            msg.sender,
            address(this),
            paymentGaugeRewardAmount + paymentAmountToAddLiquidity
        );

        // Create Lp for users
        _safeApprove(address(underlyingToken), address(router), _amount);
        _safeApprove(
            address(paymentToken),
            address(router),
            paymentAmountToAddLiquidity
        );
        (, , lpAmount) = router.addLiquidity(
            address(underlyingToken),
            address(paymentToken),
            false,
            _amount,
            paymentAmountToAddLiquidity,
            1,
            1,
            address(this),
            block.timestamp
        );

        // Stake the LP in the gauge with lock
        address _gauge = address(gauge);
        _safeApprove(address(pair), _gauge, lpAmount);
        IGauge(_gauge).depositWithLock(
            _recipient,
            lpAmount,
            getLockDurationForLpDiscount(_discount)
        );

        // notify gauge reward with payment token
        _transferRewardToGauge();

        emit ExerciseLP(
            msg.sender,
            _recipient,
            _amount,
            paymentAmount,
            lpAmount
        );
    }

    function _takeFees(
        address token,
        uint256 paymentAmount
    ) internal returns (uint256 remaining) {
        remaining = paymentAmount;
        for (uint i; i < treasuries.length; i++) {
            uint256 _fee = (paymentAmount * treasuries[i].fee) / 100;
            _safeTransferFrom(token, msg.sender, treasuries[i].treasury, _fee);
            remaining = remaining - _fee;

            if (treasuries[i].notify) {
                IZodiacNotify(treasuries[i].treasury).notify(_fee);
            }
        }
    }

    function _usePaymentAsGaugeReward(uint256 amount) internal {
        _safeTransferFrom(
            address(paymentToken),
            msg.sender,
            address(this),
            amount
        );
        _transferRewardToGauge();
    }

    function _transferRewardToGauge() internal {
        uint256 paymentTokenCollectedAmount = paymentToken.balanceOf(
            address(this)
        );

        if (rewardsAddress != address(0)) {
            _safeTransfer(
                address(paymentToken),
                rewardsAddress,
                paymentTokenCollectedAmount
            );
        } else {
            uint256 leftRewards = IGauge(gauge).left(address(paymentToken));

            if (paymentTokenCollectedAmount > leftRewards) {
                // we are sending rewards only if we have more then the current rewards in the gauge
                _safeApprove(
                    address(paymentToken),
                    address(gauge),
                    paymentTokenCollectedAmount
                );
                IGauge(gauge).notifyRewardAmount(
                    address(paymentToken),
                    paymentTokenCollectedAmount
                );
            }
        }
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
