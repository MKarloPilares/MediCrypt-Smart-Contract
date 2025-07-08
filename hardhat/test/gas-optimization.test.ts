import { expect } from "chai";
import { ethers } from "hardhat";
import { MediCrypt } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("MediCrypt Gas Optimization Tests", function () {
    let mediCrypt: MediCrypt;
    let owner: SignerWithAddress;
    let user1: SignerWithAddress;
    let agency: SignerWithAddress;

    const MINT_PRICE = ethers.parseEther("0.000038");

    beforeEach(async function () {
        [owner, user1, agency] = await ethers.getSigners();
        
        const MediCryptFactory = await ethers.getContractFactory("MediCrypt");
        mediCrypt = await MediCryptFactory.deploy();
        await mediCrypt.waitForDeployment();

        // Add agency for testing
        await mediCrypt.connect(owner).addAgency(agency.address, "Test Agency");
    });

    describe("Efficient Array Operations", function () {
        it("Should handle whitelist removal efficiently", async function () {
            // Mint token
            await mediCrypt.connect(user1).mint(
                user1.address,
                "uri1",
                "name1",
                "key1",
                { value: MINT_PRICE }
            );

            // Add multiple addresses to whitelist
            const addresses = [];
            for (let i = 0; i < 10; i++) {
                const wallet = ethers.Wallet.createRandom();
                addresses.push(wallet.address);
                await mediCrypt.connect(user1).whitelistAddress(
                    0,
                    wallet.address,
                    `User${i}`,
                    "name1"
                );
            }

            // Remove address from middle - should be efficient
            const tx = await mediCrypt.connect(user1).removeWhitelistedAddress(
                0,
                addresses[5],
                "name1"
            );
            const receipt = await tx.wait();
            
            // Gas should be reasonable (less than 100,000)
            expect(receipt?.gasUsed).to.be.lessThan(100000);
        });

        it("Should handle pagination efficiently", async function () {
            // Mint several tokens
            for (let i = 0; i < 20; i++) {
                await mediCrypt.connect(user1).mint(
                    user1.address,
                    `uri${i}`,
                    `name${i}`,
                    `key${i}`,
                    { value: MINT_PRICE }
                );
            }

            // Test pagination
            const tx = await mediCrypt.connect(agency).listTokenIdsPaginated(0, 10);
            const receipt = await tx.wait();
            
            // Gas should be reasonable
            expect(receipt?.gasUsed).to.be.lessThan(200000);
        });
    });

    describe("Gas Limits", function () {
        it("Should prevent gas limit attacks on large arrays", async function () {
            // This test ensures we can't exceed block gas limit
            await expect(
                mediCrypt.connect(agency).listTokenIdsPaginated(0, 200)
            ).to.be.revertedWith("Limit too high");
        });
    });

    describe("State Storage Optimization", function () {
        it("Should efficiently store and retrieve metadata", async function () {
            const tx = await mediCrypt.connect(user1).mint(
                user1.address,
                "https://example.com/very/long/uri/that/could/be/expensive/to/store",
                "Very Long Name That Could Be Expensive To Store",
                "very_long_encryption_key_that_could_be_expensive_to_store",
                { value: MINT_PRICE }
            );
            
            const receipt = await tx.wait();
            
            // Minting should be reasonably efficient
            expect(receipt?.gasUsed).to.be.lessThan(300000);
        });
    });
});
