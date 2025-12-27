// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AutoRevoke} from "../src/AutoRevoke.sol";
import {IAutoRevoke} from "../src/interfaces/IAutoRevoke.sol";

import {TestBaseUtilAdvanced} from "@erc7579-tests/advanced/TestBaseUtilAdvanced.t.sol";

import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {Execution} from "@erc7579/interfaces/IERC7579Account.sol";

import {ModeLib} from "@erc7579/lib/ModeLib.sol";
import {ExecutionLib} from "@erc7579/lib/ExecutionLib.sol";

import {IERC7579Account} from "@erc7579/interfaces/IERC7579Account.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC721} from "@oz/token/ERC721/IERC721.sol";
import {IERC1155} from "@oz/token/ERC1155/IERC1155.sol";

import {MockERC20With165} from "./mocks/MockERC20With165.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {MockERC1155} from "./mocks/MockERC1155.sol";
import {MockWhatever} from "./mocks/MockWhatever.sol";

contract AutoRevokeTest is TestBaseUtilAdvanced {
    AutoRevoke public autoRevoke;
    address public account;
    bytes public initCode;

    address public constant JUNK = address(0x67676767);

    MockERC20[] public erc20s;
    MockERC20With165[] public erc20With165s;
    MockERC721[] public erc721s;
    MockERC1155[] public erc1155s;
    MockWhatever public whatever;

    function setUp() public override {
        super.setUp();

        (account, initCode) = getAccountAndInitCode();

        for (uint256 i = 0; i < 10; i++) {
            erc20With165s.push(new MockERC20With165());
            erc20s.push(new MockERC20());
            erc721s.push(new MockERC721());
            erc1155s.push(new MockERC1155());
        }

        for (uint256 i = 0; i < 10; i++) {
            for (uint256 j = 0; j < 10; j++) {
                erc721s[i].mint(address(account), j);
            }
        }

        uint256[] memory ids = new uint256[](10);
        uint256[] memory amounts = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            ids[i] = i;
            amounts[i] = 1;
        }

        for (uint256 i = 0; i < 10; i++) {
            erc1155s[i].mintBatch(address(account), ids, amounts);
        }

        whatever = new MockWhatever();

        autoRevoke = new AutoRevoke();
    }

    //////////////////////////////////////////////////////////////
    // Install Helpers
    //////////////////////////////////////////////////////////////

    modifier install(bytes1 initConfig) {
        defaultInstall(initConfig);
        _;
    }

    function defaultInstall(bytes1 initConfig) internal {
        bytes memory installModuleCalldataHook =
            abi.encodeCall(IERC7579Account.installModule, (4, address(autoRevoke), abi.encode(initConfig)));
        bytes memory installModuleCalldataExecutor =
            abi.encodeCall(IERC7579Account.installModule, (2, address(autoRevoke), abi.encode(bytes1(0xFF))));
        PackedUserOperation memory userOpHook = getDefaultUserOp();
        userOpHook.sender = account;
        userOpHook.nonce = getNonce(account, address(defaultValidator));
        userOpHook.initCode = initCode;
        userOpHook.callData = installModuleCalldataHook;

        PackedUserOperation[] memory userOpsHook = new PackedUserOperation[](1);
        userOpsHook[0] = userOpHook;

        entrypoint.handleOps(userOpsHook, payable(address(0x01)));

        PackedUserOperation memory userOpSetExecutor = getDefaultUserOp();
        userOpSetExecutor.sender = account;
        userOpSetExecutor.nonce = getNonce(account, address(defaultValidator));
        userOpSetExecutor.callData = installModuleCalldataExecutor;

        PackedUserOperation[] memory userOpsSetExecutor = new PackedUserOperation[](1);
        userOpsSetExecutor[0] = userOpSetExecutor;

        entrypoint.handleOps(userOpsSetExecutor, payable(address(0x01)));
    }

    //////////////////////////////////////////////////////////////
    // Module tests
    //////////////////////////////////////////////////////////////

    function test_installModule() public {
        bytes memory installModuleCalldata0 =
            abi.encodeCall(IERC7579Account.installModule, (4, address(autoRevoke), abi.encode(bytes1(0x00))));
        bytes memory installModuleCalldata1 =
            abi.encodeCall(IERC7579Account.installModule, (4, address(autoRevoke), abi.encode(bytes1(0x01))));
        bytes memory installModuleCalldata2 =
            abi.encodeCall(IERC7579Account.installModule, (4, address(autoRevoke), abi.encode(bytes1(0x02))));

        uint256 nonce = getNonce(account, address(defaultValidator));

        PackedUserOperation memory userOp0 = getDefaultUserOp();
        userOp0.sender = account;
        userOp0.nonce = nonce;
        userOp0.initCode = initCode;
        userOp0.callData = installModuleCalldata0;

        PackedUserOperation memory userOp1 = getDefaultUserOp();
        userOp1.sender = account;
        userOp1.nonce = nonce;
        userOp1.initCode = initCode;
        userOp1.callData = installModuleCalldata1;

        PackedUserOperation memory userOp2 = getDefaultUserOp();
        userOp2.sender = account;
        userOp2.nonce = nonce;
        userOp2.initCode = initCode;
        userOp2.callData = installModuleCalldata2;

        PackedUserOperation[] memory userOps0 = new PackedUserOperation[](1);
        userOps0[0] = userOp0;

        PackedUserOperation[] memory userOps1 = new PackedUserOperation[](1);
        userOps1[0] = userOp1;

        PackedUserOperation[] memory userOps2 = new PackedUserOperation[](1);
        userOps2[0] = userOp2;

        uint256 snapshot = vm.snapshotState();

        entrypoint.handleOps(userOps0, payable(address(0x01)));
        assertTrue(autoRevoke._configs(account) == bytes1(0x01));
        vm.revertToState(snapshot);

        entrypoint.handleOps(userOps1, payable(address(0x01)));
        assertTrue(autoRevoke._configs(account) == bytes1(0x01));
        vm.revertToState(snapshot);

        entrypoint.handleOps(userOps2, payable(address(0x01)));
        assertTrue(autoRevoke._configs(account) == bytes1(0x02));
        vm.revertToState(snapshot);
    }

    //////////////////////////////////////////////////////////////
    // ERC20 tests
    //////////////////////////////////////////////////////////////

    function test_revokeApprovals_ERC20_single() public install(bytes1(0x09)) {
        // 0x09 == 00001001, this means that the module will revoke approvals in single mode, and revoke ERC20 approvals.
        PackedUserOperation memory userOp = getDefaultUserOp();
        userOp.sender = account;
        userOp.nonce = getNonce(account, address(defaultValidator));
        userOp.callData = abi.encodeCall(
            IERC7579Account.execute,
            (
                ModeLib.encodeSimpleSingle(),
                ExecutionLib.encodeSingle(
                    address(erc20s[0]), 0, abi.encodeWithSelector(IERC20.approve.selector, JUNK, uint256(1000))
                )
            )
        );

        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        entrypoint.handleOps(userOps, payable(address(0x01)));

        assertTrue(erc20s[0].allowance(account, JUNK) == 0);
    }

    function test_revokeApprovals_ERC20_single_doesNotRevoke() public install(bytes1(0x00)) {
        PackedUserOperation memory userOp = getDefaultUserOp();
        userOp.sender = account;
        userOp.nonce = getNonce(account, address(defaultValidator));
        userOp.callData = abi.encodeCall(
            IERC7579Account.execute,
            (
                ModeLib.encodeSimpleSingle(),
                ExecutionLib.encodeSingle(
                    address(erc20s[0]), 0, abi.encodeWithSelector(IERC20.approve.selector, JUNK, uint256(1000))
                )
            )
        );

        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        entrypoint.handleOps(userOps, payable(address(0x01)));

        assertTrue(erc20s[0].allowance(account, JUNK) == uint256(1000));
    }

    function test_revokeApprovals_ERC20_batch() public install(bytes1(0x00)) {
        PackedUserOperation memory userOp = getDefaultUserOp();
        userOp.sender = account;
        userOp.nonce = getNonce(account, address(defaultValidator));

        // Batch approve for 10 ERC20 tokens
        uint256 numTokens = 10;
        Execution[] memory executions = new Execution[](numTokens);
        for (uint256 i = 0; i < numTokens; i++) {
            executions[i] = Execution({
                target: address(erc20s[i]),
                value: 0,
                callData: abi.encodeWithSelector(IERC20.approve.selector, JUNK, uint256(1000 + i))
            });
        }

        userOp.callData =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(executions)));

        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        for (uint256 i = 0; i < numTokens; i++) {
            vm.expectEmit(true, true, false, true, address(erc20s[i]));
            emit IERC20.Approval(account, JUNK, uint256(1000 + i));
        }

        for (uint256 i = 0; i < numTokens; i++) {
            vm.expectEmit(true, true, false, true, address(erc20s[i]));
            emit IERC20.Approval(account, JUNK, uint256(0));
        }

        entrypoint.handleOps(userOps, payable(address(0x01)));

        for (uint256 i = 0; i < numTokens; i++) {
            assertTrue(erc20s[i].allowance(account, JUNK) == 0);
        }
    }

    function test_revokeApprovals_ERC20_batch_withInteractionsInbetween(uint8 seed) public install(bytes1(0x00)) {
        PackedUserOperation memory userOp = getDefaultUserOp();
        userOp.sender = account;
        userOp.nonce = getNonce(account, address(defaultValidator));

        // Batch approve for 10 ERC20 tokens
        uint256 numTokens = 10;

        uint256[] memory afterErc20Interaction = new uint256[](numTokens);
        uint256 totalInteractions = 0;
        for (uint256 i = 0; i < numTokens; i++) {
            uint8 x = seed % 3;
            afterErc20Interaction[i] = x;
            totalInteractions += x;
        }

        Execution[] memory executions = new Execution[](numTokens + totalInteractions);
        uint256 offset = 0;
        for (uint256 i = 0; i < numTokens; i++) {
            executions[offset + i] = Execution({
                target: address(erc20s[i]),
                value: 0,
                callData: abi.encodeWithSelector(IERC20.approve.selector, JUNK, uint256(1000 + i))
            });
            uint256 x = afterErc20Interaction[i];
            for (uint256 j = 0; j < x; j++) {
                executions[offset + numTokens + j] = Execution({
                    target: address(whatever),
                    value: 0,
                    callData: abi.encodeWithSelector(MockWhatever.whatever.selector)
                });
            }
            offset += x;
        }

        userOp.callData =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(executions)));

        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        for (uint256 i = 0; i < numTokens; i++) {
            vm.expectEmit(true, true, false, true, address(erc20s[i]));
            emit IERC20.Approval(account, JUNK, uint256(1000 + i));
        }

        for (uint256 i = 0; i < numTokens; i++) {
            vm.expectEmit(true, true, false, true, address(erc20s[i]));
            emit IERC20.Approval(account, JUNK, uint256(0));
        }

        entrypoint.handleOps(userOps, payable(address(0x01)));

        for (uint256 i = 0; i < numTokens; i++) {
            assertTrue(erc20s[i].allowance(account, JUNK) == 0);
        }
    }

    //////////////////////////////////////////////////////////////
    // ERC721 tests
    //////////////////////////////////////////////////////////////

    function test_revokeApprovals_ERC721_single_approvalForAll() public install(bytes1(0x0A)) {
        // 0x0A == 00001010, this means that the module will revoke approvals in single mode, and revoke ERC721 approvals.
        PackedUserOperation memory userOp = getDefaultUserOp();
        userOp.sender = account;
        userOp.nonce = getNonce(account, address(defaultValidator));
        userOp.callData = abi.encodeCall(
            IERC7579Account.execute,
            (
                ModeLib.encodeSimpleSingle(),
                ExecutionLib.encodeSingle(
                    address(erc721s[0]), 0, abi.encodeWithSelector(IERC721.setApprovalForAll.selector, JUNK, true)
                )
            )
        );

        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        vm.expectEmit(true, true, false, true, address(erc721s[0]));
        emit IERC721.ApprovalForAll(account, JUNK, true);

        vm.expectEmit(true, true, false, true, address(erc721s[0]));
        emit IERC721.ApprovalForAll(account, JUNK, false);

        entrypoint.handleOps(userOps, payable(address(0x01)));

        assertFalse(erc721s[0].isApprovedForAll(account, JUNK));
    }

    function test_revokeApprovals_ERC721_single_approvalForSingle() public install(bytes1(0x0A)) {
        PackedUserOperation memory userOp = getDefaultUserOp();
        userOp.sender = account;
        userOp.nonce = getNonce(account, address(defaultValidator));
        userOp.callData = abi.encodeCall(
            IERC7579Account.execute,
            (
                ModeLib.encodeSimpleSingle(),
                ExecutionLib.encodeSingle(
                    address(erc721s[0]), 0, abi.encodeWithSelector(IERC721.approve.selector, JUNK, 0)
                )
            )
        );

        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        vm.expectEmit(true, true, false, true, address(erc721s[0]));
        emit IERC721.Approval(account, JUNK, 0);

        vm.expectEmit(true, true, false, true, address(erc721s[0]));
        emit IERC721.Approval(account, address(0), 0);

        entrypoint.handleOps(userOps, payable(address(0x01)));

        assertFalse(erc721s[0].getApproved(0) == JUNK);
    }

    function test_revokeApprovals_ERC721_single_approvalForAll_doesNotRevoke() public install(bytes1(0x02)) {
        // 0x02 == 00000010, this means that the module will not revoke approvals in single mode, and revoke ERC721 approvals.
        PackedUserOperation memory userOp = getDefaultUserOp();
        userOp.sender = account;
        userOp.nonce = getNonce(account, address(defaultValidator));
        userOp.callData = abi.encodeCall(
            IERC7579Account.execute,
            (
                ModeLib.encodeSimpleSingle(),
                ExecutionLib.encodeSingle(
                    address(erc721s[0]), 0, abi.encodeWithSelector(IERC721.setApprovalForAll.selector, JUNK, true)
                )
            )
        );

        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        vm.expectEmit(true, true, false, true, address(erc721s[0]));
        emit IERC721.ApprovalForAll(account, JUNK, true);

        entrypoint.handleOps(userOps, payable(address(0x01)));

        assertTrue(erc721s[0].isApprovedForAll(account, JUNK));
    }

    function test_revokeApprovals_ERC721_single_approvalForSingle_doesNotRevoke() public install(bytes1(0x02)) {
        PackedUserOperation memory userOp = getDefaultUserOp();
        userOp.sender = account;
        userOp.nonce = getNonce(account, address(defaultValidator));
        userOp.callData = abi.encodeCall(
            IERC7579Account.execute,
            (
                ModeLib.encodeSimpleSingle(),
                ExecutionLib.encodeSingle(
                    address(erc721s[0]), 0, abi.encodeWithSelector(IERC721.approve.selector, JUNK, 0)
                )
            )
        );

        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        vm.expectEmit(true, true, false, true, address(erc721s[0]));
        emit IERC721.Approval(account, JUNK, 0);

        entrypoint.handleOps(userOps, payable(address(0x01)));

        assertTrue(erc721s[0].getApproved(0) == JUNK);
    }

    function test_revokeApprovals_ERC721_batch_approvalForSingle() public install(bytes1(0x02)) {
        PackedUserOperation memory userOp = getDefaultUserOp();
        userOp.sender = account;
        userOp.nonce = getNonce(account, address(defaultValidator));

        // Batch approve for 5 ERC721 tokens
        uint256 numTokens = 5;
        // Batch approve 5 tokens per ERC721 contract
        uint256 numPerToken = 5;
        uint256 total = numTokens * numPerToken;
        Execution[] memory executions = new Execution[](total);
        for (uint256 i = 0; i < numTokens; i++) {
            for (uint256 j = 0; j < numPerToken; j++) {
                executions[i * numPerToken + j] = Execution({
                    target: address(erc721s[i]),
                    value: 0,
                    callData: abi.encodeWithSelector(IERC721.approve.selector, JUNK, j)
                });
            }
        }

        userOp.callData =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(executions)));
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        for (uint256 i = 0; i < numTokens; i++) {
            for (uint256 j = 0; j < numPerToken; j++) {
                vm.expectEmit(true, true, false, true, address(erc721s[i]));
                emit IERC721.Approval(account, address(JUNK), j);
            }
        }

        for (uint256 i = 0; i < numTokens; i++) {
            for (uint256 j = 0; j < numPerToken; j++) {
                vm.expectEmit(true, true, false, true, address(erc721s[i]));
                emit IERC721.Approval(account, address(0), j);
            }
        }

        entrypoint.handleOps(userOps, payable(address(0x01)));

        for (uint256 i = 0; i < numTokens; i++) {
            for (uint256 j = 0; j < numPerToken; j++) {
                assertFalse(erc721s[i].getApproved(j) == JUNK);
            }
        }
    }

    function test_revokeApprovals_ERC721_batch_approvalForAll() public install(bytes1(0x02)) {
        PackedUserOperation memory userOp = getDefaultUserOp();
        userOp.sender = account;
        userOp.nonce = getNonce(account, address(defaultValidator));

        // Batch approve for 10 ERC721 tokens
        uint256 numTokens = 10;
        Execution[] memory executions = new Execution[](numTokens);
        for (uint256 i = 0; i < numTokens; i++) {
            executions[i] = Execution({
                target: address(erc721s[i]),
                value: 0,
                callData: abi.encodeWithSelector(IERC721.setApprovalForAll.selector, JUNK, true)
            });
        }

        userOp.callData =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(executions)));
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        for (uint256 i = 0; i < numTokens; i++) {
            vm.expectEmit(true, true, false, true, address(erc721s[i]));
            emit IERC721.ApprovalForAll(account, address(JUNK), true);
        }

        for (uint256 i = 0; i < numTokens; i++) {
            vm.expectEmit(true, true, false, true, address(erc721s[i]));
            emit IERC721.ApprovalForAll(account, address(JUNK), false);
        }

        entrypoint.handleOps(userOps, payable(address(0x01)));

        for (uint256 i = 0; i < numTokens; i++) {
            assertFalse(erc721s[i].isApprovedForAll(account, JUNK));
        }
    }

    //////////////////////////////////////////////////////////////
    // ERC1155 tests
    //////////////////////////////////////////////////////////////

    function test_revokeApprovals_ERC1155_single() public install(bytes1(0x0C)) {
        // 0x0C == 00001100, this means that the module will revoke approvals in single mode, and revoke ERC1155 approvals.
        PackedUserOperation memory userOp = getDefaultUserOp();
        userOp.sender = account;
        userOp.nonce = getNonce(account, address(defaultValidator));
        userOp.callData = abi.encodeCall(
            IERC7579Account.execute,
            (
                ModeLib.encodeSimpleSingle(),
                ExecutionLib.encodeSingle(
                    address(erc1155s[0]), 0, abi.encodeWithSelector(IERC1155.setApprovalForAll.selector, JUNK, true)
                )
            )
        );

        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        vm.expectEmit(true, true, false, true, address(erc1155s[0]));
        emit IERC1155.ApprovalForAll(account, JUNK, true);

        vm.expectEmit(true, true, false, true, address(erc1155s[0]));
        emit IERC1155.ApprovalForAll(account, JUNK, false);

        entrypoint.handleOps(userOps, payable(address(0x01)));

        assertFalse(erc1155s[0].isApprovedForAll(account, JUNK));
    }

    function test_revokeApprovals_ERC1155_batch() public install(bytes1(0x04)) {
        // 0x04 == 000001000, this means that the module will revoke approvals for ERC1155 tokens.
        PackedUserOperation memory userOp = getDefaultUserOp();
        userOp.sender = account;
        userOp.nonce = getNonce(account, address(defaultValidator));

        // Batch approve for 10 ERC1155 tokens
        uint256 numTokens = 10;
        Execution[] memory executions = new Execution[](numTokens);
        for (uint256 i = 0; i < numTokens; i++) {
            executions[i] = Execution({
                target: address(erc1155s[i]),
                value: 0,
                callData: abi.encodeWithSelector(IERC1155.setApprovalForAll.selector, JUNK, true)
            });
        }

        userOp.callData =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(executions)));

        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        for (uint256 i = 0; i < numTokens; i++) {
            vm.expectEmit(true, true, false, true, address(erc1155s[i]));
            emit IERC1155.ApprovalForAll(account, JUNK, true);
        }

        for (uint256 i = 0; i < numTokens; i++) {
            vm.expectEmit(true, true, false, true, address(erc1155s[i]));
            emit IERC1155.ApprovalForAll(account, JUNK, false);
        }

        entrypoint.handleOps(userOps, payable(address(0x01)));

        for (uint256 i = 0; i < numTokens; i++) {
            assertFalse(erc1155s[i].isApprovedForAll(account, JUNK));
        }
    }

    //////////////////////////////////////////////////////////////
    // Batch revoke tests
    //////////////////////////////////////////////////////////////
    function test_batchRevoke() public install(0x00) {
        // 0x00 means that we will default to just revoking ERC20 in batch mode.
        PackedUserOperation memory userOp = getDefaultUserOp();
        userOp.sender = account;
        userOp.nonce = getNonce(account, address(defaultValidator));

        IAutoRevoke.Revoke[] memory revokes = new IAutoRevoke.Revoke[](3);
        revokes[0] = IAutoRevoke.Revoke({
            target: address(erc20s[0]),
            spender: JUNK,
            tokenId: IAutoRevoke.TokenId({tokenId: 0, active: false})
        });
        revokes[1] = IAutoRevoke.Revoke({
            target: address(erc721s[0]),
            spender: JUNK,
            tokenId: IAutoRevoke.TokenId({tokenId: 0, active: true})
        });
        revokes[2] = IAutoRevoke.Revoke({
            target: address(erc1155s[0]),
            spender: JUNK,
            tokenId: IAutoRevoke.TokenId({tokenId: 0, active: false})
        });

        Execution[] memory executions = new Execution[](5);
        executions[0] = Execution({
            target: address(autoRevoke),
            value: 0,
            callData: abi.encodeWithSelector(AutoRevoke.toggleExcludedSpender.selector, JUNK, true)
        });
        executions[1] = Execution({
            target: address(erc20s[0]),
            value: 0,
            callData: abi.encodeWithSelector(IERC20.approve.selector, JUNK, 1000)
        });
        executions[2] = Execution({
            target: address(erc721s[0]),
            value: 0,
            callData: abi.encodeWithSelector(IERC721.approve.selector, JUNK, 0)
        });
        executions[3] = Execution({
            target: address(erc1155s[0]),
            value: 0,
            callData: abi.encodeWithSelector(IERC1155.setApprovalForAll.selector, JUNK, true)
        });
        executions[4] = Execution({
            target: address(autoRevoke),
            value: 0,
            callData: abi.encodeWithSelector(AutoRevoke.revoke.selector, revokes)
        });

        userOp.callData =
            abi.encodeCall(IERC7579Account.execute, (ModeLib.encodeSimpleBatch(), ExecutionLib.encodeBatch(executions)));

        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        // Expect ExcludedSpender event
        vm.expectEmit(true, true, false, true, address(autoRevoke));
        emit AutoRevoke.ExcludedSpender(account, JUNK, true);

        // Expect approval events (approvals are set but not auto-revoked due to excluded spender)
        vm.expectEmit(true, true, false, true, address(erc20s[0]));
        emit IERC20.Approval(account, JUNK, 1000);

        vm.expectEmit(true, true, true, true, address(erc721s[0]));
        emit IERC721.Approval(account, JUNK, 0);

        vm.expectEmit(true, true, false, true, address(erc1155s[0]));
        emit IERC1155.ApprovalForAll(account, JUNK, true);

        // Expect revoke events from manual revoke call
        vm.expectEmit(true, true, false, true, address(erc20s[0]));
        emit IERC20.Approval(account, JUNK, 0);

        vm.expectEmit(true, true, true, true, address(autoRevoke));
        emit AutoRevoke.Revoked(account, address(erc20s[0]), JUNK);

        vm.expectEmit(true, true, true, true, address(erc721s[0]));
        emit IERC721.Approval(account, address(0), 0);

        vm.expectEmit(true, true, true, true, address(autoRevoke));
        emit AutoRevoke.Revoked(account, address(erc721s[0]), JUNK);

        vm.expectEmit(true, true, false, true, address(erc1155s[0]));
        emit IERC1155.ApprovalForAll(account, JUNK, false);

        vm.expectEmit(true, true, true, true, address(autoRevoke));
        emit AutoRevoke.Revoked(account, address(erc1155s[0]), JUNK);

        entrypoint.handleOps(userOps, payable(address(0x01)));

        // Assert all approvals have been revoked
        assertEq(erc20s[0].allowance(account, JUNK), 0, "ERC20 approval should be revoked");
        assertEq(erc721s[0].getApproved(0), address(0), "ERC721 approval should be revoked");
        assertFalse(erc1155s[0].isApprovedForAll(account, JUNK), "ERC1155 approval should be revoked");
    }
}
