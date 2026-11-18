// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal stand-in for the SPACE ID Agent ID contract (BSC mainnet
/// 0x60b9262456de011f7d15a54cdd8c48baaa8b022f), which does not exist on BSC
/// testnet. Mirrors the two behaviours NamedPay depends on: ownerOf reverts
/// for unknown tokenIds, and tokenId = keccak256(lowercase label).
contract MockAgentID {
    mapping(uint256 => address) private _owners;

    event NameMinted(uint256 indexed tokenId, string label, address indexed owner);

    function mint(string memory label, address owner_) external {
        uint256 tokenId = uint256(keccak256(bytes(_lower(label))));
        require(_owners[tokenId] == address(0), "already minted");
        _owners[tokenId] = owner_;
        emit NameMinted(tokenId, label, owner_);
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address o = _owners[tokenId];
        require(o != address(0), "ERC721: invalid token ID");
        return o;
    }

    function _lower(string memory label) internal pure returns (string memory) {
        bytes memory b = bytes(label);
        for (uint256 i = 0; i < b.length; i++) {
            bytes1 c = b[i];
            if (c >= 0x41 && c <= 0x5A) {
                b[i] = bytes1(uint8(c) + 32);
            }
        }
        return string(b);
    }
}
