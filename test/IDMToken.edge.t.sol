// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IDMToken} from "../src/IDMToken.sol";

/// @dev Complements the original suite with allowance boundaries, failure atomicity, and round trips.
/// forge-config: default.fuzz.runs = 1024
contract IDMTokenEdgeTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    IDMToken internal token;
    address internal deployer;
    address internal holder;
    address internal recipient;
    address internal spender;
    address internal otherSpender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        deployer = makeAddr("edge deployer");
        holder = makeAddr("edge holder");
        recipient = makeAddr("edge recipient");
        spender = makeAddr("edge spender");
        otherSpender = makeAddr("edge other spender");
        vm.prank(deployer);
        token = new IDMToken();
    }

    function test_OneBaseUnitRoundTripIsExact() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, holder, 1);
        vm.prank(deployer);
        assertTrue(token.transfer(holder, 1));
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(holder, deployer, 1);
        vm.prank(holder);
        assertTrue(token.transfer(deployer, 1));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferFailsWithoutArithmeticPanic() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max
            )
        );
        vm.prank(deployer);
        token.transfer(recipient, type(uint256).max);

        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumDelegatedTransferStillRequiresBalance() public {
        vm.prank(deployer);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(deployer, recipient, type(uint256).max);

        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumMinusOneAllowanceIsFinite() public {
        vm.prank(deployer);
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, recipient, 1));
        assertEq(token.allowance(deployer, spender), type(uint256).max - 2);

        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, recipient, SUPPLY - 1));
        assertEq(token.allowance(deployer, spender), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_UnlimitedAllowanceSurvivesEmptyBalanceAndRefillThenCanBeRevoked() public {
        vm.prank(deployer);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, holder, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.allowance(deployer, spender), type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(deployer, recipient, 1);
        assertEq(token.allowance(deployer, spender), type(uint256).max);

        vm.prank(holder);
        assertTrue(token.transfer(deployer, SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, recipient, 1));
        assertEq(token.allowance(deployer, spender), type(uint256).max);

        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(deployer, spender, 0);
        vm.prank(deployer);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(deployer, recipient, 1);
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferCannotBypassBalanceCheck() public {
        vm.prank(deployer);
        assertTrue(token.transfer(holder, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 1, 2));
        vm.prank(holder);
        token.transfer(holder, 2);

        vm.prank(holder);
        assertTrue(token.approve(spender, 2));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 1, 2));
        vm.prank(spender);
        token.transferFrom(holder, holder, 2);
        assertEq(token.allowance(holder, spender), 2);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_OwnerUsingTransferFromNeedsItsOwnAllowance() public {
        vm.prank(deployer);
        assertTrue(token.approve(spender, SUPPLY));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1)
        );
        vm.prank(deployer);
        token.transferFrom(deployer, holder, 1);

        vm.prank(deployer);
        assertTrue(token.approve(deployer, 1));
        vm.prank(deployer);
        assertTrue(token.transferFrom(deployer, holder, 1));
        assertEq(token.allowance(deployer, deployer), 0);
        assertEq(token.allowance(deployer, spender), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.balanceOf(holder), 1);
    }

    function test_ZeroDelegatedTransferEmitsEventAndPreservesExistingAllowance() public {
        uint256[3] memory approvals = [uint256(0), 1, type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            vm.prank(holder);
            assertTrue(token.approve(spender, approvals[i]));
            vm.expectEmit(true, true, false, true, address(token));
            emit Transfer(holder, recipient, 0);
            vm.prank(spender);
            assertTrue(token.transferFrom(holder, recipient, 0));
            assertEq(token.allowance(holder, spender), approvals[i]);
            assertEq(token.balanceOf(holder), 0);
            assertEq(token.balanceOf(recipient), 0);
        }
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroApprovalToZeroSpenderIsRejected() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 0);
        assertEq(token.allowance(deployer, address(0)), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_ZeroDelegatedTransferToZeroRecipientIsRejected() public {
        vm.prank(holder);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), 0);
        assertEq(token.allowance(holder, spender), type(uint256).max);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_FailedDelegatedSpendPreservesAllowanceAndCanBeRetried(
        uint256 rawBalance,
        uint256 rawMissing,
        uint256 rawApproval,
        bool unlimited
    ) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY - 1);
        uint256 missing = bound(rawMissing, 1, SUPPLY - balance);
        uint256 amount = balance + missing;
        uint256 approval = unlimited ? type(uint256).max : bound(rawApproval, amount, type(uint256).max - 1);

        vm.prank(deployer);
        assertTrue(token.transfer(holder, balance));
        vm.prank(holder);
        assertTrue(token.approve(spender, approval));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, amount)
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, amount);
        assertEq(token.allowance(holder, spender), approval, "failed spend consumed approval");
        assertEq(token.balanceOf(holder), balance, "failed spend changed holder balance");
        assertEq(token.balanceOf(recipient), 0, "failed spend credited recipient");
        assertEq(token.balanceOf(deployer), SUPPLY - balance);

        // An approval is authority over future funds too. The identical spend must now succeed.
        vm.prank(deployer);
        assertTrue(token.transfer(holder, missing));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, amount));
        assertEq(token.allowance(holder, spender), unlimited ? approval : approval - amount);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ZeroRecipientFailurePreservesAnyApproval(uint256 approval, uint256 rawAmount) public {
        uint256 limit = approval < SUPPLY ? approval : SUPPLY;
        uint256 amount = bound(rawAmount, 0, limit);
        vm.prank(deployer);
        assertTrue(token.approve(spender, approval));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(deployer, address(0), amount);
        assertEq(token.allowance(deployer, spender), approval);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);

        // A rejected destination must not consume the permission needed for a valid destination.
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, recipient, amount));
        assertEq(
            token.allowance(deployer, spender), approval == type(uint256).max ? approval : approval - amount
        );
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.balanceOf(recipient), amount);
    }

    function testFuzz_ApprovalsAreIsolatedByOwnerAndSpender(
        uint256 rawAmount,
        uint256 allowanceForOtherSpender,
        uint256 allowanceForOtherOwner
    ) public {
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.approve(spender, amount));
        vm.prank(deployer);
        assertTrue(token.approve(otherSpender, allowanceForOtherSpender));
        vm.prank(holder);
        assertTrue(token.approve(spender, allowanceForOtherOwner));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, recipient, amount));

        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.allowance(deployer, otherSpender), allowanceForOtherSpender);
        assertEq(token.allowance(holder, spender), allowanceForOtherOwner);
        assertEq(token.allowance(spender, deployer), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(holder), 0);

        vm.prank(deployer);
        assertTrue(token.approve(otherSpender, 0));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, otherSpender, 0, 1)
        );
        vm.prank(otherSpender);
        token.transferFrom(deployer, recipient, 1);
        assertEq(token.allowance(holder, spender), allowanceForOtherOwner);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ReplacingUnlimitedAllowanceEnforcesTheNewFiniteLimit(
        uint256 rawReplacement,
        uint256 rawExcess
    ) public {
        uint256 replacement = bound(rawReplacement, 0, SUPPLY - 1);
        uint256 tooMuch = replacement + bound(rawExcess, 1, SUPPLY - replacement);
        vm.prank(deployer);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(deployer, spender, replacement);
        vm.prank(deployer);
        assertTrue(token.approve(spender, replacement));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, replacement, tooMuch
            )
        );
        vm.prank(spender);
        token.transferFrom(deployer, recipient, tooMuch);
        assertEq(token.allowance(deployer, spender), replacement);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, recipient, replacement));
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - replacement);
        assertEq(token.balanceOf(recipient), replacement);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitDelegatedTransfersEqualOneTransfer(
        uint256 rawAmount,
        uint256 rawFirst,
        bool unlimited
    ) public {
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        uint256 first = bound(rawFirst, 0, amount);
        uint256 approval = unlimited ? type(uint256).max : amount;
        vm.prank(deployer);
        IDMToken singleTransferToken = new IDMToken();

        vm.prank(deployer);
        assertTrue(token.approve(spender, approval));
        vm.prank(deployer);
        assertTrue(singleTransferToken.approve(spender, approval));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, holder, first));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, holder, amount - first));
        vm.prank(spender);
        assertTrue(singleTransferToken.transferFrom(deployer, holder, amount));

        assertEq(token.balanceOf(deployer), singleTransferToken.balanceOf(deployer));
        assertEq(token.balanceOf(holder), singleTransferToken.balanceOf(holder));
        assertEq(token.allowance(deployer, spender), singleTransferToken.allowance(deployer, spender));
        assertEq(token.balanceOf(holder), amount);
        assertEq(token.allowance(deployer, spender), unlimited ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY);

        // A fee-free round trip must recover every base unit, irrespective of how it was split.
        vm.prank(holder);
        assertTrue(token.transfer(deployer, amount));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }
}
