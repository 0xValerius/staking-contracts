// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {ERC721A} from "ERC721A/ERC721A.sol";

contract MockNFT is ERC721A {
    constructor(string memory _name, string memory _symbol) ERC721A(_name, _symbol) {}

    function mint(address _to, uint256 _tokenId) external {
        _mint(_to, _tokenId);
    }
}
