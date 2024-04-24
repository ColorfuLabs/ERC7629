pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC7629Mock} from "./mock/ERC7629Mock.sol";
import {ERC7629} from "../src/ERC7629.sol";
import {IERC7629} from "../src/interfaces/IERC7629.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";

abstract contract ERC721TokenReceiver {
    function onERC721Received(address, address, uint256, bytes calldata) external virtual returns (bytes4) {
        return ERC721TokenReceiver.onERC721Received.selector;
    }
}

contract ERC721Recipient is ERC721TokenReceiver {
    address public operator;
    address public from;
    uint256 public id;
    bytes public data;

    function onERC721Received(address _operator, address _from, uint256 _id, bytes calldata _data)
        public
        virtual
        override
        returns (bytes4)
    {
        operator = _operator;
        from = _from;
        id = _id;
        data = _data;

        return ERC721TokenReceiver.onERC721Received.selector;
    }
}

contract RevertingERC721Recipient is ERC721TokenReceiver {
    error RevertFromERC721Received();

    function onERC721Received(address, address, uint256, bytes calldata) public virtual override returns (bytes4) {
        revert RevertFromERC721Received();
    }
}

contract WrongReturnDataERC721Recipient is ERC721TokenReceiver {
    function onERC721Received(address, address, uint256, bytes calldata) public virtual override returns (bytes4) {
        return 0xCAFEBEEF;
    }
}

contract NonERC721Recipient {}

contract ERC7629Test is Test {
    ERC7629Mock erc7629;

    function setUp() public {
        erc7629 = new ERC7629Mock("Test", "TST", 18, 10_000);
    }

    /* %=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*& */
    /*                        Common metadata                       */
    /* %=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*& */

    function test_name() public {
        string memory name = erc7629.name();
        assertEq(name, "Test");
    }

    function test_symbol() public {
        string memory symbol = erc7629.symbol();
        assertEq(symbol, "TST");
    }

    function test_decimals() public {
        uint8 decimals = erc7629.decimals();
        assertEq(decimals, 18);
    }

    /* %=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*& */
    /*                   ERC7629 specify functions                  */
    /* %=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*& */

    function test_get_uint() public {
        uint256 unit = erc7629.getUnit();
        uint256 expectedUnit = 10_000 * 10 ** 18;
        assertEq(unit, expectedUnit);
    }

    function test_erc20_to_erc721_with_0_minted() public {
        uint256 unit = erc7629.getUnit();
        uint256 expectedAmount = 1;
        uint256 amountToConvert = expectedAmount * unit;

        address user = address(0x1);

        erc7629.mintERC20(user, amountToConvert);

        vm.prank(user);
        erc7629.erc20ToERC721(amountToConvert);

        uint256[] memory tokenIds = erc7629.owned(user);
        uint256 tokenId = tokenIds[0];

        assertEq(tokenIds.length, 1);
        assertEq(tokenId, 1);

        uint256 balance = erc7629.erc20BalanceOf(user);

        assertEq(balance, 0);
    }

    function test_erc721_to_erc20() public {
        uint256 unit = erc7629.getUnit();
        uint256 tokenId = 1;

        address user = address(0x1);

        // mint erc271
        erc7629.mintERC721(user, tokenId);

        // convert single
        vm.prank(user);
        erc7629.erc721ToERC20(tokenId);

        uint256[] memory ownedTokenIds = erc7629.owned(user);
        uint256 balance = erc7629.erc20BalanceOf(user);

        assertEq(ownedTokenIds.length, 0);
        assertEq(balance, unit);

        // // contract erc721 vault checking
        uint256[] memory contractTokenIds = erc7629.owned(address(erc7629));
        uint256 contractTokenId = contractTokenIds[0];

        assertEq(contractTokenIds.length, 1);
        assertEq(contractTokenId, 1);
    }

    function test_erc20_to_erc721_batch_of_10_with_5_minted() public {
        uint256 unit = erc7629.getUnit();
        uint256 expectedAmount = 5;
        uint256 amountToConvert = expectedAmount * unit;

        address user = address(0x1);

        erc7629.mintERC20(user, amountToConvert);

        for (uint256 i = 1; i <= 5; i++) {
            erc7629.mintERC721(user, i);
            vm.prank(user);
            erc7629.erc721ToERC20(i);
        }

        vm.prank(user);
        erc7629.erc20ToERC721((expectedAmount + 5) * unit);

        uint256[] memory tokenIds = erc7629.owned(user);

        assertEq(tokenIds.length, 10);

        assertEq(tokenIds[0], 6);
        assertEq(tokenIds[1], 7);
        assertEq(tokenIds[2], 8);
        assertEq(tokenIds[3], 9);
        assertEq(tokenIds[4], 10);
        assertEq(tokenIds[5], 5);
        assertEq(tokenIds[6], 4);
        assertEq(tokenIds[7], 3);
        assertEq(tokenIds[8], 2);
        assertEq(tokenIds[9], 1);

        assertEq(erc7629.erc20BalanceOf(user), 0);
    }

    function test_erc20_to_erc721_with_insufficient_balance_reverts() public {
        uint256 unit = erc7629.getUnit();
        uint256 expectedAmount = 1;
        uint256 amountToConvert = expectedAmount * unit;

        address user = address(0x1);

        vm.expectRevert(ERC7629.ERC20InsufficientBalance.selector);
        vm.prank(user);
        erc7629.erc20ToERC721(amountToConvert);
    }

    function test_transfer_from_erc20_invalid_receiver_reverts() public {
        erc7629.mintERC20(address(0x1), 10_000);

        vm.prank(address(0x1));
        erc7629.approve(address(this), 10_000);

        vm.expectRevert(ERC7629.ERC20InvalidReceiver.selector);
        erc7629.transferFrom(address(0x1), address(0), 10_000);
    }

    // the following tests handles ERC7629 functions that implements ERC721
    // as the transfer flow includes, minting, approving and transferring
    // the approve implements _erc721TransferFrom
    // the transferFrom implements _erc721Approve
    function test_erc721_transfer_flow() public {
        uint256 tokenId = 1;
        address user = address(0x1);
        address spender = address(0x2);

        // mint erc271
        erc7629.mintERC721(user, tokenId);

        uint256 minted = erc7629.erc721TotalSupply();
        assertEq(minted, tokenId);

        uint256[] memory ownedTokenIds = erc7629.owned(user);
        uint256 ownedTokenId = ownedTokenIds[0];

        assertEq(ownedTokenIds.length, 1);
        assertEq(ownedTokenId, tokenId);

        address approved = erc7629.getApproved(tokenId);
        assertEq(approved, address(0));

        // approve
        vm.prank(user);
        erc7629.approve(spender, tokenId);

        // check approval
        approved = erc7629.getApproved(tokenId);
        assertEq(approved, spender);

        // transfer from
        vm.prank(spender);
        erc7629.transferFrom(user, spender, tokenId);

        approved = erc7629.getApproved(tokenId);
        assertEq(approved, address(0));

        // spender balance
        uint256[] memory spenderTokenIds = erc7629.owned(spender);
        uint256 spenderTokenId = spenderTokenIds[0];

        assertEq(spenderTokenIds.length, 1);
        assertEq(spenderTokenId, tokenId);

        // user balance
        ownedTokenIds = erc7629.owned(user);
        assertEq(ownedTokenIds.length, 0);
    }

    function test_erc721_transfer_flow_with_invalid_receiver_reverts() public {
        uint256 tokenId = 1;
        address user = address(0x1);
        address spender = address(0x2);

        // mint erc271
        erc7629.mintERC721(user, tokenId);

        vm.expectRevert(ERC7629.ERC721InvalidReceiver.selector);
        vm.prank(spender);
        erc7629.transferFrom(user, address(0), tokenId);
    }

    // the following tests handles ERC7629 functions that implements ERC20
    // as the transfer flow includes, minting, approving and transferring
    // the approve implements _erc20TransferFrom
    // the transferFrom implements _erc20Approve
    function test_erc20_transfer_flow() public {
        uint256 amount = 10_000 * 1e18;

        address user = address(0x1);
        address spender = address(0x2);

        // mint erc20
        erc7629.mintERC20(user, amount);

        // approve
        vm.prank(user);
        erc7629.approve(spender, amount);

        // check allowance
        assertEq(erc7629.allowance(user, spender), amount);

        // transfer from
        vm.prank(spender);
        erc7629.transferFrom(user, spender, amount);

        assertEq(erc7629.allowance(user, spender), 0);

        // spender balance
        assertEq(erc7629.erc20BalanceOf(spender), amount);

        // user balance
        assertEq(erc7629.erc20BalanceOf(user), 0);
    }

    /* %=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*& */
    /*                        ERC20 functions                       */
    /* %=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*& */

    function test_erc20_mint() public {
        uint256 amountToMint = 10_000;
        erc7629.mintERC20(address(0x1), amountToMint);

        assertEq(erc7629.erc20BalanceOf(address(0x1)), amountToMint);
        assertEq(erc7629.totalSupply(), amountToMint);
    }

    function test_erc20_mint_over_uint_reverts() public {
        erc7629.mintERC20(address(0x1), type(uint256).max);
        vm.expectRevert(ERC7629.TotalSupplyOverflow.selector);
        erc7629.mintERC20(address(0x1), 1);
    }

    function test_erc20_mint_to_0_reverts() public {
        vm.expectRevert(ERC7629.ERC20InvalidReceiver.selector);
        erc7629.mintERC20(address(0), 10_000);
    }

    function test_erc20_burn() public {
        uint256 amountToMint = 10_000;
        erc7629.mintERC20(address(0x1), amountToMint);

        erc7629.burnERC20(address(0x1), amountToMint);

        assertEq(erc7629.erc20BalanceOf(address(0x1)), 0);
    }

    function test_erc20_burn_from_0_reverts() public {
        vm.expectRevert(ERC7629.ERC20InvalidSender.selector);
        erc7629.burnERC20(address(0), 10_000);
    }

    function test_erc20_burn_with_insufficient_balance_reverts() public {
        uint256 amountToMint = 10_000;
        erc7629.mintERC20(address(0x1), amountToMint);

        vm.expectRevert(ERC7629.ERC20InsufficientBalance.selector);
        erc7629.burnERC20(address(0x1), amountToMint + 1);
    }

    function test_total_supply() public {
        uint256 totalSupply = erc7629.totalSupply();
        uint256 expectedTotalSupply = 0;
        assertEq(totalSupply, expectedTotalSupply);

        // mint 10_000 tokens
        uint256 amountToMint = 10_000;
        erc7629.mintERC20(address(0x1), amountToMint);

        totalSupply = erc7629.totalSupply();
        assertEq(totalSupply, amountToMint);
    }

    function test_erc20_total_supply() public {
        uint256 totalSupply = erc7629.erc20TotalSupply();
        uint256 expectedTotalSupply = 0;
        assertEq(totalSupply, expectedTotalSupply);

        // mint 10_000 tokens
        uint256 amountToMint = 10_000;
        erc7629.mintERC20(address(0x1), amountToMint);

        totalSupply = erc7629.erc20TotalSupply();
        assertEq(totalSupply, amountToMint);
    }

    function test_balance_of() public {
        uint256 balance = erc7629.balanceOf(address(0x1));
        uint256 expectedBalance = 0;
        assertEq(balance, expectedBalance);

        // mint 10_000 tokens
        uint256 amountToMint = 10_000;
        erc7629.mintERC20(address(0x1), amountToMint);

        balance = erc7629.balanceOf(address(0x1));
        assertEq(balance, amountToMint);
    }

    function test_transfer() public {
        uint256 amountToMint = 10_000;
        erc7629.mintERC20(address(0x1), amountToMint);

        vm.prank(address(0x1));
        erc7629.transfer(address(0x2), amountToMint);

        assertEq(erc7629.erc20BalanceOf(address(0x1)), 0);
        assertEq(erc7629.erc20BalanceOf(address(0x2)), amountToMint);
    }

    function test_transfer_with_insufficient_balance_reverts() public {
        uint256 amountToMint = 10_000;
        erc7629.mintERC20(address(0x1), amountToMint);

        vm.expectRevert(ERC7629.ERC20InsufficientBalance.selector);
        vm.prank(address(0x1));
        erc7629.transfer(address(0x2), amountToMint + 1);
    }

    function test_transfer_from_0_reverts() public {
        vm.expectRevert(ERC7629.ERC20InvalidSender.selector);
        vm.prank(address(0));
        erc7629.transfer(address(0x1), 10_000);
    }

    function test_transfer_to_0_reverts() public {
        uint256 amountToMint = 10_000;
        erc7629.mintERC20(address(0x1), amountToMint);

        vm.expectRevert(ERC7629.ERC20InvalidReceiver.selector);
        vm.prank(address(0x1));
        erc7629.transfer(address(0), amountToMint);
    }

    function test_erc20_approve() public {
        uint256 amountToMint = 10_000;
        erc7629.mintERC20(address(0x1), amountToMint);

        address spender = address(0x2);
        vm.prank(address(0x1));
        erc7629.erc20Approve(spender, amountToMint);

        assertEq(erc7629.allowance(address(0x1), spender), amountToMint);
    }

    function test_erc20_approve_with_invalid_spender_reverts() public {
        vm.expectRevert(ERC7629.ERC20InvalidSpender.selector);
        erc7629.erc20Approve(address(0), 10_000);
    }

    function test_erc20_transfer_from() public {
        uint256 amountToMint = 10_000 * 1e18;
        erc7629.mintERC20(address(0x1), amountToMint);

        vm.prank(address(0x1));
        erc7629.erc20Approve(address(this), amountToMint);

        erc7629.erc20TransferFrom(address(0x1), address(0x2), amountToMint);

        assertEq(erc7629.erc20BalanceOf(address(0x1)), 0);
        assertEq(erc7629.erc20BalanceOf(address(0x2)), amountToMint);
    }

    function test_erc20_transfer_from_with_insufficient_allowance_reverts() public {
        uint256 amountToMint = 10_000 * 1e18;
        erc7629.mintERC20(address(0x1), amountToMint);
        vm.expectRevert(ERC7629.ERC20InsufficientAllowance.selector);
        erc7629.erc20TransferFrom(address(0x1), address(0x2), amountToMint);
    }

    /* %=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*& */
    /*                        ERC721 functions                      */
    /* %=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*& */

    function test_erc721_mint() public {
        uint256 tokenId = 1;
        address owner = address(0x1);
        erc7629.mintERC721(owner, tokenId);

        uint256[] memory tokenIds = erc7629.owned(owner);
        assertEq(tokenIds.length, 1);
        assertEq(tokenIds[0], tokenId);

        assertEq(erc7629.ownerOf(tokenId), owner);
        assertEq(erc7629.erc721BalanceOf(owner), 1);
        assertEq(erc7629.erc721TotalSupply(), 1);
    }

    function test_erc721_mint_to_0_reverts() public {
        vm.expectRevert(ERC7629.ERC721InvalidReceiver.selector);
        erc7629.mintERC721(address(0), 1);
    }

    function test_erc721_mint_minted_token_reverts() public {
        erc7629.mintERC721(address(0x1), 1);
        vm.expectRevert(ERC7629.ERC721InvalidSender.selector);
        erc7629.mintERC721(address(0x1), 1);
    }

    function test_erc721_total_supply() public {
        uint256 totalSupply = erc7629.erc721TotalSupply();
        uint256 expectedTotalSupply = 0;
        assertEq(totalSupply, expectedTotalSupply);

        uint256 tokenId = 1;
        erc7629.mintERC721(address(0x1), tokenId);

        totalSupply = erc7629.erc721TotalSupply();
        expectedTotalSupply = 1;
        assertEq(totalSupply, expectedTotalSupply);

        tokenId = 2;
        erc7629.mintERC721(address(0x1), tokenId);

        totalSupply = erc7629.erc721TotalSupply();
        expectedTotalSupply = 2;
        assertEq(totalSupply, expectedTotalSupply);
    }

    function test_erc721_balance_of() public {
        uint256 balance = erc7629.erc721BalanceOf(address(0x1));
        uint256 expectedBalance = 0;
        assertEq(balance, expectedBalance);

        uint256 tokenId = 1;
        erc7629.mintERC721(address(0x1), tokenId);

        balance = erc7629.erc721BalanceOf(address(0x1));
        expectedBalance = 1;
        assertEq(balance, expectedBalance);

        tokenId = 2;
        erc7629.mintERC721(address(0x1), tokenId);

        balance = erc7629.erc721BalanceOf(address(0x1));
        expectedBalance = 2;
        assertEq(balance, expectedBalance);
    }

    function test_erc721_owned() public {
        uint256 tokenId = 1;
        erc7629.mintERC721(address(0x1), tokenId);

        uint256[] memory tokenIds = erc7629.owned(address(0x1));
        assertEq(tokenIds.length, 1);
        assertEq(tokenIds[0], tokenId);

        tokenId = 2;
        erc7629.mintERC721(address(0x1), tokenId);

        tokenIds = erc7629.owned(address(0x1));
        assertEq(tokenIds.length, 2);
        assertEq(tokenIds[0], 1);
        assertEq(tokenIds[1], 2);
    }

    function test_erc721_owner_of() public {
        uint256 tokenId = 1;
        address owner = address(0x1);
        erc7629.mintERC721(owner, tokenId);

        address tokenOwner = erc7629.ownerOf(tokenId);
        assertEq(tokenOwner, owner);
    }

    function test_get_approved_with_non_exist_token() public {
        vm.expectRevert(ERC7629.ERC721NonexistentToken.selector);
        erc7629.getApproved(1);
    }

    function test_erc721_approve() public {
        uint256 tokenId = 1;
        address owner = address(0x1);
        address spender = address(0x2);
        erc7629.mintERC721(owner, tokenId);

        address approved = erc7629.getApproved(tokenId);
        assertEq(approved, address(0));

        vm.prank(owner);
        erc7629.erc721Approve(spender, tokenId);

        approved = erc7629.getApproved(tokenId);
        assertEq(approved, spender);
    }

    function test_erc721_approve_with_invalid_approver_reverts() public {
        erc7629.mintERC721(address(0x1), 1);

        vm.expectRevert(ERC7629.ERC721InvalidApprover.selector);
        erc7629.erc721Approve(address(0x2), 1);
    }

    function test_set_approval_for_all() public {
        address owner = address(0x1);
        address operator = address(0x2);

        bool isApproved = erc7629.isApprovedForAll(owner, operator);
        assertEq(isApproved, false);

        vm.prank(owner);
        erc7629.setApprovalForAll(operator, true);

        isApproved = erc7629.isApprovedForAll(owner, operator);
        assertEq(isApproved, true);
    }

    function test_set_approval_for_all_with_invalid_operator_reverts() public {
        vm.expectRevert(ERC7629.ERC721InvalidOperator.selector);
        erc7629.setApprovalForAll(address(0), true);
    }

    function test_erc721_transfer_from() public {
        address from = address(0x1);
        address to = address(0x2);

        erc7629.mintERC721(from, 1);
        erc7629.mintERC721(from, 2);

        vm.prank(from);
        erc7629.erc721TransferFrom(from, to, 1);

        assertEq(erc7629.ownerOf(1), to);
        assertEq(erc7629.erc721BalanceOf(from), 1);
        assertEq(erc7629.erc721BalanceOf(to), 1);
    }

    function test_erc721_transfer_from_by_operator() public {
        address from = address(0x1);
        address to = address(0x2);

        erc7629.mintERC721(from, 1);

        vm.prank(from);
        erc7629.setApprovalForAll(address(this), true);

        erc7629.erc721TransferFrom(from, to, 1);

        assertEq(erc7629.ownerOf(1), to);
        assertEq(erc7629.erc721BalanceOf(from), 0);
        assertEq(erc7629.erc721BalanceOf(to), 1);
    }

    function test_erc721_transfer_from_non_exist_token_reverts() public {
        vm.expectRevert(ERC7629.ERC721NonexistentToken.selector);
        erc7629.erc721TransferFrom(address(0x1), address(0x2), 1);
    }

    function test_erc721_transfer_from_incorrect_owner_reverts() public {
        erc7629.mintERC721(address(0x1), 1);
        vm.expectRevert(ERC7629.ERC721IncorrectOwner.selector);
        erc7629.erc721TransferFrom(address(0x2), address(0x3), 1);
    }

    function test_erc721_safe_transfer_from() public {
        address from = address(0x1);
        address to = address(new ERC721Recipient());

        erc7629.mintERC721(from, 1);

        vm.prank(from);
        erc7629.setApprovalForAll(address(this), true);

        erc7629.safeTransferFrom(from, to, 1);

        assertEq(erc7629.ownerOf(1), to);
        assertEq(erc7629.erc721BalanceOf(from), 0);
        assertEq(erc7629.erc721BalanceOf(to), 1);
        assertEq(erc7629.getApproved(1), address(0));
    }

    function test_erc721_safe_transfer_from_with_data() public {
        address from = address(0x1);
        address to = address(new ERC721Recipient());

        erc7629.mintERC721(from, 1);

        vm.prank(from);
        erc7629.setApprovalForAll(address(this), true);

        erc7629.safeTransferFrom(from, to, 1, "0x1234");

        assertEq(erc7629.ownerOf(1), to);
        assertEq(erc7629.erc721BalanceOf(from), 0);
        assertEq(erc7629.erc721BalanceOf(to), 1);
        assertEq(erc7629.getApproved(1), address(0));
    }

    function test_erc721_safe_transfer_to_non_erc721_recipient_reverts() public {
        address from = address(0x1);
        address nonERC721Recipient = address(new NonERC721Recipient());

        erc7629.mintERC721(from, 1);

        vm.prank(from);
        erc7629.setApprovalForAll(address(this), true);

        vm.expectRevert(ERC7629.ERC721InvalidReceiver.selector);
        erc7629.safeTransferFrom(from, nonERC721Recipient, 1);
    }

    function test_erc721_safe_transfer_to_non_erc721_recipient_with_data_reverts() public {
        address from = address(0x1);
        address nonERC721Recipient = address(new NonERC721Recipient());

        erc7629.mintERC721(from, 1);

        vm.prank(from);
        erc7629.setApprovalForAll(address(this), true);

        vm.expectRevert(ERC7629.ERC721InvalidReceiver.selector);
        erc7629.safeTransferFrom(from, nonERC721Recipient, 1, "0x1234");
    }

    function test_burn_erc721() public {
        address from = address(0x1);
        erc7629.mintERC721(from, 1);

        vm.prank(from);
        erc7629.burnERC721(1);

        assertEq(erc7629.owned(from).length, 0);

        vm.expectRevert(ERC7629.ERC721NonexistentToken.selector);
        assertEq(erc7629.ownerOf(1), address(0));
    }

    function test_burn_erc721_non_minted_token_reverts() public {
        vm.expectRevert(ERC7629.ERC721NonexistentToken.selector);
        erc7629.burnERC721(1);
    }

    // TODO: burn erc721 with non owner reverts

    /* %=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*& */
    /*                        ERC165 functions                      */
    /* %=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*& */

    function test_supports_interface_erc165() public {
        assertEq(erc7629.supportsInterface(type(IERC165).interfaceId), true);
    }

    function test_supports_interface_erc7629() public {
        assertEq(erc7629.supportsInterface(type(IERC7629).interfaceId), true);
    }

    function test_supports_interface_false() public {
        assertEq(erc7629.supportsInterface(0x12345678), false);
    }
}
