//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IERC7629.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

abstract contract ERC7629 is IERC7629 {
    // ERC-721 related errors
    error ERC721InvalidApprover();
    error ERC721InvalidOperator();
    error ERC721InvalidSender();
    error ERC721InvalidReceiver();
    error ERC721IncorrectOwner();
    error ERC721NonexistentToken();
    error ERC721AccountBalanceOverflow();

    // ERC-20 related errors
    error TotalSupplyOverflow();
    error ERC20InvalidSpender();
    error ERC20InsufficientAllowance();
    error ERC20InvalidSender();
    error ERC20InvalidReceiver();
    error ERC20InsufficientBalance();

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    // Token decimals
    uint8 private immutable _decimals;

    // Token unit (for ERC-20 conversion)
    uint256 private immutable _units;

    /// @dev The balance slot of `owner` is given by:
    /// ```
    ///     mstore(0x0c, _ERC20_BALANCE_SLOT_SEED)
    ///     mstore(0x00, owner)
    ///     let balanceSlot := keccak256(0x0c, 0x20)
    /// ```
    uint256 private constant _ERC20_BALANCE_SLOT_SEED = 0xa37c0223;

    /// @dev The allowance slot of (`owner`, `spender`) is given by:
    /// ```
    ///     mstore(0x20, spender)
    ///     mstore(0x0c, _ERC20_ALLOWANCE_SLOT_SEED)
    ///     mstore(0x00, owner)
    ///     let allowanceSlot := keccak256(0x0c, 0x34)
    /// ```
    uint256 private constant _ERC20_ALLOWANCE_SLOT_SEED = 0xb9f3e18c;

    // Storage slot for the total supply of ERC-20 tokens
    uint256 private constant _TOTAL_SUPPLY_SLOT = 0x05345cdf77eb68f44c;

    /// @dev An account can hold up to 4294967295 tokens.
    uint256 internal constant _MAX_ACCOUNT_BALANCE = 0xffffffff;

    // ERC-721 balance mapping
    /// @dev The ownership data slot of `id` is given by:
    /// ```
    ///     mstore(0x00, id)
    ///     mstore(0x1c, _ERC721_MASTER_SLOT_SEED)
    ///     let ownershipSlot := add(id, add(id, keccak256(0x00, 0x20)))
    /// ```
    /// Bits Layout:
    /// - [0..159]   `addr`
    /// - [160..255] `extraData`
    ///
    /// The approved address slot is given by: `add(1, ownershipSlot)`.
    ///
    /// See: https://notes.ethereum.org/%40vbuterin/verkle_tree_eip
    ///
    /// The balance slot of `owner` is given by:
    /// ```
    ///     mstore(0x1c, _ERC721_MASTER_SLOT_SEED)
    ///     mstore(0x00, owner)
    ///     let balanceSlot := keccak256(0x0c, 0x1c)
    /// ```
    /// Bits Layout:
    /// - [0..31]   `balance`
    /// - [32..255] `aux`
    ///
    /// The `operator` approval slot of `owner` is given by:
    /// ```
    ///     mstore(0x1c, or(_ERC721_MASTER_SLOT_SEED, operator))
    ///     mstore(0x00, owner)
    ///     let operatorApprovalSlot := keccak256(0x0c, 0x30)
    /// ```
    uint256 private constant _ERC721_MASTER_SLOT_SEED = 0x7d8825530a5a2e7a << 192;

    /// @dev Pre-shifted and pre-masked constant.
    uint256 private constant _ERC721_MASTER_SLOT_SEED_MASKED = 0x0a5a2e7a00000000;

    /// @dev The owned data slot seed for ERC-721 tokens. Original tokenIds uint256[].
    /// The first slot is given by:
    /// ```
    ///    mstore(0x1c, _ERC721_OWNED_SLOT_SEED)
    ///    mstore(0x00, owner)
    ///    let firstSlot := keccak256(0x1c, 0x20)
    /// ```
    ///
    /// Additional tokenIds are stored in subsequent slots.
    /// Take the first slot and add the index to get the subsequent slots.
    /// ```
    ///    let tokenIdSlot := add(firstSlot, index)
    /// ```
    uint256 private constant _ERC721_OWNED_SLOT_SEED = 0xaad1f1e3d5ff0d06;

    /// @dev The owned index slot seed for ERC-721 tokens.
    /// The owned index slot is given by:
    /// ```
    ///    mstore(0x1c, _ERC721_OWNED_INDEX_SLOT_SEED)
    ///    mstore(0x00, tokenId)
    ///    let indexSlot := keccak256(0x0c, 0x1c)
    /// ```
    uint256 private constant _ERC721_OWNED_INDEX_SLOT_SEED = 0x70c5f0ea1f688ebb;

    // Counter for minted ERC-721 tokens
    uint256 public minted;

    /**
     * @dev Constructor for the ERC-7629 Hybrid Token.
     * @param name_ The name of the token.
     * @param symbol_ The symbol of the token.
     * @param decimals_ The number of decimals used in the token.
     * @param units_ The unit value for ERC-20 conversion.
     */
    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 units_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        _units = units_ * 10 ** _decimals;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used in the token.
     */
    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }

    /**
     * @dev Returns the total supply of the ERC-20 tokens.
     */
    function totalSupply() public view virtual returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := sload(_TOTAL_SUPPLY_SLOT)
        }
    }

    /**
     * @dev Returns the balance of an address for ERC-20 tokens.
     * @param owner The address to query the balance of.
     */
    function balanceOf(address owner) public view virtual returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x0c, _ERC20_BALANCE_SLOT_SEED)
            mstore(0x00, owner)
            result := sload(keccak256(0x0c, 0x20))
        }
    }

    /**
     * @dev Returns the total supply of ERC-20 tokens.
     */
    function erc20TotalSupply() external view returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := sload(_TOTAL_SUPPLY_SLOT)
        }
    }

    /**
     * @dev Returns the balance of an address for ERC-20 tokens.
     * @param owner The address to query the balance of.
     */
    function erc20BalanceOf(address owner) external view returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x0c, _ERC20_BALANCE_SLOT_SEED)
            mstore(0x00, owner)
            result := sload(keccak256(0x0c, 0x20))
        }
    }

    /**
     * @dev Returns the total supply of ERC-721 tokens.
     */
    function erc721TotalSupply() external view returns (uint256) {
        return minted;
    }

    /**
     * @dev Returns the balance of an address for ERC-721 tokens.
     * @param owner The address to query the balance of.
     */
    function erc721BalanceOf(address owner) external view returns (uint256) {
        return _erc721BalanceOf(owner);
    }

    /**
     * @dev Returns the balance of an address for ERC-721 tokens.
     * @param owner The address to query the balance of.
     */
    function _erc721BalanceOf(address owner) public view returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            // Revert if the `owner` is the zero address.
            if iszero(owner) {
                mstore(0x00, 0x8f4eb604) // `BalanceQueryForZeroAddress()`.
                revert(0x1c, 0x04)
            }
            mstore(0x1c, _ERC721_MASTER_SLOT_SEED)
            mstore(0x00, owner)
            result := and(sload(keccak256(0x0c, 0x1c)), _MAX_ACCOUNT_BALANCE)
        }
    }

    /**
     * @dev Checks if an operator is approved for all tokens of a given owner.
     * @param owner The address of the token owner.
     * @param operator The address of the operator to check.
     */
    function isApprovedForAll(address owner, address operator) public view returns (bool result) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x1c, operator)
            mstore(0x08, _ERC721_MASTER_SLOT_SEED_MASKED)
            mstore(0x00, owner)
            result := sload(keccak256(0x0c, 0x30))
        }
    }

    /**
     * @dev Returns the remaining number of tokens that spender will be allowed to spend on behalf of owner.
     * @param owner The address of the token owner.
     * @param spender The address of the spender.
     */
    function allowance(address owner, address spender) public view returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x20, spender)
            mstore(0x0c, _ERC20_ALLOWANCE_SLOT_SEED)
            mstore(0x00, owner)
            result := sload(keccak256(0x0c, 0x34))
        }
    }

    /**
     * @dev Returns the array of ERC-721 token IDs owned by a specific address.
     * @param owner The address to query the tokens of.
     */
    function owned(address owner) external view returns (uint256[] memory result) {
        uint256 tokenCount = _erc721BalanceOf(owner);

        result = new uint256[](tokenCount);

        assembly {
            // Setup for the first slot calculation
            mstore(0x1c, _ERC721_OWNED_SLOT_SEED)
            mstore(0x00, owner)
            let firstSlot := keccak256(0x1c, 0x20)

            // Iterate over each token owned by the owner, starting from the first token
            for { let i := 0x0 } lt(i, tokenCount) { i := add(i, 0x1) } {
                // For each subsequent token, calculate its slot based on the firstSlot and index
                let tokenIdSlot := add(firstSlot, i)

                // Retrieve the tokenId from the calculated slot and store it in the memory array
                mstore(add(result, add(0x20, mul(i, 0x20))), sload(tokenIdSlot))
            }
        }
    }

    /**
     * @dev Returns the address that owns a specific ERC-721 token.
     * @param tokenId The token ID.
     */
    function ownerOf(uint256 tokenId) public view returns (address result) {
        result = _ownerOf(tokenId);
        /// @solidity memory-safe-assembly
        assembly {
            if iszero(result) {
                mstore(0x00, 0x52f4210a) // `ERC721NonexistentToken()`.
                revert(0x1c, 0x04)
            }
        }
    }

    /// @dev Returns the owner of token `id`.
    /// Returns the zero address instead of reverting if the token does not exist.
    function _ownerOf(uint256 tokenId) internal view virtual returns (address result) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, tokenId)
            mstore(0x1c, _ERC721_MASTER_SLOT_SEED)
            result := shr(96, shl(96, sload(add(tokenId, add(tokenId, keccak256(0x00, 0x20))))))
        }
    }

    /**
     * @dev Approve or disapprove the operator to spend or transfer all of the sender's tokens.
     * @param spender The address of the spender.
     * @param amountOrId The amount of ERC-20 tokens or ID of ERC-721 tokens.
     */
    function approve(address spender, uint256 amountOrId) external returns (bool) {
        if (amountOrId > 0 && amountOrId <= minted) {
            _erc721Approve(spender, amountOrId);
        } else {
            return _erc20Approve(spender, amountOrId);
        }
        return true;
    }

    /**
     * @dev Approve the specified address to spend the specified amount of tokens on behalf of the sender.
     * @param spender The address to be approved.
     * @param value The amount of tokens to be approved for spending.
     * @return True if the approval was successful.
     */
    function _erc20Approve(address spender, uint256 value) internal returns (bool) {
        /// @solidity memory-safe-assembly
        assembly {
            if iszero(spender) {
                mstore(0x00, 0xdeed3d66) // `ERC20InvalidSpender()`.
                revert(0x1c, 0x04)
            }

            // Compute the allowance slot and store the value.
            mstore(0x20, spender)
            mstore(0x0c, _ERC20_ALLOWANCE_SLOT_SEED)
            mstore(0x00, caller())
            sstore(keccak256(0x0c, 0x34), value)
        }

        emit Approval(msg.sender, spender, value);
        emit ERC20Approval(msg.sender, spender, value);

        return true;
    }

    /**
     * @dev Approve the specified address to spend the specified ERC-721 token on behalf of the sender.
     * @param spender The address to be approved.
     * @param tokenId The ID of the ERC-721 token to be approved.
     */
    function _erc721Approve(address spender, uint256 tokenId) internal {
        _approveERC721(spender, tokenId, msg.sender, true);
    }

    /**
     * @dev Internal function to handle ERC-721 approvals.
     * @param to The address to be approved.
     * @param tokenId The ID of the ERC-721 token to be approved.
     * @param auth The address authorizing the approval.
     * @param emitEvent A boolean indicating whether to emit the Approval event.
     */
    function _approveERC721(address to, uint256 tokenId, address auth, bool emitEvent) internal virtual {
        address owner;

        assembly {
            // Clear the upper 96 bits.
            let bitmaskAddress := shr(96, not(0))
            to := and(bitmaskAddress, to)
            auth := and(bitmaskAddress, auth)
            // Load the owner of the token.
            mstore(0x00, tokenId)
            mstore(0x1c, or(_ERC721_MASTER_SLOT_SEED, auth))
            let ownershipSlot := add(tokenId, add(tokenId, keccak256(0x00, 0x20)))
            owner := and(bitmaskAddress, sload(ownershipSlot))

            // If `auth` is not the zero address or emitEvent, do the authorization check.
            // Revert if `auth` is not the owner, nor approved.
            if or(iszero(iszero(emitEvent)), iszero(or(iszero(auth), eq(auth, owner)))) {
                mstore(0x1c, auth)
                mstore(0x08, _ERC721_MASTER_SLOT_SEED_MASKED)
                mstore(0x00, owner)

                // if (owner != auth && !isApprovedForAll(owner, auth))
                if and(iszero(eq(owner, auth)), iszero(sload(keccak256(0x0c, 0x30)))) {
                    mstore(0x00, 0xbd92be0e) // `ERC721InvalidApprover()`.
                    revert(0x1c, 0x04)
                }
            }
            // Sets `to` as the approved to to manage `tokenId`.
            sstore(add(1, ownershipSlot), to)
        }

        if (emitEvent) {
            emit Approval(owner, to, tokenId);
            emit ERC721Approval(owner, to, tokenId);
        }
    }

    /**
     * @dev Set or unset the approval of a given operator.
     * @param operator The address of the operator to approve or revoke.
     * @param approved A boolean indicating whether to approve or revoke the operator.
     */
    function setApprovalForAll(address operator, bool approved) external {
        /// @solidity memory-safe-assembly
        assembly {
            if iszero(operator) {
                mstore(0x00, 0x91d71e2f) // `ERC721InvalidOperator()`.
                revert(0x1c, 0x04)
            }

            // Convert to 0 or 1.
            approved := iszero(iszero(approved))
            // Update the `isApproved` for (`msg.sender`, `operator`).
            mstore(0x1c, operator)
            mstore(0x08, _ERC721_MASTER_SLOT_SEED_MASKED)
            mstore(0x00, caller())
            sstore(keccak256(0x0c, 0x30), approved)
        }
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /// @dev Returns the approved address for a token ID, or the zero address if no address is approved.
    function getApproved(uint256 tokenId) public view virtual returns (address result) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, tokenId)
            mstore(0x1c, _ERC721_MASTER_SLOT_SEED)
            let ownershipSlot := add(tokenId, add(tokenId, keccak256(0x00, 0x20)))
            if iszero(shl(96, sload(ownershipSlot))) {
                mstore(0x00, 0x52f4210a) // `ERC721NonexistentToken()`.
                revert(0x1c, 0x04)
            }
            result := sload(add(1, ownershipSlot))
        }
    }

    /**
     * @dev Transfers a token from one address to another, checking if the recipient is a smart contract.
     * @param from The address to transfer the token from.
     * @param to The address to transfer the token to.
     * @param tokenId The ID of the token to transfer.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) public {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev Transfers a token from one address to another, checking if the recipient is a smart contract.
     * @param from The address to transfer the token from.
     * @param to The address to transfer the token to.
     * @param tokenId The ID of the token to transfer.
     * @param data Additional data with no specified format, sent in call to `to`.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public virtual {
        transferFrom(from, to, tokenId);
        _checkOnERC721Received(from, to, tokenId, data);
    }

    /**
     * @dev Checks if the recipient is a smart contract by calling onERC721Received, if implemented.
     * @param from The address from which the token is transferred.
     * @param to The address to which the token is transferred.
     * @param tokenId The ID of the token being transferred.
     * @param data Additional data with no specified format, sent in call to `to`.
     * @notice Throws an error if the recipient is a smart contract and does not implement onERC721Received.
     */
    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory data) private {
        if (to.code.length > 0) {
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
                if (retval != IERC721Receiver.onERC721Received.selector) {
                    /// @solidity memory-safe-assembly
                    assembly {
                        mstore(0x00, 0xb2e2a9c1) // `ERC721InvalidReceiver()`.
                        revert(0x1c, 0x04)
                    }
                }
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    /// @solidity memory-safe-assembly
                    assembly {
                        mstore(0x00, 0xb2e2a9c1) // `ERC721InvalidReceiver()`.
                        revert(0x1c, 0x04)
                    }
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        }
    }

    /**
     * @dev Transfer tokens or NFTs from one address to another.
     * @param from The address to transfer from.
     * @param to The address to transfer to.
     * @param amountOrId The amount of tokens (for ERC-20) or the ID of the NFT (for ERC-721) to transfer.
     * @return True if the transfer was successful.
     */
    function transferFrom(address from, address to, uint256 amountOrId) public returns (bool) {
        if (amountOrId <= minted) {
            _erc721TransferFrom(from, to, amountOrId);
        } else {
            return _erc20TransferFrom(from, to, amountOrId);
        }

        return true;
    }

    /**
     * @dev Internal function to handle ERC-20 transfers.
     * @param from The address to transfer tokens from.
     * @param to The address to transfer tokens to.
     * @param value The amount of tokens to transfer.
     * @return True if the transfer was successful.
     */
    function _erc20TransferFrom(address from, address to, uint256 value) internal returns (bool) {
        /// @solidity memory-safe-assembly
        assembly {
            let spender := caller()

            // Compute the allowance slot and load its value.
            mstore(0x20, spender)
            mstore(0x0c, _ERC20_ALLOWANCE_SLOT_SEED)
            mstore(0x00, from)
            let allowanceSlot := keccak256(0x0c, 0x34)
            let allowance_ := sload(allowanceSlot)
            // If the allowance is not the maximum uint256 value.
            if add(allowance_, 1) {
                // Revert if the value to be transferred exceeds the allowance.
                if gt(value, allowance_) {
                    mstore(0x00, 0x2fc50d60) // `ERC20InsufficientAllowance()`.
                    revert(0x1c, 0x04)
                }
                // Subtract and store the updated allowance.
                sstore(allowanceSlot, sub(allowance_, value))
            }
        }
        _transferERC20(from, to, value);
        return true;
    }

    /**
     * @dev Internal function to handle ERC-20 transfers.
     * @param from The address to transfer tokens from.
     * @param to The address to transfer tokens to.
     * @param value The amount of tokens to transfer.
     */
    function _transferERC20(address from, address to, uint256 value) internal {
        /// @solidity memory-safe-assembly
        assembly {
            if iszero(from) {
                mstore(0x00, 0x5b168993) // `ERC20InvalidSender()`.
                revert(0x1c, 0x04)
            }
            if iszero(to) {
                mstore(0x00, 0x04786ad1) // `ERC20InvalidReceiver()`.
                revert(0x1c, 0x04)
            }
        }

        _updateERC20(from, to, value);
    }

    /**
     * @dev Updates ERC-20 token balances during a transfer.
     * @param from The address from which tokens are transferred.
     * @param to The address to which tokens are transferred.
     * @param value The amount of ERC-20 tokens to transfer.
     * @notice Handles minting and burning tokens, preventing overflow and emitting transfer events.
     */
    function _updateERC20(address from, address to, uint256 value) internal virtual {
        /// @solidity memory-safe-assembly
        assembly {
            switch iszero(from)
            case 1 {
                // Overflow check required: The rest of the code assumes that totalSupply never overflows
                let totalSupplyBefore := sload(_TOTAL_SUPPLY_SLOT)
                let totalSupplyAfter := add(totalSupplyBefore, value)
                // Revert if the total supply overflows.
                if lt(totalSupplyAfter, totalSupplyBefore) {
                    mstore(0x00, 0xe5cfe957) // `TotalSupplyOverflow()`.
                    revert(0x1c, 0x04)
                }
                // Store the updated total supply.
                sstore(_TOTAL_SUPPLY_SLOT, totalSupplyAfter)
            }
            default {
                mstore(0x0c, _ERC20_BALANCE_SLOT_SEED)
                mstore(0x00, from)

                let fromBalanceSlot := keccak256(0x0c, 0x20)
                let fromBalance := sload(fromBalanceSlot)

                if gt(value, fromBalance) {
                    let ptr := mload(0x40)
                    mstore(0x00, 0x590b7c5c) // `ERC20InsufficientBalance()`.
                    revert(0x1c, 0x04)
                }

                // Overflow not possible: value <= fromBalance <= totalSupply.
                // Subtract and store the updated balance.
                sstore(fromBalanceSlot, sub(fromBalance, value))
            }

            switch iszero(to)
            case 1 {
                // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply.
                sstore(_TOTAL_SUPPLY_SLOT, sub(sload(_TOTAL_SUPPLY_SLOT), value))
            }
            default {
                // Compute the balance slot of `to`.
                mstore(0x0c, _ERC20_BALANCE_SLOT_SEED)
                mstore(0x00, to)
                let toBalanceSlot := keccak256(0x0c, 0x20)
                // Add and store the updated balance of `to`.
                // Will not overflow because the sum of all user balances
                // cannot exceed the maximum uint256 value.
                sstore(toBalanceSlot, add(sload(toBalanceSlot), value))
            }
        }

        emit ERC20Transfer(from, to, value);
    }

    /**
     * @dev Transfer ERC-721 token from one address to another.
     * @param from The address to transfer ERC-721 token from.
     * @param to The address to transfer ERC-721 token to.
     * @param tokenId The ID of the ERC-721 token to transfer.
     */
    function _erc721TransferFrom(address from, address to, uint256 tokenId) internal {
        /// @solidity memory-safe-assembly
        assembly {
            if iszero(to) {
                mstore(0x00, 0xb2e2a9c1) // `ERC721InvalidReceiver()`.
                revert(0x1c, 0x04)
            }
        }

        address previousOwner = _updateERC721(to, tokenId);

        /// @solidity memory-safe-assembly
        assembly {
            if iszero(previousOwner) {
                mstore(0x00, 0x52f4210a) // `ERC721NonexistentToken()`.
                revert(0x1c, 0x04)
            }
            if iszero(eq(previousOwner, from)) {
                mstore(0x00, 0x4829a139) // `ERC721IncorrectOwner()`.
                revert(0x1c, 0x04)
            }
        }
    }

    /**
     * @dev Updates the ownership of an ERC-721 token during a transfer.
     * @param to The address to which the token is being transferred.
     * @param tokenId The ID of the ERC-721 token being transferred.
     * @notice Clears approval, updates balances, and emits transfer events.
     * @notice will return the previous owner of the token
     */
    function _updateERC721(address to, uint256 tokenId) internal virtual returns (address from) {
        /// @solidity memory-safe-assembly
        assembly {
            // Set slot seed for further calculations.
            mstore(0x1c, _ERC721_MASTER_SLOT_SEED)

            // Clear the upper 96 bits.
            let bitmaskAddress := shr(96, not(0))
            to := and(bitmaskAddress, to)

            // Load the ownership data.
            mstore(0x00, tokenId)
            mstore(0x1c, or(_ERC721_MASTER_SLOT_SEED, caller()))
            let ownershipSlot := add(tokenId, add(tokenId, keccak256(0x00, 0x20)))
            let ownershipPacked := sload(ownershipSlot)
            from := and(bitmaskAddress, ownershipPacked)

            // if from is not 0
            if iszero(iszero(from)) {
                // Clear approval. No need to re-authorize or emit the Approval event
                // Delete the approved address if any.
                if sload(add(1, ownershipSlot)) { sstore(add(1, ownershipSlot), 0) }

                // Decrement the balance of `from`.
                {
                    mstore(0x1c, _ERC721_MASTER_SLOT_SEED)
                    mstore(0x00, from)
                    let fromBalanceSlot := keccak256(0x0c, 0x1c)
                    sstore(fromBalanceSlot, sub(sload(fromBalanceSlot), 1))
                    let fromBalance := sload(fromBalanceSlot)

                    // update tokenIds array
                    // the tokenIndex will be the from balance as it has been decremented
                    mstore(0x1c, _ERC721_OWNED_SLOT_SEED)
                    mstore(0x00, from)
                    let firstSlot := keccak256(0x1c, 0x20)
                    let updatedIdSlot := add(firstSlot, fromBalance)
                    let updatedId := sload(updatedIdSlot)

                    // replace the old tokenId with the updatedId(last tokenId in the array)
                    if iszero(eq(updatedId, tokenId)) {
                        // get original tokenId index
                        mstore(0x1c, _ERC721_OWNED_INDEX_SLOT_SEED)
                        mstore(0x00, tokenId)
                        let ownedIndexSlot := keccak256(0x1c, 0x20)
                        let tokenIdOwnedIndex := sload(ownedIndexSlot)

                        // replace the tokenId with the updatedId
                        let tokenIdSlot := add(firstSlot, tokenIdOwnedIndex)
                        sstore(tokenIdSlot, updatedId)

                        // update the index of the updatedId
                        mstore(0x00, updatedId)
                        ownedIndexSlot := keccak256(0x1c, 0x20)
                        sstore(ownedIndexSlot, tokenIdOwnedIndex)
                    }
                }
            }

            // if to is not 0
            if iszero(iszero(to)) {
                // Increment the balance of `to`.
                {
                    mstore(0x1c, _ERC721_MASTER_SLOT_SEED)
                    mstore(0x00, to)
                    let toBalanceSlot := keccak256(0x0c, 0x1c)
                    let toBalance := sload(toBalanceSlot)
                    let toBalanceSlotPacked := add(toBalance, 1)

                    // Revert if the account balance overflows.
                    if iszero(and(toBalanceSlotPacked, _MAX_ACCOUNT_BALANCE)) {
                        mstore(0x00, 0x56f42d6e) // `ERC721AccountBalanceOverflow()`.
                        revert(0x1c, 0x04)
                    }
                    sstore(toBalanceSlot, toBalanceSlotPacked)

                    // update tokenIds array
                    // the tokenIndex will be the original toBalance before add as it has been incremented
                    mstore(0x1c, _ERC721_OWNED_SLOT_SEED)
                    mstore(0x00, to)
                    let firstSlot := keccak256(0x1c, 0x20)
                    let nextSlot := add(firstSlot, toBalance)
                    sstore(nextSlot, tokenId)

                    // update the index of the tokenId
                    mstore(0x1c, _ERC721_OWNED_INDEX_SLOT_SEED)
                    mstore(0x00, tokenId)
                    let ownedIndexSlot := keccak256(0x1c, 0x20)
                    sstore(ownedIndexSlot, toBalance)
                }
            }

            // Update with the new owner.
            sstore(ownershipSlot, xor(ownershipPacked, xor(from, to)))
        }

        emit ERC721Transfer(from, to, tokenId);
        emit Transfer(from, to, tokenId);

        return from;
    }

    /**
     * @dev Transfers ERC-20 tokens from one address to another.
     * @param to The address to transfer the tokens to.
     * @param amount The amount of ERC-20 tokens to transfer.
     * @return A boolean indicating success.
     * @notice Prevents burning tokens to address(0).
     */
    function transfer(address to, uint256 amount) external returns (bool) {
        _transferERC20(msg.sender, to, amount);
        return true;
    }

    /**
     * @dev Mints new ERC-20 tokens to the specified account.
     * @param account The account to which new ERC-20 tokens are minted.
     * @param value The amount of ERC-20 tokens to mint.
     * @notice Prevents minting tokens to address(0).
     */
    function _mintERC20(address account, uint256 value) internal {
        /// @solidity memory-safe-assembly
        assembly {
            if iszero(account) {
                mstore(0x00, 0x04786ad1) // `ERC20InvalidReceiver()`.
                revert(0x1c, 0x04)
            }
        }
        _updateERC20(address(0), account, value);
    }

    /**
     * @dev Burns ERC-20 tokens from the specified account.
     * @param account The account from which ERC-20 tokens are burned.
     * @param value The amount of ERC-20 tokens to burn.
     * @notice Prevents burning tokens from address(0).
     */
    function _burnERC20(address account, uint256 value) internal {
        /// @solidity memory-safe-assembly
        assembly {
            if iszero(account) {
                mstore(0x00, 0x5b168993) // `ERC20InvalidSender()`.
                revert(0x1c, 0x04)
            }
        }
        _updateERC20(account, address(0), value);
    }

    /**
     * @dev Mint a new ERC-721 token and assign ownership to the specified address.
     * @param to The address to receive the minted ERC-721 token.
     * @param tokenId The ID of the ERC-721 token to be minted.
     */
    function _mintERC721(address to, uint256 tokenId) internal {
        /// @solidity memory-safe-assembly
        assembly {
            if iszero(to) {
                mstore(0x00, 0xb2e2a9c1) // `ERC721InvalidReceiver()`.
                revert(0x1c, 0x04)
            }
        }

        address previousOwner = _updateERC721(to, tokenId);

        /// @solidity memory-safe-assembly
        assembly {
            if iszero(iszero(previousOwner)) {
                mstore(0x00, 0x73378f7d) // `ERC721InvalidSender()`.
                revert(0x1c, 0x04)
            }

            sstore(minted.slot, add(sload(minted.slot), 1))
        }
    }

    /**
     * @dev Burn an existing ERC-721 token, removing it from circulation.
     * @param tokenId The ID of the ERC-721 token to be burned.
     */
    function _burnERC721(uint256 tokenId) internal {
        address previousOwner = _updateERC721(address(0), tokenId);

        /// @solidity memory-safe-assembly
        assembly {
            if iszero(previousOwner) {
                mstore(0x00, 0x52f4210a) // `ERC721NonexistentToken()`.
                revert(0x1c, 0x04)
            }
        }
    }

    /**
     * @dev Converts ERC-721 token to ERC-20 tokens.
     * @param tokenId The unique identifier of the ERC-721 token.
     */
    function erc721ToERC20(uint256 tokenId) external {
        address from = msg.sender;
        address to = address(this);

        _erc721TransferFrom(from, to, tokenId);
        _mintERC20(from, _units);
        emit ERC721ToERC20(to, tokenId, _units);
    }

    /**
     * @dev Converts ERC-20 tokens to an ERC-721 token.
     * @param amount The amount of ERC-20 tokens to convert.
     */
    function erc20ToERC721(uint256 amount) external {
        uint256 nftAmount = amount / _units;

        _burnERC20(msg.sender, amount);

        uint256 amountSwappable = _erc721BalanceOf(address(this));
        uint256 nftMintAmount = amountSwappable < nftAmount ? nftAmount - amountSwappable : 0;
        uint256 nftTransferAmount = nftAmount - nftMintAmount;

        uint256[] memory tokenIds = new uint256[](nftAmount);

        for (uint256 i = 0; i < nftMintAmount; i++) {
            uint256 tokenId = minted + 1;
            _mintERC721(msg.sender, tokenId);
            tokenIds[i] = tokenId;
        }

        uint256 tokenCount = _erc721BalanceOf(address(this));
        for (uint256 i = 0; i < nftTransferAmount; i++) {
            uint256 tokenId = _getTokenIdAtIndex(address(this), tokenCount - i - 1);
            _updateERC721(msg.sender, tokenId);
            tokenIds[i + nftMintAmount] = tokenId;
        }
        emit ERC20ToERC721(msg.sender, amount, tokenIds);
    }

    /**
     * @dev Retrieves the unit value associated with the token.
     * @return The unit value.
     */
    function getUnit() external view returns (uint256) {
        return _units;
    }

    /**
     * @dev Checks if the contract supports a given interface.
     * @param interfaceId The interface identifier.
     * @return True if the contract supports the given interface, false otherwise.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IERC7629).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /**
     * @dev Get the token ID at the specified index in the array of tokens owned by the address.
     * @param owner The address to query the tokens of.
     * @param index The index of the token in the array.
     * @notice Return the last token ID owned by the address.
     */
    function _getTokenIdAtIndex(address owner, uint256 index) internal view returns (uint256 tokenId) {
        assembly {
            // Setup for the first slot calculation
            mstore(0x1c, _ERC721_OWNED_SLOT_SEED)
            mstore(0x00, owner)
            let firstSlot := keccak256(0x1c, 0x20)

            // Get the last token ID owned by the owner
            tokenId := sload(add(firstSlot, index))
        }
    }
}
