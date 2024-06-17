// // SPDX-License-Identifier: MIT

// pragma solidity =0.8.19;

// import {Test} from "forge-std/Test.sol";
// import {IERC20} from "forge-std/interfaces/IERC20.sol";

// import {SigUtils} from "./SigUtils.sol";
// import {GasbotV2} from "src/Flexy.sol";

// contract MockERC20 {
//     function transfer(address to, uint256 amount) external pure {
//         revert();
//     }
// }

// /// forge test --match-path test/GasbotV2.t.sol -vvv
// /// forge coverage --match-path test/GasbotV2.t.sol
// contract BaseGasbotV2Test is Test {
//     event Bridge(
//         address indexed sender,
//         uint256 fromChainId,
//         address fromToken,
//         uint256 indexed toChainId,
//         address indexed toToken,
//         uint256 nativeAmount,
//         uint256 homeTokenAmount
//     );

//     SigUtils internal sigUtils;

//     uint256 public constant DEFAULT_GAS_LIMIT = 3_000;

//     address public constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
//     address public constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
//     address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
//     address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
//     address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
//     address public constant RELAYER =
//         0x757EEB3E60d0D3f9a8a34A8540AB6c88eB058e49;
//     address public constant UNI_V3_ROUTER =
//         0xE592427A0AEce92De3Edee1F18E0157C05861564;
//     address public constant UNI_V2_ROUTER =
//         0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

//     bytes32 public constant USDC_DOMAIN_SEPARATOR =
//         0x06c37168a7db5138defc7866392bb87a741f9b3d104deb5094588ce041cae335;
//     GasbotV2 public gasbot;

//     function setUp() public virtual {
//         vm.createSelectFork(vm.rpcUrl("mainnet"), 18835949);

//         gasbot = new GasbotV2(
//             address(this),
//             RELAYER,
//             UNI_V3_ROUTER,
//             true,
//             WETH,
//             USDC,
//             100
//         );

//         sigUtils = new SigUtils(USDC_DOMAIN_SEPARATOR);
//     }
// }

// // contract Constructor is BaseGasbotV2Test {
// //     function setUp() public override {
// //         vm.createSelectFork(vm.rpcUrl("mainnet"), 18835949);
// //     }

// //     function test_revertsIf_ownerIsAddressZero() public {
// //         vm.expectRevert();
// //         new GasbotV2(address(0), RELAYER, UNI_V3_ROUTER, true, WETH, USDC, 100);
// //     }

// //     function test_revertsIf_uniswapRouterIsAddressZero() public {
// //         vm.expectRevert();
// //         new GasbotV2(address(this), RELAYER, address(0), true, WETH, USDC, 100);
// //     }

// //     function test_revertsIf_wethIsAddressZero() public {
// //         vm.expectRevert();
// //         new GasbotV2(
// //             address(this),
// //             RELAYER,
// //             UNI_V3_ROUTER,
// //             true,
// //             address(0),
// //             USDC,
// //             100
// //         );
// //     }

// //     function test_revertsIf_homeTokenIsAddressZero() public {
// //         vm.expectRevert();
// //         new GasbotV2(
// //             address(this),
// //             RELAYER,
// //             UNI_V3_ROUTER,
// //             true,
// //             WETH,
// //             address(0),
// //             100
// //         );
// //     }

// //     /// @dev Running into "too many inputs" error after adding maxValue to contructor.
// //     // function test_successful(
// //     //     address owner,
// //     //     address relayer,
// //     //     address router,
// //     //     bool isV3,
// //     //     address weth,
// //     //     address homeToken
// //     // ) public {
// //     //     vm.assume(owner != address(0));
// //     //     vm.assume(relayer != address(0));
// //     //     vm.assume(router != address(0));
// //     //     vm.assume(weth != address(0));
// //     //     vm.assume(homeToken == USDC);

// //     //     gasbot = new GasbotV2(
// //     //         owner,
// //     //         relayer,
// //     //         router,
// //     //         isV3,
// //     //         weth,
// //     //         homeToken,
// //     //         50
// //     //     );

// //     //     address[] memory relayers = new address[](1);
// //     //     relayers[0] = relayer;

// //     //     // Can call functions as deployment was successful
// //     //     gasbot.getRelayerBalances(relayers);
// //     // }
// // }

// // contract Receive is BaseGasbotV2Test {
// //     function test_revertsIf_receiveEther() public {
// //         (bool ok, ) = address(gasbot).call{value: 1 ether}("");
// //         assertFalse(ok);
// //     }
// // }

// contract RelayTokenIn is BaseGasbotV2Test {
//     function test_revertsIf_notAuthorizedRelayer(address caller) public {
//         GasbotV2.PermitParams memory params = GasbotV2.PermitParams(
//             0xf466385C089e1772893947BA01f81264946D57D8,
//             0x59aF55fE00CcC0f0c248510fCC774fdC4919BBBf,
//             4000000,
//             0,
//             0,
//             bytes32(0),
//             bytes32(0)
//         );

//         vm.assume(caller != RELAYER);
//         vm.expectRevert("Unauthorized");
//         vm.prank(caller);

//         bytes memory uniV3Path = abi.encode(FRAX, 500, WETH);
//         address[] memory uniV2Path = new address[](0);
//         gasbot.relayIn(
//             FRAX,
//             params,
//             UNI_V3_ROUTER,
//             uniV3Path,
//             uniV2Path,
//             1_000e18,
//             block.timestamp
//         );
//     }

//     function test_successful_alreadyApprovedNoSwap() public {
//         uint256 amount = 4000000;
//         address owner = 0xf466385C089e1772893947BA01f81264946D57D8;

//         deal(USDC, owner, amount);

//         GasbotV2.PermitParams memory params = GasbotV2.PermitParams(
//             owner,
//             0x59aF55fE00CcC0f0c248510fCC774fdC4919BBBf,
//             amount,
//             0,
//             0,
//             bytes32(0),
//             bytes32(0)
//         );

//         assertEq(IERC20(USDC).balanceOf(address(gasbot)), 0);

//         vm.prank(owner);
//         IERC20(USDC).approve(address(gasbot), amount);

//         bytes memory uniV3Path = abi.encode(USDC, 500, WETH);
//         address[] memory uniV2Path = new address[](0);

//         vm.prank(RELAYER);
//         gasbot.relayTokenIn(
//             USDC,
//             params,
//             UNI_V3_ROUTER,
//             uniV3Path,
//             uniV2Path,
//             1_000e18,
//             block.timestamp
//         );

//         assertEq(IERC20(USDC).balanceOf(address(gasbot)), amount);
//     }

//     function test_successful_alreadyApprovedWithSwap_uniV2() public {
//         gasbot.setDefaultRouter(UNI_V2_ROUTER, false);

//         uint256 amount = 10 ether; // ~$10 FRAX
//         uint256 minAmountOut = 1_000_000; // 1 USDC
//         address owner = 0xf466385C089e1772893947BA01f81264946D57D8;

//         deal(FRAX, owner, amount);

//         GasbotV2.PermitParams memory params = GasbotV2.PermitParams(
//             owner,
//             0x59aF55fE00CcC0f0c248510fCC774fdC4919BBBf,
//             amount,
//             0,
//             0,
//             bytes32(0),
//             bytes32(0)
//         );

//         assertEq(IERC20(FRAX).balanceOf(address(gasbot)), 0);

//         vm.prank(owner);
//         IERC20(FRAX).approve(address(gasbot), amount);

//         bytes memory uniV3Path = new bytes(0);
//         address[] memory uniV2Path = new address[](2);
//         uniV2Path[0] = FRAX;
//         uniV2Path[1] = USDC;

//         vm.prank(RELAYER);
//         gasbot.relayTokenIn(
//             FRAX,
//             params,
//             UNI_V2_ROUTER,
//             uniV3Path,
//             uniV2Path,
//             minAmountOut,
//             block.timestamp
//         );

//         assertEq(IERC20(AAVE).balanceOf(address(gasbot)), 0);
//         assertGe(IERC20(USDC).balanceOf(address(gasbot)), minAmountOut);
//     }

//     function test_successful_alreadyApprovedWithSwap_uniV3() public {
//         // FRAX/USDC is ~1:1
//         uint256 amount = 40 ether;
//         uint256 minAmountOut = 35_000_000;
//         address owner = 0xf466385C089e1772893947BA01f81264946D57D8;

//         deal(FRAX, owner, amount);

//         GasbotV2.PermitParams memory params = GasbotV2.PermitParams(
//             owner,
//             0x59aF55fE00CcC0f0c248510fCC774fdC4919BBBf,
//             amount,
//             0,
//             0,
//             bytes32(0),
//             bytes32(0)
//         );

//         assertEq(IERC20(FRAX).balanceOf(address(gasbot)), 0);

//         vm.prank(owner);
//         IERC20(FRAX).approve(address(gasbot), amount);

//         uint24 poolFee = 500;
//         bytes memory uniV3Path = abi.encodePacked(FRAX, poolFee, USDC);
//         address[] memory uniV2Path = new address[](0);

//         vm.prank(RELAYER);
//         gasbot.relayTokenIn(
//             FRAX,
//             params,
//             UNI_V3_ROUTER,
//             uniV3Path,
//             uniV2Path,
//             minAmountOut,
//             block.timestamp
//         );

//         assertEq(IERC20(FRAX).balanceOf(address(gasbot)), 0);
//         assertGe(IERC20(USDC).balanceOf(address(gasbot)), minAmountOut);
//     }

//     function test_successful_permitNoSwap() public {
//         uint256 deadline = block.timestamp;
//         uint256 amount = 4000000;
//         uint256 minAmountOut = 35_000000;

//         uint256 ownerPrivateKey = 0xA11cE;
//         address owner = vm.addr(ownerPrivateKey);

//         deal(USDC, owner, amount);

//         SigUtils.Permit memory permit = SigUtils.Permit({
//             owner: owner,
//             spender: address(gasbot),
//             value: amount,
//             nonce: 0,
//             deadline: deadline
//         });

//         bytes32 digest = sigUtils.getTypedDataHash(permit);

//         (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

//         GasbotV2.PermitParams memory params = GasbotV2.PermitParams(
//             owner,
//             address(gasbot),
//             amount,
//             deadline,
//             v,
//             r,
//             s
//         );

//         assertEq(IERC20(USDC).balanceOf(address(gasbot)), 0);

//         vm.prank(RELAYER);
//         gasbot.relayTokenIn(
//             USDC,
//             params,
//             UNI_V3_ROUTER,
//             new bytes(0),
//             new address[](0),
//             minAmountOut,
//             block.timestamp
//         );

//         assertEq(IERC20(USDC).balanceOf(address(gasbot)), amount);
//     }
// }

// // contract TransferGasOut is BaseGasbotV2Test {
// //     function test_revertsIf_notAuthorizedRelayer(address caller) public {
// //         vm.assume(caller != RELAYER);
// //         vm.expectRevert("Unauthorized");
// //         vm.prank(caller);
// //         gasbot.transferGasOut(
// //             1 ether,
// //             RELAYER,
// //             1 ether,
// //             1,
// //             DEFAULT_GAS_LIMIT,
// //             block.timestamp
// //         );
// //     }

// //     function test_revertsIf_expiredOutboundId() public {
// //         address recipient = makeAddr("recipient");
// //         uint256 minAmountOut = 0.02 ether;
// //         deal(USDC, address(gasbot), 100e6);

// //         vm.prank(RELAYER);
// //         gasbot.transferGasOut(
// //             50e6,
// //             recipient,
// //             minAmountOut,
// //             1,
// //             DEFAULT_GAS_LIMIT,
// //             block.timestamp
// //         );

// //         vm.expectRevert("Expired outbound ID");
// //         vm.prank(RELAYER);
// //         gasbot.transferGasOut(
// //             50e6,
// //             recipient,
// //             minAmountOut,
// //             1,
// //             DEFAULT_GAS_LIMIT,
// //             block.timestamp
// //         );
// //     }

// //     function test_revertsIf_lowGasLimit() public {
// //         uint256 minAmountOut = 0.02 ether;
// //         deal(USDC, address(gasbot), 100e6);

// //         vm.expectRevert("Transfer failed");
// //         vm.prank(RELAYER);
// //         gasbot.transferGasOut(50e6, WETH, minAmountOut, 1, 50, block.timestamp); // Using USDC contract for simple payable contract
// //     }

// //     function test_succeedsIf_highGasLimit() public {
// //         uint256 minAmountOut = 0.02 ether;
// //         deal(USDC, address(gasbot), 100e6);

// //         vm.prank(RELAYER);
// //         gasbot.transferGasOut(
// //             50e6,
// //             WETH,
// //             minAmountOut,
// //             1,
// //             30000,
// //             block.timestamp
// //         ); // Using WETH contract for simple payable contract
// //     }

// //     function test_revertsIf_notEnoughBalance() public {
// //         address recipient = makeAddr("recipient");
// //         uint256 minAmountOut = 0.02 ether;
// //         deal(USDC, address(gasbot), 100e6);

// //         vm.mockCall(
// //             WETH,
// //             abi.encodeWithSelector(IERC20.balanceOf.selector),
// //             abi.encode(0)
// //         );

// //         vm.expectRevert("Native balance too low");
// //         vm.prank(RELAYER);
// //         gasbot.transferGasOut(
// //             50e6,
// //             recipient,
// //             minAmountOut,
// //             1,
// //             DEFAULT_GAS_LIMIT,
// //             block.timestamp
// //         );
// //     }

// //     function test_successful() public {
// //         address recipient = makeAddr("recipient");
// //         uint256 minAmountOut = 0.02 ether;
// //         deal(USDC, address(gasbot), 100e6);

// //         assertEq(IERC20(USDC).balanceOf(address(gasbot)), 100e6);
// //         assertEq(address(recipient).balance, 0);

// //         vm.prank(RELAYER);
// //         gasbot.transferGasOut(
// //             50e6,
// //             recipient,
// //             minAmountOut,
// //             1,
// //             DEFAULT_GAS_LIMIT,
// //             block.timestamp
// //         );

// //         assertEq(IERC20(USDC).balanceOf(address(gasbot)), 50e6);
// //         assertGe(address(recipient).balance, minAmountOut);
// //     }
// // }

// // contract RelayAndTransfer is BaseGasbotV2Test {
// //     function test_revertsIf_notAuthorizedRelayer(address caller) public {
// //         GasbotV2.PermitParams memory params = GasbotV2.PermitParams(
// //             0xf466385C089e1772893947BA01f81264946D57D8,
// //             0x59aF55fE00CcC0f0c248510fCC774fdC4919BBBf,
// //             4000000,
// //             0,
// //             0,
// //             bytes32(0),
// //             bytes32(0)
// //         );

// //         vm.assume(caller != RELAYER);
// //         vm.expectRevert("Unauthorized");

// //         uint24 poolFee = 500;
// //         bytes memory uniV3Path = abi.encodePacked(AAVE, poolFee, USDC);
// //         address[] memory uniV2Path = new address[](0);

// //         vm.prank(caller);
// //         gasbot.relayAndTransfer(
// //             AAVE,
// //             params,
// //             UNI_V3_ROUTER,
// //             uniV3Path,
// //             uniV2Path,
// //             1_000e18,
// //             0,
// //             DEFAULT_GAS_LIMIT,
// //             block.timestamp
// //         );
// //     }

// //     function test_revertsIf_invalidAmount() public {
// //         GasbotV2.PermitParams memory params = GasbotV2.PermitParams(
// //             0xf466385C089e1772893947BA01f81264946D57D8,
// //             0x59aF55fE00CcC0f0c248510fCC774fdC4919BBBf,
// //             1 ether,
// //             0,
// //             0,
// //             bytes32(0),
// //             bytes32(0)
// //         );

// //         uint24 poolFee = 500;
// //         bytes memory uniV3Path = abi.encodePacked(AAVE, poolFee, USDC);
// //         address[] memory uniV2Path = new address[](0);

// //         vm.expectRevert("Invalid swap amount");
// //         vm.prank(RELAYER);
// //         gasbot.relayAndTransfer(
// //             AAVE,
// //             params,
// //             UNI_V3_ROUTER,
// //             uniV3Path,
// //             uniV2Path,
// //             2 ether,
// //             0,
// //             DEFAULT_GAS_LIMIT,
// //             block.timestamp
// //         );
// //     }

// //     function test_successful_withApproval_uniV3() public {
// //         // $50 of USDC is ~0.017 WETH on 12/23/2023
// //         uint256 amount = 50e6;
// //         uint256 minAmountOut = 0.02 ether;
// //         address owner = 0xf466385C089e1772893947BA01f81264946D57D8;

// //         deal(USDC, owner, amount);

// //         GasbotV2.PermitParams memory params = GasbotV2.PermitParams(
// //             owner,
// //             0x59aF55fE00CcC0f0c248510fCC774fdC4919BBBf,
// //             amount,
// //             0,
// //             0,
// //             bytes32(0),
// //             bytes32(0)
// //         );

// //         assertEq(IERC20(USDC).balanceOf(address(gasbot)), 0);

// //         vm.prank(owner);
// //         IERC20(USDC).approve(address(gasbot), amount);

// //         uint256 ownerBalanceBefore = address(owner).balance;

// //         uint24 poolFee = 500;
// //         bytes memory uniV3Path = abi.encodePacked(USDC, poolFee, WETH);
// //         address[] memory uniV2Path = new address[](0);

// //         vm.prank(RELAYER);
// //         gasbot.relayAndTransfer(
// //             USDC,
// //             params,
// //             UNI_V3_ROUTER,
// //             uniV3Path,
// //             uniV2Path,
// //             amount - 1e6,
// //             minAmountOut,
// //             DEFAULT_GAS_LIMIT,
// //             block.timestamp
// //         );

// //         assertEq(IERC20(USDC).balanceOf(address(gasbot)), 1e6);
// //         assertEq(IERC20(WETH).balanceOf(address(gasbot)), 0);
// //         assertEq(IERC20(WETH).balanceOf(address(owner)), 0);
// //         assertGe(address(owner).balance, ownerBalanceBefore + minAmountOut);
// //     }
// // }

// // contract SwapGas is BaseGasbotV2Test {
// //     function test_revertsIf_amountIsZero() public {
// //         uint256 minAmountOut = 40e6;
// //         address caller = makeAddr("caller");
// //         deal(caller, 1 ether);

// //         vm.expectRevert("Invalid amount");
// //         vm.prank(caller);
// //         gasbot.swapGas{value: 0}(minAmountOut, 137, block.timestamp);
// //     }

// //     function test_successful() public {
// //         // 0.02 ETH ~40 USDC
// //         uint256 minAmountOut = 40e6;
// //         address caller = makeAddr("caller");
// //         deal(caller, 1 ether);

// //         assertEq(IERC20(USDC).balanceOf(address(gasbot)), 0);

// //         vm.expectEmit(true, true, true, true);
// //         emit GasSwap(caller, 0.02 ether, 44693653, 1, 137);
// //         vm.prank(caller);
// //         gasbot.swapGas{value: 0.02 ether}(minAmountOut, 137, block.timestamp);

// //         assertGe(IERC20(USDC).balanceOf(address(gasbot)), minAmountOut);
// //     }

// //     function test_revertsIf_greaterThanMaxValue() public {
// //         uint256 minAmountOut = 110e6;
// //         address caller = makeAddr("caller");
// //         deal(caller, 10 ether);

// //         assertEq(IERC20(USDC).balanceOf(address(gasbot)), 0);

// //         vm.expectRevert("Exceeded max value");
// //         vm.prank(caller);
// //         gasbot.swapGas{value: 1 ether}(minAmountOut, 137, block.timestamp);
// //     }

// //     function test_revertsIf_lowerThanMaxValue() public {
// //         uint256 minAmountOut = 0;
// //         address caller = makeAddr("caller");
// //         deal(caller, 10 ether);

// //         assertEq(IERC20(USDC).balanceOf(address(gasbot)), 0);

// //         vm.expectRevert("Below min value");
// //         vm.prank(caller);
// //         gasbot.swapGas{value: 0.000000000001 ether}(
// //             minAmountOut,
// //             137,
// //             block.timestamp
// //         );
// //     }
// // }

// // contract SetDefaultRouter is BaseGasbotV2Test {
// //     function test_revertsIf_notOwner(address caller) public {
// //         vm.assume(caller != address(this));
// //         vm.expectRevert("Unauthorized");
// //         vm.prank(caller);
// //         gasbot.setDefaultRouter(makeAddr("new-router"), false);
// //     }

// //     function test_revertsIf_routerIsAddressZero() public {
// //         vm.expectRevert();
// //         gasbot.setDefaultRouter(address(0), false);
// //     }

// //     function test_successful(address newRouter, bool isV3) public {
// //         vm.assume(newRouter != address(0));
// //         gasbot.setDefaultRouter(newRouter, isV3);
// //     }
// // }

// // contract SetHomeToken is BaseGasbotV2Test {
// //     function test_revertsIf_notOwner(address caller) public {
// //         vm.assume(caller != address(this));
// //         vm.expectRevert("Unauthorized");
// //         vm.prank(caller);
// //         gasbot.setHomeToken(makeAddr("new-token"));
// //     }

// //     function test_revertsIf_routerIsAddressZero() public {
// //         vm.expectRevert();
// //         gasbot.setHomeToken(address(0));
// //     }

// //     function test_successful() public {
// //         uint256 maxValue = gasbot.getMaxValue();

// //         gasbot.setHomeToken(FRAX);
// //         assertEq(gasbot.getHomeToken(), FRAX);
// //         assertEq(
// //             gasbot.getMaxValue(),
// //             (maxValue * 10 ** IERC20(FRAX).decimals()) /
// //                 10 ** IERC20(USDC).decimals()
// //         );

// //         gasbot.setHomeToken(USDC);
// //         assertEq(gasbot.getHomeToken(), USDC);
// //         assertEq(gasbot.getMaxValue(), maxValue); // Should be back to original value
// //     }
// // }

// // contract SetMaxValue is BaseGasbotV2Test {
// //     function test_revertsIf_notOwner(address caller) public {
// //         vm.assume(caller != address(this));
// //         vm.expectRevert("Unauthorized");
// //         vm.prank(caller);
// //         gasbot.setMaxValue(50);
// //     }

// //     function test_successful(address newToken) public {
// //         gasbot.setMaxValue(50);
// //     }

// //     function test_successful_swapRevertsIfSetTo0() public {
// //         gasbot.setMaxValue(0);

// //         uint256 minAmountOut = 20e6;
// //         address caller = makeAddr("caller");
// //         deal(caller, 1 ether);

// //         assertEq(IERC20(USDC).balanceOf(address(gasbot)), 0);

// //         vm.expectRevert("Exceeded max value");
// //         vm.prank(caller);
// //         gasbot.swapGas{value: 0.02 ether}(minAmountOut, 137, block.timestamp);
// //     }
// // }

// // contract SetRelayer is BaseGasbotV2Test {
// //     function test_revertsIf_notOwner(address caller) public {
// //         vm.assume(caller != address(this));
// //         vm.expectRevert("Unauthorized");
// //         vm.prank(caller);
// //         gasbot.setRelayer(makeAddr("new-relayer"), true);
// //     }

// //     function test_successful_relayerCanCall() public {
// //         address owner = 0xf466385C089e1772893947BA01f81264946D57D8;
// //         GasbotV2.PermitParams memory params = GasbotV2.PermitParams(
// //             owner,
// //             0x59aF55fE00CcC0f0c248510fCC774fdC4919BBBf,
// //             4000000,
// //             0,
// //             0,
// //             bytes32(0),
// //             bytes32(0)
// //         );

// //         deal(USDC, owner, 1 ether);

// //         vm.prank(owner);
// //         IERC20(USDC).approve(address(gasbot), 1 ether);

// //         address newRelayer = makeAddr("new-relayer");
// //         vm.expectRevert("Unauthorized");
// //         vm.prank(newRelayer);
// //         gasbot.relayTokenIn(
// //             USDC,
// //             params,
// //             UNI_V3_ROUTER,
// //             new bytes(0),
// //             new address[](0),
// //             0,
// //             block.timestamp
// //         );

// //         gasbot.setRelayer(newRelayer, true);

// //         vm.prank(newRelayer);
// //         gasbot.relayTokenIn(
// //             USDC,
// //             params,
// //             UNI_V3_ROUTER,
// //             new bytes(0),
// //             new address[](0),
// //             0,
// //             block.timestamp
// //         );
// //     }

// //     function test_successful_removedRelayerCannotCall() public {
// //         address owner = 0xf466385C089e1772893947BA01f81264946D57D8;
// //         GasbotV2.PermitParams memory params = GasbotV2.PermitParams(
// //             owner,
// //             0x59aF55fE00CcC0f0c248510fCC774fdC4919BBBf,
// //             4000000,
// //             0,
// //             0,
// //             bytes32(0),
// //             bytes32(0)
// //         );

// //         deal(USDC, owner, 1 ether);

// //         vm.prank(owner);
// //         IERC20(USDC).approve(address(gasbot), 100 ether);

// //         vm.prank(RELAYER);
// //         gasbot.relayTokenIn(
// //             USDC,
// //             params,
// //             UNI_V3_ROUTER,
// //             new bytes(0),
// //             new address[](0),
// //             0,
// //             block.timestamp
// //         );

// //         gasbot.setRelayer(RELAYER, false);
// //         vm.expectRevert("Unauthorized");
// //         vm.prank(RELAYER);
// //         gasbot.relayTokenIn(
// //             USDC,
// //             params,
// //             UNI_V3_ROUTER,
// //             new bytes(0),
// //             new address[](0),
// //             0,
// //             block.timestamp
// //         );
// //     }
// // }

// // contract Execute is BaseGasbotV2Test {
// //     function test_revertsIf_notOwner(address caller) public {
// //         vm.assume(caller != address(this));

// //         vm.expectRevert("Unauthorized");
// //         vm.prank(caller);
// //         gasbot.execute(address(0), bytes(""), 0, address(0));
// //     }

// //     function test_revertsIf_callNotSuccessful() public {
// //         MockERC20 erc20 = new MockERC20();

// //         bytes memory data = abi.encodeCall(
// //             MockERC20.transfer,
// //             (address(this), 1 ether)
// //         );

// //         vm.expectRevert();
// //         gasbot.execute(address(erc20), data, 0, address(0));
// //     }

// //     function test_successful_transferToRecipient() public {
// //         address recipient = makeAddr("recipient");

// //         deal(address(gasbot), 1 ether);

// //         assertEq(address(gasbot).balance, 1 ether);
// //         assertEq(address(recipient).balance, 0);

// //         gasbot.execute(address(0), bytes(""), 0, recipient);

// //         assertEq(address(gasbot).balance, 0);
// //         assertEq(address(recipient).balance, 1 ether);
// //     }

// //     function test_successful_noRecipient() public {
// //         uint256 dealAmount = 100e6;

// //         deal(USDC, address(gasbot), dealAmount);

// //         bytes memory data = abi.encodeCall(
// //             IERC20.transfer,
// //             (address(this), dealAmount)
// //         );

// //         assertEq(IERC20(USDC).balanceOf(address(gasbot)), dealAmount);
// //         assertEq(IERC20(USDC).balanceOf(address(this)), 0);

// //         gasbot.execute(USDC, data, 0, address(0));

// //         assertEq(IERC20(USDC).balanceOf(address(gasbot)), 0);
// //         assertEq(IERC20(USDC).balanceOf(address(this)), dealAmount);
// //     }

// //     function test_successful_withRecipient() public {
// //         address recipient = makeAddr("recipient");
// //         uint256 dealAmount = 100e6;

// //         deal(address(gasbot), 1 ether);
// //         deal(USDC, address(gasbot), dealAmount);

// //         bytes memory data = abi.encodeCall(
// //             IERC20.transfer,
// //             (address(this), dealAmount)
// //         );

// //         assertEq(address(gasbot).balance, 1 ether);
// //         assertEq(address(recipient).balance, 0);
// //         assertEq(IERC20(USDC).balanceOf(address(gasbot)), dealAmount);
// //         assertEq(IERC20(USDC).balanceOf(address(this)), 0);

// //         gasbot.execute(USDC, data, 0, recipient);

// //         assertEq(address(gasbot).balance, 0);
// //         assertEq(address(recipient).balance, 1 ether);
// //         assertEq(IERC20(USDC).balanceOf(address(gasbot)), 0);
// //         assertEq(IERC20(USDC).balanceOf(address(this)), dealAmount);
// //     }
// // }

// // contract ReplenishRelayers is BaseGasbotV2Test {
// //     function test_revertsIf_notOwner(address caller) public {
// //         vm.assume(caller != address(this));

// //         address[] memory relayers = new address[](1);
// //         relayers[0] = RELAYER;
// //         uint256[] memory amounts = new uint256[](1);
// //         amounts[0] = 1 ether;

// //         vm.expectRevert("Unauthorized");
// //         vm.prank(caller);
// //         gasbot.replenishRelayers(
// //             relayers,
// //             amounts,
// //             1 ether,
// //             1 ether,
// //             DEFAULT_GAS_LIMIT,
// //             block.timestamp
// //         );
// //     }

// //     function test_revertsIf_notRelayer() public {
// //         uint256 dealAmount = 50e6;
// //         uint256 minAmountOut = 0.02 ether;

// //         deal(USDC, address(gasbot), dealAmount);

// //         assertEq(IERC20(USDC).balanceOf(address(gasbot)), dealAmount);

// //         uint256 balanceRelayerBefore = RELAYER.balance;

// //         address[] memory relayers = new address[](1);
// //         relayers[0] = makeAddr("not-relayer");
// //         uint256[] memory amounts = new uint256[](1);
// //         amounts[0] = minAmountOut;

// //         vm.expectRevert("Invalid relayer");
// //         gasbot.replenishRelayers(
// //             relayers,
// //             amounts,
// //             dealAmount,
// //             minAmountOut,
// //             DEFAULT_GAS_LIMIT,
// //             block.timestamp
// //         );
// //     }

// //     function test_successful() public {
// //         uint256 dealAmount = 50e6;
// //         uint256 minAmountOut = 0.02 ether;

// //         deal(USDC, address(gasbot), dealAmount);

// //         assertEq(IERC20(USDC).balanceOf(address(gasbot)), dealAmount);

// //         uint256 balanceRelayerBefore = RELAYER.balance;

// //         address[] memory relayers = new address[](1);
// //         relayers[0] = RELAYER;
// //         uint256[] memory amounts = new uint256[](1);
// //         amounts[0] = minAmountOut;

// //         gasbot.replenishRelayers(
// //             relayers,
// //             amounts,
// //             dealAmount,
// //             minAmountOut,
// //             DEFAULT_GAS_LIMIT,
// //             block.timestamp
// //         );

// //         assertEq(IERC20(USDC).balanceOf(address(gasbot)), 0);
// //         assertGe(RELAYER.balance, balanceRelayerBefore + minAmountOut);
// //     }

// //     function test_successful_multiplerRelayers() public {
// //         uint256 dealAmount = 50e6;
// //         uint256 minAmountOut = 0.02 ether;

// //         deal(USDC, address(gasbot), dealAmount);

// //         assertEq(IERC20(USDC).balanceOf(address(gasbot)), dealAmount);

// //         address newRelayer = makeAddr("new-relayer");
// //         gasbot.setRelayer(newRelayer, true);

// //         uint256 balanceRelayerBefore = RELAYER.balance;
// //         uint256 balanceNewRelayerBefore = newRelayer.balance;

// //         address[] memory relayers = new address[](2);
// //         relayers[0] = RELAYER;
// //         relayers[1] = newRelayer;
// //         uint256[] memory amounts = new uint256[](2);
// //         amounts[0] = (minAmountOut * 1) / 3;
// //         amounts[1] = (minAmountOut * 2) / 3;

// //         gasbot.replenishRelayers(
// //             relayers,
// //             amounts,
// //             dealAmount,
// //             minAmountOut,
// //             DEFAULT_GAS_LIMIT,
// //             block.timestamp
// //         );

// //         assertEq(IERC20(USDC).balanceOf(address(gasbot)), 0);
// //         assertGe(
// //             RELAYER.balance,
// //             balanceRelayerBefore + (minAmountOut * 1) / 3
// //         );
// //         assertGe(
// //             newRelayer.balance,
// //             balanceNewRelayerBefore + (minAmountOut * 2) / 3
// //         );
// //     }
// // }

// // contract Withdraw is BaseGasbotV2Test {
// //     function test_revertsIf_notOwner(address caller) public {
// //         uint256 _balance = IERC20(USDC).balanceOf(address(gasbot));
// //         vm.assume(caller != address(this));
// //         vm.expectRevert("Unauthorized");
// //         vm.prank(caller);
// //         gasbot.withdraw(USDC, _balance);
// //     }

// //     function test_successful() public {
// //         uint256 dealAmount = 100e6;
// //         deal(USDC, address(gasbot), dealAmount);
// //         uint256 _balance = IERC20(USDC).balanceOf(address(gasbot));

// //         assertEq(IERC20(USDC).balanceOf(address(gasbot)), dealAmount);
// //         assertEq(IERC20(USDC).balanceOf(address(this)), 0);

// //         gasbot.withdraw(USDC, _balance);

// //         assertEq(IERC20(USDC).balanceOf(address(gasbot)), 0);
// //         assertEq(IERC20(USDC).balanceOf(address(this)), dealAmount);
// //     }
// // }

// // contract GetTokenBalances is BaseGasbotV2Test {
// //     function setUp() public override {
// //         vm.createSelectFork(vm.rpcUrl("mainnet"), 18835949);
// //         gasbot = new GasbotV2(
// //             address(this),
// //             RELAYER,
// //             UNI_V3_ROUTER,
// //             true,
// //             WETH,
// //             USDC,
// //             100
// //         );
// //     }

// //     function test_successful_onlyNative() public {
// //         address user = makeAddr("user");
// //         address[] memory ownedTokens = new address[](0);

// //         (address[] memory tokens, uint256[] memory balances) = gasbot
// //             .getTokenBalances(user, ownedTokens);

// //         assertEq(tokens.length, balances.length);
// //         assertEq(tokens.length, 1);
// //         assertEq(balances[0], 0);
// //         assertEq(tokens[0], address(0));
// //     }

// //     function test_successful_passedTokens() public {
// //         uint256 usdcAmount = 1_000e6;
// //         address user = makeAddr("user");

// //         address[] memory ownedTokens = new address[](2);
// //         ownedTokens[0] = AAVE;
// //         ownedTokens[1] = USDC;

// //         vm.mockCall(
// //             AAVE,
// //             abi.encodeWithSelector(IERC20.balanceOf.selector),
// //             abi.encode(0)
// //         );

// //         vm.mockCall(
// //             USDC,
// //             abi.encodeWithSelector(IERC20.balanceOf.selector),
// //             abi.encode(usdcAmount)
// //         );

// //         (address[] memory tokens, uint256[] memory balances) = gasbot
// //             .getTokenBalances(user, ownedTokens);

// //         assertEq(tokens.length, balances.length);
// //         assertEq(tokens.length, 3);
// //         assertEq(balances[0], 0);
// //         assertEq(tokens[0], address(0));
// //         assertEq(balances[1], 0);
// //         assertEq(tokens[1], AAVE);
// //         assertEq(balances[2], usdcAmount);
// //         assertEq(tokens[2], USDC);
// //     }
// // }

// // contract GetRelayerBalances is BaseGasbotV2Test {
// //     function setUp() public override {
// //         vm.createSelectFork(vm.rpcUrl("mainnet"), 18835949);
// //         vm.deal(RELAYER, 0);
// //         gasbot = new GasbotV2(
// //             address(this),
// //             RELAYER,
// //             UNI_V3_ROUTER,
// //             true,
// //             WETH,
// //             USDC,
// //             100
// //         );
// //     }

// //     function test_revertsIf_invalidRelayer(address relayer) public {
// //         vm.assume(relayer != RELAYER);

// //         address[] memory relayers = new address[](1);
// //         relayers[0] = relayer;

// //         vm.expectRevert("Invalid relayer");
// //         gasbot.getRelayerBalances(relayers);
// //     }

// //     function test_successful() public {
// //         address[] memory relayers = new address[](1);
// //         relayers[0] = RELAYER;

// //         uint256[] memory balances = gasbot.getRelayerBalances(relayers);

// //         assertEq(balances[0], 0);

// //         RELAYER.call{value: 1 ether}("");

// //         balances = gasbot.getRelayerBalances(relayers);

// //         assertEq(balances[0], 1 ether);
// //     }
// // }
