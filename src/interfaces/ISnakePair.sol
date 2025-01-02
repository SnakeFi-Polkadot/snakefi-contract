// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

interface ISnakePair {
    function claimFees() external returns (uint256, uint256);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function permit(
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    function mint(address receiver) external returns (uint256 lpAmount);

    function burn(
        address burner
    ) external returns (uint256 amount0, uint256 amount1);

    function setHasGauge(uint256, address) external;

    function setExternalBribe(address) external;

    function setVoter(address) external;

    /* ----------------------------- VIEW FUNCTIONS ----------------------------- */
    function metadata()
        external
        view
        returns (
            uint256 decimal0,
            uint256 decimal1,
            uint256 reserve0,
            uint256 reserve1,
            bool stable,
            address token0,
            address token1
        );

    function externalBribe() external view returns (address);

    function voter() external view returns (address);

    function factory() external view returns (address);

    function fees() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function tokens() external view returns (address, address);

    function getAmountOut(
        uint256 amountIn,
        address tokenIn
    ) external view returns (uint256 amountOut);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function totalSupply() external view returns (uint256);

    function decimals() external view returns (uint8);

    function claimable0(address _user) external view returns (uint256);

    function claimable1(address _user) external view returns (uint256);

    function hasGauge() external view returns (bool);

    function stable() external view returns (bool);

    function prices(
        address tokenIn,
        uint256 amountIn,
        uint256 points
    ) external view returns (uint256[] memory);

    function balanceOf(address _user) external view returns (uint256);

    function allowance(
        address _owner,
        address _spender
    ) external view returns (uint256);

    function getReserves() external view returns (uint256, uint256, uint256);
}
