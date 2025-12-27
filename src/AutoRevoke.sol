// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC7579Hook} from "./interfaces/IERC7579/IERC7579Hook.sol";
import {IAutoRevoke} from "./interfaces/IAutoRevoke.sol";

import {Execution} from "@erc7579/interfaces/IERC7579Account.sol";
import {ExecutionLib} from "@erc7579/lib/ExecutionLib.sol";
import {ModeLib, ModeCode, CallType, CALLTYPE_SINGLE, CALLTYPE_BATCH} from "@erc7579/lib/ModeLib.sol";
import {MSAAdvanced} from "@erc7579/MSAAdvanced.sol";

import {IERC165} from "./interfaces/IERC165.sol";
import {IERC20} from "./interfaces/token/IERC20.sol";
import {IERC721} from "./interfaces/token/IERC721.sol";
import {IERC1155} from "./interfaces/token/IERC1155.sol";

import {console} from "forge-std/console.sol";

/**
 * @title AutoRevoke
 * @author z (@zisbraindead) for Braindead Digital (@braindeaddgtl)
 * @notice AutoRevoke is an ERC7579-compliant module that automatically revokes all token (ERC20, ERC721, ERC1155) approvals once
 *         the transaction has been executed. The user can set a configuration byte that will determine which token types to revoke*
 *         approvals for. The user can also set a set of spender addresses that will be excluded from the auto-revoke
 *         process, in the case of OTC marketplaces, for example.
 *
 *         In reality, ERC721 does not really make much sense to revoke approvals for, as the approval is only valid until transfer,
 *         but it's still included for completeness, users can still choose to revoke approvals for ERC721 tokens if they want to,
 *         though it's not recommended.
 */
contract AutoRevoke is IERC7579Hook, IAutoRevoke {
    using ExecutionLib for bytes;
    using ModeLib for ModeCode;

    bytes1 private constant DEFAULT_CONFIG = 0x01; // 00000001, this means that by default, if no configuration is set, the module will only revoke ERC20 approvals in batch mode.
    //////////////////////////////////////////////////////////////
    // State Variables
    //////////////////////////////////////////////////////////////

    mapping(address => bytes1) public _configs;
    mapping(address => mapping(address => bool)) public _excludedSpenders;

    //////////////////////////////////////////////////////////////
    // Errors
    //////////////////////////////////////////////////////////////
    error AlreadyInstalled();
    error InvalidConfig();

    //////////////////////////////////////////////////////////////
    // Events
    //////////////////////////////////////////////////////////////
    event Installed(address indexed account, bytes1 config);
    event InstalledAsExecutor(address indexed account);
    event Uninstalled(address indexed account);
    event UninstalledAsExecutor(address indexed account);
    event Revoked(address indexed account, address indexed target, address indexed spender);
    event RevokeFailed(address indexed account, address indexed target, address indexed spender, uint8 reason);
    event ExcludedSpender(address indexed account, address indexed spender, bool excluded);
    event ConfigSet(address indexed account, bytes1 config);

    //////////////////////////////////////////////////////////////
    // IERC7579Module Interface
    //////////////////////////////////////////////////////////////

    // @inheritdoc IERC7579Module
    function isModuleType(uint256 moduleTypeId) external pure override returns (bool) {
        return moduleTypeId == 4 || moduleTypeId == 2; // 4 == Hook type ID, 2 == Executor type ID
    }

    // @inheritdoc IERC7579Module
    function onInstall(bytes calldata data) external override {
        if (data[0] == 0xFF) {
            emit InstalledAsExecutor(msg.sender);
            return;
        }
        require(_configs[msg.sender] == 0x00, AlreadyInstalled());
        require(data[0] <= 0x0F, InvalidConfig()); // 0x0F means the rightmost nibble is maxxed out
        bytes1 config = bytes1(data[0]) == 0x00 ? DEFAULT_CONFIG : bytes1(data[0]);
        _configs[msg.sender] = config;
        emit Installed(msg.sender, config);
    }

    // @inheritdoc IERC7579Module
    function onUninstall(bytes calldata data) external override {
        if (data[0] == 0xFF) {
            emit UninstalledAsExecutor(msg.sender);
            return;
        }
        delete _configs[msg.sender];
        emit Uninstalled(msg.sender);
    }

    //////////////////////////////////////////////////////////////
    // IERC7579Hook Interface
    //////////////////////////////////////////////////////////////

    // @inheritdoc IERC7579Hook
    function preCheck(address target, uint256, /* value */ bytes calldata msgData)
        external
        override
        returns (bytes memory hookData)
    {
        if (
            bytes4(msgData[0:4]) != MSAAdvanced.execute.selector
                && bytes4(msgData[0:4]) != MSAAdvanced.executeFromExecutor.selector || target == address(this)
        ) {
            return "";
        }
        bytes memory data = _handleCalldata(msgData, _configs[msg.sender]);
        return data;
    }

    // @inheritdoc IERC7579Hook
    function postCheck(bytes calldata hookData) external override {
        if (hookData.length == 0) {
            return;
        }
        Approval[] memory approvals = _decodePostCheckData(hookData);
        uint256 length = approvals.length;
        for (uint256 i = 0; i < length;) {
            Approval memory approval = approvals[i];
            _revokeApproval(approval.target, approval.spender, approval.tokenType, approval.tokenId);
            unchecked {
                ++i;
            }
        }
    }

    //////////////////////////////////////////////////////////////
    // Public Functions
    //////////////////////////////////////////////////////////////

    // @inheritdoc IAutoRevoke
    function setConfig(bytes1 config) external override {
        _configs[msg.sender] = config;
        emit ConfigSet(msg.sender, config);
    }

    // @inheritdoc IAutoRevoke
    function toggleExcludedSpender(address spender, bool excluded) external override {
        _excludedSpenders[msg.sender][spender] = excluded;
        emit ExcludedSpender(msg.sender, spender, excluded);
    }

    // @inheritdoc IAutoRevoke
    function revoke(Revoke[] calldata revokes) external override {
        uint256 len = revokes.length;
        for (uint256 i = 0; i < len;) {
            Revoke memory _revoke = revokes[i];
            address target = _revoke.target;
            TokenType tokenType = _getTokenType(target);
            _revokeApproval(target, _revoke.spender, tokenType, _revoke.tokenId);
            unchecked {
                ++i;
            }
        }
    }

    //////////////////////////////////////////////////////////////
    // Internal Functions
    //////////////////////////////////////////////////////////////

    /**
     * @dev Decodes the configuration data that is passed onInstall. The data must be encoded with the rightmost bit being the
     *      ERC20 flag, the second rightmost bit being the ERC721 flag, the third rightmost bit being the ERC1155 flag, and the
     *      fourth rightmost bit being the single flag.
     * @param config the configuration data to decode
     * @return erc20 the ERC20 flag
     * @return erc721 the ERC721 flag
     * @return erc1155 the ERC1155 flag
     * @return single the single flag
     */
    function _decodeConfig(bytes1 config) internal pure returns (bool erc20, bool erc721, bool erc1155, bool single) {
        erc20 = (uint8(config) & 1) == 1; // 00000001
        erc721 = (uint8(config) & 2) == 2; // 00000010
        erc1155 = (uint8(config) & 4) == 4; // 00000100
        single = (uint8(config) & 8) == 8; // 00001000
    }

    /**
     * @dev Safely checks if a contract supports an interface using staticcall.
     * Uses assembly to prevent reverts from bubbling up when the function doesn't exist.
     * @param target the address of the contract to check
     * @param interfaceId the interface ID to check
     * @return supported true if the interface is supported, false otherwise
     */
    function _supportsInterface(address target, bytes4 interfaceId) internal view returns (bool supported) {
        bytes4 selector = IERC165.supportsInterface.selector;
        bytes memory callData = abi.encodeWithSelector(selector, interfaceId);

        assembly {
            let success := staticcall(gas(), target, add(callData, 0x20), mload(callData), 0x00, 0x20)

            if and(success, gt(returndatasize(), 0x1f)) { supported := mload(0x00) }
        }
    }

    /**
     * @dev Gets the type of the token contract.
     * @param target the address of the token contract
     * @return tokenType the type of the token contract (0 = ERC20, 1 = ERC721, 2 = ERC1155, 3 = Unknown)
     */
    function _getTokenType(address target) internal view returns (TokenType tokenType) {
        if (_supportsInterface(target, type(IERC20).interfaceId)) {
            return TokenType.ERC20;
        }

        if (_supportsInterface(target, type(IERC721).interfaceId)) {
            return TokenType.ERC721;
        }

        if (_supportsInterface(target, type(IERC1155).interfaceId)) {
            return TokenType.ERC1155;
        }

        return TokenType.UNKNOWN;
    }

    /**
     * @dev Checks if a call is an approval.
     * @param callData the data of the call
     * @param tokenType the type of the call (0 = ERC20, 1 = ERC721, 2 = ERC1155)
     * @return isApproval true if the call is an approval, false otherwise
     */
    function _isApproval(bytes memory callData, TokenType tokenType) internal pure returns (bool isApproval) {
        bytes4 selector;
        assembly {
            selector := mload(add(callData, 0x20))
        }
        // We will assume that if we haven't found a match, it's an ERC20 approval.
        if (tokenType == TokenType.ERC20 || tokenType == TokenType.UNKNOWN) {
            uint256 amount;
            assembly {
                amount := mload(add(callData, 0x44))
            }
            return selector == IERC20.approve.selector && amount > 0;
        } else if (tokenType == TokenType.ERC721) {
            if (selector == IERC721.approve.selector) {
                bytes32 spender;
                assembly {
                    spender := mload(add(callData, 0x24))
                }
                return spender != 0;
            } else if (selector == IERC721.setApprovalForAll.selector) {
                bool approved;
                assembly {
                    approved := mload(add(callData, 0x44))
                }
                return approved;
            }
            return false;
        } else if (tokenType == TokenType.ERC1155) {
            bool approved;
            assembly {
                approved := mload(add(callData, 0x44))
            }
            return selector == IERC1155.setApprovalForAll.selector && approved;
        }
    }

    /**
     * @dev Gets the spender from the call data.
     * @param callData The data of the call
     * @return spender The spender
     */
    function _getSpender(bytes memory callData) internal pure returns (address spender) {
        assembly {
            spender := mload(add(callData, 0x24))
        }
    }

    /**
     * @dev Gets the tokenId from the calldata
     * @param callData The data of the call\
     * @return tokenId The tokenId
     * @return active If this is a relevant approval
     */
    function _getTokenId(bytes memory callData) internal pure returns (uint256 tokenId, bool active) {
        assembly {
            //                                shl(0x095ea7b3, 0xe0)
            if eq(mload(add(callData, 0x20)), 0x095ea7b300000000000000000000000000000000000000000000000000000000) {
                tokenId := mload(add(callData, 0x44))
                active := true
            }
        }
    }

    /**
     * @dev Checks if the token type should be revoked.
     * @param erc20 The ERC20 flag
     * @param erc721 The ERC721 flag
     * @param erc1155 The ERC1155 flag
     * @param tokenType The type of the token
     * @return shouldRevoke true if the token type should be revoked, false otherwise
     */
    function _shouldRevoke(bool erc20, bool erc721, bool erc1155, TokenType tokenType) internal pure returns (bool) {
        return erc20 && tokenType == TokenType.ERC20 || erc20 && tokenType == TokenType.UNKNOWN
            || erc721 && tokenType == TokenType.ERC721 || erc1155 && tokenType == TokenType.ERC1155;
    }

    /**
     * @dev Handles the calldata and returns the PCD.
     * @param data The calldata to parse
     * @param config The configuration byte
     * @return _data The parsed calldata
     */
    function _handleCalldata(bytes calldata data, bytes1 config) internal view returns (bytes memory _data) {
        (bool erc20, bool erc721, bool erc1155, bool single) = _decodeConfig(config);
        bytes32 rawMode = bytes32(data[4:36]);
        (CallType callType,,,) = ModeCode.wrap(rawMode).decode();
        uint256 offset = uint256(bytes32(data[36:68]));
        bytes calldata executionCalldata = data[4 + offset + 32:];

        // Note: CallType 0xFF (delegatecall) is not supported.

        // We will only revoke approvals if the call type is single and the single flag is set, because
        // otherwise, a single approval transaction will just never actually result in an approval. Of
        // course, if a user wants to disallow single approval transactions, the functionality is still
        // supported.
        if (callType == CALLTYPE_SINGLE && single) {
            // Standard call
            (address target,, bytes memory callData) = executionCalldata.decodeSingle();

            uint256 codeSize;
            assembly {
                codeSize := extcodesize(target)
            }
            if (codeSize == 0) {
                return ""; // We don't want to revoke approvals for contracts that don't exist.
            }

            TokenType _type = _getTokenType(target);
            address spender = _getSpender(callData);

            bool shouldRevoke = _shouldRevoke(erc20, erc721, erc1155, _type);
            bool isExcluded = _excludedSpenders[msg.sender][spender];
            bool isApproval = _isApproval(callData, _type);
            uint256 tokenId;
            bool active;
            if (_type == TokenType.ERC721) {
                (tokenId, active) = _getTokenId(callData);
            }

            if (!isExcluded && shouldRevoke && isApproval) {
                Approval[] memory approvals = new Approval[](1);
                approvals[0] = Approval({
                    target: target,
                    tokenType: _type,
                    spender: spender,
                    tokenId: TokenId({tokenId: tokenId, active: active})
                });
                _data = abi.encode(approvals);
            } else {
                _data = "";
            }
        }

        if (callType == CALLTYPE_BATCH) {
            // Batch call
            Execution[] calldata executions = executionCalldata.decodeBatch();

            Approval[] memory approvals = new Approval[](executions.length);

            for (uint256 i = 0; i < executions.length; i++) {
                Execution memory execution = executions[i];
                address target = execution.target;

                uint256 codeSize;
                assembly {
                    codeSize := extcodesize(target)
                }
                if (codeSize == 0) {
                    continue;
                }

                bytes memory callData = execution.callData;

                TokenType _type = _getTokenType(target);
                address spender = _getSpender(callData);

                bool shouldRevoke = _shouldRevoke(erc20, erc721, erc1155, _type);
                bool isExcluded = _excludedSpenders[msg.sender][spender];
                bool isApproval = _isApproval(callData, _type);
                uint256 tokenId;
                bool active;
                if (_type == TokenType.ERC721) {
                    (tokenId, active) = _getTokenId(callData);
                }

                if (!isExcluded && shouldRevoke && isApproval) {
                    approvals[i] = Approval({
                        target: target,
                        tokenType: _type,
                        spender: spender,
                        tokenId: TokenId({tokenId: tokenId, active: active})
                    });
                }
            }

            _data = abi.encode(approvals);
        }
    }

    /**
     * @dev Revokes the approval for the given target, spender, and type.
     * @param target The address of the token contract
     * @param spender The address of the spender
     * @param tokenType The type of the token (0 = ERC20, 1 = ERC721, 2 = ERC1155)
     * @param tokenId The ID of the token and whether it should be considered
     */
    function _revokeApproval(address target, address spender, TokenType tokenType, TokenId memory tokenId) internal {
        ModeCode mode = ModeLib.encodeSimpleSingle();
        if (tokenType != TokenType.ERC721 && tokenType != TokenType.ERC1155) {
            bytes memory executionCalldata =
                ExecutionLib.encodeSingle(target, 0, abi.encodeWithSelector(IERC20.approve.selector, spender, 0));
            (bool success,) =
                msg.sender.call(abi.encodeWithSignature("executeFromExecutor(bytes32,bytes)", mode, executionCalldata));
            if (!success) {
                emit RevokeFailed(msg.sender, target, spender, 0);
                return;
            }
            emit Revoked(msg.sender, target, spender);
        } else if (tokenType == TokenType.ERC721) {
            bytes memory callData = tokenId.active
                ? abi.encodeWithSelector(IERC721.approve.selector, address(0), tokenId)
                : abi.encodeWithSelector(IERC721.setApprovalForAll.selector, spender, false);
            bytes memory executionCalldata = ExecutionLib.encodeSingle(target, 0, callData);
            (bool success,) =
                msg.sender.call(abi.encodeWithSignature("executeFromExecutor(bytes32,bytes)", mode, executionCalldata));

            if (!success) {
                emit RevokeFailed(msg.sender, target, spender, 0);
                return;
            }
            emit Revoked(msg.sender, target, spender);
        } else if (tokenType == TokenType.ERC1155) {
            bytes memory executionCalldata = ExecutionLib.encodeSingle(
                target, 0, abi.encodeWithSelector(IERC1155.setApprovalForAll.selector, spender, false)
            );
            (bool success,) =
                msg.sender.call(abi.encodeWithSignature("executeFromExecutor(bytes32,bytes)", mode, executionCalldata));

            if (!success) {
                emit RevokeFailed(msg.sender, target, spender, 0);
                return;
            }
            emit Revoked(msg.sender, target, spender);
        }
    }

    /**
     * @dev Decodes the post-check data and returns the approvals.
     * @param data The data to parse
     * @return approvals The approvals
     */
    function _decodePostCheckData(bytes calldata data) internal pure returns (Approval[] memory) {
        return abi.decode(data, (Approval[]));
    }
}
