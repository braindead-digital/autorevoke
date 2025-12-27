// SPDX-License-Identifier: CC0
pragma solidity ^0.8.13;

/**
 * @title IERC7579Module
 * @author zeroknots (@zeroknots), Konrad Kopp (@kopy-kat), Taek Lee (@leekt), Fil Makarov (@filmakarov), Elim Poon (@yaonam), Lyu Min (@rockmin216)
 * @notice Please see https://eips.ethereum.org/EIPS/eip-7579 for more details.
 */
interface IERC7579Module {
    /**
     * @dev This function is called by the smart account during installation of the module
     * @param data arbitrary data that may be required on the module during `onInstall` initialization
     *
     * MUST revert on error (e.g. if module is already enabled)
     */
    function onInstall(bytes calldata data) external;

    /**
     * @dev This function is called by the smart account during uninstallation of the module
     * @param data arbitrary data that may be required on the module during `onUninstall` de-initialization
     *
     * MUST revert on error
     */
    function onUninstall(bytes calldata data) external;

    /**
     * @dev Returns boolean value if module is a certain type
     * @param moduleTypeId the module type ID according the ERC-7579 spec
     *
     * MUST return true if the module is of the given type and false otherwise
     */
    function isModuleType(uint256 moduleTypeId) external view returns (bool);
}
