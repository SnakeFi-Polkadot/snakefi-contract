// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

import {ISnakeFactory} from "../interfaces/ISnakeFactory.sol";
import {SnakePair} from "./SnakePair.sol";

contract SnakeFactory is ISnakeFactory {

    uint256 public stableFee;
    uint256 public dynamicFee;
    uint256 public constant MAX_FEE = 50; // 0.5%
    uint256 public constant WAD_FEE = 100;

    bool public isPaused;
    address public pauser;
    address public feeSetter;
    address public override voter;
    address public team;
    address public override tank;
    address public immutable deployer;

    /* ------------------- token0 -> token1 -> stable -> pair ------------------- */
    mapping(address => mapping(address => mapping(bool => address))) public override getPair;
    mapping(address => bool) public override isPair;
    address[] public allPairs;

    /* ------------------------- Track the creation history ------------------------- */
    address internal _token0;
    address internal _token1;
    bool internal _stable;

    /* ---------------------------------- EVENT --------------------------------- */
    event PairCreated(address indexed token0, address indexed token1, bool stable, address pair, uint256);

    constructor() {
        pauser = msg.sender;
        isPaused = false;
        feeSetter = msg.sender;
        stableFee = 2; // 0.02%
        dynamicFee = 20; // 0.2%
        deployer = msg.sender;
    }

    function setTeam(address _team) external {
        require(msg.sender == deployer, "No permission");
        require(team == address(0), "Already Initialized");
        team = _team;
    }

    function setVoter(address _voter) external {
        require(msg.sender == deployer, "No permission");
        require(voter == address(0), "Already Initialized");
        voter = _voter;
    }

    function setTank(address _tank) external {
        require(msg.sender == deployer, "No permission");
        require(tank == address(0), "Already Initialized");
        team = _team;
    }

    function setPause(bool _pause) external {
        require(msg.sender == pauser, "No permission");
        pause = _pause;
    }
    
    function setFeeSetter(address _feeSetter) external {
        require(msg.sender == deployer, "No permission");
        feeSetter = _feeSetter;
    }

    function setFee(bool _stable_, uint256 _fee) external {
        require(msg.sender == feeSetter, "No permission");
        require(_fee <= MAX_FEE, "Exceeds max fee");
        require(_fee == 0, "Fee must be nonzero");
        if (_stable_) {
            stableFee = _fee;
        }
        else {
            dynamicFee = _fee;
        }
    }

    function createPair(address token0, address token1, bool stable) external override returns(address pair) {
        require(token0 != token1, "IA"); // "Pair: IDENTICAL_ADDRESSES"
        (address tokenA, address tokenB) = token0 < token1 ? (token0, token1) : (token1, token0);
        require(tokenA != address(0), "ZA"); // "Pair: ZERO_ADDRESS"
        require(getPair(tokenA, tokenB, stable) == address(0), "PE"); // "Pair: Pair Exists"
        bytes32 salt = keccak256(abi.encodePacked(
            tokenA,
            tokenB,
            stable
        ));
        (_token0, _token1, _stable) = (tokenA, tokenB, stable);
        pair = address(new SnakePair{salt: salt}());
        getPair[tokenA][tokenB][stable] = pair;
        getPair[tokenB][tokenA][stable] = pair;
        isPair[pair] = true;
        allPairs.push(pair);
        
        emit PairCreated(tokenA, tokenB, stable, pair, allPairs.length);
    }

    /* ------------------------------ VIEW FUNCTIONS ----------------------------- */

    function allPairLength() external view override returns(uint256) {
        return allPairs.length;
    }

    function pairCodeHash() external pure returns(bytes32) {
        return keccak256(type(SnakePair).creationCode);
    }

    function getInitializable() external view returns(address, address, bool) {
        return (_token0, _token1, _stable);
    }
}