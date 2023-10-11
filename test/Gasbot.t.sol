// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../src/Gasbot.sol";
import "ds-test/test.sol";
import "forge-std/Script.sol";

// import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract Gasbot is DSTest, Script {
    GasBot gasbot;
    IERC20 usdc = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    address user = 0x90319087Bf0Baa2d62b2966b308E8E3f6fb73964;

    function setUp() external {
        string memory rpc = "https://rpc.ankr.com/base";
        uint256 forkId = vm.createFork(rpc);
        vm.selectFork(forkId);

        gasbot = new GasBot(msg.sender, msg.sender);
    }

    // ============================
    // Test Implementation Update
    // ============================
    function test_getTokenBalances() external {
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        gasbot.getTokenBalances(user, tokens);
    }
}
