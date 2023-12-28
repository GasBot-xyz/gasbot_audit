//SPDX-License-Identifier: MIT

pragma solidity =0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Interface.sol";

/// @title GasbotV2
/// @author 0xDjango
/// @notice This contract is used to relay gas across chains. The contract holds a single "homeToken" to use as liquidity.
/// @dev This contract may hold other tokens as a result of calling relayAndTransfer() with a token other than the home token.
contract GasbotV2 {
    using SafeERC20 for IERC20;

    struct PermitParams {
        address owner;
        address spender;
        uint256 amount;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    address private immutable owner;
    mapping(address => bool) private isRelayer;
    mapping(uint256 => bool) private isOutboundIdUsed;

    IWETH private immutable WETH;
    address private defaultRouter;
    bool private isV3Router; // true if router is Uniswap V3 router, false if Uniswap V2 router
    address private homeToken;
    uint24 private defaultPoolFee = 500; // 0.05%

    event GasSwap(
        address indexed sender,
        uint256 nativeAmount,
        uint256 usdAmount,
        uint256 indexed fromChainId,
        uint256 indexed toChainId
    );

    constructor(
        address _owner,
        address _relayer,
        address _defaultRouter,
        bool _isV3Router,
        address _weth,
        address _homeToken
    ) {
        require(_owner != address(0));
        require(_defaultRouter != address(0));
        require(_weth != address(0));
        require(_homeToken != address(0));

        owner = _owner;
        isRelayer[_relayer] = true;
        defaultRouter = _defaultRouter;
        isV3Router = _isV3Router;
        WETH = IWETH(_weth);
        homeToken = _homeToken;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Unauthorized");
        _;
    }

    modifier onlyRelayer() {
        require(isRelayer[msg.sender], "Unauthorized");
        _;
    }

    /////// Protected External Functions ///////

    /// @notice This function pulls in accepted tokens from the user's wallet.
    /// @param _token The token to pull in.
    /// @param _permitData The permit data to use for tokens supporting a permit() function.
    /// @param _customRouter The router to use for swapping.
    /// @param _uniV3Path The Uniswap V3 path to use for swapping.
    /// @param _uniV2Path The Uniswap V2 path to use for swapping.
    /// @param _minAmountOut The minimum amount of tokens to receive from the swap.
    /// @dev If the token does not support permit, the user must approve this contract to spend the token.
    ///      In this case, the passed permit signature will be ignored.
    /// @dev If the token is the home token, no swap will be performed.
    function relayTokenIn(
        address _token,
        PermitParams calldata _permitData,
        address _customRouter,
        bytes calldata _uniV3Path,
        address[] calldata _uniV2Path,
        uint256 _minAmountOut
    ) external onlyRelayer {
        _permitAndTransferIn(_token, _permitData);
        if (_token == homeToken) {
            return; // no need to swap
        }
        _swap(
            _customRouter,
            _token,
            _uniV3Path,
            _uniV2Path,
            _permitData.amount,
            _minAmountOut
        );
    }

    /// @notice This function transfers out accepted tokens to the user's wallet.
    /// @param _swapAmount The amount of homeToken to swap.
    /// @param _recipient The address to transfer the swapped tokens to.
    /// @param _minAmountOut The minimum amount of wrapped native (eg WETH) to receive from the swap.
    /// @param outbound_id The ID of the outbound transaction. Must be unique to prevent accidental replay.
    function transferGasOut(
        uint256 _swapAmount,
        address _recipient,
        uint256 _minAmountOut,
        uint256 outbound_id
    ) external onlyRelayer {
        require(!isOutboundIdUsed[outbound_id], "Expired outbound ID");
        isOutboundIdUsed[outbound_id] = true;

        (
            bytes memory uniV3Path,
            address[] memory uniV2Path
        ) = getDefaultSwapPaths(true);
        _swap(
            defaultRouter,
            homeToken,
            uniV3Path,
            uniV2Path,
            _swapAmount,
            _minAmountOut
        );
        _unwrap();
        _transferAtLeast(_recipient, _minAmountOut);
    }

    /// @notice This function pulls in accepted tokens from the user's wallet and transfers out native to the user's wallet.
    /// @param _token The token to pull in.
    /// @param _permitData The permit data to use for tokens supporting a permit() function.
    /// @param _customRouter The router to use for swapping.
    /// @param _uniV3Path The Uniswap V3 path to use for swapping.
    /// @param _uniV2Path The Uniswap V2 path to use for swapping.
    /// @param _swapAmount The amount of _token to swap. This will be lower than the permit amount as a result of Gasbot fees and relay txn fees.
    /// @param _minAmountOut The minimum amount of wrapped native (eg WETH) to receive from the swap.
    /// @dev This function is used for same-chain swaps.
    function relayAndTransfer(
        address _token,
        PermitParams calldata _permitData,
        address _customRouter,
        bytes calldata _uniV3Path,
        address[] calldata _uniV2Path,
        uint256 _swapAmount,
        uint256 _minAmountOut
    ) external onlyRelayer {
        require(_swapAmount < _permitData.amount, "Invalid swap amount");
        _permitAndTransferIn(_token, _permitData);
        _swap(
            _customRouter,
            _token,
            _uniV3Path,
            _uniV2Path,
            _swapAmount,
            _minAmountOut
        );
        _unwrap();
        _transferAtLeast(_permitData.owner, _minAmountOut);
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
    /// @param _toChainId The chain ID of the destination chain.
    function swapGas(
        uint256 _minAmountOut,
        uint16 _toChainId
    ) external payable {
        require(msg.value > 0, "Invalid amount");
        uint256 initialBalance = IERC20(homeToken).balanceOf(address(this));
        WETH.deposit{value: msg.value}();

        (
            bytes memory uniV3Path,
            address[] memory uniV2Path
        ) = getDefaultSwapPaths(false);
        _swap(
            defaultRouter,
            address(WETH),
            uniV3Path,
            uniV2Path,
            msg.value,
            _minAmountOut
        );
        uint256 addedValue = IERC20(homeToken).balanceOf(address(this)) -
            initialBalance;

        emit GasSwap(
            msg.sender,
            msg.value,
            addedValue,
            block.chainid,
            _toChainId
        );
    }

    /////// Internal/Private Functions ///////

    function _permitAndTransferIn(
        address _token,
        PermitParams calldata _permitData
    ) private {
        if (
            IERC20(_token).allowance(_permitData.owner, address(this)) <
            _permitData.amount
        ) {
            IERC20Permit(_token).permit(
                _permitData.owner,
                _permitData.spender,
                _permitData.amount,
                _permitData.deadline,
                _permitData.v,
                _permitData.r,
                _permitData.s
            );
        }
        IERC20(_token).safeTransferFrom(
            _permitData.owner,
            address(this),
            _permitData.amount
        );
    }

    function _swap(
        address _router,
        address _tokenIn,
        bytes memory _uniV3Path,
        address[] memory _uniV2Path,
        uint256 _amount,
        uint256 _minAmountOut
    ) private {
        IERC20(_tokenIn).approve(_router, _amount);
        if (_uniV3Path.length > 0) {
            IUniswapRouterV3(_router).exactInput(
                IUniswapRouterV3.ExactInputParams({
                    path: _uniV3Path,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: _amount,
                    amountOutMinimum: _minAmountOut
                })
            );
        } else {
            IUniswapRouterV2(_router).swapExactTokensForTokens(
                _amount,
                _minAmountOut,
                _uniV2Path,
                address(this),
                block.timestamp
            );
        }
    }

    function _unwrap() private {
        uint256 wethBalance = WETH.balanceOf(address(this));
        if (wethBalance == 0) return;
        WETH.withdraw(wethBalance);
    }

    function _transferAtLeast(address _recipient, uint256 _minAmount) private {
        require(address(this).balance >= _minAmount, "Native balance too low");
        payable(_recipient).transfer(address(this).balance);
    }

    /////// Admin-Only Functions ///////

    /// @notice This function is used to set the default router used for swapping in the swapGas() and transferGasOut() functions.
    /// @param _defaultRouter The address of the default router.
    /// @param _isV3Router True if the router is a Uniswap V3 router, false if it is a Uniswap V2 router.
    function setDefaultRouter(
        address _defaultRouter,
        bool _isV3Router
    ) external onlyOwner {
        require(_defaultRouter != address(0));
        defaultRouter = _defaultRouter;
        isV3Router = _isV3Router;
    }

    /// @notice This function is used to set the default pool fee used for swapping in the swapGas() and transferGasOut() functions.
    /// @param _defaultPoolFee The default pool fee.
    function setDefaultPoolFee(uint24 _defaultPoolFee) external onlyOwner {
        require(_defaultPoolFee > 0);
        defaultPoolFee = _defaultPoolFee;
    }

    /// @notice This function is used to set the home token for the contract.
    ///         It will likely only be changed as a result of a stablecoin depeg or decline in liquidity.
    /// @param _homeToken The address of the new home token.
    function setHomeToken(address _homeToken) external onlyOwner {
        require(_homeToken != address(0));
        homeToken = _homeToken;
    }

    /// @notice This function is used to add or remove relayers.
    /// @param _relayer The address of the relayer.
    function setRelayer(address _relayer, bool _status) external onlyOwner {
        isRelayer[_relayer] = _status;
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
        (bool success, ) = _target.call{value: _value}(_data);
        require(success);

        if (_recipient != address(0)) {
            payable(_recipient).transfer(address(this).balance);
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
        uint256 _minAmountOut
    ) external payable onlyOwner {
        (
            bytes memory uniV3Path,
            address[] memory uniV2Path
        ) = getDefaultSwapPaths(true);
        _swap(
            defaultRouter,
            homeToken,
            uniV3Path,
            uniV2Path,
            _swapAmount,
            _minAmountOut
        );
        _unwrap();

        uint256 length = _relayers.length;
        for (uint256 i = 0; i < length; ++i) {
            require(isRelayer[_relayers[i]], "Invalid relayer");
            if (i == length - 1) {
                _transferAtLeast(_relayers[i], _amounts[i]); // Any extra goes to the last relayer
            } else {
                payable(_relayers[i]).transfer(_amounts[i]);
            }
        }
    }

    /// @notice This function will withdraw any ERC20 tokens held by the contract.
    /// @param _token The address of the token to withdraw.
    function withdraw(address _token) external onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, balance);
    }

    /////// View Functions ///////

    /// @notice This function is used by the Gasbot UI to scan user wallets for native and token balances.
    /// @param _user The address of the user.
    /// @param _tokens The addresses of the tokens to query.
    function getTokenBalances(
        address _user,
        address[] calldata _tokens
    ) public view returns (address[] memory, uint256[] memory) {
        uint256 length = _tokens.length + 1;
        address[] memory tokens_ = new address[](length);
        uint256[] memory balances_ = new uint256[](length);

        // Query user's native balance

        tokens_[0] = address(0);
        balances_[0] = _user.balance;

        // Query user's token balances
        for (uint256 i = 1; i < length; i++) {
            // @audit ++i is a tiny bit cheaper than i++
            balances_[i] = IERC20(_tokens[i - 1]).balanceOf(_user); // @audit Bug - index-out-of-bounds error
            tokens_[i] = _tokens[i - 1];
        }
        return (tokens_, balances_);
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

    function getDefaultSwapPaths(
        bool _toWeth
    )
        private
        view
        returns (bytes memory uniV3Path, address[] memory uniV2Path)
    {
        if (isV3Router) {
            if (_toWeth) {
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
        } else {
            uniV2Path = new address[](2);
            if (_toWeth) {
                uniV2Path[0] = homeToken;
                uniV2Path[1] = address(WETH);
            } else {
                uniV2Path[0] = address(WETH);
                uniV2Path[1] = homeToken;
            }
        }
    }

    receive() external payable {}
}
