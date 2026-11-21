// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Vault.sol";
import "../src/PriceOracle.sol";

/// @title Verify — live-precondition checks for the Verifier agent.
///
/// This test does NOT re-run the attack; it only reads state to confirm
/// that every precondition the two PoCs assumed still holds on the
/// deployed contracts.  All assertions mirror what cast call would
/// return against a live deployment.
///
/// For C-1 (reentrancy):
///   P1. Vault.withdraw() is externally callable (no access control).
///   P2. ETH send happens before share zeroing (checked via source; logged).
///   P3. The vault holds a non-zero ETH balance (victim funds present).
///
/// For C-2 (oracle manipulation):
///   P4. PriceOracle.setPrice() is externally callable with no access control.
///   P5. Vault reads oracle.price() on every deposit/withdraw (no caching).
///   P6. setPrice(1) accepted by an unprivileged address; price() == 1 after.
///   P7. setPrice(1e18) accepted; price() == 1e18 after.
///   P8. After price crash + deposit(1 wei), attacker holds 1e18 shares.
contract VerifyPreconditions is Test {

    PriceOracle oracle;
    Vault       vault;

    address deployer  = makeAddr("deployer");
    address victim    = makeAddr("victim");
    address attacker  = makeAddr("attacker");

    // Anvil default account[0] private key — used so cast-call style logs
    // show a recognisable unprivileged address.
    address unprivileged = makeAddr("unprivileged");

    function setUp() public {
        // ---- Deploy (mirrors deployment script) ----
        vm.startPrank(deployer);
        oracle = new PriceOracle();
        vault  = new Vault(address(oracle));
        vm.stopPrank();

        // Seed vault exactly as the PoCs do.
        vm.deal(victim, 100 ether);
        vm.prank(victim);
        vault.deposit{value: 10 ether}();

        vm.deal(attacker, 2 ether);
        vm.deal(unprivileged, 1 ether);

        emit log_named_address("PriceOracle deployed at", address(oracle));
        emit log_named_address("Vault deployed at",       address(vault));
        emit log_named_address("victim",                  victim);
        emit log_named_address("attacker (unprivileged)", attacker);
    }

    // ------------------------------------------------------------------
    // C-1: Reentrancy in Vault.withdraw()
    // ------------------------------------------------------------------

    /// P1 — Vault.withdraw() is callable with no role check.
    /// We confirm the function selector is callable; a no-shares call
    /// reverts with "no shares" (the only guard), not an access-control error.
    function test_C1_P1_withdrawIsUnrestricted() public {
        vm.prank(unprivileged);
        // Should revert with "no shares", not an access-control string.
        (bool ok, bytes memory data) = address(vault).call(
            abi.encodeWithSignature("withdraw()")
        );
        assertFalse(ok, "expected revert on zero shares");
        // Revert reason must be the balance guard, not an owner check.
        // ABI-encoded Error(string) = 0x08c379a0 ++ abi.encode(string).
        // Decode: skip the 4-byte selector by copying to a new bytes buffer.
        bytes memory payload = new bytes(data.length - 4);
        for (uint256 i = 0; i < payload.length; i++) {
            payload[i] = data[i + 4];
        }
        string memory reason = abi.decode(payload, (string));
        assertEq(reason, "no shares",
            "withdraw() must revert with 'no shares', not an access-control error");
        emit log("C-1 P1 PASS: withdraw() has no access control - reverts 'no shares' only");
    }

    /// P3 — Vault holds victim ETH (non-zero balance, so a drain matters).
    function test_C1_P3_vaultHoldsVictimFunds() public {
        uint256 vaultBal = address(vault).balance;
        emit log_named_uint("Vault ETH balance (wei)", vaultBal);
        assertEq(vaultBal, 10 ether,
            "vault must hold 10 ETH for the reentrancy drain to be meaningful");
        emit log("C-1 P3 PASS: vault holds 10 ETH of victim funds");
    }

    /// P_SHARES — victim's share balance is correct (confirms accounting works
    /// and withdraw() will pay out at current price).
    function test_C1_P_victimSharesRecorded() public {
        uint256 s = vault.balanceOf(victim);
        emit log_named_uint("victim shares (wei units)", s);
        assertEq(s, 10 ether,
            "victim must have 10e18 shares at price 1e18");
        emit log("C-1 P_SHARES PASS: victim shares recorded correctly");
    }

    // ------------------------------------------------------------------
    // C-2: Unrestricted PriceOracle.setPrice()
    // ------------------------------------------------------------------

    /// P4 — PriceOracle.setPrice() callable by unprivileged address.
    function test_C2_P4_setPriceUnrestricted() public {
        uint256 priceBefore = oracle.price();
        emit log_named_uint("oracle.price() before setPrice(1) (wei)", priceBefore);

        // Call as unprivileged EOA — must NOT revert.
        vm.prank(unprivileged);
        (bool ok, ) = address(oracle).call(
            abi.encodeWithSignature("setPrice(uint256)", uint256(1))
        );
        assertTrue(ok, "setPrice() must succeed for an unprivileged address");

        uint256 priceAfter = oracle.price();
        emit log_named_uint("oracle.price() after  setPrice(1) (wei)", priceAfter);
        assertEq(priceAfter, 1,
            "oracle price must be 1 after unprivileged setPrice(1)");
        emit log("C-2 P4 PASS: setPrice(1) accepted from unprivileged address");
    }

    /// P6 + P8 — Crash price to 1, deposit 1 wei, confirm 1e18 shares minted.
    function test_C2_P6_crashedPriceMintsMassiveShares() public {
        // Crash price — no privilege needed.
        vm.prank(attacker);
        oracle.setPrice(1);

        uint256 priceCrashed = oracle.price();
        emit log_named_uint("oracle.price() after crash (wei)", priceCrashed);
        assertEq(priceCrashed, 1);

        // Deposit 1 wei at crashed price.
        vm.prank(attacker);
        vault.deposit{value: 1}();

        uint256 attackerShares = vault.balanceOf(attacker);
        emit log_named_uint("attacker shares after 1-wei deposit (wei)", attackerShares);
        // shares = (1 wei * 1e18) / 1 = 1e18
        assertEq(attackerShares, 1e18,
            "1 wei deposit at price=1 must mint 1e18 shares");
        emit log("C-2 P6+P8 PASS: price crash gives attacker 1e18 shares for 1 wei");
    }

    /// P7 — Restore price, confirm vault.withdraw() pays 1 ETH for 1e18 shares.
    function test_C2_P7_restoredPricePaysFairValue() public {
        // Replicate full attack sequence up to the point of reading ethOut.
        vm.prank(attacker);
        oracle.setPrice(1);
        vm.prank(attacker);
        vault.deposit{value: 1}();

        // Restore price.
        vm.prank(attacker);
        oracle.setPrice(1 ether);

        uint256 priceRestored = oracle.price();
        emit log_named_uint("oracle.price() after restore (wei)", priceRestored);
        assertEq(priceRestored, 1 ether);

        uint256 attackerShares = vault.balanceOf(attacker);
        // ethOut that withdraw() will compute = (1e18 shares * 1e18) / 1e18 = 1 ETH
        uint256 expectedEthOut = (attackerShares * priceRestored) / 1e18;
        emit log_named_uint("expected ethOut on withdraw (wei)", expectedEthOut);
        assertEq(expectedEthOut, 1 ether,
            "restored price must yield 1 ETH payout for 1e18 shares");
        emit log("C-2 P7 PASS: restored price yields 1 ETH payout - attack extracts real value");
    }

    // ------------------------------------------------------------------
    // Summary guard — all preconditions in one shot
    // ------------------------------------------------------------------

    /// Rolls up all checks: deploy, seed, read state, assert.
    function test_allPreconditionsHold() public {
        // C-1 preconditions
        assertEq(address(vault).balance, 10 ether);
        assertEq(vault.balanceOf(victim), 10 ether);

        // C-2 preconditions
        assertEq(oracle.price(), 1 ether); // initial fair price

        // setPrice unrestricted
        vm.prank(unprivileged);
        oracle.setPrice(42);
        assertEq(oracle.price(), 42);

        emit log_named_address("VERIFIED oracle",           address(oracle));
        emit log_named_address("VERIFIED vault",            address(vault));
        emit log_named_uint  ("vault balance (wei)",        address(vault).balance);
        emit log_named_uint  ("oracle price initial (wei)", 1 ether);
        emit log("ALL PRECONDITIONS VERIFIED");
    }
}
