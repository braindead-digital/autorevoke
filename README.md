#### ⚠️Warning: AutoRevoke, while designed with security in mind and considering user safety, has not been formally audited and the use of AutoRevoke is at the user's risk.
# AutoRevoke

An ERC7579-compliant hook and executor module that automatically revokes token approvals (ERC20, ERC721, ERC1155) after transaction execution.

## Overview

AutoRevoke protects smart accounts by automatically revoking approvals once a transaction completes. This prevents lingering approvals that could be exploited later.

## Batch Revoke

AutoRevoke also provides an interface for batch-revoking approvals from ERC7579 accounts, without needing to add AutoRevoke as a hook, and just an executor. This can be used to simplify and standardize batch-revoke applications.

## Installation

On installing the module, you have three options of what data to pass into the onInstall:

Value | Effect
------|-------
0x00 | Registration as a hook with default config
0x01 -> 0x0F | Registration as a hook with custom config
0xFF | Registration as an executor

### Installation workflow

Two interactions are needed for installation as a hook:
1) Installation as a hook (with initData as the config)
2) Installation as an executor (with initData as 0xFF to prevent failure)

And for installation as just an executor, omit the first interaction.

## Concepts
### Configuration

The module uses a configuration byte where:
- Bit 0 (0x01): Revoke ERC20 approvals
- Bit 1 (0x02): Revoke ERC721 approvals
- Bit 2 (0x04): Revoke ERC1155 approvals
- Bit 3 (0x08): Enable single-call mode (batch mode is default)

Default config is `0x01` (ERC20 only, batch mode).

A user can change their config after install.

#### Illustrated

An empty `bytes1` in Solidity can be illustrated as such:
```
0000 0000
```

A byte is comprised of two nibbles (`0000`) and for our configuration byte, we use only the first (right-most) nibble. Any higher value will fail when the hook is added.

We can re-visualize the configuration byte spec as follows (displaying only the used nibble):

```
0000
^--- Setting this bit to 1 will enable AutoRevoke on single calls
-^-- Setting this bit to 1 will enable AutoRevoke for ERC1155 tokens (only if ERC165-compliant)
--^- Setting this bit to 1 will enable AutoRevoke for ERC721 tokens (only if ERC165-compliant)
---^ Setting this bit to 1 will enable AutoRevoke for ERC20 tokens
```

Using this, we can for example say that a user wants to:
- Auto revoke ERC20 approvals,
- Auto revoke ERC1155 approvals,
- In batch mode

Their config would be: `0101` or in hex: `0x05`.

As another example, we can say that a user wants to:
- Auto revoke ERC20 approvals,
- Auto revoke ERC721 approvals,
- In both batch and single mode

Their config would be: `1011` or in hex: `0x0B`

### Excluded Spenders

Users can set spenders that will not have their approvals revoked, this can be useful in the case of marketplaces, escrow tools, etc.

## Features

- Exclude specific spenders from auto-revoke (useful for trusted protocols)
- Manual batch revoke via `revoke()`
- Works as both Hook (type 4) and Executor (type 2)

## Usage

```shell
forge build
forge test
```

## Author

z (@zisbraindead) for Braindead Digital (@braindeaddgtl)
