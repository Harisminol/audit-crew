// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title PriceOracle — mock price feed for the demo vault.
/// @notice BUG (High — oracle manipulation): `setPrice` has NO access
/// control. Any unprivileged caller can move the price the Vault trusts
/// to mint and redeem shares. In production this would be a Chainlink
/// feed, a TWAP, or an owner-gated setter; here it is deliberately
/// left open so the audit crew can demonstrate the full attack chain.
contract PriceOracle {
    uint256 public price = 1 ether; // 1 share == 1 ETH at genesis

    function setPrice(uint256 p) external {
        price = p;
    }
}
