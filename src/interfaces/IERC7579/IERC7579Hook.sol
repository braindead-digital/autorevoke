// SPDX-License-Identifier: CC0
pragma solidity ^0.8.13;

import {IERC7579Module} from "./IERC7579Module.sol";

/**
 * @title IERC7579Hook
 * @author zeroknots (@zeroknots), Konrad Kopp (@kopy-kat), Taek Lee (@leekt), Fil Makarov (@filmakarov), Elim Poon (@yaonam), Lyu Min (@rockmin216)
 * @notice Please see https://eips.ethereum.org/EIPS/eip-7579 for more details.
 */
interface IERC7579Hook is IERC7579Module {
    /**
     * @dev Called by the smart account before execution
     * @param msgSender the address that called the smart account
     * @param value the value that was sent to the smart account
     * @param msgData the data that was sent to the smart account
     *
     * MAY return arbitrary data in the `hookData` return value
     */
    function preCheck(address msgSender, uint256 value, bytes calldata msgData)
        external
        returns (bytes memory hookData);

    /**
     * @dev Called by the smart account after execution
     * @param hookData the data that was returned by the `preCheck` function
     *
     * MAY validate the `hookData` to validate transaction context of the `preCheck` function
     */
    function postCheck(bytes calldata hookData) external;
}
