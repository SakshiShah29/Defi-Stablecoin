//SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract DSCEngineTest is Test {
    DeployDSC public deployer;
    DecentralizedStableCoin public dsc;
    DSCEngine public dscEngine;
    HelperConfig public helperConfig;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, ) = helperConfig
            .activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    ///////////////////////
    /////CONSTRUCTOR TESTS/////
    //////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIfTokenLengthDoesNotMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(
            DSCEngine.DSCEngine__TokenAndPriceFeedLengthMismatch.selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ///////////////////////
    /////PRICE TESTS/////
    //////////////////////

    function testGetUsdValue() public view {
        uint256 amount = 15e18; // 15 ETH
        uint256 price = 2000e8; // 2000 USD
        uint256 expectedUsdValue = (amount * price) / 1e8; // Adjust for price feed decimals
        uint256 actualUsdValue = dscEngine.getUsdValue(weth, amount);
        assertEq(
            actualUsdValue,
            expectedUsdValue,
            "USD value calculation is incorrect"
        );
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWethAmount = (usdAmount * 1e8) / 2000e8; // Adjust for price feed decimals
        uint256 actualWethAmount = dscEngine.getTokenAmountFromUsd(
            weth,
            usdAmount
        );
        assertEq(
            actualWethAmount,
            expectedWethAmount,
            "Token amount from USD calculation is incorrect"
        );
    }

    ///////////////////////
    //DEPOSIT TESTS/////
    //////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(
            DSCEngine.DSCEngine__NeedsMoreThanZeroCollateral.selector
        );
        dscEngine.depositCollatoral(weth, 0);

        vm.stopPrank();
    }

    function testRevertsIfUnapprovedCollateral() public {
        ERC20Mock randToken = new ERC20Mock();
        vm.startPrank(USER);
        vm.expectRevert(
            DSCEngine.DSCEngine__CollateralTokenNotAllowed.selector
        );
        dscEngine.depositCollatoral(address(randToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollatoral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testDepositCollateralAndGetAccountInfo() public depositCollateral {
        (uint256 totalDscMinted, uint256 collateraValueInUsd) = dscEngine
            .getAccountInformation(USER);
        assertEq(totalDscMinted, 0, "Total DSC minted should be zero");
        assertEq(
            AMOUNT_COLLATERAL,
            dscEngine.getTokenAmountFromUsd(weth, collateraValueInUsd),
            "Collateral value in USD is incorrect"
        );
    }

    function testDepositCollateralEmitsEvents() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, true);
        emit DSCEngine.CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        dscEngine.depositCollatoral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testTokenTransferedAfterDepositCollateralToContract()
        public
        depositCollateral
    {
        uint256 contractBalance = ERC20Mock(weth).balanceOf(address(dscEngine));
        assertEq(
            contractBalance,
            AMOUNT_COLLATERAL,
            "Contract should hold the deposited collateral"
        );
        uint256 userBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(
            userBalance,
            STARTING_ERC20_BALANCE - AMOUNT_COLLATERAL,
            "User's balance should be reduced by the deposited amount"
        );
    }

    function testIfTokenTransferIsNotSuccessItReverts() public {
        bytes memory transferFromSelector = abi.encodeWithSelector(
            IERC20.transferFrom.selector,
            USER,
            address(dscEngine),
            AMOUNT_COLLATERAL
        );
        vm.mockCall(weth, transferFromSelector, abi.encode(false));

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        dscEngine.depositCollatoral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ///////////////////////
    //MINT TESTS/////
    //////////////////////

    function testShouldRevertIfAmountZero() public depositCollateral {
        vm.startPrank(USER);
        vm.expectRevert(
            DSCEngine.DSCEngine__NeedsMoreThanZeroCollateral.selector
        );
        dscEngine.mintDsc(0);
        vm.stopPrank();
    }

    function testUpdatesAccountInfoBeforeMint() public depositCollateral {
        vm.startPrank(USER);
        uint256 amountToMint = 10e18; // 10 DSC
        dscEngine.mintDsc(amountToMint);
        (uint256 totalDscMinted, ) = dscEngine.getAccountInformation(USER);
        assertEq(
            totalDscMinted,
            amountToMint,
            "Total DSC minted should match the minted amount"
        );
        vm.stopPrank();
    }

    //   function testRevertIfHealthFactorIsTooLow() public depositCollateral {
    //     vm.startPrank(USER);
    //     uint256 amountToMint = 11 ether; // 1000 DSC
    //     vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
    //     dscEngine.mintDsc(amountToMint);
    //     vm.stopPrank();
    //   } //FIX THIS

    function testMintDSCAndEmitEvent() public depositCollateral {
        vm.startPrank(USER);
        uint256 amountToMint = 10e18; // 10 DSC
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(0), USER, amountToMint);
        dscEngine.mintDsc(amountToMint);
        vm.stopPrank();
    }

    ///////////////////////
    ///REDEEM TESTS/////
    //////////////////////

    function testRevertIfAmountZeroOnRedeem() public depositCollateral {
        vm.startPrank(USER);
        vm.expectRevert(
            DSCEngine.DSCEngine__NeedsMoreThanZeroCollateral.selector
        );
        dscEngine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testUpdatesAccountAndEmitsEventAfterRedeem()
        public
        depositCollateral
    {
        vm.startPrank(USER);
        uint256 amountToMint = 10e18; // 10 DSC
        dscEngine.mintDsc(amountToMint);
        uint256 amountToRedeem = 5 ether; // 5 ETH
        vm.expectEmit(true, true, true, true);
        emit DSCEngine.CollateralRedeemed(USER, USER, weth, amountToRedeem);
        dscEngine.redeemCollateral(weth, amountToRedeem);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
            .getAccountInformation(USER);
        assertEq(
            totalDscMinted,
            10e18,
            "Total DSC minted should be zero after redeeming collateral"
        );
        assertEq(
            amountToRedeem,
            dscEngine.getTokenAmountFromUsd(weth, collateralValueInUsd),
            "Collateral value in USD is incorrect after redeeming"
        );
        vm.stopPrank();
    }

    function testRedeemTransfersCollateralToUser() public depositCollateral {
        vm.startPrank(USER);
        uint256 amountToMint = 10e18; // 10 DSC
        dscEngine.mintDsc(amountToMint);
        uint256 amountToRedeem = 5 ether; // 5 ETH
        dscEngine.redeemCollateral(weth, amountToRedeem);
        uint256 userBalanceAfterRedeem = ERC20Mock(weth).balanceOf(USER);
        assertEq(
            userBalanceAfterRedeem,
            STARTING_ERC20_BALANCE - AMOUNT_COLLATERAL + amountToRedeem,
            "User's balance should be updated after redeeming collateral"
        );
        vm.stopPrank();
    }
    //    function testRevertsIfHeathFactorIsTooLowOnRedeem() public depositCollateral {
    //         vm.startPrank(USER);
    //         uint256 amountToMint = 11 ether; // 11 DSC
    //         dscEngine.mintDsc(amountToMint);
    //         uint256 amountToRedeem = 9 ether; // 5 ETH
    //           console.log("Health Factor:", dscEngine.getHealthFactor(USER));
    //         vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
    //         dscEngine.redeemCollateral(weth, amountToRedeem);

    //         vm.stopPrank();
    //     }

    ///////////////////////
    ///LIQUIDATE TESTS/////
    //////////////////////
}
