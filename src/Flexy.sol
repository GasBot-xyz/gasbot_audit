//SPDX-License-Identifier: MIT

pragma solidity =0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./FlexyInterface.sol";

/// @title Flexy
/// @author 0xDjango
/// @notice This contract is used to relay tokens across chains. The contract holds a single "homeToken" to use as liquidity.
/// @dev This contract may hold other tokens as a result of calling relayAndTransfer() with a token other than the home token.
contract Flexy is IFlexy {
    using SafeERC20 for IERC20;

    address private owner;
    address public pendingOwner;
    mapping(address => bool) private isRelayer;
    mapping(uint256 => bool) private isOutboundIdUsed;

    IWETH private WETH;
    IPermit2 private permit2;
    address private defaultRouter;
    RouterType private defaultRouterType; // Router type (Uniswap V2, Uniswap V3, Custom)
    address private homeToken; // token held by this contract to be used as liquidity
    uint24 private defaultPoolFee = 500; // 0.05%
    uint256 private maxValue; // max value of homeToken that can be accepted via bridge()
    uint256 private minValue; // min value of homeToken that can be accepted via bridge()

    event Bridge(
        address indexed sender,
        uint256 fromChainId,
        address fromToken,
        uint256 indexed toChainId,
        address indexed toToken,
        uint256 nativeAmount,
        uint256 homeTokenAmount
    );

    constructor(
        address _owner,
        address _relayer,
        address _defaultRouter,
        RouterType _defaultRouterType,
        address _weth,
        address _homeToken,
        address _permit2,
        uint256 _maxValue
    ) {
        require(_owner != address(0));
        require(_defaultRouter != address(0));
        require(_defaultRouterType != RouterType.Custom);
        require(_weth != address(0));
        require(_homeToken != address(0));
        require(_homeToken != _weth);
        require(_permit2 != address(0));

        owner = _owner;
        isRelayer[_relayer] = true;
        defaultRouter = _defaultRouter;
        defaultRouterType = _defaultRouterType;
        WETH = IWETH(_weth);
        homeToken = _homeToken;
        permit2 = IPermit2(_permit2);
        maxValue = _maxValue * 10 ** IERC20Metadata(_homeToken).decimals();
        minValue = 2 * 10 ** IERC20Metadata(_homeToken).decimals();
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Unauthorized");
        _;
    }

    modifier onlyRelayer() {
        require(isRelayer[msg.sender], "Unauthorized");
        _;
    }

    modifier ensureDeadline(uint256 _deadline) {
        require(_deadline >= block.timestamp, "Expired deadline");
        _;
    }

    /////// Protected External Functions ///////

    /// @notice This function pulls in accepted tokens from the user's wallet.
    /// @param _token The token to pull in.
    /// @param _permitData The permit data to use for tokens supporting a permit() function.
    /// @param _customRouter The router to use for swapping.
    /// @param _swapData The swap data to use for swapping.
    /// @param _minAmountOut The minimum amount of tokens to receive from the swap.
    /// @param _deadline The deadline for the swap.
    /// @dev If the token does not support permit, the user must approve this contract to spend the token.
    ///      In this case, the passed permit signature will be ignored.
    /// @dev If the token is the home token, no swap will be performed.
    // @audit Should put home token output check to ensure proper swap path. This function should always increase home token balance.
    function relayIn(
        address _token,
        PermitParams calldata _permitData,
        Permit2Params calldata _permit2Data,
        address _customRouter,
        bytes calldata _swapData,
        uint256 _minAmountOut,
        uint256 _deadline
    ) external onlyRelayer ensureDeadline(_deadline) {
        _permitAndTransferIn(
            _token,
            _permitData.owner,
            _permitData,
            _permit2Data
        );

        address _homeToken = homeToken;
        if (_token == _homeToken) {
            emit Bridge(
                _permitData.owner,
                block.chainid,
                _homeToken,
                0,
                _homeToken,
                _permitData.amount,
                _permitData.amount
            );
            return;
        } // no need to swap

        _approve(_token, _customRouter, _permitData.amount);
        uint256 amountOut = _swap(
            _customRouter,
            _homeToken,
            _swapData,
            _minAmountOut
        );
        require(amountOut <= maxValue, "Exceeded max value");

        emit Bridge(
            _permitData.owner,
            block.chainid,
            _token,
            0,
            _homeToken,
            _permitData.amount,
            amountOut
        );
    }

    /// @notice This function transfers out accepted tokens to the user's wallet.
    /// @param _outputToken The token to transfer out.
    /// @param _swapAmount The amount of homeToken to swap.
    /// @param _recipient The address to transfer the swapped tokens to.
    /// @param _customRouter The router to use for swapping.
    /// @param _swapData The swap data to use for swapping.
    /// @param _minAmountOut The minimum amount of wrapped native (eg WETH) to receive from the swap.
    /// @param outbound_id The ID of the outbound transaction. Must be unique to prevent accidental replay.
    /// @param _gasLimit The gas limit for the transfer.
    /// @param _deadline The deadline for the swap.
    function transferOut(
        address _outputToken,
        address _recipient,
        address _customRouter,
        bytes calldata _swapData,
        uint256 _swapAmount,
        uint256 _minAmountOut,
        uint256 outbound_id,
        uint256 _gasLimit,
        uint256 _deadline
    ) external payable onlyRelayer ensureDeadline(_deadline) {
        require(!isOutboundIdUsed[outbound_id], "Expired outbound ID");
        isOutboundIdUsed[outbound_id] = true;

        uint256 amountOut;
        if (_outputToken != homeToken) {
            _approve(homeToken, _customRouter, _swapAmount);
            amountOut = _swap(
                _customRouter,
                _outputToken,
                _swapData,
                _minAmountOut
            );
        } else {
            amountOut = _swapAmount;
        }

        if (_outputToken == address(0)) {
            require(msg.value == 0); // Receipient is receiving native, we should not be sending extra native here
            _unwrap();
            _transferAtLeast(_recipient, amountOut, _gasLimit);
            return;
        } else {
            IERC20(_outputToken).safeTransfer(_recipient, amountOut);
            _transferMsgValue(_recipient, _gasLimit);
        }
    }

    /// @notice This function pulls in accepted tokens from the user's wallet and transfers out native to the user's wallet.
    /// @param _inputToken The token to pull in.
    /// @param _outputToken The token to transfer out.
    /// @param _permitData The permit data to use for tokens supporting a permit() function.
    /// @param _customRouter The router to use for swapping.
    /// @param _swapData The swap data to use for swapping.
    /// @param _swapAmount The amount of _token to swap. This will be lower than the permit amount as a result of Gasbot fees and relay txn fees.
    /// @param _minAmountOut The minimum amount of wrapped native (eg WETH) to receive from the swap.
    /// @param _gasLimit The gas limit for the transfer.
    /// @param _deadline The deadline for the swap.
    /// @dev This function is used for same-chain swaps.
    function relayAndTransfer(
        address _inputToken,
        address _outputToken,
        PermitParams calldata _permitData,
        Permit2Params calldata _permit2Data,
        address _customRouter,
        bytes calldata _swapData,
        uint256 _swapAmount,
        uint256 _minAmountOut,
        uint256 _gasLimit,
        uint256 _deadline
    ) external payable onlyRelayer ensureDeadline(_deadline) {
        require(_swapAmount <= _permitData.amount, "Invalid swap amount");
        _permitAndTransferIn(
            _inputToken,
            _permitData.owner,
            _permitData,
            _permit2Data
        );

        _approve(_inputToken, _customRouter, _swapAmount);
        uint256 amountOut = _swap(
            _customRouter,
            _outputToken,
            _swapData,
            _minAmountOut
        );

        if (_outputToken == address(0)) {
            require(msg.value == 0); // Receipient is receiving native, we should not be sending extra native here
            _unwrap();
            _transferAtLeast(_permitData.owner, amountOut, _gasLimit);
            return;
        } else {
            IERC20(_outputToken).safeTransfer(_permitData.owner, amountOut);
            _transferMsgValue(_permitData.owner, _gasLimit);
        }
    }

    /////// Public Functions ///////

    /// @notice This function is used to swap native to the home token. It can be called by anyone and emits an event that broadcasts
    ///         the amount of native swapped and the amount of homeToken received as a result of the swap.
    /// @notice This function should be called from a verified Gasbot UI to ensure its completion on the destination chain.
    ///         If this function is called from an unverified UI, the user should verify the transaction
    ///         by submitting the transaction hash to the Gasbot UI at https://gasbot.xyz/verify-txn
    ///         If the user-supplied _toChainId is not supported, gas will be transferred back to the caller with Gasbot fee deducted.
    /// @notice Gasbot transfers native using .transfer(),
    ///         therefore it is crucial that the caller of this function either be an EOA or a contract that will not revert with .tranfer() gas stipend.
    /// @param _minAmountOut The minimum amount of homeToken to receive from the swap.
    /// @param _toToken The address of the token to receive on the destination chain.
    /// @param _toChainId The chain ID of the destination chain.
    /// @param _deadline The deadline for the swap.
    function bridgeNative(
        uint256 _toChainId,
        address _toToken,
        uint256 _minAmountOut,
        uint256 _deadline
    ) external payable ensureDeadline(_deadline) {
        require(msg.value > 0, "Invalid amount");
        require(
            (_toChainId != block.chainid) && (_toChainId != 0),
            "Invalid chain ID"
        );

        address homeToken_ = homeToken;
        WETH.deposit{value: msg.value}();

        bytes memory swapData = getDefaultSwapData(
            false,
            msg.value,
            _minAmountOut,
            _deadline
        );
        _approve(address(WETH), defaultRouter, msg.value);
        uint256 amountOut = _swap(
            defaultRouter,
            homeToken_,
            swapData,
            _minAmountOut
        );

        require(amountOut <= maxValue, "Exceeded max value");
        require(amountOut >= minValue, "Below min value");

        emit Bridge(
            msg.sender,
            block.chainid,
            address(0),
            _toChainId,
            _toToken,
            msg.value,
            amountOut
        );
    }

    /////// Internal/Private Functions ///////

    function _permitAndTransferIn(
        address _token,
        address _owner,
        PermitParams calldata _permitData,
        Permit2Params calldata _permit2Data
    ) private {
        if (
            IERC20(_token).allowance(_owner, address(this)) >=
            _permitData.amount
        ) {
            IERC20(_token).safeTransferFrom(
                _owner,
                address(this),
                _permitData.amount
            );
        } else {
            if (_permitData.v != 0) {
                IERC20Permit(_token).permit(
                    _owner,
                    _permitData.spender,
                    _permitData.amount,
                    _permitData.deadline,
                    _permitData.v,
                    _permitData.r,
                    _permitData.s
                );
                IERC20(_token).safeTransferFrom(
                    _owner,
                    address(this),
                    _permitData.amount
                );
            } else {
                ISignatureTransfer.SignatureTransferDetails
                    memory transferDetails = _generateTransferDetails(
                        address(this),
                        _permitData.amount
                    );
                permit2.permitTransferFrom(
                    _permit2Data.permit,
                    transferDetails,
                    _owner,
                    _permit2Data.signature
                );
            }
        }
    }

    function _approve(
        address _tokenIn,
        address _router,
        uint256 _swapAmount
    ) private {
        IERC20(_tokenIn).forceApprove(_router, _swapAmount);
    }

    function _swap(
        address _router,
        address _tokenOut,
        bytes memory _swapData,
        uint256 _minAmountOut
    ) private returns (uint256 amountOut) {
        uint256 initialBalance = _getContractBalance(_tokenOut);

        (bool success, ) = _router.call(_swapData);
        require(success, "Swap failed");

        amountOut = _getContractBalance(_tokenOut) - initialBalance;
        require(amountOut >= _minAmountOut, "Invalid amount out");
        return amountOut;
    }

    function _unwrap() private {
        uint256 wethBalance = _getContractBalance(address(WETH));
        if (wethBalance == 0) return;
        WETH.withdraw(wethBalance);
    }

    function _transferAtLeast(
        address _recipient,
        uint256 _minAmount,
        uint256 _gasLimit
    ) private {
        require(address(this).balance >= _minAmount, "Native balance too low");
        (bool success, ) = payable(_recipient).call{
            value: address(this).balance,
            gas: _gasLimit
        }("");
        require(success, "Transfer failed");
    }

    function _transferMsgValue(address _recipient, uint256 _gasLimit) private {
        if (msg.value > 0) {
            (bool success, ) = payable(_recipient).call{
                value: msg.value,
                gas: _gasLimit
            }("");
            require(success, "Transfer failed");
        }
    }

    function _generateTransferDetails(
        address _to,
        uint256 _amount
    )
        private
        pure
        returns (ISignatureTransfer.SignatureTransferDetails memory)
    {
        ISignatureTransfer.SignatureTransferDetails
            memory transferDetails = ISignatureTransfer
                .SignatureTransferDetails({to: _to, requestedAmount: _amount});

        return transferDetails;
    }

    function _getContractBalance(
        address _token
    ) private view returns (uint256) {
        if (_token == address(0)) _token = address(WETH);
        return IERC20(_token).balanceOf(address(this));
    }

    /////// Admin-Only Functions ///////

    /// @notice This function is used to set the default router used for swapping in the swapGas() and transferGasOut() functions.
    /// @param _defaultRouter The address of the default router.
    /// @param _defaultRouterType The type of the default router.
    function setDefaultRouter(
        address _defaultRouter,
        RouterType _defaultRouterType
    ) external onlyOwner {
        require(_defaultRouter != address(0));
        defaultRouter = _defaultRouter;
        defaultRouterType = _defaultRouterType;
    }

    /// @notice This function is used to set the default pool fee used for swapping in the swapGas() and transferGasOut() functions.
    /// @param _defaultPoolFee The default pool fee.
    function setDefaultPoolFee(uint24 _defaultPoolFee) external onlyOwner {
        require(_defaultPoolFee > 0);
        defaultPoolFee = _defaultPoolFee;
    }

    /// @notice This function is used to set the home token for the contract.
    ///         It will likely only be changed as a result of a stablecoin depeg or decline in liquidity.
    ///         This will also update the maxValue and minValue to the new token's decimals.
    /// @param _homeToken The address of the new home token.
    function setHomeToken(address _homeToken) external onlyOwner {
        require(_homeToken != address(0));
        require(_homeToken != address(WETH));

        uint256 _prevDecimals = IERC20Metadata(homeToken).decimals();
        homeToken = _homeToken;
        maxValue =
            (maxValue * 10 ** IERC20Metadata(_homeToken).decimals()) /
            (10 ** _prevDecimals);
        minValue =
            (minValue * 10 ** IERC20Metadata(_homeToken).decimals()) /
            (10 ** _prevDecimals);
    }

    /// @notice This function is used to set the WETH contract address.
    /// @param _weth The address of the WETH contract.
    function setWETH(address _weth) external onlyOwner {
        require(_weth != address(0));
        require(_weth != homeToken);
        WETH = IWETH(_weth);
    }

    /// @notice This function is used to set the permit2 contract address.
    /// @param _permit2 The address of the permit2 contract.
    function setPermit2(address _permit2) external onlyOwner {
        require(_permit2 != address(0));
        permit2 = IPermit2(_permit2);
    }

    /// @notice This function is used to set the maximum amount of homeToken that can be accepted using the swapGas() function.
    /// @param _maxValue The new maximum value.
    /// @dev The value is stored as a uint256, so it must be passed in as the value multiplied by 10^decimals.
    /// @dev Setting the max value to 0 will disable use of the swapGas() function.
    function setMaxValue(uint256 _maxValue) external onlyOwner {
        maxValue = _maxValue * 10 ** IERC20Metadata(homeToken).decimals();
    }

    /// @notice This function is used to set the minimum amount of homeToken that can be accepted using the swapGas() function.
    /// @param _minValue The new minimum value.
    /// @dev The value is stored as a uint256, so it must be passed in as the value multiplied by 10^decimals.
    function setMinValue(uint256 _minValue) external onlyOwner {
        minValue = _minValue * 10 ** IERC20Metadata(homeToken).decimals();
    }

    /// @notice This function is used to add or remove relayers.
    /// @param _relayer The address of the relayer.
    function setRelayer(address _relayer, bool _status) external onlyOwner {
        isRelayer[_relayer] = _status;
    }

    /// @notice This function is used to transfer ownership of the contract.
    /// @param _newOwner The address of the new owner.
    function setPendingOwner(address _newOwner) external onlyOwner {
        require(_newOwner != address(0));
        pendingOwner = _newOwner;
    }

    /// @notice This function is used to accept ownership of the contract.
    function acceptOwnership() external {
        require(msg.sender == pendingOwner);
        pendingOwner = address(0);
        owner = msg.sender;
    }

    /**
     * This function can be used to execute any arbitrary set of instructions.
     * Example use cases:
     * 1. Call a function on another contract
     * 2. Transfer out ETH or ERC20 tokens
     * 3. Swap ERC20 tokens to ETH and transfer to relayer
     * NOTE: Since this contract will never hold funds belonging to users, this function is not a security risk.
     */
    function execute(
        address _target,
        bytes calldata _data,
        uint256 _value,
        address _recipient
    ) external onlyOwner {
        (bool success, ) = payable(_target).call{value: _value}(_data);
        require(success);

        if (_recipient != address(0)) {
            (success, ) = payable(_recipient).call{
                value: address(this).balance
            }("");
            require(success, "Transfer failed");
        }
    }

    /// @notice This function will swap the home token for native and send it to the relayers.
    /// @param _relayers The addresses of the relayers.
    /// @param _amounts The amounts of gas to send to each relayer.
    /// @param _swapAmount The amount of homeToken to swap.
    /// @param _minAmountOut The minimum amount of wrapped native (eg WETH) to receive from the swap.
    /// @dev All passed relayers must be valid relayers.
    function replenishRelayers(
        address[] calldata _relayers,
        uint256[] calldata _amounts,
        uint256 _swapAmount,
        uint256 _minAmountOut,
        uint256 _gasLimit,
        uint256 _deadline
    ) external payable onlyOwner {
        bytes memory swapData = getDefaultSwapData(
            true,
            _swapAmount,
            _minAmountOut,
            _deadline
        );
        _swap(defaultRouter, address(WETH), swapData, _minAmountOut);
        _unwrap();

        for (uint256 i = 0; i < _relayers.length; ) {
            require(isRelayer[_relayers[i]], "Invalid relayer");
            if (i == _relayers.length - 1) {
                _transferAtLeast(_relayers[i], _amounts[i], _gasLimit); // Any extra goes to the last relayer
            } else {
                (bool success, ) = payable(_relayers[i]).call{
                    value: _amounts[i]
                }("");
                require(success, "Transfer failed");
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice This function will swap any extra tokens in this contract to home token to be used as liquidity.
    ///         Non-home tokens can be retained by this contract as a result of relayAndTransfer() when using non-home tokens.
    /// @param _token The address of the token to swap.
    /// @param _customRouter The router to use for swapping.
    /// @param _swapData The swap data to use for swapping.
    /// @param _minAmountOut The minimum amount of homeToken to receive from the swap.
    /// @param _deadline The deadline for the swap.
    function swapTokenToHomeToken(
        address _token,
        address _customRouter,
        bytes calldata _swapData,
        uint256 _minAmountOut,
        uint256 _deadline
    ) external onlyOwner ensureDeadline(_deadline) {
        address homeToken_ = homeToken;
        require(_token != homeToken_, "Invalid token");

        _swap(_customRouter, homeToken, _swapData, _minAmountOut);
    }

    /// @notice This function will withdraw any ERC20 tokens held by the contract.
    /// @param _token The address of the token to withdraw.
    function withdraw(address _token, uint256 _amount) external onlyOwner {
        uint256 balance = _getContractBalance(_token);
        if (_amount > balance) _amount = balance;
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    /////// View Functions ///////

    /// @notice This function returns home token address.
    function getHomeToken() external view returns (address) {
        return homeToken;
    }

    /// @notice This function returns the maximum amount of homeToken that can be accepted using the swapGas() function.
    function getMaxValue() external view returns (uint256) {
        return maxValue;
    }

    /// @notice This function is used by the Gasbot UI to scan user wallets for native and token balances.
    /// @param _user The address of the user.
    /// @param _tokens The addresses of the tokens to query.
    function getTokenBalancesAndPermit2Allowances(
        address _user,
        address[] calldata _tokens
    )
        public
        view
        returns (address[] memory, uint256[] memory, uint256[] memory)
    {
        uint256 length = _tokens.length + 1;
        address[] memory tokens_ = new address[](length);
        uint256[] memory balances_ = new uint256[](length);
        uint256[] memory allowances_ = new uint256[](length);

        // Query user's native balance
        tokens_[0] = address(0);
        balances_[0] = _user.balance;
        allowances_[0] = 0;

        // Query user's token balances and permit2 allowances
        for (uint256 i = 1; i < length; ++i) {
            balances_[i] = IERC20(_tokens[i - 1]).balanceOf(_user);
            allowances_[i] = IERC20(_tokens[i - 1]).allowance(
                address(permit2),
                _user
            );
            tokens_[i] = _tokens[i - 1];
        }
        return (tokens_, balances_, allowances_);
    }

    function getRelayerBalances(
        address[] calldata _relayers
    ) external view returns (uint256[] memory) {
        uint256 length = _relayers.length;
        uint256[] memory balances_ = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            require(isRelayer[_relayers[i]], "Invalid relayer"); // @audit maybe continue if not valid relayer?
            balances_[i] = _relayers[i].balance;
        }
        return balances_;
    }

    // @audit change visibility to private after audit
    function getDefaultSwapData(
        bool _toWeth,
        uint256 _swapAmount,
        uint256 _minAmountOut,
        uint256 deadline
    ) private view returns (bytes memory swapData) {
        if (defaultRouterType == RouterType.UniswapV3) {
            bytes memory uniV3Path;
            if (_toWeth) {
                //@audit see if uniV3path is needed or if can directly add tokenIn, tokenOut, and fee to swapData
                uniV3Path = abi.encodePacked(
                    homeToken,
                    defaultPoolFee,
                    address(WETH)
                );
            } else {
                uniV3Path = abi.encodePacked(
                    address(WETH),
                    defaultPoolFee,
                    homeToken
                );
            }

            swapData = abi.encodeWithSelector(
                IUniswapRouterV3.exactInput.selector,
                IUniswapRouterV3.ExactInputParams({
                    path: uniV3Path,
                    recipient: address(this),
                    deadline: deadline,
                    amountIn: _swapAmount,
                    amountOutMinimum: _minAmountOut
                })
            );
        } else if (defaultRouterType == RouterType.UniswapV2) {
            address[] memory uniV2Path = new address[](2);
            if (_toWeth) {
                uniV2Path[0] = homeToken;
                uniV2Path[1] = address(WETH);
            } else {
                uniV2Path[0] = address(WETH);
                uniV2Path[1] = homeToken;
            }

            swapData = abi.encodeWithSelector(
                IUniswapRouterV2.swapExactTokensForTokens.selector,
                _swapAmount,
                _minAmountOut,
                uniV2Path,
                address(this),
                deadline
            );
        } else {
            revert("Invalid default router type");
        }
    }

    receive() external payable {
        require(msg.sender == address(WETH), "Invalid sender");
    }
}
