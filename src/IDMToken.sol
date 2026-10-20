// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title IDM
/// @notice Fixed supply of one billion IDM, with 18 decimals.
/// @dev The deploying account receives the entire supply. No post-deployment minting or admin role.
/// @custom:website https://x.com/theidmfun
contract IDMToken is ERC20 {
    /// @notice Total issuance, denominated in the smallest token unit.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev On the custom-token launch, msg.sender is the launch factory.
    constructor() ERC20("IDM", "IDM") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
