// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

import {ISnakeFactory} from "../interfaces/ISnakeFactory.sol";
import {ISnakePair} from "../interfaces/ISnakePair.sol";
import {SnakePair} from "./SnakePair.sol";
import {IWrappedWND} from "../interfaces/IWrappedWND.sol";

contract SnakeRouter {
    using FixedPointMathLib for uint256;

    struct Route {
        address token0;
        address token1;
        bool stable;
    }

    struct TransactionSignature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    address public immutable factory;

    IWrappedWND public immutable wrappedWND;

    uint256 internal constant MINIMUM_LIQUIDITY = 10 ** 3;

    bytes32 immutable pairCodeHash;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, "SnakeRouter: EXPIRED");
        _;
    }

    constructor(address _factory, address _wrappedWND) {
        factory = _factory;
        wrappedWND = IWrappedWND(_wrappedWND);
        pairCodeHash = keccak256(type(SnakePair).creationCode);
    }

    receive() external payable {
        assert(msg.sender == address(wrappedWND)); // only accept WND via fallback from the WrappedWND contract
    }

    function sortToken(
        address token0,
        address token1
    ) public view returns (address tokenA, address tokenB) {
        tokenA = token0 < token1 ? token0 : token1;
        tokenB = token0 < token1 ? token1 : token0;
        require(tokenA != address(0), "SnakeRouter: ZERO_ADDRESS");
    }

    function pairFor(
        address token0,
        address token1,
        bool stable
    ) public view returns (address pair) {
        (address tokenA, address tokenB) = sortToken(token0, token1);
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(abi.encodePacked(tokenA, tokenB, stable)),
                            pairCodeHash
                        )
                    )
                )
            )
        );
    }

    function getReserves(
        address tokenA,
        address tokenB,
        bool stable
    ) public view returns (uint256 reserveA, uint256 reserveB) {
        (address token0, ) = sortToken(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1, ) = ISnakePair(
            pairFor(tokenA, tokenB, stable)
        ).getReserves();
        (reserveA, reserveB) = tokenA == token0
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
    }

    function getAmountOut(
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) public view returns (uint256 amountOut, bool stable) {
        address pair = pairFor(tokenIn, tokenOut, true);

        uint256 amountStable;
        uint256 amountVolatile;

        if (ISnakeFactory(factory).isPair(pair)) {
            amountStable = ISnakePair(pair).getAmountOut(amountIn, tokenIn);
        }

        pair = pairFor(tokenIn, tokenOut, false);

        if (ISnakeFactory(factory).isPair(pair)) {
            amountVolatile = ISnakePair(pair).getAmountOut(amountIn, tokenIn);
        }

        return
            amountStable > amountVolatile
                ? (amountStable, true)
                : (amountVolatile, false);
    }

    function getAmountsOut(
        uint256 amountIn,
        Route[] memory routes
    ) public view returns (uint256[] memory amounts) {
        require(routes.length > 0, "SnakeRouter: EMPTY_PATH");

        amounts = new uint256[](routes.length + 1);
        amounts[0] = amountIn;

        for (uint256 i = 0; i < routes.length; i++) {
            address pair = pairFor(
                routes[i].token0,
                routes[i].token1,
                routes[i].stable
            );
            if (ISnakeFactory(factory).isPair(pair)) {
                amounts[i + 1] = ISnakePair(pair).getAmountOut(
                    amounts[i],
                    routes[i].token0
                );
            }
        }
    }

    function isPair(address pair) public view returns (bool) {
        return ISnakeFactory(factory).isPair(pair);
    }

    function quoteAddLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired
    )
        external
        view
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        address _pair = ISnakeFactory(factory).getPair(tokenA, tokenB, stable);
        (uint256 reserveA, uint256 reserveB) = (0, 0);
        uint256 _totalSupply = 0;

        if (_pair != address(0)) {
            _totalSupply = ISnakePair(_pair).totalSupply();
            (reserveA, reserveB) = getReserves(tokenA, tokenB, stable);
        }

        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
            liquidity = (amountA * amountB).sqrt() - MINIMUM_LIQUIDITY;
        } else {
            uint256 amountBOptimal = _quoteLiquidity(
                amountADesired,
                reserveA,
                reserveB
            );
            if (amountBOptimal > amountBDesired) {
                uint256 amountAOptimal = _quoteLiquidity(
                    amountBDesired,
                    reserveB,
                    reserveA
                );
                (amountA, amountB) = (amountAOptimal, amountBOptimal);
                liquidity = FixedPointMathLib.min(
                    (amountA * _totalSupply) / reserveA,
                    (amountB * _totalSupply) / reserveB
                );
            } else {
                (amountA, amountB) = (amountADesired, amountBDesired);
                liquidity = FixedPointMathLib.min(
                    (amountA * _totalSupply) / reserveA,
                    (amountB * _totalSupply) / reserveB
                );
            }
        }
    }

    function quoteRemoveLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity
    ) external view returns (uint256 amountA, uint256 amountB) {
        address _pair = ISnakeFactory(factory).getPair(tokenA, tokenB, stable);
        if (_pair == address(0)) {
            return (0, 0);
        }

        (uint256 reserveA, uint256 reserveB) = getReserves(
            tokenA,
            tokenB,
            stable
        );

        uint256 _totalSupply = ISnakePair(_pair).totalSupply();

        amountA = (liquidity * reserveA) / _totalSupply;
        amountB = (liquidity * reserveB) / _totalSupply;
    }

    /* -------------------------------------------------------------------------- */
    /*                                ADD LIQUIDITY                               */
    /* -------------------------------------------------------------------------- */

    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        ensure(deadline)
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        (amountA, amountB) = _addLiquidity(
            tokenA,
            tokenB,
            stable,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );

        address pair = pairFor(tokenA, tokenB, stable);
        _safeTransferFrom(tokenA, msg.sender, to, amountA);
        _safeTransferFrom(tokenB, msg.sender, to, amountB);
        liquidity = ISnakePair(pair).mint(to);
    }

    function addLiquidityWND(
        address token,
        bool stable,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountWNDMin,
        address to,
        uint256 deadline
    )
        external
        payable
        ensure(deadline)
        returns (uint256 amountToken, uint256 amountWND, uint256 liquidity)
    {
        (amountToken, amountWND) = _addLiquidity(
            token,
            address(wrappedWND),
            stable,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountWNDMin
        );

        address pair = pairFor(token, address(wrappedWND), stable);
        _safeTransferFrom(token, msg.sender, pair, amountToken);
        wrappedWND.deposit{value: amountWND}();
        assert(wrappedWND.transfer(pair, amountWND));
        liquidity = ISnakePair(pair).mint(to);
        // refund dust wnd, if any
        if (msg.value > amountWND) {
            payable(msg.sender).transfer(msg.value - amountWND);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                              REMOVE LIQUIDITY                              */
    /* -------------------------------------------------------------------------- */

    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = pairFor(tokenA, tokenB, stable);
        require(ISnakePair(pair).transferFrom(msg.sender, pair, liquidity));
        (uint256 amount0, uint256 amount1) = ISnakePair(pair).burn(to);
        (address token0, ) = sortToken(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0
            ? (amount0, amount1)
            : (amount1, amount0);

        // Slippage check
        require(amountA >= amountAMin, "SnakeRouter: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "SnakeRouter: INSUFFICIENT_B_AMOUNT");
    }

    function removeLiquidityWND(
        address token,
        bool stable,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountWNDMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountToken, uint256 amountWND) {
        (amountToken, amountWND) = removeLiquidity(
            token,
            address(wrappedWND),
            stable,
            liquidity,
            amountTokenMin,
            amountWNDMin,
            to,
            deadline
        );
        _safeTransfer(token, to, amountToken);
        wrappedWND.withdraw(amountWND);
        _safeTransferWND(to, amountWND);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        TransactionSignature memory signature
    ) external returns (uint256 amountA, uint256 amountB) {
        address pair = pairFor(tokenA, tokenB, stable);
        {
            uint256 value = approveMax ? type(uint256).max : liquidity;
            ISnakePair(pair).permit(
                msg.sender,
                address(this),
                value,
                deadline,
                signature.v,
                signature.r,
                signature.s
            );
        }
        (amountA, amountB) = removeLiquidity(
            tokenA,
            tokenB,
            stable,
            liquidity,
            amountAMin,
            amountBMin,
            to,
            deadline
        );
    }

    function removeLiquidityWNDWithPermit(
        address token,
        bool stable,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountWNDMin,
        address to,
        uint256 deadline,
        bool approveMax,
        TransactionSignature memory signature
    ) external ensure(deadline) returns (uint256, uint256) {
        uint256 value = approveMax ? type(uint256).max : liquidity;
        ISnakePair(pairFor(token, address(wrappedWND), stable)).permit(
            msg.sender,
            address(this),
            value,
            deadline,
            signature.v,
            signature.r,
            signature.s
        );
        return
            removeLiquidityWND(
                token,
                stable,
                liquidity,
                amountTokenMin,
                amountWNDMin,
                to,
                deadline
            );
    }

    /* -------------------------------------------------------------------------- */
    /*                                    SWAP                                    */
    /* -------------------------------------------------------------------------- */

    function swapExactTokensForTokensSimple(
        uint256 amountIn,
        uint256 amountOutIn,
        address tokenFrom,
        address tokenTo,
        bool stable,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        Route[] memory routes = new Route[](1);
        routes[0].token0 = tokenFrom;
        routes[0].token1 = tokenTo;
        routes[0].stable = stable;
        amounts = getAmountsOut(amountIn, routes);
        require(
            amounts[amounts.length - 1] >= amountOutIn,
            "SnakeRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        _safeTransferFrom(
            routes[0].token0,
            msg.sender,
            pairFor(routes[0].token0, routes[0].token1, routes[0].stable),
            amounts[0]
        );
        _swap(amounts, routes, to);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutIn,
        Route[] memory routes,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = getAmountsOut(amountIn, routes);
        require(
            amounts[amounts.length - 1] >= amountOutIn,
            "SnakeRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        _safeTransferFrom(
            routes[0].token0,
            msg.sender,
            pairFor(routes[0].token0, routes[0].token1, routes[0].stable),
            amounts[0]
        );
        _swap(amounts, routes, to);
    }

    function swapExactWNDForTokens(
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) returns (uint256[] memory amounts) {
        require(
            routes[0].token0 == address(wrappedWND),
            "SnakeRouter: INVALID_PATH"
        );
        amounts = getAmountsOut(msg.value, routes);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "SnakeRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        wrappedWND.deposit{value: amounts[0]}();
        assert(
            wrappedWND.transfer(
                pairFor(routes[0].token0, routes[0].token1, routes[0].stable),
                amounts[0]
            )
        );
        _swap(amounts, routes, to);
    }

    function swapExactTokensForWND(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        require(
            routes[routes.length - 1].token1 == address(wrappedWND),
            "Router: INVALID_PATH"
        );
        amounts = getAmountsOut(amountIn, routes);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "Router: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        _safeTransferFrom(
            routes[0].token0,
            msg.sender,
            pairFor(routes[0].token0, routes[0].token1, routes[0].stable),
            amounts[0]
        );
        _swap(amounts, routes, address(this));
        wrappedWND.withdraw(amounts[amounts.length - 1]);
        _safeTransferWND(to, amounts[amounts.length - 1]);
    }

    function UNSAFE_swapExactTokensForTokens(
        uint256[] memory amounts,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory) {
        _safeTransferFrom(
            routes[0].token0,
            msg.sender,
            pairFor(routes[0].token0, routes[0].token1, routes[0].stable),
            amounts[0]
        );
        _swap(amounts, routes, to);
        return amounts;
    }

    /* -------------------------------------------------------------------------- */
    /*                                  INTERNAL                                  */
    /* -------------------------------------------------------------------------- */

    function _quoteLiquidity(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256 amountB) {
        require(amountA > 0, "SnakeRouter: INSUFFICIENT_AMOUNT");
        require(
            reserveA > 0 && reserveB > 0,
            "SnakeRouter: INSUFFICIENT_LIQUIDITY"
        );
        amountB = (amountA * reserveB) / reserveA;
    }

    function _addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal returns (uint256 amountA, uint256 amountB) {
        require(amountADesired >= amountAMin);
        require(amountBDesired >= amountBMin);

        address _pair = ISnakeFactory(factory).getPair(tokenA, tokenB, stable);
        if (_pair == address(0)) {
            _pair = ISnakeFactory(factory).createPair(tokenA, tokenB, stable);
        }

        (uint256 reserveA, uint256 reserveB) = getReserves(
            tokenA,
            tokenB,
            stable
        );

        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = _quoteLiquidity(
                amountADesired,
                reserveA,
                reserveB
            );
            if (amountBOptimal > amountBDesired) {
                uint256 amountAOptimal = _quoteLiquidity(
                    amountBDesired,
                    reserveB,
                    reserveA
                );
                assert(amountAOptimal <= amountADesired);
                // Slippage check
                require(
                    amountAOptimal >= amountAMin,
                    "SnakeRouter: INSUFFICIENT_A_AMOUNT"
                );
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            } else {
                // Slippage check
                require(
                    amountBOptimal >= amountBMin,
                    "SnakeRouter: INSUFFICIENT_B_AMOUNT"
                );
                (amountA, amountB) = (amountADesired, amountBOptimal);
            }
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        require(token.code.length > 0);

        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        require(token.code.length > 0);

        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                from,
                to,
                amount
            )
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function _safeTransferWND(address to, uint256 amount) internal {
        (bool success, ) = to.call{value: amount}(new bytes(0));
        require(success, "WND_TRANSFER_FAILED");
    }

    function _swap(
        uint256[] memory amounts,
        Route[] memory routes,
        address _to
    ) internal virtual {
        for (uint256 i = 0; i < routes.length; i++) {
            (address token0, ) = sortToken(routes[i].token0, routes[i].token1);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = routes[i].token0 ==
                token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < routes.length - 1
                ? pairFor(
                    routes[i + 1].token0,
                    routes[i + 1].token1,
                    routes[i + 1].stable
                )
                : _to;
            ISnakePair(
                pairFor(routes[i].token0, routes[i].token0, routes[i].stable)
            ).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
}
