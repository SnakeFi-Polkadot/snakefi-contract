// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

import {ISnakeFactory} from "../interfaces/ISnakeFactory.sol";
import {SnakePair} from "./SnakePair.sol";

contract SnakeFactory is ISnakeFactory {
    /// @notice MAX_REFERRAL_FEE is the maximum referral fee for each trader in the referral system that can be set for the referral program
    /// @return Documents the return variables of a contract’s function state variable
    uint256 public constant MAX_REFERRAL_FEE = 1200; // 12%
    uint256 public constant MAX_FEE = 50; // 0.5%
    uint256 public constant WAD_FEE = 100;

    uint256 public stableFee;
    uint256 public volatileFee;

    uint256 public stakingNFTFee;

    bool public isPaused;
    address public pauser;

    address public feeSetter;
    address public override voter;

    address public override stakingFeeHandler; // Staking Fee Handler
    address public override referrerFeeHandler; // Referral Fee Handler

    bool public initial_staking_fee_handler;
    bool public initial_referral_fee_handler;

    address public team; // Team wallet could be multisig or distinct with the deployer
    address public immutable deployer; // This deployer address could be same as the feeSetter

    /* ------------------- token0 -> token1 -> snake -> pair ------------------- */
    mapping(address => mapping(address => mapping(bool => address))) public override getPair;
    mapping(address => bool) public override isPair;
    address[] public allPairs;

    /* ------------------------- Track the creation history ------------------------- */
    address internal _token0;
    address internal _token1;
    bool internal _stable;

    /* ---------------------------------- EVENT --------------------------------- */
    event PairCreated(address indexed token0, address indexed token1, bool snake, address pair, uint256);

    constructor() {
        pauser = msg.sender;
        isPaused = false;
        feeSetter = msg.sender;
        stableFee = 2; // 0.02%
        volatileFee = 20; // 0.2%
        // snakeFee = 20; // 0.2%
        stakingNFTFee = 1000; // 10% of stable / volatile fee
        deployer = msg.sender;
    }

    function setStakingFeeHandler(address _stakingFeeHandler) external {
        require(msg.sender == deployer, "No permission");
        require(!initial_staking_fee_handler, "Already Initialized");
        stakingFeeHandler = _stakingFeeHandler;
        initial_staking_fee_handler = true;
    }

    function setReferralFeeHandler(address _referrerFeeHandler) external {
        require(msg.sender == deployer, "No permission");
        require(!initial_referral_fee_handler, "Already Initialized");
        referrerFeeHandler = _referrerFeeHandler;
        initial_referral_fee_handler = true;
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

    function setPause(bool _isPaused) external {
        require(msg.sender == pauser, "No permission");
        isPaused = _isPaused;
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
        } else {
            volatileFee = _fee;
        }
    }

    function createPair(address token0, address token1, bool stable) external override returns (address pair) {
        require(token0 != token1, "IA"); // "Pair: IDENTICAL_ADDRESSES"
        (address tokenA, address tokenB) = token0 < token1 ? (token0, token1) : (token1, token0);
        require(tokenA != address(0), "ZA"); // "Pair: ZERO_ADDRESS"
        require(getPair[tokenA][tokenB][stable] == address(0), "PE"); // "Pair: Pair Exists"
        bytes32 salt = keccak256(abi.encodePacked(tokenA, tokenB, stable));
        (_token0, _token1, _stable) = (tokenA, tokenB, stable);
        pair = address(new SnakePair{salt: salt}());
        getPair[tokenA][tokenB][stable] = pair;
        getPair[tokenB][tokenA][stable] = pair;
        isPair[pair] = true;
        allPairs.push(pair);

        emit PairCreated(tokenA, tokenB, stable, pair, allPairs.length);
    }

    /* ------------------------------ VIEW FUNCTIONS ----------------------------- */

    function allPairLength() external view override returns (uint256) {
        return allPairs.length;
    }

    function pairCodeHash() external pure override returns (bytes32) {
        return keccak256(type(SnakePair).creationCode);
    }

    function getInitializable() external view override returns (address, address, bool) {
        return (_token0, _token1, _stable);
    }

    function getFee(bool _stable_) external view override returns (uint256) {
        return _stable_ ? stableFee : volatileFee;
    }
}
