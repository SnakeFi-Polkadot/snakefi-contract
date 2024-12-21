// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title SnakePairFees
/// @author Thenafi (https://github.com/ThenafiBNB/THENA-Contracts/blob/main/contracts/PairFees.sol)
/// @notice This contract is used as 1:1 pair relationship with SnakePair contract to separate fees from the main contract
contract SnakePairFees {
    address internal immutable pair;
    address internal immutable token0;
    address internal immutable token1;

    uint256 public toStake0;
    uint256 public toStake1;

    constructor(address _token0, address _token1) {
        pair = msg.sender;
        token0 = _token0;
        token1 = _token1;
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        require(token.code.length > 0, "SnakePairFees: invalid token");

        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SnakePairFees: TRANSFER_FAILED");
    }

    function claimFeesFor(address receiver, uint256 amount0, uint256 amount1) external {
        require(msg.sender == pair, "SnakePairFees: FORBIDDEN");
        if (amount0 > 0) _safeTransfer(token0, receiver, amount0);
        if (amount1 > 0) _safeTransfer(token1, receiver, amount1);
    }

    function processStakingFees(uint256 amount, bool isTokenZero) external {
        require(msg.sender == pair, "SnakePairFees: FORBIDDEN");
        if (amount > 0 && isTokenZero) toStake0 += amount;
        if (amount > 0 && !isTokenZero) toStake1 += amount;
    }

    function withdrawStakingFees(address receiver) external {
        require(msg.sender == pair, "SnakePairFees: FORBIDDEN");
        if (toStake0 > 0) {
            _safeTransfer(token0, receiver, toStake0);
            toStake0 = 0;
        }
        if (toStake1 > 0) {
            _safeTransfer(token1, receiver, toStake1);
            toStake1 = 0;
        }
    }
}
