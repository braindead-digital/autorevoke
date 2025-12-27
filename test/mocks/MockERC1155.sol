// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC1155} from "@oz/token/ERC1155/ERC1155.sol";

contract MockERC1155 is ERC1155 {
    constructor() ERC1155("MockERC1155") {}

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts) public {
        _mintBatch(to, ids, amounts, "");
    }
}
