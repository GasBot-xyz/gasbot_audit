//SPDX-License-Identifier: MIT

pragma solidity =0.8.17;

import {Test} from "forge-std/Test.sol";

import {GasbotV2} from "src/GasbotV2.sol";

/// forge test --match-path test/GasbotV2.t.sol -vvv
contract BaseGasbotV2Test is Test {
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant RELAYER =
        0x757EEB3E60d0D3f9a8a34A8540AB6c88eB058e49;
    address public constant UNI_V3_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    GasbotV2 public gasbot;

    function setUp() public virtual {
        gasbot = new GasbotV2(
            address(this),
            RELAYER,
            UNI_V3_ROUTER,
            true,
            WETH,
            USDC
        );
    }
}

contract Constructor is BaseGasbotV2Test {
    function setUp() public override {}

    function test_revertsIf_ownerIsAddressZero() public {
        vm.expectRevert();
        new GasbotV2(address(0), RELAYER, UNI_V3_ROUTER, true, WETH, USDC);
    }

    function test_revertsIf_uniswapRouterIsAddressZero() public {
        vm.expectRevert();
        new GasbotV2(address(this), RELAYER, address(0), true, WETH, USDC);
    }

    function test_revertsIf_wethIsAddressZero() public {
        vm.expectRevert();
        new GasbotV2(
            address(this),
            RELAYER,
            UNI_V3_ROUTER,
            true,
            address(0),
            USDC
        );
    }

    function test_revertsIf_homeTokenIsAddressZero() public {
        vm.expectRevert();
        new GasbotV2(
            address(this),
            RELAYER,
            UNI_V3_ROUTER,
            true,
            WETH,
            address(0)
        );
    }

    function test_successful(
        address owner,
        address relayer,
        address router,
        bool isV3,
        address weth,
        address homeToken
    ) public {
        vm.assume(owner != address(0));
        vm.assume(relayer != address(0));
        vm.assume(router != address(0));
        vm.assume(weth != address(0));
        vm.assume(homeToken != address(0));

        gasbot = new GasbotV2(owner, relayer, router, isV3, weth, homeToken);

        address[] memory relayers = new address[](1);
        relayers[0] = relayer;

        uint256[] memory balances = gasbot.getRelayerBalances(relayers);

        assertEq(balances[0], 0);
    }
}
