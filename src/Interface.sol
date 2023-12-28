//SPDX-License-Identifier: MIT
pragma solidity =0.8.22;

interface IWETH {
    function deposit() external payable;

    function withdraw(uint wad) external;

    function balanceOf(address account) external view returns (uint);
}

interface IUniswapRouterV2 {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

interface IUniswapRouterV3 {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(
        ExactInputParams calldata params
    ) external payable returns (uint256 amountOut);
}
