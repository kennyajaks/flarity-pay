// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockFAsset
 * @notice A basic ERC20 implementation representing a wrapped FAsset (e.g. fXRP, fBTC).
 * @dev Used to simulate minting upon successful cross-chain payment verification.
 */
contract MockFAsset {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    address public gateway;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    modifier onlyGateway() {
        require(msg.sender == gateway, "Only gateway can execute this");
        _;
    }
    
    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        gateway = msg.sender;
    }
    
    /**
     * @notice Transfer gateway privileges to a new address.
     * @param _newGateway The new gateway contract address.
     */
    function setGateway(address _newGateway) external onlyGateway {
        gateway = _newGateway;
    }
    
    /**
     * @notice Mint representation FAsset tokens to a merchant.
     * @param _to The address receiving the minted tokens.
     * @param _amount The amount to mint.
     */
    function mint(address _to, uint256 _amount) external onlyGateway {
        balanceOf[_to] += _amount;
        totalSupply += _amount;
        emit Transfer(address(0), _to, _amount);
    }
    
    function transfer(address _to, uint256 _value) external returns (bool) {
        require(balanceOf[msg.sender] >= _value, "Insufficient balance");
        balanceOf[msg.sender] -= _value;
        balanceOf[_to] += _value;
        emit Transfer(msg.sender, _to, _value);
        return true;
    }
    
    function approve(address _spender, uint256 _value) external returns (bool) {
        allowance[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }
    
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool) {
        require(balanceOf[_from] >= _value, "Insufficient balance");
        require(allowance[_from][msg.sender] >= _value, "Insufficient allowance");
        balanceOf[_from] -= _value;
        balanceOf[_to] += _value;
        allowance[_from][msg.sender] -= _value;
        emit Transfer(_from, _to, _value);
        return true;
    }
}
