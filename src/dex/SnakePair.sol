// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ISnakePair} from "../interfaces/ISnakePair.sol";
import {ISnakeFactory} from "../interfaces/ISnakeFactory.sol";
import {ISnakePairCallee} from "../interfaces/ISnakePairCallee.sol";
import {SnakeFactory} from "./SnakeFactory.sol";
import {SnakePairFees} from "./SnakePairFees.sol";

contract SnakePair is ISnakePair {
    using FixedPointMathLib for uint256;

    struct Observation {
        uint256 timestamp;
        uint256 reserve0Cumulative;
        uint256 reserve1Cumulative;
    }

    string public override name;
    string public override symbol;

    uint8 public constant override decimals = 18;

    // This is used to determine if the pair is stable or volatile.
    // For example, USDT/USDC would be stable, while ETH/USDT would be volatile
    bool public immutable override stable;

    bytes32 internal DOMAIN_SEPARATOR;
    // keccak256(Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline))
    bytes32 internal constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint256) public nonces;

    uint256 internal constant MINIMUM_LIQUIDITY = 10 ** 3;

    uint256 public override totalSupply = 0;
    mapping(address => mapping(address => uint256)) public override allowance;
    mapping(address => uint256) public override balanceOf;

    address public immutable override token0;
    address public immutable override token1;
    address public immutable override fees; // Address to receive trading fees
    address public immutable override factory;

    // bool public hasGauge;

    // Reading from the oracles every 30 minutes
    uint32 constant periodSize = 1800;

    Observation[] public observations;

    uint8 internal immutable decimal0;
    uint8 internal immutable decimal1;

    uint256 public reserve0;
    uint256 public reserve1;
    uint256 public blockTimestampLast;

    uint256 public reserve0CumulativeLast;
    uint256 public reserve1CumulativeLast;

    // index0 and index1 are used to accumulate fees, this is split out from normal trades to keep the swap "clean"
    // this further allows LP holders to easily claim fees for tokens they have/staked
    uint256 public index0 = 0;
    uint256 public index1 = 0;

    // position assigned to each LP to track their current index0 & index1 vs the global position
    mapping(address => uint256) public supplyIndex0;
    mapping(address => uint256) public supplyIndex1;

    // tracks the amount of unclaimed tokens, but claimable tokens off of fees for token0 and token1
    mapping(address => uint256) public override claimable0;
    mapping(address => uint256) public override claimable1;

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */
    event Fees(address indexed sender, uint256 amount0, uint256 amount1);

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);

    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);

    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );

    event Sync(uint256 reserve0, uint256 reserve1);

    event Claim(address indexed sender, address indexed receiver, uint256 amount0, uint256 amount1);

    event Transfer(address indexed from, address indexed to, uint256 amount);

    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /* -------------------------------------------------------------------------- */
    /*                                  MODIFIER                                  */
    /* -------------------------------------------------------------------------- */
    uint256 internal unlocked = 1;

    modifier lock() {
        require(unlocked == 1, "SnakePair: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    constructor() {
        address _factory = msg.sender;
        factory = _factory;
        (address _token0, address _token1, bool _stable) = ISnakeFactory(_factory).getInitializable();
        (token0, token1, stable) = (_token0, _token1, _stable);
        fees = address(new SnakePairFees(_token0, _token1));
        if (_stable) {
            name = string(
                abi.encodePacked(
                    "StableV1 AMM - ", IERC20Metadata(_token0).symbol(), "/", IERC20Metadata(_token1).symbol()
                )
            );
            symbol = string(
                abi.encodePacked("sAMM-", IERC20Metadata(_token0).symbol(), "/", IERC20Metadata(_token1).symbol())
            );
        } else {
            name = string(
                abi.encodePacked(
                    "VolatileV1 AMM - ", IERC20Metadata(_token0).symbol(), "/", IERC20Metadata(_token1).symbol()
                )
            );
            symbol = string(
                abi.encodePacked("vAMM-", IERC20Metadata(_token0).symbol(), "/", IERC20Metadata(_token1).symbol())
            );
        }

        decimal0 = IERC20Metadata(_token0).decimals();
        decimal1 = IERC20Metadata(_token1).decimals();

        observations.push(Observation({timestamp: block.timestamp, reserve0Cumulative: 0, reserve1Cumulative: 0}));
    }

    /// @notice Claim the accumulated fees but unclaimed
    function claimFees() external override returns (uint256 claimed0, uint256 claimed1) {
        address sender = msg.sender;
        _updateFor(sender);

        claimed0 = claimable0[msg.sender];
        claimed1 = claimable1[msg.sender];

        if (claimed0 > 0 || claimed1 > 0) {
            claimable0[msg.sender] = 0;
            claimable1[msg.sender] = 0;

            SnakePairFees(fees).claimFeesFor(sender, claimed0, claimed1);

            emit Claim(msg.sender, msg.sender, claimed0, claimed1);
        }
    }

    function claimStakingFees() external {
        address _feeHandler = SnakeFactory(factory).stakingFeeHandler();
        SnakePairFees(fees).withdrawStakingFees(_feeHandler);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transferTokens(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        address spender = msg.sender;
        uint256 spenderAllowance = allowance[from][spender];

        if (spender != from && spenderAllowance != type(uint256).max) {
            uint256 newAllowance = spenderAllowance - amount;

            allowance[from][spender] = newAllowance;

            emit Approval(from, spender, amount);
        }
        _transferTokens(from, to, amount);
        return true;
    }

    function permit(address owner, address spender, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        override
    {
        require(deadline >= block.timestamp, "SnakePair: PERMIT_EXPIRED");
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(abi.encodePacked(uint256(1))),
                block.chainid,
                address(this)
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, amount, nonces[owner]++, deadline))
            )
        );

        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, "Pair: INVALID_SIGNATURE");
        allowance[owner][spender] = amount;

        emit Approval(owner, spender, amount);
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external override lock {
        require(!SnakeFactory(factory).isPaused());
        require(amount0Out > 0 || amount1Out > 0, "IOA"); // Pair: INSUFFICIENT_OUTPUT_AMOUNT
        (uint256 _reserve0, uint256 _reserve1) = (reserve0, reserve1);
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "IL"); // Pair: INSUFFICIENT_LIQUIDITY

        uint256 _balance0;
        uint256 _balance1;
        {
            // scope for _token{0,1}, avoids stack too deep errors
            (address _token0, address _token1) = (token0, token1);
            require(to != _token0 && to != _token1, "IT"); // Pair: INVALID_TO
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
            if (data.length > 0) ISnakePairCallee(to).hook(msg.sender, amount0Out, amount1Out, data); // callback, used for flash loans
            _balance0 = IERC20(_token0).balanceOf(address(this));
            _balance1 = IERC20(_token1).balanceOf(address(this));
        }

        uint256 amount0In = _balance0 > _reserve0 - amount0Out ? _balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = _balance1 > _reserve1 - amount1Out ? _balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "IIA"); // Pair: INSUFFICIENT_INPUT_AMOUNT

        {
            // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            (address _token0, address _token1) = (token0, token1);
            if (amount0In > 0) _update0(amount0In * SnakeFactory(factory).getFee(stable) / 10000); // accrue fees for token0 and move them out of pool
            if (amount1In > 0) _update1(amount1In * SnakeFactory(factory).getFee(stable) / 10000); // accrue fees for token1 and move them out of pool
            _balance0 = IERC20(_token0).balanceOf(address(this)); // since we removed tokens, we need to reconfirm balances, can also simply use previous balance - amountIn/ 10000, but doing balanceOf again as safety check
            _balance1 = IERC20(_token1).balanceOf(address(this));
            // The curve, either x3y+y3x for stable pools, or x*y for volatile pools
            require(_k(_balance0, _balance1) >= _k(_reserve0, _reserve1), "K"); // Pair: K
        }

        _update(_balance0, _balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function mint(address receiver, uint256 amount) external override returns (uint256 lpAmount) {}

    function burn(address burner, uint256 amount) external override returns (uint256 amount0, uint256 amount1) {}

    // force balances to match reserves
    function skim(address to) external lock {
        (address _token0, address _token1) = (token0, token1);
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)) - (reserve0));
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)) - (reserve1));
    }

    // force reserves to match balances
    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }

    /* -------------------------------------------------------------------------- */
    /*                           EXTERNAL VIEW FUNCTIONS                          */
    /* -------------------------------------------------------------------------- */

    function observationsLength() public view returns (uint256) {
        return observations.length;
    }

    function lastObservation() public view returns (Observation memory) {
        return observations[observations.length - 1];
    }

    function metadata()
        external
        view
        override
        returns (
            uint256 _decimal0,
            uint256 _decimal1,
            uint256 _reserve0,
            uint256 _reserve1,
            bool _stable,
            address _token0,
            address _token1
        )
    {
        return (decimal0, decimal1, reserve0, reserve1, stable, token0, token1);
    }

    function tokens() external view override returns (address, address) {
        return (token0, token1);
    }

    function getReserves() public view returns (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast) {
        (_reserve0, _reserve1, _blockTimestampLast) = (reserve0, reserve1, blockTimestampLast);
    }

    // produces the cumulative price using counterfactuals to save gas and avoid a call to sync.
    function currentCumulativePrices()
        public
        view
        returns (uint256 reserve0Cumulative, uint256 reserve1Cumulative, uint256 blockTimestamp)
    {
        blockTimestamp = block.timestamp;
        reserve0Cumulative = reserve0CumulativeLast;
        reserve1Cumulative = reserve1CumulativeLast;

        (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast) = getReserves();
        if (_blockTimestampLast != blockTimestamp) {
            uint256 timeElapsed = blockTimestamp - _blockTimestampLast;
            reserve0Cumulative += _reserve0 * timeElapsed;
            reserve1Cumulative += _reserve1 * timeElapsed;
        }
    }

    // Get the current twap price measured from amountIn * tokenIn gives amountOut
    function current(address tokenIn, uint256 amountIn) external view returns (uint256 amountOut) {
        Observation memory _observation = lastObservation();
        (uint256 reserve0Cumulative, uint256 reserve1Cumulative,) = currentCumulativePrices();
        if (block.timestamp > _observation.timestamp) {
            _observation = observations[observations.length - 2];
        }

        uint256 timeElapsed = block.timestamp - _observation.timestamp;
        uint256 _reserve0 = (reserve0Cumulative - _observation.reserve0Cumulative) / timeElapsed;
        uint256 _reserve1 = (reserve1Cumulative - _observation.reserve1Cumulative) / timeElapsed;
        amountOut = _getAmountOut(amountIn, tokenIn, _reserve0, _reserve1);
    }

    function getAmountOut(uint256 amountIn, address tokenIn) external view override returns (uint256 amountOut) {
        (uint256 _reserve0, uint256 _reserve1) = (reserve0, reserve1);
        amountIn -= amountIn * SnakeFactory(factory).getFee(stable) / 10000; // remove fee from amount received
        return _getAmountOut(amountIn, tokenIn, _reserve0, _reserve1);
    }

    // as per `current`, however allows user configured granularity up to the full window size
    function quote(address tokenIn, uint256 amountIn, uint256 granularity) external view returns (uint256 amountOut) {
        uint256[] memory _prices = sample(tokenIn, amountIn, granularity, 1);
        uint256 priceAverageCumulative;
        for (uint256 i = 0; i < _prices.length; i++) {
            priceAverageCumulative += _prices[i];
        }
        return priceAverageCumulative / granularity;
    }

    // returns a memory set of twap prices
    function prices(address tokenIn, uint256 amountIn, uint256 points) external view returns (uint256[] memory) {
        return sample(tokenIn, amountIn, points, 1);
    }

    function sample(address tokenIn, uint256 amountIn, uint256 points, uint256 window)
        public
        view
        returns (uint256[] memory)
    {
        uint256[] memory _prices = new uint256[](points);
        uint256 length = observations.length - 1;
        uint256 i = length - (points * window);

        uint256 nextIndex = 0;
        uint256 index = 0;

        for (; i < length; i += window) {
            nextIndex = i + window;
            uint256 timeElapsed = observations[nextIndex].timestamp - observations[i].timestamp;
            uint256 _reserve0 =
                (observations[nextIndex].reserve0Cumulative - observations[i].reserve0Cumulative) / timeElapsed;
            uint256 _reserve1 =
                (observations[nextIndex].reserve1Cumulative - observations[i].reserve1Cumulative) / timeElapsed;
            _prices[index] = _getAmountOut(amountIn, tokenIn, _reserve0, _reserve1);
            // index < length; length cannot overflow
            unchecked {
                index = index + 1;
            }
        }
        return _prices;
    }

    /* -------------------------------------------------------------------------- */
    /*                             INTERNAL FUNCTIONS                             */
    /* -------------------------------------------------------------------------- */

    function _transferTokens(address from, address to, uint256 amount) internal {
        _updateFor(from);
        _updateFor(to);

        balanceOf[from] -= amount;
        balanceOf[to] += amount;

        emit Transfer(from, to, amount);
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint256 balance0, uint256 balance1, uint256 _reserve0, uint256 _reserve1) internal {
        uint256 blockTimestamp = block.timestamp;
        uint256 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            reserve0CumulativeLast += _reserve0 * timeElapsed;
            reserve1CumulativeLast += _reserve1 * timeElapsed;
        }

        Observation memory _point = lastObservation();
        timeElapsed = blockTimestamp - _point.timestamp; // compare the last observation with current timestamp, if greater than 30 minutes, record a new event
        if (timeElapsed > periodSize) {
            observations.push(Observation(blockTimestamp, reserve0CumulativeLast, reserve1CumulativeLast));
        }
        reserve0 = balance0;
        reserve1 = balance1;
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // this function MUST be called on any balance changes, otherwise can be used to infinitely claim fees
    // Fees are segregated from core funds, so fees can never put liquidity at risk
    function _updateFor(address recipient) internal {
        uint256 _supplied = balanceOf[recipient]; // get LP balance of `recipient`
        if (_supplied > 0) {
            uint256 _supplyIndex0 = supplyIndex0[recipient]; // get last adjusted index0 for recipient
            uint256 _supplyIndex1 = supplyIndex1[recipient];
            uint256 _index0 = index0; // get global index0 for accumulated fees
            uint256 _index1 = index1;
            supplyIndex0[recipient] = _index0; // update user current position to global position
            supplyIndex1[recipient] = _index1;
            uint256 _delta0 = _index0 - _supplyIndex0; // see if there is any difference that need to be accrued
            uint256 _delta1 = _index1 - _supplyIndex1;
            if (_delta0 > 0) {
                uint256 _share = _supplied.mulWad(_delta0); // add accrued difference for each supplied token
                claimable0[recipient] += _share;
            }
            if (_delta1 > 0) {
                uint256 _share = _supplied.mulWad(_delta1);
                claimable1[recipient] += _share;
            }
        } else {
            supplyIndex0[recipient] = index0; // new users are set to the default global state
            supplyIndex1[recipient] = index1;
        }
    }

    // Accrue fees on token0
    function _update0(uint256 amount) internal {
        // get referral fees
        address _referrerFeeHandler = SnakeFactory(factory).referrerFeeHandler();
        uint256 _maxReferralFee = SnakeFactory(factory).MAX_REFERRAL_FEE();
        uint256 _referralFee = amount * _maxReferralFee / SnakeFactory(factory).WAD_FEE();
        _safeTransfer(token0, _referrerFeeHandler, _referralFee); // transfer the fees out to PairFees
        unchecked {
            amount -= _referralFee;
        }

        // get the staking and lp fee
        uint256 _stakingNFTFee = amount * SnakeFactory(factory).stakingNFTFee() / SnakeFactory(factory).WAD_FEE();
        SnakePairFees(fees).processStakingFees(_stakingNFTFee, true);
        _safeTransfer(token0, fees, amount); // transfer the fees out to PairFees

        // remove staking fees from lpFees
        amount -= _stakingNFTFee;
        uint256 _ratio = amount.divWad(totalSupply);
        if (_ratio > 0) {
            index0 += _ratio;
        }
        emit Fees(msg.sender, amount + _referralFee, 0);
    }

    // Accrue fees on token1
    function _update1(uint256 amount) internal {
        // get referral fees
        address _referrerFeeHandler = SnakeFactory(factory).referrerFeeHandler();
        uint256 _maxReferralFee = SnakeFactory(factory).MAX_REFERRAL_FEE();
        uint256 _referralFee = amount * _maxReferralFee / SnakeFactory(factory).WAD_FEE();
        _safeTransfer(token1, _referrerFeeHandler, _referralFee); // transfer the fees out to PairFees
        unchecked {
            amount -= _referralFee;
        }

        // get the staking and lp fee
        uint256 _stakingNFTFee = amount * SnakeFactory(factory).stakingNFTFee() / SnakeFactory(factory).WAD_FEE();
        SnakePairFees(fees).processStakingFees(_stakingNFTFee, false);
        _safeTransfer(token1, fees, amount); // transfer the fees out to PairFees

        // remove staking fees from lpFees
        amount -= _stakingNFTFee;
        uint256 _ratio = amount.divWad(totalSupply);
        if (_ratio > 0) {
            index1 += _ratio;
        }
        emit Fees(msg.sender, 0, amount + _referralFee);
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SnakePair: TRANSFER_FAILED");
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        require(token.code.length > 0);
        require((amount == 0) || IERC20(token).allowance(address(this), spender) == 0, "SnakePair: APPROVE_FAILED");
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SnakePair: APPROVE_FAILED");
    }

    function _mint(address receiver, uint256 amount) internal {
        _updateFor(receiver); // balances must be updated before on mint/burn/transfer
        totalSupply += amount;
        balanceOf[receiver] += amount;

        emit Transfer(address(0), receiver, amount);
    }

    function _burn(address receiver, uint256 amount) internal {
        _updateFor(receiver);
        totalSupply -= amount;
        balanceOf[receiver] -= amount;

        emit Transfer(receiver, address(0), amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                           INTERNAL VIEW FUNCTIONS                          */
    /* -------------------------------------------------------------------------- */

    function _f(uint256 x0, uint256 y) internal pure returns (uint256) {
        return x0.mulWad(y.mulWad(y).mulWad(y)) + y.mulWad(x0.mulWad(x0).mulWad(x0));
    }

    function _d(uint256 x0, uint256 y) internal pure returns (uint256) {
        return 3 * x0.mulWad(y.mulWad(y)) + x0.mulWad(x0).mulWad(x0);
    }

    function _get_y(uint256 x0, uint256 xy, uint256 y) internal pure returns (uint256) {
        for (uint256 i = 0; i < 255; i++) {
            uint256 y_prev = y;
            uint256 k = _f(x0, y);
            if (k < xy) {
                uint256 dy = (xy - k).divWad(_d(x0, y));
                y = y + dy;
            } else {
                uint256 dy = (k - xy).divWad(_d(x0, y));
                y = y - dy;
            }
            if (y > y_prev) {
                if (y - y_prev <= 1) {
                    return y;
                }
            } else {
                if (y_prev - y <= 1) {
                    return y;
                }
            }
        }
        return y;
    }

    function _getAmountOut(uint256 amountIn, address tokenIn, uint256 _reserve0, uint256 _reserve1)
        internal
        view
        returns (uint256)
    {
        if (stable) {
            uint256 xy = _k(_reserve0, reserve1);
            _reserve0 = _reserve0.divWad(decimal0);
            _reserve1 = _reserve1.divWad(decimal1);
            (uint256 reserveA, uint256 reserveB) = tokenIn == token0 ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
            amountIn = tokenIn == token0 ? amountIn.divWad(decimal0) : amountIn.divWad(decimal1);
            uint256 y = reserveB - _get_y(amountIn + reserveA, xy, reserveB);
            return y.mulWad(tokenIn == token0 ? decimal1 : decimal0);
        } else {
            (uint256 reserveA, uint256 reserveB) = tokenIn == token0 ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
            return amountIn * reserveB / (reserveA + amountIn);
        }
    }

    function _k(uint256 x, uint256 y) internal view returns (uint256) {
        if (stable) {
            uint256 _x = x.mulWad(decimal0);
            uint256 _y = y.mulWad(decimal1);
            uint256 _a = _x.mulWad(_y);
            uint256 _b = _x.mulWad(_x) + _y.mulWad(_y);
            return _a.mulWad(_b); // x^3 * y + y^3 * x >= k
        } else {
            return x * y; // x * y >= k
        }
    }
}
