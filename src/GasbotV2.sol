//SPDX-License-Identifier: MIT

pragma solidity =0.8.17;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Interface.sol";

contract GasbotV2 {
    using SafeERC20 for IERC20;

    address private immutable owner;
    mapping(address => bool) private isRelayer;
    mapping(uint256 => bool) private isOutboundIdUsed;

    IWETH immutable WETH; // @audit missing visibility
    address uniswapRouter; // @audit missing visibility
    bool private isV3Router; // true if router is Uniswap V3 router, false if Uniswap V2 router
    address private homeToken;
    uint24 private defaultPoolFee = 500; // 0.05% @audit can be constant

    event GasSwap(
        address indexed sender,
        uint256 nativeAmount,
        uint256 usdAmount,
        uint256 indexed fromChainId,
        uint256 indexed toChainId
    );

    struct PermitParams {
        address owner;
        address spender;
        uint256 amount;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    constructor(
        address _owner,
        address _relayer,
        address _uniswapRouter,
        bool _isV3Router,
        address _weth,
        address _homeToken
    ) {
        require(_owner != address(0));
        require(_uniswapRouter != address(0));
        require(_weth != address(0));
        require(_homeToken != address(0));

        owner = _owner;
        isRelayer[_relayer] = true; // @audit potentially setting address(0) as authorized unnecessarily
        uniswapRouter = _uniswapRouter;
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

    function relayTokenIn(
        address _token,
        PermitParams calldata _permitData,
        uint24 _poolFee,
        uint256 _minAmountOut
    ) external onlyRelayer {
        _permitAndTransferIn(_token, _permitData);
        if (_token == homeToken) {
            return; // no need to swap
        }
        _swap(_token, homeToken, _poolFee, _permitData.amount, _minAmountOut);
    }

    function transferGasOut(
        uint256 _swapAmount,
        address _recipient,
        uint24 _poolFee,
        uint256 _minAmountOut,
        uint256 outbound_id
    ) external onlyRelayer {
        require(!isOutboundIdUsed[outbound_id], "Expired outbound ID");
        isOutboundIdUsed[outbound_id] = true;

        _swap(homeToken, address(WETH), _poolFee, _swapAmount, _minAmountOut);
        _unwrap();
        _transferAtLeast(_recipient, _minAmountOut);
    }

    function relayAndTransfer(
        address _token,
        PermitParams calldata _permitData,
        uint24 _poolFee,
        uint256 _swapAmount,
        uint256 _minAmountOut
    ) external onlyRelayer {
        require(_swapAmount < _permitData.amount, "Invalid swap amount");
        _permitAndTransferIn(_token, _permitData);
        _swap(_token, address(WETH), _poolFee, _swapAmount, _minAmountOut);
        _unwrap();
        _transferAtLeast(_permitData.owner, _minAmountOut);
    }

    /////// Public Functions ///////

    // NOTE: This function should be called from a verified Gasbot UI to ensure its completion on the destination chain.
    // If this function is called from an unverified UI, the user should verify the transaction
    // by submitting the transaction hash to the Gasbot UI at https://gasbot.xyz/verify-tx
    // If the user-supplied _toChainId is not supported, gas will be transferred back to the caller with Gasbot fee deducted.
    function swapGas(
        uint256 _minAmountOut,
        uint16 _toChainId
    ) external payable {
        // @audit maybe exit early is msg.value == 0? Right now, it'll fail at the Uniswap level
        // after calling balanceOf and deposit
        uint256 initialBalance = IERC20(homeToken).balanceOf(address(this));
        WETH.deposit{value: msg.value}();
        _swap(address(WETH), homeToken, 0, msg.value, _minAmountOut);
        uint256 balanceDiff = IERC20(homeToken).balanceOf(address(this)) -
            initialBalance;
        emit GasSwap(
            msg.sender,
            msg.value,
            balanceDiff,
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
        address _tokenIn,
        address _tokenOut,
        uint24 _poolFee,
        uint256 _amount,
        uint256 _minAmountOut
    ) private {
        IERC20(_tokenIn).approve(uniswapRouter, _amount);
        if (isV3Router) {
            IUniswapRouterV3(uniswapRouter).exactInputSingle(
                IUniswapRouterV3.ExactInputSingleParams({
                    tokenIn: _tokenIn,
                    tokenOut: _tokenOut,
                    fee: _poolFee > 0 ? _poolFee : defaultPoolFee,
                    recipient: address(this),
                    deadline: block.timestamp, // @audit Missing deadline means TX with always revert
                    amountIn: _amount,
                    amountOutMinimum: _minAmountOut,
                    sqrtPriceLimitX96: 0
                })
            );
        } else {
            address[] memory path = new address[](2);
            path[0] = _tokenIn;
            path[1] = _tokenOut;
            IUniswapRouterV2(uniswapRouter).swapExactTokensForETH( // @audit This will revert because tokenOut is not WETH (supposed to be home token)
                _amount,
                _minAmountOut,
                path,
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
        require(address(this).balance >= _minAmount, "Send amount too small"); // @audit Revert message doesn't make sense?
        payable(_recipient).transfer(address(this).balance);
    }

    /////// Admin-Only Functions ///////

    function setUniswapRouter(
        address _uniswapRouter,
        bool _isV3Router
    ) external onlyOwner {
        require(_uniswapRouter != address(0));
        uniswapRouter = _uniswapRouter;
        isV3Router = _isV3Router;
    }

    function setHomeToken(address _homeToken) external onlyOwner {
        require(_homeToken != address(0));
        homeToken = _homeToken;
    }

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

    function replenishRelayer(
        // @audit typo: replenish
        address _relayer,
        uint24 _poolFee,
        uint256 _swapAmount,
        uint256 _minAmountOut
    ) external payable onlyOwner {
        require(isRelayer[_relayer], "Invalid relayer");
        _swap(homeToken, address(WETH), _poolFee, _swapAmount, _minAmountOut);
        _unwrap();
        payable(_relayer).transfer(address(this).balance);
    }

    function withdraw(address _token) external onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, balance);
    }

    /////// View Functions ///////

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

    receive() external payable {}
}