pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC7629AMock} from "./mock/ERC7629AMock.sol";
import {ERC7629A} from "../src/ERC7629A.sol";
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

contract ERC7629ATest is Test {
    ERC7629AMock erc7629a;

    function setUp() public {
        erc7629a = new ERC7629AMock("Test", "TST", 18, 10_000);
    }

    /* %=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*& */
    /*                        Common metadata                       */
    /* %=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*& */

    function test_name() public {
        string memory name = erc7629a.name();
        assertEq(name, "Test");
    }

    function test_symbol() public {
        string memory symbol = erc7629a.symbol();
        assertEq(symbol, "TST");
    }

    function test_decimals() public {
        uint8 decimals = erc7629a.decimals();
        assertEq(decimals, 18);
    }

    /* %=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*& */
    /*                   ERC7629A specify functions                  */
    /* %=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*& */

    function test_get_uint() public {
        uint256 unit = erc7629a.getUnit();
        uint256 expectedUnit = 10_000 * 10 ** 18;
        assertEq(unit, expectedUnit);
    }

    function test_erc20_to_erc721_with_0_minted() public {
        uint256 unit = erc7629a.getUnit();
        uint256 expectedAmount = 1;
        uint256 amountToConvert = expectedAmount * unit;

        address user = address(0x1);

        erc7629a.mintERC20(user, amountToConvert);

        vm.prank(user);
        erc7629a.erc20ToERC721(amountToConvert);

        uint256[] memory tokenIds = erc7629a.owned(user);
        uint256 tokenId = tokenIds[0];

        assertEq(tokenIds.length, 1);
        assertEq(tokenId, 1);

        uint256 balance = erc7629a.erc20BalanceOf(user);

        assertEq(balance, 0);
    }

    function test_erc721_to_erc20() public {
        uint256 unit = erc7629a.getUnit();
        uint256 amount = 1;
        uint256 tokenId = 1;

        address user = address(0x1);

        // mint erc271
        erc7629a.mintERC721(user, amount);

        // convert single
        vm.prank(user);
        erc7629a.erc721ToERC20(tokenId);

        uint256[] memory ownedTokenIds = erc7629a.owned(user);
        uint256 balance = erc7629a.erc20BalanceOf(user);

        assertEq(ownedTokenIds.length, 0);
        assertEq(balance, unit);

        // // contract erc721 vault checking
        uint256[] memory contractTokenIds = erc7629a.owned(address(erc7629a));
        uint256 contractTokenId = contractTokenIds[0];

        assertEq(contractTokenIds.length, amount);
        assertEq(contractTokenId, tokenId);
    }

    function test_erc20_to_erc721_batch_of_10_with_5_minted() public {
        uint256 unit = erc7629a.getUnit();
        uint256 mintAmount = 5;
        uint256 expectedAmount = 5;
        uint256 amountToConvert = expectedAmount * unit;

        address user = address(0x1);

        erc7629a.mintERC20(user, amountToConvert);

        erc7629a.mintERC721(user, 5);

        for (uint256 i = 1; i <= mintAmount; i++) {
            vm.prank(user);
            erc7629a.erc721ToERC20(i);
        }

        vm.prank(user);
        erc7629a.erc20ToERC721((expectedAmount + mintAmount) * unit);

        uint256[] memory tokenIds = erc7629a.owned(user);

        assertEq(tokenIds.length, expectedAmount + mintAmount);

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

        assertEq(erc7629a.erc20BalanceOf(user), 0);
    }

    function test_erc20_to_erc721_with_insufficient_balance_reverts() public {
        uint256 unit = erc7629a.getUnit();
        uint256 expectedAmount = 1;
        uint256 amountToConvert = expectedAmount * unit;

        address user = address(0x1);

        vm.expectRevert(ERC7629A.ERC20InsufficientBalance.selector);
        vm.prank(user);
        erc7629a.erc20ToERC721(amountToConvert);
    }

    function test_transfer_from_erc20_invalid_receiver_reverts() public {
        erc7629a.mintERC20(address(0x1), 10_000);

        vm.prank(address(0x1));
        erc7629a.approve(address(this), 10_000);

        vm.expectRevert(ERC7629A.ERC20InvalidReceiver.selector);
        erc7629a.transferFrom(address(0x1), address(0), 10_000);
    }

    // the following tests handles ERC7629A functions that implements ERC721
    // as the transfer flow includes, minting, approving and transferring
    // the approve implements _erc721TransferFrom
    // the transferFrom implements _erc721Approve
    function test_erc721_transfer_flow() public {
        uint256 amount = 1;
        uint256 tokenId = 1;
        address user = address(0x1);
        address spender = address(0x2);

        // mint erc271
        erc7629a.mintERC721(user, amount);

        uint256 minted = erc7629a.erc721TotalSupply();
        assertEq(minted, amount);

        uint256[] memory ownedTokenIds = erc7629a.owned(user);
        uint256 ownedTokenId = ownedTokenIds[0];

        assertEq(ownedTokenIds.length, amount);
        assertEq(ownedTokenId, tokenId);

        address approved = erc7629a.getApproved(tokenId);
        assertEq(approved, address(0));

        // approve
        vm.prank(user);
        erc7629a.approve(spender, tokenId);

        // check approval
        approved = erc7629a.getApproved(tokenId);
        assertEq(approved, spender);

        // transfer from
        vm.prank(spender);
        erc7629a.transferFrom(user, spender, tokenId);

        approved = erc7629a.getApproved(tokenId);
        assertEq(approved, address(0));

        // spender balance
        uint256[] memory spenderTokenIds = erc7629a.owned(spender);
        uint256 spenderTokenId = spenderTokenIds[0];

        assertEq(spenderTokenIds.length, amount);
        assertEq(spenderTokenId, tokenId);

        // user balance
        ownedTokenIds = erc7629a.owned(user);
        assertEq(ownedTokenIds.length, 0);
    }

    function test_erc721_transfer_flow_with_invalid_receiver_reverts() public {
        uint256 amount = 1;
        uint256 tokenId = 1;
        address user = address(0x1);
        address spender = address(0x2);

        // mint erc271
        erc7629a.mintERC721(user, amount);

        vm.expectRevert(ERC7629A.ERC721InvalidReceiver.selector);
        vm.prank(spender);
        erc7629a.transferFrom(user, address(0), tokenId);
    }

    // the following tests handles ERC7629A functions that implements ERC20
    // as the transfer flow includes, minting, approving and transferring
    // the approve implements _erc20TransferFrom
    // the transferFrom implements _erc20Approve
    function test_erc20_transfer_flow() public {
        uint256 amount = 10_000 * 1e18;

        address user = address(0x1);
        address spender = address(0x2);

        // mint erc20
        erc7629a.mintERC20(user, amount);

        // approve
        vm.prank(user);
        erc7629a.approve(spender, amount);

        // check allowance
        assertEq(erc7629a.allowance(user, spender), amount);

        // transfer from
        vm.prank(spender);
        erc7629a.transferFrom(user, spender, amount);

        assertEq(erc7629a.allowance(user, spender), 0);

        // spender balance
        assertEq(erc7629a.erc20BalanceOf(spender), amount);

        // user balance
        assertEq(erc7629a.erc20BalanceOf(user), 0);
    }

    /* %=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*& */
    /*                        ERC20 functions                       */
    /* %=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*& */

    function test_erc20_mint() public {
        uint256 amountToMint = 10_000;
        erc7629a.mintERC20(address(0x1), amountToMint);

        assertEq(erc7629a.erc20BalanceOf(address(0x1)), amountToMint);
        assertEq(erc7629a.totalSupply(), amountToMint);
    }

    function test_erc20_mint_over_uint_reverts() public {
        erc7629a.mintERC20(address(0x1), type(uint256).max);
        vm.expectRevert(ERC7629A.TotalSupplyOverflow.selector);
        erc7629a.mintERC20(address(0x1), 1);
    }

    function test_erc20_mint_to_0_reverts() public {
        vm.expectRevert(ERC7629A.ERC20InvalidReceiver.selector);
        erc7629a.mintERC20(address(0), 10_000);
    }

    function test_erc20_burn() public {
        uint256 amountToMint = 10_000;
        erc7629a.mintERC20(address(0x1), amountToMint);

        erc7629a.burnERC20(address(0x1), amountToMint);

        assertEq(erc7629a.erc20BalanceOf(address(0x1)), 0);
    }

    function test_erc20_burn_from_0_reverts() public {
        vm.expectRevert(ERC7629A.ERC20InvalidSender.selector);
        erc7629a.burnERC20(address(0), 10_000);
    }

    function test_erc20_burn_with_insufficient_balance_reverts() public {
        uint256 amountToMint = 10_000;
        erc7629a.mintERC20(address(0x1), amountToMint);

        vm.expectRevert(ERC7629A.ERC20InsufficientBalance.selector);
        erc7629a.burnERC20(address(0x1), amountToMint + 1);
    }

    function test_total_supply() public {
        uint256 totalSupply = erc7629a.totalSupply();
        uint256 expectedTotalSupply = 0;
        assertEq(totalSupply, expectedTotalSupply);

        // mint 10_000 tokens
        uint256 amountToMint = 10_000;
        erc7629a.mintERC20(address(0x1), amountToMint);

        totalSupply = erc7629a.totalSupply();
        assertEq(totalSupply, amountToMint);
    }

    function test_erc20_total_supply() public {
        uint256 totalSupply = erc7629a.erc20TotalSupply();
        uint256 expectedTotalSupply = 0;
        assertEq(totalSupply, expectedTotalSupply);

        // mint 10_000 tokens
        uint256 amountToMint = 10_000;
        erc7629a.mintERC20(address(0x1), amountToMint);

        totalSupply = erc7629a.erc20TotalSupply();
        assertEq(totalSupply, amountToMint);
    }

    function test_balance_of() public {
        uint256 balance = erc7629a.balanceOf(address(0x1));
        uint256 expectedBalance = 0;
        assertEq(balance, expectedBalance);

        // mint 10_000 tokens
        uint256 amountToMint = 10_000;
        erc7629a.mintERC20(address(0x1), amountToMint);

        balance = erc7629a.balanceOf(address(0x1));
        assertEq(balance, amountToMint);
    }

    function test_transfer() public {
        uint256 amountToMint = 10_000;
        erc7629a.mintERC20(address(0x1), amountToMint);

        vm.prank(address(0x1));
        erc7629a.transfer(address(0x2), amountToMint);

        assertEq(erc7629a.erc20BalanceOf(address(0x1)), 0);
        assertEq(erc7629a.erc20BalanceOf(address(0x2)), amountToMint);
    }

    function test_transfer_with_insufficient_balance_reverts() public {
        uint256 amountToMint = 10_000;
        erc7629a.mintERC20(address(0x1), amountToMint);

        vm.expectRevert(ERC7629A.ERC20InsufficientBalance.selector);
        vm.prank(address(0x1));
        erc7629a.transfer(address(0x2), amountToMint + 1);
    }

    function test_transfer_from_0_reverts() public {
        vm.expectRevert(ERC7629A.ERC20InvalidSender.selector);
        vm.prank(address(0));
        erc7629a.transfer(address(0x1), 10_000);
    }

    function test_transfer_to_0_reverts() public {
        uint256 amountToMint = 10_000;
        erc7629a.mintERC20(address(0x1), amountToMint);

        vm.expectRevert(ERC7629A.ERC20InvalidReceiver.selector);
        vm.prank(address(0x1));
        erc7629a.transfer(address(0), amountToMint);
    }

    function test_erc20_approve() public {
        uint256 amountToMint = 10_000;
        erc7629a.mintERC20(address(0x1), amountToMint);

        address spender = address(0x2);
        vm.prank(address(0x1));
        erc7629a.erc20Approve(spender, amountToMint);

        assertEq(erc7629a.allowance(address(0x1), spender), amountToMint);
    }

    function test_erc20_approve_with_invalid_spender_reverts() public {
        vm.expectRevert(ERC7629A.ERC20InvalidSpender.selector);
        erc7629a.erc20Approve(address(0), 10_000);
    }

    function test_erc20_transfer_from() public {
        uint256 amountToMint = 10_000 * 1e18;
        erc7629a.mintERC20(address(0x1), amountToMint);

        vm.prank(address(0x1));
        erc7629a.erc20Approve(address(this), amountToMint);

        erc7629a.erc20TransferFrom(address(0x1), address(0x2), amountToMint);

        assertEq(erc7629a.erc20BalanceOf(address(0x1)), 0);
        assertEq(erc7629a.erc20BalanceOf(address(0x2)), amountToMint);
    }

    function test_erc20_transfer_from_with_insufficient_allowance_reverts() public {
        uint256 amountToMint = 10_000 * 1e18;
        erc7629a.mintERC20(address(0x1), amountToMint);
        vm.expectRevert(ERC7629A.ERC20InsufficientAllowance.selector);
        erc7629a.erc20TransferFrom(address(0x1), address(0x2), amountToMint);
    }

    /* %=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*& */
    /*                        ERC721 functions                      */
    /* %=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*& */

    function test_erc721_mint() public {
        uint256 amount = 2;
        address owner = address(0x1);
        erc7629a.mintERC721(owner, amount);

        uint256[] memory tokenIds = erc7629a.owned(owner);
        assertEq(tokenIds.length, amount);
        assertEq(tokenIds[0], 1);
        assertEq(tokenIds[1], 2);

        assertEq(erc7629a.ownerOf(1), owner);
        assertEq(erc7629a.ownerOf(2), owner);
        assertEq(erc7629a.erc721BalanceOf(owner), amount);
        assertEq(erc7629a.erc721TotalSupply(), amount);
    }

    function test_erc721_mint_to_0_reverts() public {
        vm.expectRevert(ERC7629A.ERC721InvalidReceiver.selector);
        erc7629a.mintERC721(address(0), 1);
    }

    function test_erc721_total_supply() public {
        uint256 totalSupply = erc7629a.erc721TotalSupply();
        uint256 expectedTotalSupply = 0;
        assertEq(totalSupply, expectedTotalSupply);

        erc7629a.mintERC721(address(0x1), 1);

        totalSupply = erc7629a.erc721TotalSupply();
        expectedTotalSupply = 1;
        assertEq(totalSupply, expectedTotalSupply);

        erc7629a.mintERC721(address(0x1), 1);

        totalSupply = erc7629a.erc721TotalSupply();
        expectedTotalSupply = 2;
        assertEq(totalSupply, expectedTotalSupply);
    }

    function test_erc721_balance_of() public {
        uint256 balance = erc7629a.erc721BalanceOf(address(0x1));
        uint256 expectedBalance = 0;
        assertEq(balance, expectedBalance);

        erc7629a.mintERC721(address(0x1), 1);

        balance = erc7629a.erc721BalanceOf(address(0x1));
        expectedBalance = 1;
        assertEq(balance, expectedBalance);

        erc7629a.mintERC721(address(0x1), 1);

        balance = erc7629a.erc721BalanceOf(address(0x1));
        expectedBalance = 2;
        assertEq(balance, expectedBalance);
    }

    function test_erc721_owned() public {
        erc7629a.mintERC721(address(0x1), 1);

        uint256[] memory tokenIds = erc7629a.owned(address(0x1));
        assertEq(tokenIds.length, 1);
        assertEq(tokenIds[0], 1);

        erc7629a.mintERC721(address(0x1), 2);

        tokenIds = erc7629a.owned(address(0x1));
        assertEq(tokenIds.length, 3);
        assertEq(tokenIds[0], 1);
        assertEq(tokenIds[1], 2);
        assertEq(tokenIds[2], 3);
    }

    function test_erc721_owner_of() public {
        address owner = address(0x1);
        erc7629a.mintERC721(owner, 1);

        address tokenOwner = erc7629a.ownerOf(1);
        assertEq(tokenOwner, owner);
    }

    function test_get_approved_with_non_exist_token() public {
        vm.expectRevert(ERC7629A.ERC721NonexistentToken.selector);
        erc7629a.getApproved(1);
    }

    function test_erc721_approve() public {
        uint256 tokenId = 1;
        address owner = address(0x1);
        address spender = address(0x2);
        erc7629a.mintERC721(owner, 1);

        address approved = erc7629a.getApproved(tokenId);
        assertEq(approved, address(0));

        vm.prank(owner);
        erc7629a.erc721Approve(spender, tokenId);

        approved = erc7629a.getApproved(tokenId);
        assertEq(approved, spender);
    }

    function test_erc721_approve_with_invalid_approver_reverts() public {
        erc7629a.mintERC721(address(0x1), 1);

        vm.expectRevert(ERC7629A.ERC721InvalidApprover.selector);
        erc7629a.erc721Approve(address(0x2), 1);
    }

    function test_set_approval_for_all() public {
        address owner = address(0x1);
        address operator = address(0x2);

        bool isApproved = erc7629a.isApprovedForAll(owner, operator);
        assertEq(isApproved, false);

        vm.prank(owner);
        erc7629a.setApprovalForAll(operator, true);

        isApproved = erc7629a.isApprovedForAll(owner, operator);
        assertEq(isApproved, true);
    }

    function test_set_approval_for_all_with_invalid_operator_reverts() public {
        vm.expectRevert(ERC7629A.ERC721InvalidOperator.selector);
        erc7629a.setApprovalForAll(address(0), true);
    }

    function test_erc721_transfer_from() public {
        address from = address(0x1);
        address to = address(0x2);

        erc7629a.mintERC721(from, 3);

        vm.prank(from);
        erc7629a.erc721TransferFrom(from, to, 2);

        assertEq(erc7629a.ownerOf(1), from);
        assertEq(erc7629a.ownerOf(2), to);
        assertEq(erc7629a.ownerOf(3), from);
        assertEq(erc7629a.erc721BalanceOf(from), 2);
        assertEq(erc7629a.erc721BalanceOf(to), 1);
    }

    function test_erc721_transfer_from_by_operator() public {
        address from = address(0x1);
        address to = address(0x2);

        erc7629a.mintERC721(from, 1);

        vm.prank(from);
        erc7629a.setApprovalForAll(address(this), true);

        erc7629a.erc721TransferFrom(from, to, 1);

        assertEq(erc7629a.ownerOf(1), to);
        assertEq(erc7629a.erc721BalanceOf(from), 0);
        assertEq(erc7629a.erc721BalanceOf(to), 1);
    }

    function test_erc721_transfer_from_non_exist_token_reverts() public {
        vm.expectRevert(ERC7629A.ERC721NonexistentToken.selector);
        erc7629a.erc721TransferFrom(address(0x1), address(0x2), 1);
    }

    function test_erc721_transfer_from_incorrect_owner_reverts() public {
        erc7629a.mintERC721(address(0x1), 1);
        vm.expectRevert(ERC7629A.ERC721IncorrectOwner.selector);
        erc7629a.erc721TransferFrom(address(0x2), address(0x3), 1);
    }

    function test_erc721_safe_transfer_from() public {
        address from = address(0x1);
        address to = address(new ERC721Recipient());

        erc7629a.mintERC721(from, 1);

        vm.prank(from);
        erc7629a.setApprovalForAll(address(this), true);

        erc7629a.safeTransferFrom(from, to, 1);

        assertEq(erc7629a.ownerOf(1), to);
        assertEq(erc7629a.erc721BalanceOf(from), 0);
        assertEq(erc7629a.erc721BalanceOf(to), 1);
        assertEq(erc7629a.getApproved(1), address(0));
    }

    function test_erc721_safe_transfer_from_with_data() public {
        address from = address(0x1);
        address to = address(new ERC721Recipient());

        erc7629a.mintERC721(from, 1);

        vm.prank(from);
        erc7629a.setApprovalForAll(address(this), true);

        erc7629a.safeTransferFrom(from, to, 1, "0x1234");

        assertEq(erc7629a.ownerOf(1), to);
        assertEq(erc7629a.erc721BalanceOf(from), 0);
        assertEq(erc7629a.erc721BalanceOf(to), 1);
        assertEq(erc7629a.getApproved(1), address(0));
    }

    function test_erc721_safe_transfer_to_non_erc721_recipient_reverts() public {
        address from = address(0x1);
        address nonERC721Recipient = address(new NonERC721Recipient());

        erc7629a.mintERC721(from, 1);

        vm.prank(from);
        erc7629a.setApprovalForAll(address(this), true);

        vm.expectRevert(ERC7629A.ERC721InvalidReceiver.selector);
        erc7629a.safeTransferFrom(from, nonERC721Recipient, 1);
    }

    function test_erc721_safe_transfer_to_non_erc721_recipient_with_data_reverts() public {
        address from = address(0x1);
        address nonERC721Recipient = address(new NonERC721Recipient());

        erc7629a.mintERC721(from, 1);

        vm.prank(from);
        erc7629a.setApprovalForAll(address(this), true);

        vm.expectRevert(ERC7629A.ERC721InvalidReceiver.selector);
        erc7629a.safeTransferFrom(from, nonERC721Recipient, 1, "0x1234");
    }

    function test_burn_erc721() public {
        address from = address(0x1);
        erc7629a.mintERC721(from, 1);

        vm.prank(from);
        erc7629a.burnERC721(1);

        assertEq(erc7629a.owned(from).length, 0);

        vm.expectRevert(ERC7629A.ERC721NonexistentToken.selector);
        assertEq(erc7629a.ownerOf(1), address(0));
    }

    function test_burn_erc721_non_minted_token_reverts() public {
        vm.expectRevert(ERC7629A.ERC721NonexistentToken.selector);
        erc7629a.burnERC721(1);
    }

    // TODO: burn erc721 with non owner reverts

    /* %=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*& */
    /*                        ERC165 functions                      */
    /* %=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*& */

    function test_supports_interface_erc165() public {
        assertEq(erc7629a.supportsInterface(type(IERC165).interfaceId), true);
    }

    function test_supports_interface_erc7629() public {
        assertEq(erc7629a.supportsInterface(type(IERC7629).interfaceId), true);
    }

    function test_supports_interface_false() public {
        assertEq(erc7629a.supportsInterface(0x12345678), false);
    }
}
