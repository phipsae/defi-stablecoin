// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {DeployDsc} from "script/DeployDsc.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20MockOwn} from "test/mocks/ERC20MockOwn.sol";

contract DSCEngineTest is Test {
    DeployDsc deployer;
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig helperConfig;
    address ethUsdPriceFeed;
    address weth;
    address wbtcUsdPriceFeed;
    address wbtc;

    address public USER = makeAddr("USER");
    uint256 public AMOUNT_COLLATERAL = 100 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;
    uint256 public constant DSC_MINTED = 100 ether;
    uint256 public constant DSC_BURNED = 50 ether;
    uint256 public constant AMOUNT_COLLATERAL_REDEEMED = 10 ether;

    function setUp() public {
        deployer = new DeployDsc();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, wbtcUsdPriceFeed, weth,) = helperConfig.activeNetworkConfig();
        ERC20MockOwn(weth).mint(USER, STARTING_ERC20_BALANCE);
        vm.prank(dscEngine.owner());
        dscEngine.setDscContractAddress(address(dsc));
    }

    /////////////////////////
    /// Constructor Tests ///
    /////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeedLength() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeEqualLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses);
    }

    ////////////////////////
    /// Price Feed Tests ///
    ////////////////////////
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedEthUsdValue = 30000e18;
        uint256 actualUsdValue = dscEngine.getUsdValue(weth, ethAmount);
        assertEq(actualUsdValue, expectedEthUsdValue);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWEthAmount = 0.05 ether;
        uint256 actualWEthAmount = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualWEthAmount, expectedWEthAmount);
    }

    ////////////////////////////////
    /// Deposit Collateral Tests ///
    ////////////////////////////////
    function testRevertsIfCollateralZero() public {
        vm.prank(USER);
        ERC20MockOwn(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20MockOwn ranToken = new ERC20MockOwn("RanToken", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20MockOwn(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueinUSD) = dscEngine.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmountValueinUSD = dscEngine.getTokenAmountFromUsd(weth, collateralValueinUSD);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmountValueinUSD);
    }

    function testDepositCollateralAndMintDsc() public {
        uint256 expectedAmountCollateral = 1 ether;
        uint256 expectedDscToMint = 999 ether;

        vm.startPrank(USER);
        ERC20MockOwn(weth).approve(address(dscEngine), expectedAmountCollateral);
        // dsc.approve(address(dscEngine), expectedDscToMint);
        dscEngine.depositCollateralAndMintDsc(weth, expectedAmountCollateral, expectedDscToMint);
        vm.stopPrank();

        // (uint256 totalDiscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        // assertEq(totalDiscMinted, expectedDscToMint);
        // assertEq(collateralValueInUsd, expectedAmountCollateral);
    }

    ////////////////////////////////
    /// Redeem Collateral Tests ///
    ////////////////////////////////

    function testRedeemCollateral() public depositedCollateral {
        (, uint256 beforeDepositedCollateralInUsd) = dscEngine.getAccountInformation(USER);
        uint256 beforeDepositedCollateral = dscEngine.getTokenAmountFromUsd(weth, beforeDepositedCollateralInUsd);

        vm.prank(USER);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL_REDEEMED);

        (, uint256 afterDepositedCollateralInUsd) = dscEngine.getAccountInformation(USER);
        uint256 afterDepositedCollateral = dscEngine.getTokenAmountFromUsd(weth, afterDepositedCollateralInUsd);
        assertEq(beforeDepositedCollateral - AMOUNT_COLLATERAL_REDEEMED, afterDepositedCollateral);
    }

    // redeemCollateralForDsc

    ///////////////////////
    /// Mint DSC Tests ///
    //////////////////////

    modifier mintedDsc() {
        vm.startPrank(USER);
        dscEngine.mintDsc(DSC_MINTED);
        console.log("DSC_MINTED: ", dsc.balanceOf(address(dscEngine)));
        vm.stopPrank();
        _;
    }

    function testMintDsc() public depositedCollateral mintedDsc {
        (uint256 afterTotalDscMinted,) = dscEngine.getAccountInformation(USER);
        assertEq(afterTotalDscMinted, DSC_MINTED);
    }

    ///////////////////////
    /// Burn DSC Tests ///
    //////////////////////

    function testBurnDsc() public depositedCollateral mintedDsc {
        (uint256 beforeTotalDscMinted, uint256 depositedCollateralInUSD) = dscEngine.getAccountInformation(USER);
        uint256 expectedDscToBurn = 50 ether;

        console.log("beforeTotalDscMinted: ", beforeTotalDscMinted);
        console.log("Address User: ", address(USER));
        console.log("Address DSC: ", address(dsc));
        console.log("Address DSC Engine: ", address(dscEngine));
        console.log("depositedCollateralInUSD: ", depositedCollateralInUSD);
        console.log("BalanceOf", dsc.balanceOf(address(USER)));

        vm.startPrank(USER);
        ERC20MockOwn(address(dsc)).approve(address(dscEngine), expectedDscToBurn);
        dscEngine.burnDsc(expectedDscToBurn);
        vm.stopPrank();

        (uint256 afterTotalDscMinted,) = dscEngine.getAccountInformation(USER);
        assertEq(afterTotalDscMinted, beforeTotalDscMinted - expectedDscToBurn);
    }

    function testLiquidate() public {}
}
