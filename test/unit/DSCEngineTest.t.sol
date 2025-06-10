//SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC public deployer;
    DecentralizedStableCoin public dsc;
    DSCEngine public dscEngine;
    HelperConfig public helperConfig;
    address ethUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, , weth, , ) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
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
}
