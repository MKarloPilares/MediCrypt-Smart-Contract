
This repository was created as a code sample and to document work completed in 2024.

MediCrypt is a decentralized application built with the purpose of storing medical records in the IPFS while using NFTs give ownership and access control to users. It is meant to eliminate the need for retaking of medical records and trivialize sharing of documents to medical providers anywhere in the world.

MediCrypt is a fullstack project that: 
1. Has a frontend application built with Typescript and ReactTS.
2. Has a smart contract made with Solidity and deployed with hardhat to the Arbitrum Sepolia test network.

This repository contains the project's smart contract only for the frontend application see: https://github.com/MKarloPilares/MediCrypt


To Deploy Contracts

1. npx hardhat compile
2. npx hardhat run scripts/deploy_mediCrypt.ts --network arbitrumSepolia
3. copy output address
4. npx hardhat verify [copied address] --network arbitrumSepolia