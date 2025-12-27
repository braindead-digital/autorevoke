// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC721} from "@oz/token/ERC721/ERC721.sol";

contract MockERC721 is ERC721 {
    constructor() ERC721("MockERC721", "Mock721") {}

    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }
}
