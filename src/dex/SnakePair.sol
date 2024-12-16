// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

import {ISnakePair} from "../interfaces/ISnakePair.sol";

contract SnakePair is ISnakePair {

    struct Observation {
        uint256 timestamp;
        uint256 reserve0Cumulative;
        uint256 reserve1Cumulative;
    }

    string public immutable name;
    string public immutable symbol;
    uint8 public constant decimals = 18;

    bool public immutable stable;

    bytes32 internal DOMAIN_SEPARATOR;
    // keccak256(Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline))
    bytes32 internal constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint256) public nonces;

    uint256 public totalSupply = 0;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public balanceOf;

    address public immutable token0;
    address public immutable token1;
    address public immutable fees; // Address to receive trading fees
    address public immutable factory;
    //TODO: Implement the address of external bribe
    // address public immutable externalBribe;
    address public immutable voter; 
    //TODO: Implement the address of tank which holds the liquidity or other meaning !!!
    // address public immutable tank;
    bool public hasGauge;

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

    /* ---------------------------------- EVENT --------------------------------- */
    event Transfer(address indexed from, address indexed to, uint256 amount);

    // event 

    /* ---------------------------------- ERROR --------------------------------- */

    // error 

    /* -------------------------------- MODIFIER -------------------------------- */


    constructor() {}
}