// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title IAutoRevoke
 * @author z (@zisbraindead) for Braindead Digital (@braindeaddgtl)
 * @notice IAutoRevoke is an interface for the AutoRevoke contract.
 */
interface IAutoRevoke {
    enum TokenType {
        ERC20, // 0
        ERC721, // 1
        ERC1155, // 2
        UNKNOWN // 3

    }

    struct TokenId {
        uint256 tokenId; // ID of the token
        bool active; // If this tokenId is valid
    }

    struct Approval {
        address target; // The address of the token contract.
        TokenType tokenType; // The type of the token.
        address spender; // The address of the spender.
        TokenId tokenId; // Used for ERC721 revokes.
    }

    struct Revoke {
        address target; // The address of the token contract.
        address spender; // The address of the spender.
        TokenId tokenId; // Used for ERC721 revokes.
    }

    /**
     * @dev Sets the configuration byte for the smart account
     * @param config the configuration byte to set
     */
    function setConfig(bytes1 config) external;

    /**
     * @dev Toggles the excluded spenders for the smart account
     * @param spender the spender to toggle
     * @param excluded whether to exclude the spender
     */
    function toggleExcludedSpender(address spender, bool excluded) external;

    /**
     * @dev Toggles the excluded spenders for the smart account in batch
     * @param spenders the spenders to toggle
     * @param excluded whether to exclude the spender at the same index
     */
    function toggleExcludedSpenders(address[] calldata spenders, bool[] calldata excluded) external;

    /**
     * @dev Revokes approvals in batch
     * @notice This should only be used from ERC7579 smart accounts, even though anyone can call it
     * @param revokes the info of which approvals to revoke
     */
    function revoke(Revoke[] calldata revokes) external;
}
