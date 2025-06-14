// //SPDX-License-Identifier: MIT
// // Have our invariants aka properties hold

// // What are our invariants?

// // -The total supply of DSC should be lower than the total value of collateral
// // - getter view functions should never revert<<--evergreen invariant

// pragma solidity ^0.8.20;
// import "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {DeployDSC} from "../../script/DeployDSC.s.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// contract OpenInvariantsTest is StdInvariant,Test{
//     DeployDSC public deployer;
//     DecentralizedStableCoin public dsc;
//     DSCEngine public dscEngine;
//     HelperConfig public helperConfig;
//     address public weth;
//     address public wbtc;
//     function setUp() external{
// deployer = new DeployDSC();
//         (dsc, dscEngine, helperConfig) = deployer.run();
//         ( , ,weth,wbtc,)=helperConfig.activeNetworkConfig();
//         targetContract(address(dscEngine));
//     }

//     function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
//   //get the value of collateral in the protocol and compare it to the debt (dsc)
// uint256 totalSupply= dsc.totalSupply();
// uint256 totalWethDeposited= IERC20(weth).balanceOf(address(dscEngine));
// uint256 totalWbtcDeposited= IERC20(wbtc).balanceOf(address(dscEngine));
// uint256 wethValue= dscEngine.getUsdValue(weth,totalWethDeposited);
// uint256 wbtcValue= dscEngine.getUsdValue(wbtc,totalWbtcDeposited);
// uint256 totalCollateralValue= wethValue + wbtcValue;

//         assert(totalCollateralValue >= totalSupply);
//     }

// }
