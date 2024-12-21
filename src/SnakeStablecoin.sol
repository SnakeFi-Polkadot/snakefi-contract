// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

import {IERC20Metadata} from "./interfaces/IERC20Metadata.sol";

import {ISnakeStableCoin} from "./interfaces/ISnakeStableCoin.sol";

contract SnakeStablecoin is ISnakeStableCoin, IERC20Metadata {
    string public constant override name = "SNAKE_FINANCE STABLECOIN";
    string public constant override symbol = "SAE";
    uint8 public constant override decimals = 18;

    uint256 public override totalSupply;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    bool public initialized;
    address public minter;

    /* --------------------------------- EVENTS --------------------------------- */
    event Transfer(address indexed from, address indexed to, uint256 amount);

    event Approval(address indexed owner, address indexed spender, uint256 amount);

    constructor(address _minter) {
        minter = _minter;
    }

    function setMinter(address _minter) external override {
        require(msg.sender == minter, "No permission");
        minter = _minter;
    }

    function initialSupply(address receiver, uint256 supply) external override {
        require(!initialized, "Already Initialized");
        require(msg.sender == minter, "No permission");
        initialized = true;

        _mint(receiver, supply);
    }

    function mint(address receiver) external override {
        require(msg.sender == minter, "No permission");
        _mint(receiver, 1 * 10 ** 18);
    }

    function approve(address _spender, uint256 _amount) external override {
        allowance[msg.sender][_spender] = _amount;
        emit Approval(msg.sender, _spender, _amount);
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(allowance[from][msg.sender] >= amount, "Insufficient Allowance");

        // Cannot underflow
        unchecked {
            allowance[from][msg.sender] -= amount;
        }

        return _transfer(from, to, amount);
    }

    /* --------------------------- INTERNAL FUNCTIONS --------------------------- */

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient Balance");

        unchecked {
            balanceOf[from] -= amount;
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);
        return true;
    }

    function _mint(address receiver, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[receiver] += amount;

        emit Transfer(address(0), receiver, amount);
    }
}
