// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

/// @title Governor
/// @author Modified from https://github.com/withtally/rollcall/blob/main/src/standards/L2Governor.sol
abstract contract Governor is
    Context,
    ERC165,
    EIP712,
    IGovernor,
    Nonces,
    IERC721Receiver,
    IERC1155Receiver
{
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    using SafeCast for uint256;

    bytes32 public constant BALLOT_TYPEHASH =
        keccak256("Ballot(uint256 proposalId,uint8 support)");
    bytes32 public ADVANCED_BALLOT_TYPEHASH =
        keccak256(
            "AdvancedBallot(uint256 proposalId,uint8 support,string reason)"
        );

    struct ProposalCore {
        address proposer;
        uint256 voteStart;
        uint256 voteEnd;
        bool executed;
        bool canceled;
        //  uint48 etaSeconds;
    }

    string private _name;

    mapping(uint256 => ProposalCore) private _proposals;

    DoubleEndedQueue.Bytes32Deque private _governanceCalls;

    modifier onlyGovernance() {
        require(_msgSender() == _executor(), "Governor: FORBIDDEN");
        if (_executor() != address(this)) {
            bytes32 msgDataHash = keccak256(_msgData());
            while (_governanceCalls.popFront() != msgDataHash) {}
        }
        _;
    }

    constructor(string memory _name_) EIP712(_name_, version()) {
        _name = _name_;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    receive() external payable virtual {
        require(_executor() == address(this));
    }

    function propose(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        string memory _description
    ) public virtual override returns (uint256 proposalId) {
        require(
            getVotes(_msgSender(), block.timestamp - 1) >= proposalThreshold(),
            "Governor: proposer votes below proposal threshold"
        );

        proposalId = hashProposal(
            _targets,
            _values,
            _calldatas,
            keccak256(bytes(_description))
        );

        require(
            _targets.length == _values.length,
            "Governor: invalid proposal length"
        );
        require(
            _targets.length == _calldatas.length,
            "Governor: invalid proposal length"
        );
        require(_targets.length > 0, "Governor: empty proposal");

        ProposalCore storage proposal = _proposals[proposalId];
        require(proposal.voteStart == 0, "Governor: proposal already exists");
        uint64 start = block.timestamp.toUint64() - votingDelay().toUint64();
        uint256 end = start + votingPeriod().toUint64();
        proposal.proposer = _msgSender();
        proposal.voteStart = start;
        proposal.voteEnd = end;

        emit ProposalCreated(
            proposalId,
            _msgSender(),
            _targets,
            _values,
            new string[](_targets.length),
            _calldatas,
            start,
            end,
            _description
        );
    }

    function cancel(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        bytes32 _descriptionHash
    ) public virtual override returns (uint256 proposalId) {
        proposalId = hashProposal(
            _targets,
            _values,
            _calldatas,
            _descriptionHash
        );

        ProposalState status = state(proposalId);

        require(
            status != ProposalState.Pending,
            "Governor: proposal not active"
        );
        if (_msgSender() != proposalProposer(proposalId)) {
            revert GovernorOnlyProposer(_msgSender());
        }

        return _cancel(_targets, _values, _calldatas, _descriptionHash);
    }

    function queue(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public virtual override returns (uint256 proposalId) {}

    function execute(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        bytes32 _descriptionHash
    ) public payable virtual override returns (uint256 proposalId) {
        proposalId = hashProposal(
            _targets,
            _values,
            _calldatas,
            _descriptionHash
        );

        ProposalState status = state(proposalId);

        require(
            status == ProposalState.Queued || status == ProposalState.Succeeded,
            "Governor: proposal not successfully"
        );
        _proposals[proposalId].executed = true;

        emit ProposalExecuted(proposalId);

        _beforeExecute(
            proposalId,
            _targets,
            _values,
            _calldatas,
            _descriptionHash
        );
        _execute(proposalId, _targets, _values, _calldatas, _descriptionHash);
        _afterExecute(
            proposalId,
            _targets,
            _values,
            _calldatas,
            _descriptionHash
        );
    }

    function castVote(
        uint256 _proposalId,
        uint8 _support
    ) public virtual returns (uint256) {
        address voter = _msgSender();
        return _castVote(_proposalId, voter, _support, "");
    }

    function castVoteWithReason(
        uint256 _proposalId,
        uint8 _support,
        string memory _reason
    ) public virtual returns (uint256) {
        address voter = _msgSender();
        return _castVote(_proposalId, voter, _support, _reason);
    }

    function castVoteWithReasonAndParams(
        uint256 _proposalId,
        uint8 _support,
        string calldata _reason,
        bytes memory // params
    ) public virtual returns (uint256) {
        address voter = _msgSender();
        return _castVote(_proposalId, voter, _support, _reason);
    }

    function castVoteBySig(
        uint256 _proposalId,
        uint8 _support,
        address _voter,
        bytes memory _signature
    ) public virtual override returns (uint256) {
        bool valid = SignatureChecker.isValidSignatureNow(
            _voter,
            _hashTypedDataV4(
                keccak256(
                    abi.encode(BALLOT_TYPEHASH, _proposalId, _support, _voter)
                )
            ),
            _signature
        );
        if (!valid) {
            revert("Governor: invalid signature");
        }
        return _castVote(_proposalId, _voter, _support, "");
    }

    function castVoteWithReasonAndParamsBySig(
        uint256 _proposalId,
        uint8 _support,
        address _voter,
        string memory _reason,
        bytes memory _params,
        bytes memory _signature
    ) public virtual returns (uint256) {
        bool valid = SignatureChecker.isValidSignatureNow(
            _voter,
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        ADVANCED_BALLOT_TYPEHASH,
                        _proposalId,
                        _support,
                        _voter,
                        _useNonce(_voter),
                        keccak256(bytes(_reason)),
                        keccak256(_params)
                    )
                )
            ),
            _signature
        );
        if (!valid) {
            revert("Governor: invalid signature");
        }
        return _castVote(_proposalId, _voter, _support, _reason, _params);
    }

    function relay(
        address _target,
        uint256 _value,
        bytes memory _params
    ) external virtual onlyGovernance {
        Address.functionCallWithValue(_target, _params, _value);
    }

    /* -------------------------------------------------------------------------- */
    /*                               VIEW FUNCTIONS                               */
    /* -------------------------------------------------------------------------- */

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(IERC165, ERC165) returns (bool) {
        return
            interfaceId == type(IGovernor).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function version() public pure override returns (string memory) {
        return "1.0.0";
    }

    function hashProposal(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        bytes32 _descriptionHash
    ) public pure virtual override returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encode(_targets, _values, _calldatas, _descriptionHash)
                )
            );
    }

    function state(uint256 _proposalId) public view returns (ProposalState) {
        ProposalCore storage proposal = _proposals[_proposalId];

        if (proposal.executed) {
            return ProposalState.Executed;
        }

        if (proposal.canceled) {
            return ProposalState.Canceled;
        }

        uint256 startTime = proposalSnapshot(_proposalId);

        if (startTime == 0) {
            revert("Governor: proposal not found");
        }

        if (block.timestamp < startTime) {
            return ProposalState.Pending;
        }

        uint256 deadline = proposalDeadline(_proposalId);
        if (block.timestamp <= deadline) {
            return ProposalState.Active;
        }

        if (_quorumReached(_proposalId) && _voteSucceeded(_proposalId)) {
            return ProposalState.Succeeded;
        } else {
            return ProposalState.Defeated;
        }
    }

    function proposalSnapshot(
        uint256 _proposalId
    ) public view virtual override returns (uint256) {
        return _proposals[_proposalId].voteStart;
    }

    function proposalDeadline(
        uint256 _proposalId
    ) public view virtual override returns (uint256) {
        return _proposals[_proposalId].voteEnd;
    }

    function proposalThreshold() public view virtual returns (uint256) {
        return 0;
    }

    function getVotes(
        address _account,
        uint256 _blockTimestamp
    ) public view virtual override returns (uint256) {
        return _getVotes(_account, _blockTimestamp, _defaultParams());
    }

    function getVotesWithParams(
        address _account,
        uint256 _blockTimestamp,
        bytes memory _params
    ) public view virtual override returns (uint256) {
        return _getVotes(_account, _blockTimestamp, _params);
    }

    function proposalEta(
        uint256 // proposalId
    ) public view virtual override returns (uint256) {
        return 0;
    }

    function proposalNeedsQueuing(
        uint256
    ) public view virtual override returns (bool) {
        return false;
    }

    function proposalProposer(
        uint256 proposalId
    ) public view virtual override returns (address) {
        return _proposals[proposalId].proposer;
    }

    function clock() public view virtual returns (uint48);

    function CLOCK_MODE() public view virtual returns (string memory);

    function votingDelay() public view virtual returns (uint256);

    function votingPeriod() public view virtual returns (uint256);

    function quorum(uint256 timestamp) public view virtual returns (uint256);

    /* -------------------------------------------------------------------------- */
    /*                             INTERNAL FUNCTIONS                             */
    /* -------------------------------------------------------------------------- */

    function _beforeExecute(
        uint256, // _proposalId
        address[] memory _targets,
        uint256[] memory, // _values
        bytes[] memory _calldatas,
        bytes32 // _descriptionHash
    ) internal virtual {
        if (_executor() != address(this)) {
            for (uint256 i = 0; i < _targets.length; i++) {
                if (_targets[i] == address(this)) {
                    _governanceCalls.pushBack(keccak256(_calldatas[i]));
                }
            }
        }
    }

    function _afterExecute(
        uint256, // _proposalId
        address[] memory, // _targets
        uint256[] memory, // _values
        bytes[] memory, // _calldatas
        bytes32 // _descriptionHash
    ) internal virtual {
        if (_executor() != address(this)) {
            if (!_governanceCalls.empty()) {
                _governanceCalls.clear();
            }
        }
    }

    function _execute(
        uint256, // _proposalId
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        bytes32 // _descriptionHash
    ) internal {
        for (uint256 i = 0; i < _targets.length; i++) {
            (bool success, bytes memory data) = _targets[i].call{
                value: _values[i]
            }(_calldatas[i]);
            Address.verifyCallResult(success, data);
        }
    }

    function _cancel(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        bytes32 _descriptionHash
    ) internal virtual returns (uint256 proposalId) {
        proposalId = hashProposal(
            _targets,
            _values,
            _calldatas,
            _descriptionHash
        );
        ProposalState status = state(proposalId);

        require(
            status != ProposalState.Canceled &&
                status != ProposalState.Expired &&
                status != ProposalState.Executed,
            "Governor: proposal not active"
        );
        _proposals[proposalId].canceled = true;
        emit ProposalCanceled(proposalId);
    }

    function _castVote(
        uint256 _proposalId,
        address _account,
        uint8 _support,
        string memory _reason
    ) internal virtual returns (uint256) {
        return
            _castVote(
                _proposalId,
                _account,
                _support,
                _reason,
                _defaultParams()
            );
    }

    function _castVote(
        uint256 _proposalId,
        address _account,
        uint8 _support,
        string memory _reason,
        bytes memory _params
    ) internal virtual returns (uint256 totalWeight) {
        ProposalCore storage proposal = _proposals[_proposalId];
        require(
            state(_proposalId) == ProposalState.Active,
            "Governor: voting not currently active"
        );
        totalWeight = _getVotes(_account, proposal.voteStart, _params);
        _countVote(_proposalId, _account, _support, totalWeight, _params);
        if (_params.length == 0) {
            emit VoteCast(
                _account,
                _proposalId,
                _support,
                totalWeight,
                _reason
            );
        } else {
            emit VoteCastWithParams(
                _account,
                _proposalId,
                _support,
                totalWeight,
                _reason,
                _params
            );
        }
    }

    /// @notice Must to override this function
    /// @dev Check whether the quorum of the proposal reached
    function _quorumReached(
        uint256 _proposalId
    ) internal view virtual returns (bool);

    /// @notice Must to override this function
    /// @dev Check whether the vote succeeded
    function _voteSucceeded(
        uint256 _proposalId
    ) internal view virtual returns (bool);

    /// @dev Register a vote with a given support and voting weight
    function _countVote(
        uint256 _proposalId,
        address _account,
        uint8 _support,
        uint256 weight,
        bytes memory params
    ) internal virtual returns (uint256);

    function _getVotes(
        address _account,
        uint256 _blockTimestamp,
        bytes memory _params
    ) internal view virtual returns (uint256);

    function _defaultParams() internal view virtual returns (bytes memory) {
        return "";
    }

    function _executor() internal view virtual returns (address) {
        return address(this);
    }
}
