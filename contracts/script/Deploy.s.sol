// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PriceOracle.sol";
import "../src/Vault.sol";

/// @notice Deploys PriceOracle then Vault, seeds the vault with 10 ETH
///         from account[1] (victim), then prints all addresses.
contract Deploy is Script {
    function run() external {
        // accounts[0] = deployer, accounts[1] = victim
        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        uint256 victimKey   = vm.envUint("VICTIM_KEY");

        vm.startBroadcast(deployerKey);
        PriceOracle oracle = new PriceOracle();
        Vault vault = new Vault(address(oracle));
        vm.stopBroadcast();

        // Seed vault with 10 ETH as victim
        vm.startBroadcast(victimKey);
        vault.deposit{value: 10 ether}();
        vm.stopBroadcast();

        console2.log("ORACLE_ADDR:", address(oracle));
        console2.log("VAULT_ADDR:", address(vault));
    }
}
