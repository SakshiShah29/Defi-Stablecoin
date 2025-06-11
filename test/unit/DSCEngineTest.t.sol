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
import {MockFailingERC20} from "../mocks/MockFailingERC20.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

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
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 100 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, ) = helperConfig
            .activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, 100 ether);
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

    modifier depositCollateralAndMintDSC() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDSC(
            weth,
            AMOUNT_COLLATERAL,
            AMOUNT_TO_MINT
        );
        vm.stopPrank();
        _;
    }

    function testRevertsIfHeathFactorIsTooLowOnRedeem()
        public
        depositCollateralAndMintDSC
    {
        vm.startPrank(USER);
        uint256 amountToRedeem = 9.99 ether;
        // 10-9.99= 0.01 ether;
        // 0.01*1e18 *2000=20e18
        //20e18*0.5= 10e18
        //10e18/100=0.1  which is less than 1 and it will break the health factor
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__HealthFactorIsBroken.selector,
                0.1 ether,
                1 ether
            )
        );
        // Redeeming collateral with very low health factor to trigger revert
        dscEngine.redeemCollateral(weth, amountToRedeem);
        vm.stopPrank();
    }

    //    function testRedeemCollateralForDsc() public depositCollateralAndMintDSC {
    //     vm.startPrank(USER);
    //     uint256 amountToRedeem = 2 ether; // 2 ETH
    //     dscEngine.redeemCollateralForDSC(weth, amountToRedeem,50 ether);
    //           (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
    //         .getAccountInformation(USER);
    //         assertEq(
    //         totalDscMinted,
    //         50 ether,
    //         "Total DSC minted should be 50 after redeeming collateral for DSC"); //because it would burn 50 ether
    //     assertEq(
    //         amountToRedeem,
    //         dscEngine.getTokenAmountFromUsd(weth, collateralValueInUsd),
    //         "Collateral value in USD is incorrect after redeeming for DSC"
    //     );
    //     vm.stopPrank();
    // }
    ///////////////////////
    ///HEALTH FACOR TESTS/////
    //////////////////////

    function testProperlyReportsHealthFactor()
        public
        depositCollateralAndMintDSC
    {
        uint256 expectedHealthFactor = 100 ether;
        uint256 healthFactor = dscEngine.getHealthFactor(USER);
        assertEq(
            healthFactor,
            expectedHealthFactor,
            "Health factor should be 100"
        );
    }

    function testHealthFactorRevertIfCollateralTooLow() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), 0.01 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__HealthFactorIsBroken.selector,
                0.1 ether,
                1 ether
            )
        );
        // Minting DSC with very low collateral to trigger health factor revert
        dscEngine.depositCollateralAndMintDSC(weth, 0.01 ether, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testHealthFactorRevertsIfDSCMintedExceeds() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__HealthFactorIsBroken.selector,
                0.5 ether,
                1 ether
            )
        );
        dscEngine.depositCollateralAndMintDSC(
            weth,
            AMOUNT_COLLATERAL,
            20000 ether
        );
        vm.stopPrank();
    }

    /////////////////////
    //BURN DSC TESTS/////
    /////////////////////
    function testAmountToBurnShouldBeMoreThanZero()
        public
        depositCollateralAndMintDSC
    {
        vm.startPrank(USER);
        vm.expectRevert(
            DSCEngine.DSCEngine__NeedsMoreThanZeroCollateral.selector
        );
        dscEngine.burnDSC(0);
        vm.stopPrank();
    }

    function testBurnDscCorrectlyReducesDSCBalanceAndTransfersFromTheOwnerToContract()
        public
        depositCollateralAndMintDSC
    {
        vm.startPrank(USER);
        uint256 amountToBurn = 10 ether; // 10 DSC
        ERC20Mock(address(dsc)).approve(address(dscEngine), amountToBurn);
        uint256 userBalanceBeforeBurn = dsc.balanceOf(USER);
        // First Transfer: from USER to DSCEngine
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(USER, address(dscEngine), amountToBurn);

        // Second Transfer: from DSCEngine to 0x0 (burn)
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(dscEngine), address(0), amountToBurn);
        dscEngine.burnDSC(amountToBurn);

        uint256 userBalanceAfterBurn = dsc.balanceOf(USER);

        assertEq(
            userBalanceAfterBurn,
            userBalanceBeforeBurn - amountToBurn,
            "User's DSC balance should be reduced by the burned amount"
        );
        (uint256 totalDscMinted, ) = dscEngine.getAccountInformation(USER);

        assertEq(
            totalDscMinted,
            90 ether,
            "Total DSC minted should be 90 after burning"
        );

        vm.stopPrank();
    }

    //////////////////
    //LIQUIDATE TESTS/////
    //////////////////
    function testRevertIfLiquidateZeroAmount() public {
        vm.startPrank(USER);
        vm.expectRevert(
            DSCEngine.DSCEngine__NeedsMoreThanZeroCollateral.selector
        );
        dscEngine.liquidate(weth, USER, 0);
        vm.stopPrank();
    }

    function testRevertsIfTheHealthFactorIsOkay()
        public
        depositCollateralAndMintDSC
    {
        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__HealthFactorIsOkay.selector,
                100 ether,
                1 ether
            )
        );
        dscEngine.liquidate(weth, USER, 1 ether);
        vm.stopPrank();
    }

    function testShouldAllowLiquidatorToLiquidateTheUserPosition()
        public
        depositCollateralAndMintDSC
    {
        //   Liquidator setup
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dscEngine), 100 ether);
        dscEngine.depositCollateralAndMintDSC(weth, 100 ether, 102 ether);

        // Set the price feed to a low value to trigger liquidation
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(15e8);
        //User health factor and the health factor of liquidator is still up
        uint256 userHealthBefore = dscEngine.getHealthFactor(USER);
        uint256 liquidatorHealthBefore = dscEngine.getHealthFactor(LIQUIDATOR);
        assertGt(
            liquidatorHealthBefore,
            dscEngine.getMinHealthFactor(),
            "User health factor should be above minimum"
        );
        assertLt(
            userHealthBefore,
            dscEngine.getMinHealthFactor(),
            "User health factor should be below minimum"
        );
        dsc.approve(address(dscEngine), AMOUNT_TO_MINT);

        // As the user's health factor is low the liquidator will liquidate the position
        dscEngine.liquidate(weth, USER, AMOUNT_TO_MINT);

        //Users debt should be zero after liquidation
        (uint256 totalDscMinted, ) = dscEngine.getAccountInformation(USER);
        assertEq(
            totalDscMinted,
            0,
            "User's DSC balance should be zero after liquidation"
        );

        //The liquidator recieved user's collateral +10% bonus for liquidation
        uint256 tokenAmountFromDebt = dscEngine.getTokenAmountFromUsd(
            weth,
            AMOUNT_TO_MINT
        );
        uint256 bonus = (tokenAmountFromDebt *
            dscEngine.getLiquidationBonus()) /
            dscEngine.getLiquidationPrecision();
        uint256 expectedCollateralReceived = tokenAmountFromDebt + bonus;
        uint256 liquidatorCollateral = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        assertEq(
            liquidatorCollateral,
            expectedCollateralReceived,
            "Liquidator should get collateral + bonus"
        );

        // Making sure the health factor of the liquidator is still up and did not decrease
        uint256 liquidatorHealthAfter = dscEngine.getHealthFactor(LIQUIDATOR);
        assertGt(
            liquidatorHealthAfter,
            dscEngine.getMinHealthFactor(),
            "Liquidator health factor should be above minimum after liquidation"
        );
        vm.stopPrank();
    }
}
