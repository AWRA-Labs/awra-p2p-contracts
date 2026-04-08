// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {AwraOnOffRamp} from "../src/AwraOnOffRamp.sol";
import {Test} from "../lib/openzeppelin-contracts/lib/forge-std/src/Test.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
    {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract AwraOnOffRampTest is Test {
    AwraOnOffRamp internal ramp;
    MockERC20 internal token;

    address internal owner = makeAddr("owner");
    address internal user = makeAddr("user");
    address internal onRampUser = makeAddr("onRampUser");

    function setUp() public {
        vm.prank(owner);
        ramp = new AwraOnOffRamp();

        token = new MockERC20("Mock USD", "mUSD");
        token.mint(user, 1_000e18);

        vm.prank(owner);
        ramp.addSupportedToken(address(token));

        vm.prank(user);
        token.approve(address(ramp), type(uint256).max);
    }

    function test_OwnerCanAddAndRemoveSupportedTokens() public {
        MockERC20 otherToken = new MockERC20("Other USD", "oUSD");

        assertFalse(ramp.isSupportedToken(address(otherToken)));

        vm.prank(owner);
        ramp.addSupportedToken(address(otherToken));

        assertTrue(ramp.isSupportedToken(address(otherToken)));

        address[] memory supportedTokens = ramp.getSupportedTokens();
        assertEq(supportedTokens.length, 2);

        vm.prank(owner);
        ramp.removeSupportedToken(address(otherToken));

        assertFalse(ramp.isSupportedToken(address(otherToken)));
    }

    function test_CreateOffRampRevertsForUnsupportedToken() public {
        MockERC20 otherToken = new MockERC20("Other USD", "oUSD");
        otherToken.mint(user, 100e18);

        vm.startPrank(user);
        otherToken.approve(address(ramp), type(uint256).max);
        vm.expectRevert(bytes("Unsupported token"));
        ramp.createOffRamp(address(otherToken), 10e18);
        vm.stopPrank();
    }

    function test_CreateOffRampStoresTransactionAndLocksBalance() public {
        uint256 amount = 100e18;

        vm.prank(user);
        ramp.createOffRamp(address(token), amount);

        (
            address storedUser,
            address storedToken,
            uint256 storedAmount,
            AwraOnOffRamp.TxType txType,
            bool processed
        ) = ramp.transactions(0);

        assertEq(storedUser, user);
        assertEq(storedToken, address(token));
        assertEq(storedAmount, amount);
        assertEq(uint256(txType), uint256(AwraOnOffRamp.TxType.OFFRAMP));
        assertFalse(processed);
        assertEq(ramp.lockedBalances(address(token)), amount);
        assertEq(ramp.txId(), 1);
    }

    function test_ProcessOffRampMarksTransactionProcessedAndUnlocksBalance()
        public
    {
        uint256 amount = 75e18;

        vm.prank(user);
        ramp.createOffRamp(address(token), amount);

        vm.prank(owner);
        ramp.processTransaction(
            0,
            address(0),
            address(0),
            0,
            AwraOnOffRamp.TxType.OFFRAMP
        );

        (, , , , bool processed) = ramp.transactions(0);
        assertTrue(processed);
        assertEq(ramp.lockedBalances(address(token)), 0);
    }

    function test_ProcessOnRampTransfersTokensAndCreatesProcessedTransaction()
        public
    {
        uint256 amount = 50e18;
        token.mint(address(ramp), 200e18);

        vm.prank(owner);
        ramp.processTransaction(
            999,
            onRampUser,
            address(token),
            amount,
            AwraOnOffRamp.TxType.ONRAMP
        );

        (
            address storedUser,
            address storedToken,
            uint256 storedAmount,
            AwraOnOffRamp.TxType txType,
            bool processed
        ) = ramp.transactions(0);

        assertEq(token.balanceOf(onRampUser), amount);
        assertEq(storedUser, onRampUser);
        assertEq(storedToken, address(token));
        assertEq(storedAmount, amount);
        assertEq(uint256(txType), uint256(AwraOnOffRamp.TxType.ONRAMP));
        assertTrue(processed);
        assertEq(ramp.txId(), 1);
    }

    function test_ProcessOnRampCannotSpendLockedOffRampLiquidity() public {
        token.mint(address(ramp), 100e18);

        vm.prank(user);
        ramp.createOffRamp(address(token), 40e18);

        vm.expectRevert(bytes("Insufficient liquidity"));
        vm.prank(owner);
        ramp.processTransaction(
            0,
            onRampUser,
            address(token),
            101e18,
            AwraOnOffRamp.TxType.ONRAMP
        );
    }

    function test_WithdrawTokenCannotUseLockedOffRampBalances() public {
        token.mint(address(ramp), 100e18);

        vm.prank(user);
        ramp.createOffRamp(address(token), 40e18);

        vm.expectRevert(bytes("Insufficient available balance"));
        vm.prank(owner);
        ramp.withdrawToken(address(token), owner, 101e18);

        vm.prank(owner);
        ramp.withdrawToken(address(token), owner, 100e18);

        assertEq(token.balanceOf(owner), 100e18);
        assertEq(token.balanceOf(address(ramp)), 40e18);
    }
}
