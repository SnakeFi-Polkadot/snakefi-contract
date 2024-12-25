// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

contract WrappedWND {

    uint8 public constant decimals = 12;

    mapping(address => uint256) public balanceOf;

    mapping(address => mapping(address => uint256)) public allowance;

    /* -------------------------------------------------------------------------- */
    /*                               EVENT FUNCTIONS                              */
    /* -------------------------------------------------------------------------- */

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor() {
        _transfer(address(0), msg.sender, 10_000_000 * 10 ** decimals);
    }

    receive() external payable {
        deposit();
    }

    function totalSupply() external view returns (uint256) {
        return address(this).balance;
    }

    function deposit() public payable {
        uint256 _amount = msg.value;
        _transfer(address(0), msg.sender, _amount);
    }

    function withdraw(uint256 _amount) external {
        require(balanceOf[msg.sender] >= _amount, "WrappedWND: INSUFFICIENT_BALANCE");
        _transfer(msg.sender, address(0), _amount);
        payable(msg.sender).transfer(_amount);
    }

    function approve(address _spender, uint256 _amount) external returns (bool) {
        allowance[msg.sender][_spender] = _amount;
        emit Approval(msg.sender, _spender, _amount);
        return true;
    }

    function transfer(address _to, uint256 _amount) external returns (bool) {
        require(balanceOf[msg.sender] >= _amount, "WrappedWND: INSUFFICIENT_BALANCE");
        _transfer(msg.sender, _to, _amount);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _amount) external  returns(bool) {
        require(balanceOf[_from] >= _amount, "WrappedWND: INSUFFICIENT_BALANCE");
        require(allowance[_from][msg.sender] >= _amount, "WrappedWND: INSUFFICIENT_ALLOWANCE");
        allowance[_from][msg.sender] -= _amount;
        _transfer(_from, _to, _amount);
        return true;
    }

    function _transfer(address _from, address _to, uint256 _amount) internal returns(bool) {
        unchecked {
            balanceOf[_from] -= _amount;
            balanceOf[_to] += _amount;
        }
        emit Transfer(_from, _to, _amount);
        return true;
    }
}