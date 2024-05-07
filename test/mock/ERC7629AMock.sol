//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../../src/ERC7629A.sol";

contract ERC7629AMock is Ownable, ERC7629A {
    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 units_)
        ERC7629A(name_, symbol_, decimals_, units_)
        Ownable(msg.sender)
    {}

    function mintERC20(address to_, uint256 amount_) public {
        _mintERC20(to_, amount_);
    }

    function mintERC721(address to_, uint256 amount_) public {
        _mintERC721(to_, amount_);
    }

    function burnERC20(address owner_, uint256 amount_) public {
        _burnERC20(owner_, amount_);
    }

    function burnERC721(uint256 id_) public {
        _burnERC721(id_);
    }

    function tokenURI(uint256 id_) public pure override returns (string memory) {
        return string.concat("https://example.com/token/", Strings.toString(id_));
    }

    function erc721Approve(address spender_, uint256 id_) public {
        _erc721Approve(spender_, id_);
    }

    function erc721TransferFrom(address from_, address to_, uint256 id_) public {
        _erc721TransferFrom(from_, to_, id_);
    }

    function erc20Approve(address spender_, uint256 amount_) public {
        _erc20Approve(spender_, amount_);
    }

    function erc20TransferFrom(address from_, address to_, uint256 amount_) public {
        _erc20TransferFrom(from_, to_, amount_);
    }
}
