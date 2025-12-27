// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20} from "@oz/token/ERC20/ERC20.sol";
import {IERC165} from "@oz/utils/introspection/IERC165.sol";

contract MockERC20With165 is ERC20, IERC165 {
    function supportsInterface(bytes4 interfaceId) public pure override(IERC165) returns (bool) {
        return interfaceId == type(ERC20).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    constructor() ERC20("MockERC20With165", "Mock20165") {}
}
