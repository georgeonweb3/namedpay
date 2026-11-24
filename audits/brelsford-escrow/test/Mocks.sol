// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// Minimal 6-decimal USDC stand-in for local testing.
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

/// USDC stand-in that refuses transfers to frozen addresses (like Circle's blacklist).
contract FreezableMockUSDC is ERC20 {
    mapping(address => bool) public frozen;
    constructor() ERC20("USD Coin", "USDC") {}
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
    function setFrozen(address a, bool f) external { frozen[a] = f; }
    function _update(address from, address to, uint256 value) internal override {
        if (frozen[from] || frozen[to]) revert("frozen");
        super._update(from, to, value);
    }
}
