//SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/*
 * @title DSCEngine
 * @author Patrick Collins
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral <= the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */

contract DSCEngine is ReentrancyGuard {
    //ERRORS

    //STATE VARIABLES
    uint256 private constant ADDITIONAL_FEED_PRICISION = 1e10; //10^10
    uint256 private constant PRECISION = 1e18; //10^18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% overcollateralised
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; //10% bonus for liquidators
    mapping(address token => address priceFeed) private s_priceFeeds; //tokentoPriceFeed
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited; //user=>token=>amount
    mapping(address user => uint256 amountDscMinted) private s_dscMinted; //user=>amountDscMinted

    address[] private s_collateralTokens;
    //IMMUTABLE VARIABLE
    DecentralizedStableCoin immutable i_dsc;

    error DSCEngine__NeedsMoreThanZeroCollateral();
    error DSCEngine__TokenAndPriceFeedLengthMismatch();
    error DSCEngine__CollateralTokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsBroken(
        uint256 healthFactor,
        uint256 minHealthFactor
    );
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorIsOkay(
        uint256 healthFactor,
        uint256 minHealthFactor
    );
    error DSCEngine__HealthFactorNotImproved();

    //EVENTS
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
    );
    //MODIFIERS

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__NeedsMoreThanZeroCollateral();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__CollateralTokenNotAllowed();
        }
        _;
    }

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddress,
        address dscAddress
    ) {
        if (tokenAddresses.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAndPriceFeedLengthMismatch();
        }
        // ETH/USD, BTC/USD
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /*
     * @notice This function deposits collateral and mints DSC to the caller's address
     * @param tokenCollateralAddress The address of the collateral token
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDscToMint The amount of DSC to mint (stableCoin)
     * @notice They must have more collatoral than minimum threshold
     * @dev The amount of DSC to mint must be greater than zero
     */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollatoral((tokenCollateralAddress), amountCollateral);
        mintDsc(amountDscToMint);
    }

    /*
     * @param tokenCollateralAddress The address of the collateral token
     * @param amountCollateral The amount of collateral to deposit
     *
     */
    function depositCollatoral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        //check if the token is supported
        //transfer the token from the user to this contract
        //update the collateral balance of the user
        //emit an event
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /*
     * @param tokenCollateralAddress The address of the collateral token
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDscToBurn The amount of DSC to burn
     *
     * @notice This function redeems collateral and burns DSC from the caller's address
     * @dev The amount of DSC to burn must be greater than zero
     */
    function redeemCollateralForDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external {
        burnDSC(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    //in order to collateral
    //1. their health factor must be above 1 AFTER collateral pulled

    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @notice This function mints DSC to the caller's address
     * @param amountDscToMint The amount of DSC to mint (stableCoin)
     * @notice They must have more collatoral than minimum threshold
     * @dev The amount of DSC to mint must be greater than zero
     */

    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDscToMint;
        //if they minted too much ($150 DSC,$100 ETH)
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDSC(uint256 amount) public moreThanZero(amount) {
        _burnDSC(msg.sender, amount, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); //not that required..... I dont think its required.
    }

    //If someone is almost undercollateralized, then we will pay you to liquidate them!
    // $75 backing $50 DSC
    // Liquidator takes $75 baciking and burn off the $50 DSC
    /*
     * @notice This function liquidates a user by taking their collateral and burning their DSC
     * @param collateral The address of the collateral token
     * @param user The address of the user to liquidate. Whose health facor is below 1
     * @param debtToCover The amount of DSC to burn
     * @dev The amount of DSC to burn must be greater than zero
     * @notice you cna partially liquidate t a user
     * @notice a known bug would be if the protocol is 10% or below collateralized i, then we would be able to liquidate them
     * for example the price of the collateral plummted before anyone could be liquidated.
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        //check health factor of user
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsOkay(
                startingUserHealthFactor,
                MIN_HEALTH_FACTOR
            );
        }
        //we want to burn their dsc debit
        // and take their collateral
        // Bad user $140 ETH , $100 DSC -> (140*50)/10000=0.7<1
        // debtToCover = 100
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            collateral,
            debtToCover
        );
        // And give them a 10% bonus
        // so we are giving the liquidator $110 of Weth for 100DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweeep the extra amounts into a treasury
        uint256 bonusAmount = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) /
            LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusAmount;
        _redeemCollateral(
            collateral,
            totalCollateralToRedeem,
            user,
            msg.sender
        );
        //burn the dsc
        _burnDSC(user, debtToCover, msg.sender);
        uint endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    //INTERNAL FUNCTIONS
    function _burnDSC(
        address onBehalfOf,
        uint256 amountDSCToBurn,
        address dscFrom
    ) private {
        s_dscMinted[onBehalfOf] -= amountDSCToBurn;
        bool success = i_dsc.transferFrom(
            dscFrom,
            address(this),
            amountDSCToBurn
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDSCToBurn);
    }

    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountOfCollateralToRedeem,
        address from,
        address to
    ) private {
        s_collateralDeposited[from][
            tokenCollateralAddress
        ] -= amountOfCollateralToRedeem;
        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountOfCollateralToRedeem
        );
        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountOfCollateralToRedeem
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_dscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /*
    * @notice This function returns how close to liquidation a user is
    If a user goes below 1 then they will be liquidated
    */
    function _healthFactor(address user) private view returns (uint256) {
        //total dsc minted
        //total collateral VALUE
        (
            uint256 totalDscMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION; //50% of collateral value
        return ((collateralAdustedForThreshold * PRECISION) / totalDscMinted);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        //check health factor(do they have enough collatoral?)
        //revert if they dont have

        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBroken(
                healthFactor,
                MIN_HEALTH_FACTOR
            );
        }
    }

    //PUBLIC FUNCTIONS
    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        //loop through each collateral token, get the amount they have deposited, and map it to the price, to get the USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        //1 ETH = $1000
        // The returned value from the chainlink would be 1000e8
        return
            ((uint256(price) * ADDITIONAL_FEED_PRICISION) * amount) / PRECISION; //amount would be in wei 1e18 and the price in 1e8 so make it unified for multiplication
    }

    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return
            (usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRICISION); //amount would be in wei 1e18 and the price in 1e8 so make it unified for multiplication
    }

    function getAccountInformation(
        address user
    )
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        uint256 healthFactor = _healthFactor(user);
        return healthFactor;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }
}
