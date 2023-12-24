// SPDX-License-Identifier: MIT

pragma solidity =0.8.17;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {SigUtils} from "./SigUtils.sol";
import {GasbotV2} from "src/GasbotV2.sol";

/// forge test --match-path test/GasbotV2.t.sol -vvv
/// forge coverage --match-path test/GasbotV2.t.sol
contract BaseGasbotV2Test is Test {
    event GasSwap(
        address indexed sender,
        uint256 nativeAmount,
        uint256 usdAmount,
        uint256 indexed fromChainId,
        uint256 indexed toChainId
    );

    SigUtils internal sigUtils;

    address public constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address public constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant RELAYER =
        0x757EEB3E60d0D3f9a8a34A8540AB6c88eB058e49;
    address public constant UNI_V3_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant UNI_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    bytes32 public constant USDC_DOMAIN_SEPARATOR =
        0x06c37168a7db5138defc7866392bb87a741f9b3d104deb5094588ce041cae335;
    GasbotV2 public gasbot;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 18835949);

        gasbot = new GasbotV2(
            address(this),
            RELAYER,
            UNI_V3_ROUTER,
            true,
            WETH,
            USDC
        );

        sigUtils = new SigUtils(USDC_DOMAIN_SEPARATOR);
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

        // Can call functions as deployment was successful
        gasbot.getRelayerBalances(relayers);
    }
}

contract Receive is BaseGasbotV2Test {
    function test_successful_canReceiveEther() public {
        (bool ok, ) = address(gasbot).call{value: 1 ether}("");
        assertTrue(ok);
    }
}

contract RelayTokenIn is BaseGasbotV2Test {
    function test_revertsIf_notAuthorizedRelayer(address caller) public {
        GasbotV2.PermitParams memory params = GasbotV2.PermitParams(
            0xf466385C089e1772893947BA01f81264946D57D8,
            0x59aF55fE00CcC0f0c248510fCC774fdC4919BBBf,
            4000000,
            0,
            0,
            bytes32(0),
            bytes32(0)
        );

        vm.assume(caller != RELAYER);
        vm.expectRevert("Unauthorized");
        vm.prank(caller);
        gasbot.relayTokenIn(AAVE, params, 100, 1_000e18);
    }

    function test_successful_alreadyApprovedNoSwap() public {
        uint256 amount = 4000000;
        address owner = 0xf466385C089e1772893947BA01f81264946D57D8;

        deal(USDC, owner, amount);

        GasbotV2.PermitParams memory params = GasbotV2.PermitParams(
            owner,
            0x59aF55fE00CcC0f0c248510fCC774fdC4919BBBf,
            amount,
            0,
            0,
            bytes32(0),
            bytes32(0)
        );

        assertEq(IERC20(USDC).balanceOf(address(gasbot)), 0);

        vm.prank(owner);
        IERC20(USDC).approve(address(gasbot), amount);

        vm.prank(RELAYER);
        gasbot.relayTokenIn(USDC, params, 100, 1_000e18);

        assertEq(IERC20(USDC).balanceOf(address(gasbot)), amount);
    }

    // function test_successful_alreadyApprovedWithSwap_uniV2() public {
    //     gasbot.setUniswapRouter(UNI_V2_ROUTER, false);

    //     uint256 amount = 0.01 ether;
    //     uint256 minAmountOut = 5_000000;
    //     address owner = 0xf466385C089e1772893947BA01f81264946D57D8;

    //     deal(AAVE, owner, amount);

    //     GasbotV2.PermitParams memory params = GasbotV2.PermitParams(
    //         owner,
    //         0x59aF55fE00CcC0f0c248510fCC774fdC4919BBBf,
    //         amount,
    //         0,
    //         0,
    //         bytes32(0),
    //         bytes32(0)
    //     );

    //     assertEq(IERC20(AAVE).balanceOf(address(gasbot)), 0);

    //     vm.prank(owner);
    //     IERC20(AAVE).approve(address(gasbot), amount);

    //     vm.prank(RELAYER);
    //     gasbot.relayTokenIn(AAVE, params, 500, minAmountOut);

    //     assertEq(IERC20(AAVE).balanceOf(address(gasbot)), 0);
    //     assertGe(IERC20(USDC).balanceOf(address(gasbot)), minAmountOut);
    // }

    function test_successful_alreadyApprovedWithSwap_uniV3() public {
        // FRAX/USDC is ~1:1
        uint256 amount = 40 ether;
        uint256 minAmountOut = 35_000000;
        address owner = 0xf466385C089e1772893947BA01f81264946D57D8;

        deal(FRAX, owner, amount);

        GasbotV2.PermitParams memory params = GasbotV2.PermitParams(
            owner,
            0x59aF55fE00CcC0f0c248510fCC774fdC4919BBBf,
            amount,
            0,
            0,
            bytes32(0),
            bytes32(0)
        );

        assertEq(IERC20(FRAX).balanceOf(address(gasbot)), 0);

        vm.prank(owner);
        IERC20(FRAX).approve(address(gasbot), amount);

        vm.prank(RELAYER);
        gasbot.relayTokenIn(FRAX, params, 500, minAmountOut);

        assertEq(IERC20(FRAX).balanceOf(address(gasbot)), 0);
        assertGe(IERC20(USDC).balanceOf(address(gasbot)), minAmountOut);
    }

    function test_successful_permitNoSwap() public {
        uint256 deadline = block.timestamp;
        uint256 amount = 4000000;
        uint256 minAmountOut = 35_000000;

        uint256 ownerPrivateKey = 0xA11cE;
        address owner = vm.addr(ownerPrivateKey);

        deal(USDC, owner, amount);

        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: address(gasbot),
            value: amount,
            nonce: 0,
            deadline: deadline
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        GasbotV2.PermitParams memory params = GasbotV2.PermitParams(
            owner,
            address(gasbot),
            amount,
            deadline,
            v,
            r,
            s
        );

        assertEq(IERC20(USDC).balanceOf(address(gasbot)), 0);

        vm.prank(RELAYER);
        gasbot.relayTokenIn(USDC, params, 100, minAmountOut);

        assertEq(IERC20(USDC).balanceOf(address(gasbot)), amount);
    }
}

contract TransferGasOut is BaseGasbotV2Test {
    function test_revertsIf_notAuthorizedRelayer(address caller) public {
        vm.assume(caller != RELAYER);
        vm.expectRevert("Unauthorized");
        vm.prank(caller);
        gasbot.transferGasOut(1 ether, RELAYER, 100, 1 ether, 1);
    }

    function test_revertsIf_expiredOutboundId() public {
        address recipient = makeAddr("recipient");
        uint256 minAmountOut = 0.02 ether;
        deal(USDC, address(gasbot), 100e6);

        vm.prank(RELAYER);
        gasbot.transferGasOut(50e6, recipient, 0, minAmountOut, 1);

        vm.expectRevert("Expired outbound ID");
        vm.prank(RELAYER);
        gasbot.transferGasOut(50e6, recipient, 0, minAmountOut, 1);
    }

    function test_successful() public {
        address recipient = makeAddr("recipient");
        uint256 minAmountOut = 0.02 ether;
        deal(USDC, address(gasbot), 100e6);

        assertEq(IERC20(USDC).balanceOf(address(gasbot)), 100e6);
        assertEq(address(recipient).balance, 0);

        vm.prank(RELAYER);
        gasbot.transferGasOut(50e6, recipient, 0, minAmountOut, 1);

        assertEq(IERC20(USDC).balanceOf(address(gasbot)), 50e6);
        assertGe(address(recipient).balance, minAmountOut);
    }
}

contract RelayAndTransfer is BaseGasbotV2Test {
    function test_revertsIf_notAuthorizedRelayer(address caller) public {
        GasbotV2.PermitParams memory params = GasbotV2.PermitParams(
            0xf466385C089e1772893947BA01f81264946D57D8,
            0x59aF55fE00CcC0f0c248510fCC774fdC4919BBBf,
            4000000,
            0,
            0,
            bytes32(0),
            bytes32(0)
        );

        vm.assume(caller != RELAYER);
        vm.expectRevert("Unauthorized");
        vm.prank(caller);
        gasbot.relayAndTransfer(AAVE, params, 100, 1 ether, 1 ether);
    }

    function test_revertsIf_invalidAmount() public {
        GasbotV2.PermitParams memory params = GasbotV2.PermitParams(
            0xf466385C089e1772893947BA01f81264946D57D8,
            0x59aF55fE00CcC0f0c248510fCC774fdC4919BBBf,
            1 ether,
            0,
            0,
            bytes32(0),
            bytes32(0)
        );

        vm.expectRevert("Invalid swap amount");
        vm.prank(RELAYER);
        gasbot.relayAndTransfer(AAVE, params, 100, 2 ether, 2 ether);
    }

    function test_successful_withApproval_uniV3() public {
        // $50 of USDC is ~0.017 WETH on 12/23/2023
        uint256 amount = 50e6;
        uint256 minAmountOut = 0.02 ether;
        address owner = 0xf466385C089e1772893947BA01f81264946D57D8;

        deal(USDC, owner, amount);

        GasbotV2.PermitParams memory params = GasbotV2.PermitParams(
            owner,
            0x59aF55fE00CcC0f0c248510fCC774fdC4919BBBf,
            amount,
            0,
            0,
            bytes32(0),
            bytes32(0)
        );

        assertEq(IERC20(USDC).balanceOf(address(gasbot)), 0);

        vm.prank(owner);
        IERC20(USDC).approve(address(gasbot), amount);

        uint256 ownerBalanceBefore = address(owner).balance;

        vm.prank(RELAYER);
        gasbot.relayAndTransfer(USDC, params, 0, amount - 1e6, minAmountOut);

        assertEq(IERC20(USDC).balanceOf(address(gasbot)), 1e6);
        assertEq(IERC20(WETH).balanceOf(address(gasbot)), 0);
        assertEq(IERC20(WETH).balanceOf(address(owner)), 0);
        assertGe(address(owner).balance, ownerBalanceBefore + minAmountOut);
    }
}

contract SwapGas is BaseGasbotV2Test {
    function test_revertsIf_amountIsZero() public {
        uint256 minAmountOut = 40e6;
        address caller = makeAddr("caller");
        deal(caller, 1 ether);

        vm.expectRevert();
        vm.prank(caller);
        gasbot.swapGas{value: 0}(minAmountOut, 137);
    }

    function test_successful() public {
        // 0.02 ETH ~40 USDC
        uint256 minAmountOut = 40e6;
        address caller = makeAddr("caller");
        deal(caller, 1 ether);

        assertEq(IERC20(USDC).balanceOf(address(gasbot)), 0);

        vm.expectEmit(true, true, true, true);
        emit GasSwap(caller, 0.02 ether, 44693653, 1, 137);
        vm.prank(caller);
        gasbot.swapGas{value: 0.02 ether}(minAmountOut, 137);

        assertGe(IERC20(USDC).balanceOf(address(gasbot)), minAmountOut);
    }
}

contract SetUniswapRouter is BaseGasbotV2Test {
    function test_revertsIf_notOwner(address caller) public {
        vm.assume(caller != address(this));
        vm.expectRevert("Unauthorized");
        vm.prank(caller);
        gasbot.setUniswapRouter(makeAddr("new-router"), false);
    }

    function test_revertsIf_routerIsAddressZero() public {
        vm.expectRevert();
        gasbot.setUniswapRouter(address(0), false);
    }

    function test_successful(address newRouter, bool isV3) public {
        vm.assume(newRouter != address(0));
        gasbot.setUniswapRouter(newRouter, isV3);
    }
}

contract SetHomeToken is BaseGasbotV2Test {
    function test_revertsIf_notOwner(address caller) public {
        vm.assume(caller != address(this));
        vm.expectRevert("Unauthorized");
        vm.prank(caller);
        gasbot.setHomeToken(makeAddr("new-token"));
    }

    function test_revertsIf_routerIsAddressZero() public {
        vm.expectRevert();
        gasbot.setHomeToken(address(0));
    }

    function test_successful(address newToken) public {
        vm.assume(newToken != address(0));
        gasbot.setHomeToken(newToken);
    }
}

contract SetRelayer is BaseGasbotV2Test {
    function test_revertsIf_notOwner(address caller) public {
        vm.assume(caller != address(this));
        vm.expectRevert("Unauthorized");
        vm.prank(caller);
        gasbot.setRelayer(makeAddr("new-relayer"), true);
    }

    function test_successful_relayerCanCall() public {
        address owner = 0xf466385C089e1772893947BA01f81264946D57D8;
        GasbotV2.PermitParams memory params = GasbotV2.PermitParams(
            owner,
            0x59aF55fE00CcC0f0c248510fCC774fdC4919BBBf,
            4000000,
            0,
            0,
            bytes32(0),
            bytes32(0)
        );

        deal(USDC, owner, 1 ether);

        vm.prank(owner);
        IERC20(USDC).approve(address(gasbot), 1 ether);

        address newRelayer = makeAddr("new-relayer");
        vm.expectRevert("Unauthorized");
        vm.prank(newRelayer);
        gasbot.relayTokenIn(USDC, params, 100, 0);

        gasbot.setRelayer(newRelayer, true);

        vm.prank(newRelayer);
        gasbot.relayTokenIn(USDC, params, 100, 0);
    }

    function test_successful_removedRelayerCannotCall() public {
        address owner = 0xf466385C089e1772893947BA01f81264946D57D8;
        GasbotV2.PermitParams memory params = GasbotV2.PermitParams(
            owner,
            0x59aF55fE00CcC0f0c248510fCC774fdC4919BBBf,
            4000000,
            0,
            0,
            bytes32(0),
            bytes32(0)
        );

        deal(USDC, owner, 1 ether);

        vm.prank(owner);
        IERC20(USDC).approve(address(gasbot), 100 ether);

        vm.prank(RELAYER);
        gasbot.relayTokenIn(USDC, params, 100, 1_000e18);

        gasbot.setRelayer(RELAYER, false);
        vm.expectRevert("Unauthorized");
        vm.prank(RELAYER);
        gasbot.relayTokenIn(USDC, params, 100, 1_000e18);
    }
}

contract Execute is BaseGasbotV2Test {
    function test_revertsIf_notOwner(address caller) public {
        vm.assume(caller != address(this));

        vm.expectRevert("Unauthorized");
        vm.prank(caller);
        gasbot.execute(address(0), bytes(""), 0, address(0));
    }

    function test_successful_transferToRecipient() public {
        address recipient = makeAddr("recipient");

        deal(address(gasbot), 1 ether);

        assertEq(address(gasbot).balance, 1 ether);
        assertEq(address(recipient).balance, 0);

        gasbot.execute(address(0), bytes(""), 0, recipient);

        assertEq(address(gasbot).balance, 0);
        assertEq(address(recipient).balance, 1 ether);
    }

    function test_successful() public {
        uint256 dealAmount = 100e6;

        deal(USDC, address(gasbot), dealAmount);

        bytes memory data = abi.encodeCall(
            IERC20.transfer,
            (address(this), dealAmount)
        );

        assertEq(IERC20(USDC).balanceOf(address(gasbot)), dealAmount);
        assertEq(IERC20(USDC).balanceOf(address(this)), 0);

        gasbot.execute(USDC, data, 0, address(0));

        assertEq(IERC20(USDC).balanceOf(address(gasbot)), 0);
        assertEq(IERC20(USDC).balanceOf(address(this)), dealAmount);
    }
}

contract ReplenishRelayer is BaseGasbotV2Test {
    function test_revertsIf_notOwner(address caller) public {
        vm.assume(caller != address(this));

        vm.expectRevert("Unauthorized");
        vm.prank(caller);
        gasbot.replenishRelayer(RELAYER, 500, 1 ether, 1 ether);
    }

    function test_revertsIf_notRelayer() public {
        vm.expectRevert("Invalid relayer");
        gasbot.replenishRelayer(makeAddr("not-relayer"), 500, 1 ether, 1 ether);
    }

    function test_successful() public {
        uint256 dealAmount = 50e6;
        uint256 minAmountOut = 0.02 ether;

        deal(USDC, address(gasbot), dealAmount);

        assertEq(IERC20(USDC).balanceOf(address(gasbot)), dealAmount);

        uint256 balanceRelayerBefore = RELAYER.balance;

        gasbot.replenishRelayer(RELAYER, 500, dealAmount, minAmountOut);

        assertEq(IERC20(USDC).balanceOf(address(gasbot)), 0);
        assertGe(RELAYER.balance, balanceRelayerBefore + minAmountOut);
    }
}

contract Withdraw is BaseGasbotV2Test {
    function test_revertsIf_notOwner(address caller) public {
        vm.assume(caller != address(this));
        vm.expectRevert("Unauthorized");
        vm.prank(caller);
        gasbot.withdraw(USDC);
    }

    function test_successful() public {
        uint256 dealAmount = 100e6;
        deal(USDC, address(gasbot), dealAmount);

        assertEq(IERC20(USDC).balanceOf(address(gasbot)), dealAmount);
        assertEq(IERC20(USDC).balanceOf(address(this)), 0);

        gasbot.withdraw(USDC);

        assertEq(IERC20(USDC).balanceOf(address(gasbot)), 0);
        assertEq(IERC20(USDC).balanceOf(address(this)), dealAmount);
    }
}

contract GetTokenBalances is BaseGasbotV2Test {
    function setUp() public override {
        gasbot = new GasbotV2(
            address(this),
            RELAYER,
            UNI_V3_ROUTER,
            true,
            WETH,
            USDC
        );
    }

    function test_successful_onlyNative() public {
        address user = makeAddr("user");
        address[] memory ownedTokens = new address[](0);

        (address[] memory tokens, uint256[] memory balances) = gasbot
            .getTokenBalances(user, ownedTokens);

        assertEq(tokens.length, balances.length);
        assertEq(tokens.length, 1);
        assertEq(balances[0], 0);
        assertEq(tokens[0], address(0));
    }

    function test_successful_passedTokens() public {
        uint256 usdcAmount = 1_000e6;
        address user = makeAddr("user");

        address[] memory ownedTokens = new address[](2);
        ownedTokens[0] = AAVE;
        ownedTokens[1] = USDC;

        vm.mockCall(
            AAVE,
            abi.encodeWithSelector(IERC20.balanceOf.selector),
            abi.encode(0)
        );

        vm.mockCall(
            USDC,
            abi.encodeWithSelector(IERC20.balanceOf.selector),
            abi.encode(usdcAmount)
        );

        (address[] memory tokens, uint256[] memory balances) = gasbot
            .getTokenBalances(user, ownedTokens);

        assertEq(tokens.length, balances.length);
        assertEq(tokens.length, 3);
        assertEq(balances[0], 0);
        assertEq(tokens[0], address(0));
        assertEq(balances[1], 0);
        assertEq(tokens[1], AAVE);
        assertEq(balances[2], usdcAmount);
        assertEq(tokens[2], USDC);
    }
}

contract GetRelayerBalances is BaseGasbotV2Test {
    function setUp() public override {
        gasbot = new GasbotV2(
            address(this),
            RELAYER,
            UNI_V3_ROUTER,
            true,
            WETH,
            USDC
        );
    }

    function test_revertsIf_invalidRelayer(address relayer) public {
        vm.assume(relayer != RELAYER);

        address[] memory relayers = new address[](1);
        relayers[0] = relayer;

        vm.expectRevert("Invalid relayer");
        gasbot.getRelayerBalances(relayers);
    }

    function test_successful() public {
        address[] memory relayers = new address[](1);
        relayers[0] = RELAYER;

        uint256[] memory balances = gasbot.getRelayerBalances(relayers);

        assertEq(balances[0], 0);

        RELAYER.call{value: 1 ether}("");

        balances = gasbot.getRelayerBalances(relayers);

        assertEq(balances[0], 1 ether);
    }
}
