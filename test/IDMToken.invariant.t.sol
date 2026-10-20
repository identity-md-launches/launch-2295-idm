// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IDMToken} from "../src/IDMToken.sol";

/// @dev Keeps an independent balance and allowance model for a closed set of holders.
contract IDMTokenHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    IDMToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        token = new IDMToken();
        actors[0] = address(this);
        actors[1] = makeAddr("holder 1");
        actors[2] = makeAddr("holder 2");
        actors[3] = makeAddr("holder 3");
        expectedBalance[address(this)] = SUPPLY;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(rawAmount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Include revocation, the unlimited sentinel, and large *finite* allowances.
        uint256 mode = rawAmount % 8;
        uint256 amount =
            mode == 0 ? type(uint256).max : mode == 1 ? 0 : mode == 2 ? type(uint256).max - 1 : rawAmount;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        uint256 limit = expectedBalance[owner] < approved ? expectedBalance[owner] : approved;
        uint256 amount = bound(rawAmount, 0, limit);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (approved != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
    }

    function rejectExcessTransfer(uint256 fromSeed, uint256 toSeed) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, balance + 1)
        );
        vm.prank(from);
        token.transfer(to, balance + 1);
    }

    function rejectExcessAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        if (approved == type(uint256).max) {
            // There is no representable amount above an infinite allowance. Revoke it,
            // then exercise a real denied spend instead of silently skipping this call.
            vm.prank(owner);
            assertTrue(token.approve(spender, 0));
            expectedAllowance[owner][spender] = 0;
            approved = 0;
        }
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1
            )
        );
        vm.prank(spender);
        token.transferFrom(owner, to, approved + 1);
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, 1);
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) public {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, bool delegated)
        public
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 limit = expectedBalance[owner];
        if (delegated && expectedAllowance[owner][spender] < limit) {
            limit = expectedAllowance[owner][spender];
        }
        uint256 amount = bound(rawAmount, 0, limit);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        if (delegated) {
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        } else {
            vm.prank(owner);
            token.transfer(address(0), amount);
        }
        // Leave the ghosts unchanged: all balances and allowances must survive the failure.
    }

    function rejectUnfundedDelegatedTransfer(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 rawExcess,
        bool unlimited
    ) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 amount = balance + bound(rawExcess, 1, type(uint256).max - balance);
        uint256 approval = unlimited ? type(uint256).max : amount;

        vm.prank(owner);
        assertTrue(token.approve(spender, approval));
        expectedAllowance[owner][spender] = approval;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
        // In particular, finite allowance deducted before the balance check must roll back.
    }

    /// @dev Always makes a nonzero delegated transfer, so sparse approvals cannot make
    /// the campaign consist entirely of zero-value transferFrom calls.
    function approveAndSpend(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 rawAmount,
        bool unlimited
    ) public {
        uint256 ownerIndex = ownerSeed % actors.length;
        for (uint256 i; i < actors.length && expectedBalance[actors[ownerIndex]] == 0; ++i) {
            ownerIndex = (ownerIndex + 1) % actors.length;
        }
        address owner = actors[ownerIndex];
        assertGt(expectedBalance[owner], 0, "the fixed supply must have a holder");
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(rawAmount, 1, expectedBalance[owner]);
        uint256 approval = unlimited ? type(uint256).max : amount;
        vm.prank(owner);
        assertTrue(token.approve(spender, approval));
        expectedAllowance[owner][spender] = approval;

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (!unlimited) expectedAllowance[owner][spender] = 0;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract IDMTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    IDMTokenHandler internal handler;
    IDMToken internal token;

    function setUp() public {
        handler = new IDMTokenHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.rejectExcessTransfer.selector;
        selectors[4] = handler.rejectExcessAllowance.selector;
        selectors[5] = handler.revoke.selector;
        selectors[6] = handler.rejectZeroSpender.selector;
        selectors[7] = handler.rejectZeroRecipient.selector;
        selectors[8] = handler.rejectUnfundedDelegatedTransfer.selector;
        selectors[9] = handler.approveAndSpend.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_BalancesMatchModelAndSupplyIsConserved() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 actual = token.balanceOf(actor);
            assertEq(actual, handler.expectedBalance(actor));
            sum += actual;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function invariant_AllowancesMatchModel() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.allowance(owner, address(0)), 0, "zero spender acquired authority");
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    function invariant_MetadataRemainsUnchanged() public view {
        assertEq(token.name(), "IDM");
        assertEq(token.symbol(), "IDM");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }

    /// @dev After every random sequence, every holder can return its entire balance.
    /// This checks transfer liveness from the states reached by the fuzzer.
    function afterInvariant() public {
        for (uint256 i = 1; i < 4; ++i) {
            address actor = handler.actors(i);
            handler.transfer(i, 0, handler.expectedBalance(actor));
            assertEq(token.balanceOf(actor), 0, "holder could not exit");
            assertEq(handler.expectedBalance(actor), 0);
        }
        assertEq(token.balanceOf(handler.actors(0)), SUPPLY, "round trip lost tokens");
        invariant_BalancesMatchModelAndSupplyIsConserved();
        invariant_AllowancesMatchModel();
    }
}
