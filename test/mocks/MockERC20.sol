// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20} from "@oz/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("MockERC20", "Mock20") {}
}
