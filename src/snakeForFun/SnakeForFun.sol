// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title S_N_A_K_E__F_O_R__F_U_N
/// @notice This contract is used to airdrop S_N_A_K_E tokens to users for fun
contract SnakeForFun {
    using ECDSA for bytes32;

    address public team;

    IERC20 public snakeToken;

    struct Snake {
        uint256 snapshotTime;
        address signer;
        uint256 totalSnake;
        mapping(address => bool) snaked;
    }

    /// @dev current turn id
    uint256 internal snakeId;

    /// @dev snakes
    mapping(uint256 => Snake) internal snakes;

    bytes32 public immutable EIP712_DOMAIN;

    bytes32 public constant SUPPORT_TYPEHASH =
        keccak256("ForFun(address forFunGuy,uint256 amount)");

    uint256 public constant MAX_ALLOCATION = 5;

    /// @dev allocation
    mapping(uint256 => mapping(uint256 => uint256)) internal allocations;

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    event BitedForFun(
        uint256 indexed turnId,
        address indexed forFunGuy,
        uint256 amount,
        uint256 snapshotTime
    );

    event ForFun(address indexed forFunGuy, uint256 amount);

    constructor(address _team, address _snakeToken) {
        team = _team;
        snakeToken = IERC20(_snakeToken);

        EIP712_DOMAIN = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("SnakeForFun")),
                keccak256(bytes("v1")),
                block.chainid,
                address(this)
            )
        );
    }

    modifier onlyTeam() {
        require(msg.sender == team, "SnakeForFun: FORBIDDEN");
        _;
    }

    function biteForFun(
        uint256 totalSnake,
        address signer,
        uint256[] memory allocation
    ) external onlyTeam {
        require(
            totalSnake <= MAX_ALLOCATION && totalSnake > 0,
            "SnakeForFun: INVALID_ALLOCATION"
        );
        require(
            totalSnake == allocation.length,
            "SnakeForFun: INVALID_ALLOCATION"
        );
        snakeId++;
        Snake storage snake = snakes[snakeId];
        snake.signer = signer;
        snake.totalSnake = totalSnake;
        snake.snapshotTime = block.timestamp;
        for (uint256 i = 0; i < totalSnake; ) {
            allocations[snakeId][i] = allocation[i];
            unchecked {
                i++;
            }
        }

        emit BitedForFun(snakeId, signer, totalSnake, block.timestamp);
    }

    function forFun(
        uint256 _turnId,
        bytes calldata _signature,
        address _guy,
        uint256 _amount
    ) external {
        Snake storage snake = snakes[_turnId];
        require(!snake.snaked[_guy], "SnakeForFun: ALREADY_SNAKED");

        bytes32 digest = toTypedDataHash(_guy, _amount);
        address sigSigner = digest.recover(_signature);

        require(sigSigner == snake.signer, "SnakeForFun: INVALID_SIGNATURE");

        require(sigSigner != address(0), "SnakeForFun: INVALID_SIGNATURE");

        snakes[_turnId].snaked[_guy] = true;
        snakeToken.transfer(_guy, _amount);

        emit ForFun(_guy, _amount);
    }

    function snapshotTime(uint256 _turnId) external view returns (uint256) {
        return snakes[_turnId].snapshotTime;
    }

    function totalSnake(uint256 _turnId) external view returns (uint256) {
        return snakes[_turnId].totalSnake;
    }

    function signer(uint256 _turnId) external view returns (address) {
        return snakes[_turnId].signer;
    }

    function snaked(
        uint256 _turnId,
        address _guy
    ) external view returns (bool) {
        return snakes[_turnId].snaked[_guy];
    }

    function allocation(
        uint256 _turnId,
        uint256 _index
    ) external view returns (uint256) {
        return allocations[_turnId][_index];
    }

    function toTypedDataHash(
        address _forFunGuy,
        uint256 _amount
    ) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(SUPPORT_TYPEHASH, _forFunGuy, _amount)
        );
        return MessageHashUtils.toTypedDataHash(EIP712_DOMAIN, structHash);
    }
}
