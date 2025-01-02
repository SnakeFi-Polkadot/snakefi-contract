// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

import {IVoter} from "./interfaces/IVoter.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";
import {IGauge} from "./interfaces/IGauge.sol";
import {IMinter} from "./interfaces/IMinter.sol";
import {ISnakePair} from "./interfaces/ISnakePair.sol";
import {ISnakeFactory} from "./interfaces/ISnakeFactory.sol";
import {IBribeFactory} from "./interfaces/IBribeFactory.sol";
import {IGaugeFactory} from "./interfaces/IGaugeFactory.sol";
import {IBribe} from "./interfaces/IBribe.sol";
import {IERC20} from "./interfaces/IERC20.sol";

contract Voter {
    uint256 public constant DURATION = 7 * 24 * 60 * 60; // 7 days
    address public immutable VOTING_ESCROW;

    address public immutable votingEscrowToken;

    // Array of the pair factories consists of the external protocol factories as well
    address[] public factories;
    address[] public gaugeFactories;
    address public bribeFactory;
    address public minter;
    address public governor;
    address public emergencyCouncil;

    uint256 public totalWeight;
    uint256 public activeGaugeNumber;
    uint256 public currentEpochRewardAmount;
    uint256 public minShareForActiveGauge = 1e16; // share of total rewards required to be considered active gauge 1e18 = 100%
    address[] public pools;
    address[] public killedGauges;

    // pool -> gauge
    mapping(address => address) public gauges;
    // gauge -> pool
    mapping(address => address) public poolForGauge;
    // gauge -> external bribe
    mapping(address => address) public externalBribes;
    // pool -> weight
    mapping(address => uint256) public weights;
    // nft -> pool -> votes
    mapping(uint256 => mapping(address => uint256)) public votes;
    // nft -> pools
    mapping(uint256 => address[]) public poolVotes;
    // nft -> total voting weight of users
    mapping(uint256 => uint256) public usedWeights;
    // nft -> timestamp of last vote to ensure one vote per epoch
    mapping(uint256 => uint256) public lastVoted;

    mapping(address => bool) public isGauge;
    mapping(address => bool) public isWhitelisted;
    mapping(address => bool) public isAlive;
    mapping(address => bool) public isFactory;
    mapping(address => bool) public isGaugeFactory;

    /* --------------------------------- EVENTS --------------------------------- */

    event GaugeCreated(
        address indexed gauge,
        address creator,
        address indexed external_bribe,
        address indexed pool
    );
    event GaugeKilledTotally(address indexed gauge);
    event GaugePaused(address indexed gauge);
    event GaugeRestarted(address indexed gauge);
    event Voted(address indexed voter, uint tokenId, uint256 weight);
    event Abstained(uint tokenId, uint256 weight);
    event Deposit(
        address indexed lp,
        address indexed gauge,
        uint tokenId,
        uint amount
    );
    event Withdraw(
        address indexed lp,
        address indexed gauge,
        uint tokenId,
        uint amount
    );
    event NotifyReward(
        address indexed sender,
        address indexed reward,
        uint amount
    );
    event DistributeReward(
        address indexed sender,
        address indexed gauge,
        uint amount
    );
    event Attach(address indexed owner, address indexed gauge, uint tokenId);
    event Detach(address indexed owner, address indexed gauge, uint tokenId);
    event Whitelisted(address indexed whitelister, address indexed token);
    event WhitelistedForGaugeCreation(
        address indexed whitelister,
        address indexed token
    );
    event Blacklisted(address indexed blacklister, address indexed token);
    event BlacklistedForGaugeCreation(
        address indexed blacklister,
        address indexed token
    );
    event BribeFactorySet(address indexed setter, address newBribeFatory);
    event ExternalBribeSet(
        address indexed setter,
        address indexed gauge,
        address externalBribes
    );
    event FactoryAdded(
        address indexed setter,
        address indexed pairFactory,
        address indexed gaugeFactory
    );
    event FactoryReplaced(
        address indexed setter,
        address indexed pairFactory,
        address indexed gaugeFactory,
        uint256 pos
    );
    event FactoryRemoved(address indexed setter, uint256 indexed pos);

    constructor(
        address _VOTING_ESCROW,
        address _factory,
        address _gauge,
        address _bribe
    ) {
        VOTING_ESCROW = _VOTING_ESCROW;
        votingEscrowToken = IVotingEscrow(_VOTING_ESCROW).token();

        factories.push(_factory);
        isFactory[_factory] = true;

        gaugeFactories.push(_gauge);
        isGaugeFactory[_gauge] = true;

        bribeFactory = _bribe;
        minter = msg.sender;
        governor = msg.sender;
        emergencyCouncil = msg.sender;
    }

    uint8 internal unlock = 1;
    modifier lock() {
        require(unlock == 1, "Voter: LOCKED");
        unlock = 2;
        _;
        unlock = 1;
    }

    modifier onlyNewEpoch(uint _tokenId) {
        // ensure new epoch since last vote
        require(
            (block.timestamp / DURATION) * DURATION > lastVoted[_tokenId],
            "TOKEN_ALREADY_VOTED_THIS_EPOCH"
        );
        _;
    }

    modifier onlyEmergencyCouncil() {
        require(msg.sender == emergencyCouncil, "not emergencyCouncil");
        _;
    }

    function initialize(address[] memory _tokens, address _minter) external {
        require(msg.sender == minter);
        for (uint i = 0; i < _tokens.length; i++) {
            _whitelist(_tokens[i]);
        }
        minter = _minter;
    }

    function setGovernor(address _governor) public {
        require(msg.sender == governor);
        governor = _governor;
    }

    function setEmergencyCouncil(address _council) public {
        require(msg.sender == governor);
        emergencyCouncil = _council;
    }

    function setBribeFactory(
        address _bribeFactory
    ) external onlyEmergencyCouncil {
        bribeFactory = _bribeFactory;
        emit BribeFactorySet(msg.sender, _bribeFactory);
    }

    function setExternalBribeFor(
        address _gauge,
        address _external
    ) external onlyEmergencyCouncil {
        require(isGauge[_gauge]);
        externalBribes[_gauge] = _external;
        address pool = poolForGauge[_gauge];
        try ISnakePair(pool).setExternalBribe(_external) {} catch {}
        emit ExternalBribeSet(msg.sender, _gauge, _external);
    }

    function addFactory(
        address _pairFactory,
        address _gaugeFactory
    ) external onlyEmergencyCouncil {
        require(_pairFactory != address(0), "addr 0");
        require(_gaugeFactory != address(0), "addr 0");
        require(!isGaugeFactory[_gaugeFactory], "g.fact true");

        factories.push(_pairFactory);
        gaugeFactories.push(_gaugeFactory);
        isFactory[_pairFactory] = true;
        isGaugeFactory[_gaugeFactory] = true;

        emit FactoryAdded(msg.sender, _pairFactory, _gaugeFactory);
    }

    function replaceFactory(
        address _pairFactory,
        address _gaugeFactory,
        uint256 _pos
    ) external onlyEmergencyCouncil {
        require(_pairFactory != address(0), "addr 0");
        require(_gaugeFactory != address(0), "addr 0");
        require(
            _pos < factoryLength() && _pos < gaugeFactoriesLength(),
            "_pos out of range"
        );
        require(isFactory[_pairFactory], "factory false");
        require(isGaugeFactory[_gaugeFactory], "g.fact false");
        address oldPF = factories[_pos];
        address oldGF = gaugeFactories[_pos];
        isFactory[oldPF] = false;
        isGaugeFactory[oldGF] = false;

        factories[_pos] = (_pairFactory);
        gaugeFactories[_pos] = (_gaugeFactory);
        isFactory[_pairFactory] = true;
        isGaugeFactory[_gaugeFactory] = true;

        emit FactoryReplaced(msg.sender, _pairFactory, _gaugeFactory, _pos);
    }

    function removeFactory(uint256 _pos) external onlyEmergencyCouncil {
        require(
            _pos < factoryLength() && _pos < gaugeFactoriesLength(),
            "_pos out of range"
        );
        address oldPF = factories[_pos];
        address oldGF = gaugeFactories[_pos];
        require(isFactory[oldPF], "factory false");
        require(isGaugeFactory[oldGF], "g.fact false");
        factories[_pos] = address(0);
        gaugeFactories[_pos] = address(0);
        isFactory[oldPF] = false;
        isGaugeFactory[oldGF] = false;

        emit FactoryRemoved(msg.sender, _pos);
    }

    function reset(uint _tokenId) external onlyNewEpoch(_tokenId) {
        require(
            IVotingEscrow(VOTING_ESCROW).isApprovedOrOwner(msg.sender, _tokenId)
        );
        _reset(_tokenId);
        IVotingEscrow(VOTING_ESCROW).abstain(_tokenId);
    }

    function _reset(uint _tokenId) internal {
        address[] storage _poolVote = poolVotes[_tokenId];
        uint _poolVoteCnt = _poolVote.length;
        uint256 _totalWeight = 0;

        for (uint i = 0; i < _poolVoteCnt; i++) {
            address _pool = _poolVote[i];
            uint256 _votes = votes[_tokenId][_pool];

            if (_votes != 0) {
                _updateFor(gauges[_pool]);
                weights[_pool] -= _votes;
                votes[_tokenId][_pool] -= _votes;
                if (_votes > 0) {
                    IBribe(externalBribes[gauges[_pool]]).withdraw(
                        uint256(_votes),
                        _tokenId
                    );
                    _totalWeight += _votes;
                } else {
                    _totalWeight -= _votes;
                }
                emit Abstained(_tokenId, _votes);
            }
        }
        totalWeight -= uint256(_totalWeight);
        usedWeights[_tokenId] = 0;
        delete poolVotes[_tokenId];
    }

    function poke(uint _tokenId) external onlyNewEpoch(_tokenId) {
        require(
            IVotingEscrow(VOTING_ESCROW).isApprovedOrOwner(
                msg.sender,
                _tokenId
            ) || msg.sender == governor
        );
        lastVoted[_tokenId] = block.timestamp;

        address[] memory _poolVote = poolVotes[_tokenId];
        uint _poolCnt = _poolVote.length;
        uint256[] memory _weights = new uint256[](_poolCnt);

        for (uint i = 0; i < _poolCnt; i++) {
            _weights[i] = votes[_tokenId][_poolVote[i]];
        }

        _vote(_tokenId, _poolVote, _weights);
    }

    function _vote(
        uint _tokenId,
        address[] memory _poolVote,
        uint256[] memory _weights
    ) internal {
        _reset(_tokenId);
        uint _poolCnt = _poolVote.length;
        uint256 _weight = IVotingEscrow(VOTING_ESCROW).balanceOfNFT(_tokenId);
        uint256 _totalVoteWeight = 0;
        uint256 _totalWeight = 0;
        uint256 _usedWeight = 0;

        for (uint i = 0; i < _poolCnt; i++) {
            _totalVoteWeight += _weights[i];
        }

        for (uint i = 0; i < _poolCnt; i++) {
            address _pool = _poolVote[i];
            address _gauge = gauges[_pool];

            if (isGauge[_gauge]) {
                require(isAlive[_gauge], "gauge already dead");
                uint256 _poolWeight = (_weights[i] * _weight) /
                    _totalVoteWeight;
                require(votes[_tokenId][_pool] == 0);
                require(_poolWeight != 0);
                _updateFor(_gauge);

                poolVotes[_tokenId].push(_pool);

                weights[_pool] += _poolWeight;
                votes[_tokenId][_pool] += _poolWeight;
                IBribe(externalBribes[_gauge]).deposit(
                    uint256(_poolWeight),
                    _tokenId
                );
                _usedWeight += _poolWeight;
                _totalWeight += _poolWeight;
                emit Voted(msg.sender, _tokenId, _poolWeight);
            }
        }
        if (_usedWeight > 0) IVotingEscrow(VOTING_ESCROW).voting(_tokenId);
        totalWeight += uint256(_totalWeight);
        usedWeights[_tokenId] = uint256(_usedWeight);
    }

    function vote(
        uint tokenId,
        address[] calldata _poolVote,
        uint256[] calldata _weights
    ) external onlyNewEpoch(tokenId) {
        require(
            IVotingEscrow(VOTING_ESCROW).isApprovedOrOwner(msg.sender, tokenId)
        );
        require(_poolVote.length == _weights.length);
        lastVoted[tokenId] = block.timestamp;
        _vote(tokenId, _poolVote, _weights);
    }

    function setMinShareForActiveGauge(uint _share) public {
        require(msg.sender == governor);
        require(_share < 1e18);

        minShareForActiveGauge = _share;
    }

    function whitelist(address _token) public {
        require(msg.sender == governor);
        _whitelist(_token);
    }

    function _whitelist(address _token) internal {
        require(!isWhitelisted[_token]);
        isWhitelisted[_token] = true;
        emit Whitelisted(msg.sender, _token);
    }

    function blacklist(address _token) public {
        require(msg.sender == governor);
        _blacklist(_token);
    }

    function _blacklist(address _token) internal {
        require(isWhitelisted[_token]);
        isWhitelisted[_token] = false;
        emit Blacklisted(msg.sender, _token);
    }

    function createGauge(
        address _pool,
        uint256 _gaugeType
    ) external returns (address) {
        require(_gaugeType < factories.length, "gaugetype big");
        require(gauges[_pool] == address(0x0), "exists");
        address[] memory allowedRewards = new address[](3);
        address[] memory internalRewards = new address[](2);
        address tokenA;
        address tokenB;
        address _factory = factories[_gaugeType];
        address _gaugeFactory = gaugeFactories[_gaugeType];
        require(_factory != address(0));
        require(_gaugeFactory != address(0));
        bool isPair = ISnakeFactory(_factory).isPair(_pool);

        if (isPair) {
            tokenA = ISnakePair(_pool).token0();
            tokenB = ISnakePair(_pool).token1();
            allowedRewards[0] = tokenA;
            allowedRewards[1] = tokenB;
            internalRewards[0] = tokenA;
            internalRewards[1] = tokenB;
            // if one of the tokens is not votingEscrowToken (SNAKE) then add votingEscrowToken(SNAKE) to allowed rewards
            if (votingEscrowToken != tokenA && votingEscrowToken != tokenB) {
                allowedRewards[2] = votingEscrowToken;
            }
        }

        if (msg.sender != governor && msg.sender != emergencyCouncil) {
            // gov can create for any pool, even non-Velocimeter pairs
            require(isPair, "!_pool");
        }

        address _external_bribe = ISnakePair(_pool).externalBribe();

        if (_external_bribe == address(0)) {
            _external_bribe = IBribeFactory(bribeFactory).createExternalBribe(
                allowedRewards
            );
        }
        address _gauge = IGaugeFactory(_gaugeFactory).createGauge(
            _pool,
            _external_bribe,
            VOTING_ESCROW,
            isPair,
            allowedRewards
        );

        IERC20(votingEscrowToken).approve(_gauge, type(uint).max);
        externalBribes[_gauge] = _external_bribe;
        gauges[_pool] = _gauge;
        poolForGauge[_gauge] = _pool;
        isGauge[_gauge] = true;
        isAlive[_gauge] = true;
        _updateFor(_gauge);
        if (claimable[_gauge] > 0) {
            claimable[_gauge] = 0;
        }
        pools.push(_pool);
        if (isPair) {
            ISnakePair(_pool).setHasGauge(true);
            ISnakePair(_pool).setExternalBribe(_external_bribe);
        }
        emit GaugeCreated(_gauge, msg.sender, _external_bribe, _pool);
        return _gauge;
    }

    function pauseGauge(address _gauge) external {
        require(isAlive[_gauge], "gauge already dead");
        isAlive[_gauge] = false;
        claimable[_gauge] = 0;
        address _pair = IGauge(_gauge).stake(); // TODO: add test cases
        try ISnakePair(_pair).setHasGauge(false) {} catch {}
        emit GaugePaused(_gauge);
    }

    function restartGauge(address _gauge) external {
        require(!isAlive[_gauge], "gauge already alive");
        isAlive[_gauge] = true;
        address _pair = IGauge(_gauge).stake(); // TODO: add test cases
        try ISnakePair(_pair).setHasGauge(true) {} catch {}
        emit GaugeRestarted(_gauge);
    }

    function killGaugeTotally(address _gauge) external {
        require(isAlive[_gauge], "gauge already dead");

        address _pool = poolForGauge[_gauge];

        delete isAlive[_gauge];
        delete externalBribes[_gauge];
        delete poolForGauge[_gauge];
        delete isGauge[_gauge];
        delete claimable[_gauge];
        delete supplyIndex[_gauge];
        delete gauges[_pool];
        try ISnakePair(_pool).setHasGauge(false) {} catch {}

        killedGauges.push(_gauge);

        emit GaugeKilledTotally(_gauge);
    }

    function attachTokenToGauge(uint tokenId, address account) external {
        require(isGauge[msg.sender]);
        require(isAlive[msg.sender]); // killed gauges cannot attach tokens to themselves
        if (tokenId > 0) IVotingEscrow(VOTING_ESCROW).attach(tokenId);
        emit Attach(account, msg.sender, tokenId);
    }

    function emitDeposit(uint tokenId, address account, uint amount) external {
        require(isGauge[msg.sender]);
        require(isAlive[msg.sender]);
        emit Deposit(account, msg.sender, tokenId, amount);
    }

    function detachTokenFromGauge(uint tokenId, address account) external {
        if (tokenId > 0) IVotingEscrow(VOTING_ESCROW).detach(tokenId);
        emit Detach(account, msg.sender, tokenId);
    }

    function emitWithdraw(uint tokenId, address account, uint amount) external {
        emit Withdraw(account, msg.sender, tokenId, amount);
    }

    function length() external view returns (uint) {
        return pools.length;
    }

    function _factories() external view returns (address[] memory) {
        return factories;
    }

    function factoryLength() public view returns (uint) {
        return factories.length;
    }

    function _gaugeFactories() external view returns (address[] memory) {
        return gaugeFactories;
    }

    function gaugeFactoriesLength() public view returns (uint) {
        return gaugeFactories.length;
    }

    function _killedGauges() external view returns (address[] memory) {
        return killedGauges;
    }

    function killedGaugesLength() public view returns (uint) {
        return killedGauges.length;
    }

    uint internal index;
    mapping(address => uint) internal supplyIndex;
    mapping(address => uint) public claimable;

    function notifyRewardAmount(uint amount) external {
        require(msg.sender == minter, "not a minter");
        activeGaugeNumber = 0;
        currentEpochRewardAmount = amount;
        _safeTransferFrom(votingEscrowToken, msg.sender, address(this), amount); // transfer the distro in
        uint256 _ratio = (amount * 1e18) / totalWeight; // 1e18 adjustment is removed during claim
        if (_ratio > 0) {
            index += _ratio;
        }
        emit NotifyReward(msg.sender, votingEscrowToken, amount);
    }

    function updateFor(address[] memory _gauges) external {
        for (uint i = 0; i < _gauges.length; i++) {
            _updateFor(_gauges[i]);
        }
    }

    function updateForRange(uint start, uint end) public {
        for (uint i = start; i < end; i++) {
            _updateFor(gauges[pools[i]]);
        }
    }

    function updateAll() external {
        updateForRange(0, pools.length);
    }

    function updateGauge(address _gauge) external {
        _updateFor(_gauge);
    }

    function _updateFor(address _gauge) internal {
        address _pool = poolForGauge[_gauge];
        uint256 _supplied = weights[_pool];
        if (_supplied > 0) {
            uint _supplyIndex = supplyIndex[_gauge];
            uint _index = index; // get global index0 for accumulated distro
            supplyIndex[_gauge] = _index; // update _gauge current position to global position
            uint _delta = _index - _supplyIndex; // see if there is any difference that need to be accrued
            if (_delta > 0) {
                uint _share = (uint(_supplied) * _delta) / 1e18; // add accrued difference for each supplied token
                if (isAlive[_gauge]) {
                    claimable[_gauge] += _share;
                }
            }
        } else {
            supplyIndex[_gauge] = index; // new users are set to the default global state
        }
    }

    function claimRewards(
        address[] memory _gauges,
        address[][] memory _tokens
    ) external {
        for (uint i = 0; i < _gauges.length; i++) {
            IGauge(_gauges[i]).getReward(msg.sender, _tokens[i]);
        }
    }

    function claimBribes(
        address[] memory _bribes,
        address[][] memory _tokens,
        uint _tokenId
    ) external {
        require(
            IVotingEscrow(VOTING_ESCROW).isApprovedOrOwner(msg.sender, _tokenId)
        );
        for (uint i = 0; i < _bribes.length; i++) {
            IBribe(_bribes[i]).getRewardForOwner(_tokenId, _tokens[i]);
        }
    }

    function distribute(address _gauge) public lock {
        IMinter(minter).updatePeriod();
        _updateFor(_gauge); // should set claimable to 0 if killed
        uint _claimable = claimable[_gauge];
        if (
            _claimable > IGauge(_gauge).left(votingEscrowToken) &&
            _claimable / DURATION > 0
        ) {
            claimable[_gauge] = 0;
            if (
                (_claimable * 1e18) / currentEpochRewardAmount >
                minShareForActiveGauge
            ) {
                activeGaugeNumber += 1;
            }

            IGauge(_gauge).notifyRewardAmount(votingEscrowToken, _claimable);
            emit DistributeReward(msg.sender, _gauge, _claimable);
        }
    }

    function distro() external {
        distribute(0, pools.length);
    }

    function distribute() external {
        distribute(0, pools.length);
    }

    function distribute(uint start, uint finish) public {
        for (uint x = start; x < finish; x++) {
            distribute(gauges[pools[x]]);
        }
    }

    function distribute(address[] memory _gauges) external {
        for (uint x = 0; x < _gauges.length; x++) {
            distribute(_gauges[x]);
        }
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                from,
                to,
                value
            )
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }
}
