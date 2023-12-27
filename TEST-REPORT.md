# Unit Test Report

Unit test coverage with 100% line coverage, 100% function coverage and 92.3% branch coverage was achieved. The missing % points of branch coverage are due to unreachable statements that will be detailed below.

Overall, four bugs were found in the code: two low impact and two high impact issues. Please see the issues section.

| File                  | % Lines           | % Statements      | % Branches       | % Funcs           |
| --------------------- | ----------------- | ----------------- | ---------------- | ----------------- |
| src/GasbotV2.sol      | 100.00% (65/65)   | 100.00% (82/82)   | 92.31% (24/26)   | 100.00% (16/16)   |
| --------------------- | ----------------- | ----------------- | ---------------- | ----------------- |

## Branch Coverage

There are two functions with unreachable statements for branch coverage (they can be visualized with genhtml).

```
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
```

Branch 0 is when allowance is >= the amount, or otherwise, when the if statement evaluates as false. There is no else statement or a major difference and unfortunately because of how the if statement is formatted to fit the lines, lcov counts against it.

The other function is:

```
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
```

If `_target.call()` evaluates as false, the require statement will make the function revert, and the branch where `success` is false means that the statement `_recipient != address(0)` will not be reached. This unreachable statement counts against branch coverage here. The code could be reworked to achieve full branch coverage of this function.

## Issues

```
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
            IUniswapRouterV2(uniswapRouter).swapExactTokensForETH( // @audit This will revert when tokenOut is not WETH (ie home token swap)
                _amount,
                _minAmountOut,
                path,
                address(this),
                block.timestamp
            );
        }
    }
```

#### High

When swapping with UniswapV3Router, the missing deadline param means all swaps will revert. The UniswapV3Router has a specific check for deadline being greater than or equal to the current block.timestamp. The missing deadline will default to the value of 0, and thus, the function will always revert.

#### High

When swapping with UniswapV2Router, the function being called will fail when swapping to a non-WETH token. This happens when swapping for the "home token." For example, if swapping from token1 to USDC, the function will revert.

```
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
            balances_[i] = IERC20(_tokens[i]).balanceOf(_user);
        }
        return (tokens_, balances_);
    }
```

#### Low

`getTokenBalances` function uses the wrong array index to compare between `balances_` and `_tokens` as they are arrays of different sizes. This will revert with an index-out-of-bounds error when a user tries to view balances.

##### Low

`getTokenBalances` function does not update the `tokens_` array with the right address, thus, users will not be able to determine which balances match which tokens.

## Miscellaneous

The code has been commented with the `@audit` tag with some minor comments/recommendations.
