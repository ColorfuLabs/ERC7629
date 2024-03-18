pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC7629Mock} from "./mock/ERC7629Mock.sol";

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

    function test_erc20_to_erc721() public {
        uint256 unit = erc7629.getUnit();
        uint256 expectedAmount = 1;
        uint256 amountToConvert = expectedAmount * unit;

        address user = address(0x1);

        erc7629.mintERC20(user, amountToConvert);

        uint256 balance = erc7629.erc20BalanceOf(user);

        assertEq(balance, amountToConvert);

        vm.prank(user);
        erc7629.erc20ToERC721(amountToConvert);

        uint256[] memory tokenIds = erc7629.owned(user);
        uint256 tokenId = tokenIds[0];

        assertEq(tokenIds.length, 1);
        assertEq(tokenId, 1);

        balance = erc7629.erc20BalanceOf(user);

        assertEq(balance, 0);
    }

    function test_erc20_to_erc721_batch_of_10() public {
        uint256 unit = erc7629.getUnit();
        uint256 expectedAmount = 10;
        uint256 amountToConvert = expectedAmount * unit;

        address user = address(0x1);

        erc7629.mintERC20(user, amountToConvert);

        uint256 balance = erc7629.erc20BalanceOf(user);

        assertEq(balance, amountToConvert);

        vm.prank(user);

        erc7629.erc20ToERC721(amountToConvert);

        uint256[] memory tokenIds = erc7629.owned(user);

        assertEq(tokenIds.length, 10);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(tokenIds[i], i + 1);
        }

        balance = erc7629.erc20BalanceOf(user);

        assertEq(balance, 0);
    }

    function test_erc721_to_erc20() public {
        uint256 unit = erc7629.getUnit();
        uint256 tokenId = 1;

        address user = address(0x1);

        // mint erc271
        erc7629.mintERC721(user, tokenId);

        uint256[] memory ownedTokenIds = erc7629.owned(user);
        uint256 ownedTokenId = ownedTokenIds[0];

        assertEq(ownedTokenIds.length, 1);
        assertEq(ownedTokenId, tokenId);

        // convert single
        vm.prank(user);
        erc7629.erc721ToERC20(tokenId);

        ownedTokenIds = erc7629.owned(user);
        uint256 balance = erc7629.erc20BalanceOf(user);

        assertEq(ownedTokenIds.length, 0);
        assertEq(balance, unit);

        // // contract erc721 vault checking
        uint256[] memory contractTokenIds = erc7629.owned(address(erc7629));
        uint256 contractTokenId = contractTokenIds[0];

        assertEq(contractTokenIds.length, 1);
        assertEq(contractTokenId, 1);
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

        // // check approval
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

        uint256 totalSupply = erc7629.totalSupply();
        assertEq(totalSupply, amount);

        uint256 balance = erc7629.erc20BalanceOf(user);
        assertEq(balance, amount);

        uint256 allowance = erc7629.allowance(user, spender);
        assertEq(allowance, 0);

        // approve
        vm.prank(user);
        erc7629.approve(spender, amount);

        // check allowance
        allowance = erc7629.allowance(user, spender);
        assertEq(allowance, amount);

        // transfer from
        vm.prank(spender);

        erc7629.transferFrom(user, spender, amount);

        allowance = erc7629.allowance(user, spender);
        assertEq(allowance, 0);

        // spender balance
        balance = erc7629.erc20BalanceOf(spender);
        assertEq(balance, amount);

        // user balance
        balance = erc7629.erc20BalanceOf(user);
        assertEq(balance, 0);
    }

    /* %=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*& */
    /*                        ERC20 functions                       */
    /* %=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*& */

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

    /* %=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*& */
    /*                        ERC721 functions                      */
    /* %=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*&%=*& */

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

    function test_erc721_transfer_from() public {
        address from = address(0x1);
        address operator = address(0x2);
        address to = address(0x3);

        erc7629.mintERC721(from, 1);
        erc7629.mintERC721(from, 2);
        erc7629.mintERC721(from, 3);

        uint256[] memory tokenIds = erc7629.owned(from);
        assertEq(tokenIds.length, 3);
        assertEq(tokenIds[0], 1);
        assertEq(tokenIds[1], 2);
        assertEq(tokenIds[2], 3);

        uint256 totalSupply = erc7629.erc721TotalSupply();

        assertEq(totalSupply, 3);

        vm.prank(from);
        erc7629.erc721TransferFrom(from, to, 1);

        tokenIds = erc7629.owned(from);
        assertEq(tokenIds.length, 2);
        assertEq(tokenIds[0], 3);
        assertEq(tokenIds[1], 2);

        tokenIds = erc7629.owned(to);
        assertEq(tokenIds.length, 1);
        assertEq(tokenIds[0], 1);

        vm.prank(from);
        erc7629.erc721Approve(operator, 2);

        assertEq(erc7629.getApproved(2), operator);

        vm.prank(operator);
        erc7629.erc721TransferFrom(from, to, 2);

        tokenIds = erc7629.owned(from);
        assertEq(tokenIds.length, 1);
        assertEq(tokenIds[0], 3);

        tokenIds = erc7629.owned(to);
        assertEq(tokenIds.length, 2);
        assertEq(tokenIds[0], 1);
        assertEq(tokenIds[1], 2);

        vm.prank(from);
        erc7629.setApprovalForAll(operator, true);

        vm.prank(from);
        assertEq(erc7629.isApprovedForAll(from, operator), true);

        vm.prank(operator);
        erc7629.erc721TransferFrom(from, to, 3);

        tokenIds = erc7629.owned(from);
        assertEq(tokenIds.length, 0);

        tokenIds = erc7629.owned(to);
        assertEq(tokenIds.length, 3);
        assertEq(tokenIds[0], 1);
        assertEq(tokenIds[1], 2);
        assertEq(tokenIds[2], 3);
    }
}
