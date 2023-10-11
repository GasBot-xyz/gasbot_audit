//SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IWETH {
    function withdraw(uint wad) external;
}

error Unauthorized();
error ExpiredOutboundId();
error InvalidPermit();
error SwapFailed();

contract GasBot {
    using SafeERC20 for IERC20;

    address private immutable owner;
    mapping(address => bool) private isRelayer;
    mapping(uint256 => bool) private isOutboundIdUsed;

    constructor(address _owner, address _relayer) {
        require(_owner != address(0));
        owner = _owner;
        isRelayer[_relayer] = true;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyRelayer() {
        if (!isRelayer[msg.sender]) revert Unauthorized();
        _;
    }

    function relayTokenIn(
        address _sender,
        address _token,
        uint256 _amount,
        bytes calldata _permitData,
        address _target,
        bytes calldata _data
    ) external onlyRelayer {
        _permitAndTransferIn(_sender, _token, _amount, _permitData);
        _swap(_token, _amount, _target, _data);
    }

    function transferGasOut(
        address _swapToken,
        uint256 _swapAmount,
        address _recipient,
        uint256 _sendAmount,
        address _target,
        bytes calldata _data,
        address _weth,
        uint256 outbound_id
    ) external onlyRelayer {
        if (isOutboundIdUsed[outbound_id]) revert ExpiredOutboundId();
        isOutboundIdUsed[outbound_id] = true;

        _swap(_swapToken, _swapAmount, _target, _data);
        _unwrap(_weth);
        payable(_recipient).transfer(_sendAmount);
        _transferExtra();
    }

    function relayAndTransfer(
        address _sender,
        address _token,
        uint256 _amount,
        bytes calldata _permitData,
        address _target,
        bytes calldata _data,
        uint256 _sendAmount,
        address _weth
    ) external onlyRelayer {
        _permitAndTransferIn(_sender, _token, _amount, _permitData);
        _swap(_token, _amount, _target, _data);
        _unwrap(_weth);
        payable(_sender).transfer(_sendAmount);
        _transferExtra();
    }

    /**
     * This function can be used to execute any arbitrary set of instructions.
     * Example use cases:
     * 1. Call a function on another contract
     * 2. Transfer out ETH or ERC20 tokens
     * 3. Swap ERC20 tokens to ETH
     * NOTE: Since this contract will never hold funds belonging to users, this function is not a security risk.
     */
    function execute(
        address _target,
        bytes calldata _data,
        uint256 _value,
        bool _unwrapWETH,
        address _weth,
        address _recipient
    ) external onlyOwner {
        (bool success, ) = _target.call{value: _value}(_data);
        require(success);

        if (_unwrapWETH) {
            _unwrap(_weth);
            payable(_recipient).transfer(address(this).balance);
        }
    }

    function setRelayer(address _relayer, bool _status) external onlyOwner {
        isRelayer[_relayer] = _status;
    }

    function withdraw(address _token) external onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, balance);
    }

    function _permitAndTransferIn(
        address _sender,
        address _token,
        uint256 _amount,
        bytes calldata _permitData
    ) private {
        (bool success, ) = _token.call(_permitData);
        if (!success) revert InvalidPermit();
        IERC20(_token).safeTransferFrom(_sender, address(this), _amount);
    }

    function _swap(
        address _token,
        uint256 _amount,
        address _target,
        bytes calldata _data
    ) private {
        if (_target != address(0)) {
            IERC20(_token).approve(_target, _amount);
            (bool success, ) = _target.call(_data);
            if (!success) revert SwapFailed();
        }
    }

    function _unwrap(address _weth) private {
        if (_weth == address(0)) {
            return;
        }
        uint256 wethBalance = IERC20(_weth).balanceOf(address(this));
        IWETH(_weth).withdraw(wethBalance);
    }

    function _transferExtra() private {
        if (address(this).balance > 0) {
            payable(msg.sender).transfer(address(this).balance);
        }
    }

    function getTokenBalances(
        address _user,
        address[] calldata _tokens
    ) public view returns (address[] memory, uint256[] memory) {
        uint256[] memory balances_ = new uint256[](_tokens.length);
        balances_ = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            balances_[i] = IERC20(_tokens[i]).balanceOf(_user);
        }
        return (_tokens, balances_);
    }

    receive() external payable {}
}
