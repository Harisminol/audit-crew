// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPriceOracle {
    function price() external view returns (uint256);
}

/// @title Vault — demo yield vault with two seeded High-severity bugs.
/// @notice Built as the audit target for AuditCrew (Kiroween 2026).
/// The bugs are intentional and documented here so judges can verify
/// the crew actually finds them:
///   BUG 1 (High — reentrancy): `withdraw` sends ETH BEFORE zeroing the
///         caller's shares (checks-effects-interactions violated).
///         A malicious receiver re-enters `withdraw` and drains the vault.
///   BUG 2 (High — oracle manipulation): share minting/redeeming trusts
///         `PriceOracle.price()`, which anyone can set via `setPrice`.
///         An attacker drops the price, mints shares nearly for free,
///         restores the price, and redeems for the whole vault balance.
/// Nothing here is production code. Do not deploy with real funds.
contract Vault {
    IPriceOracle public immutable oracle;
    mapping(address => uint256) public shares;
    uint256 public totalShares;

    constructor(address _oracle) {
        oracle = IPriceOracle(_oracle);
    }

    /// @notice Deposit ETH, receive shares priced by the oracle.
    function deposit() external payable {
        require(msg.value > 0, "zero deposit");
        uint256 p = oracle.price();
        uint256 s = (msg.value * 1e18) / p;
        require(s > 0, "zero shares");
        shares[msg.sender] += s;
        totalShares += s;
    }

    /// @notice Redeem ALL of the caller's shares for ETH at the
    /// current oracle price.
    function withdraw() external {
        uint256 s = shares[msg.sender];
        require(s > 0, "no shares");
        uint256 p = oracle.price();
        uint256 ethOut = (s * p) / 1e18;
        // BUG 1: external call before state update.
        (bool ok, ) = msg.sender.call{value: ethOut}("");
        require(ok, "ETH send failed");
        shares[msg.sender] = 0;
        totalShares -= s;
    }

    function balanceOf(address account) external view returns (uint256) {
        return shares[account];
    }
}
