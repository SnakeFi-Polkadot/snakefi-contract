// // SPDX-Identifier-License: MIT
// pragma solidity 0.8.20;

// import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// import {IERC20Metadata} from "./interfaces/IERC20Metadata.sol";
// import {ISnake} from "./interfaces/ISnake.sol";
// import {IERC404Operator} from "./interfaces/IERC404Operator.sol";
// import {ERC721Receiver} from "./ERC721Receiver.sol";

// contract Snake is ISnake, IERC20Metadata, ERC721Receiver {

//     string public override name;

//     string public override symbol;

//     uint8 public immutable override decimals;

//     uint256 public immutable override totalSupply;

//     mapping(address => uint256) public override balanceOf;

//     mapping(address => mapping(address => uint256)) public override allowance;

//     mapping(uint256 => address) public override getApproved;

//     mapping(address => mapping(address => bool)) public override isApprovedForAll;

//     mapping(uint256 => address) internal _ownerOf;

//     mapping(address => uint256[]) internal _owned;

//     mapping(uint256 => uint256) internal _ownedIndex;

//     mapping(address => bool) public whitelist;

//     IERC404Operator public operator;

//     address public router;

//     address public factory;

//     /* --------------------------------- EVENTS --------------------------------- */
    
//     event ERC20Transfer(address indexed from , address indexed to, uint256 amount);

//     event Approval(address indexed owner, address indexed spender, uint256 amount);

//     event Transfer(address indexed from, address indexed to, uint256 amount);

//     event ERC721Transfer(address indexed from, address indexed to, uint256 id);

//     event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

//     /* -------------------------------------------------------------------------- */
//     /*                                   ERRORS                                   */
//     /* -------------------------------------------------------------------------- */
//     error NotFound();
//     error AlreadyExists();
//     error InvalidRecipient();
//     error InvalidSender();
//     error UnsafeRecipient();

//     constructor(
//         string memory _name,
//         string memory _symbol,
//         address _nft,
//         address _router,
//         address _factory;
//     ) {
//         name = _name;
//         symbol = _symbol;
//         nft = IERC721(_nft);
//         router = _router;
//         factory = _factory;
//     }

//     function snakeNFT(uint256 tokenId) external {
//         require(!migrated[tokenId], "Already migrated");
//         address sender = msg.sender;
//         require(sender == nft.ownerOf(tokenId), "Not the owner of the NFT");

//         // TODO: Mint token for nft owner;
//     }

//     /* -------------------------------------------------------------------------- */
//     /*                             INTERNAL FUNCTIONS                             */
//     /* -------------------------------------------------------------------------- */
//     function _transfer(address from, address to, uint256 amount) internal returns (bool) {
//         require(from != address(0), 'ERC20: transfer from the zero address');
//         uint256 balanceBeforeSender = balanceOf[from];
//         uint256 balanceBeforeReceiver = balanceOf[to];

//         balanceOf[from] -= amount;

//         unchecked {
//             balanceOf[to] += amount;
//         }

//         if (operator.approveOperator(address(this), from)) {
//             uint256 
//         }
//     }

//     function _getUnit() internal view returns (uint256) {
//         return 10 ** decimals();
//     }
// }
