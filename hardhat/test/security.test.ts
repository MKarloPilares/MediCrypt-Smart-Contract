import { expect } from "chai";
import { ethers } from "hardhat";
import { MediCrypt } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("MediCrypt Security Tests", function () {
    let mediCrypt: MediCrypt;
    let owner: SignerWithAddress;
    let user1: SignerWithAddress;
    let user2: SignerWithAddress;
    let maliciousUser: SignerWithAddress;
    let agency: SignerWithAddress;
    let provider: SignerWithAddress;

    const MINT_PRICE = ethers.parseEther("0.000038");
    const SAMPLE_URI = "https://example.com/metadata/1";
    const SAMPLE_NAME = "Medical Record 1";
    const SAMPLE_KEY = "encryption_key_123";

    beforeEach(async function () {
        [owner, user1, user2, maliciousUser, agency, provider] = await ethers.getSigners();
        
        const MediCryptFactory = await ethers.getContractFactory("MediCrypt");
        mediCrypt = await MediCryptFactory.deploy();
        await mediCrypt.waitForDeployment();
    });

    describe("Reentrancy Protection", function () {
        it("Should prevent reentrancy attacks on mint function", async function () {
            // Create a malicious contract that tries to reenter
            const MaliciousContract = await ethers.getContractFactory("MaliciousReentrant");
            const maliciousContract = await MaliciousContract.deploy();
            await maliciousContract.waitForDeployment();

            // This should fail due to reentrancy guard
            await expect(
                maliciousContract.attackMint(
                    await mediCrypt.getAddress(),
                    user1.address,
                    SAMPLE_URI,
                    SAMPLE_NAME,
                    SAMPLE_KEY,
                    { value: MINT_PRICE }
                )
            ).to.be.revertedWith("ReentrancyGuard: reentrant call");
        });

        it("Should prevent reentrancy attacks on editTokenMetadata function", async function () {
            // First mint a token
            await mediCrypt.connect(user1).mint(
                user1.address,
                SAMPLE_URI,
                SAMPLE_NAME,
                SAMPLE_KEY,
                { value: MINT_PRICE }
            );

            // Try to attack editTokenMetadata
            const MaliciousContract = await ethers.getContractFactory("MaliciousReentrant");
            const maliciousContract = await MaliciousContract.deploy();

            await expect(
                maliciousContract.attackEditMetadata(
                    await mediCrypt.getAddress(),
                    0,
                    "new_uri",
                    "new_name",
                    "new_key",
                    { value: MINT_PRICE }
                )
            ).to.be.revertedWith("ReentrancyGuard: reentrant call");
        });
    });

    describe("Access Control Security", function () {
        beforeEach(async function () {
            // Mint a token for testing
            await mediCrypt.connect(user1).mint(
                user1.address,
                SAMPLE_URI,
                SAMPLE_NAME,
                SAMPLE_KEY,
                { value: MINT_PRICE }
            );
        });

        it("Should prevent non-owners from accessing token metadata", async function () {
            await expect(
                mediCrypt.connect(maliciousUser).getTokenMetadata(0)
            ).to.be.revertedWith("Caller is not the owner or whitelisted or agency");
        });

        it("Should prevent non-owners from whitelisting addresses", async function () {
            await expect(
                mediCrypt.connect(maliciousUser).whitelistAddress(0, user2.address, "User2", SAMPLE_NAME)
            ).to.be.revertedWith("Caller is not the owner");
        });

        it("Should prevent non-owners from editing token metadata", async function () {
            await expect(
                mediCrypt.connect(maliciousUser).editTokenMetadata(
                    0,
                    "malicious_uri",
                    "malicious_name",
                    "malicious_key",
                    { value: MINT_PRICE }
                )
            ).to.be.revertedWith("Caller is not the owner or whitelisted");
        });

        it("Should prevent non-agencies from accessing all tokens", async function () {
            await expect(
                mediCrypt.connect(maliciousUser).listAllTokenIds()
            ).to.be.revertedWith("Caller is not an agency");
        });

        it("Should allow agencies to access all tokens", async function () {
            await mediCrypt.connect(owner).addAgency(agency.address, "Government Agency");
            
            const tokenIds = await mediCrypt.connect(agency).listAllTokenIds();
            expect(tokenIds).to.have.length(1);
            expect(tokenIds[0]).to.equal(0);
        });
    });

    describe("Input Validation Security", function () {
        it("Should reject minting with zero address", async function () {
            await expect(
                mediCrypt.connect(user1).mint(
                    ethers.ZeroAddress,
                    SAMPLE_URI,
                    SAMPLE_NAME,
                    SAMPLE_KEY,
                    { value: MINT_PRICE }
                )
            ).to.be.revertedWith("Invalid owner address");
        });

        it("Should reject minting with empty URI", async function () {
            await expect(
                mediCrypt.connect(user1).mint(
                    user1.address,
                    "",
                    SAMPLE_NAME,
                    SAMPLE_KEY,
                    { value: MINT_PRICE }
                )
            ).to.be.revertedWith("NFT URI cannot be empty");
        });

        it("Should reject minting with empty name", async function () {
            await expect(
                mediCrypt.connect(user1).mint(
                    user1.address,
                    SAMPLE_URI,
                    "",
                    SAMPLE_KEY,
                    { value: MINT_PRICE }
                )
            ).to.be.revertedWith("NFT name cannot be empty");
        });

        it("Should reject minting with empty encryption key", async function () {
            await expect(
                mediCrypt.connect(user1).mint(
                    user1.address,
                    SAMPLE_URI,
                    SAMPLE_NAME,
                    "",
                    { value: MINT_PRICE }
                )
            ).to.be.revertedWith("Encryption key cannot be empty");
        });

        it("Should reject whitelisting zero address", async function () {
            await mediCrypt.connect(user1).mint(
                user1.address,
                SAMPLE_URI,
                SAMPLE_NAME,
                SAMPLE_KEY,
                { value: MINT_PRICE }
            );

            await expect(
                mediCrypt.connect(user1).whitelistAddress(0, ethers.ZeroAddress, "User", SAMPLE_NAME)
            ).to.be.revertedWith("Invalid wallet address");
        });

        it("Should reject adding agency with zero address", async function () {
            await expect(
                mediCrypt.connect(owner).addAgency(ethers.ZeroAddress, "Test Agency")
            ).to.be.revertedWith("Invalid wallet address");
        });

        it("Should reject adding agency with empty name", async function () {
            await expect(
                mediCrypt.connect(owner).addAgency(agency.address, "")
            ).to.be.revertedWith("Name cannot be empty");
        });
    });

    describe("Gas Limit Protection", function () {
        it("Should respect MAX_BATCH_SIZE limit", async function () {
            // Add agency first
            await mediCrypt.connect(owner).addAgency(agency.address, "Test Agency");

            // Mock a scenario where totalSupply exceeds MAX_BATCH_SIZE
            // This would require minting more than 100 tokens, which is expensive
            // So we'll test the pagination function instead
            
            const offset = 0;
            const limit = 150; // Exceeds MAX_BATCH_SIZE

            await expect(
                mediCrypt.connect(agency).listTokenIdsPaginated(offset, limit)
            ).to.be.revertedWith("Limit too high");
        });

        it("Should work with pagination within limits", async function () {
            await mediCrypt.connect(owner).addAgency(agency.address, "Test Agency");

            // Mint a few tokens
            for (let i = 0; i < 5; i++) {
                await mediCrypt.connect(user1).mint(
                    user1.address,
                    `${SAMPLE_URI}_${i}`,
                    `${SAMPLE_NAME}_${i}`,
                    `${SAMPLE_KEY}_${i}`,
                    { value: MINT_PRICE }
                );
            }

            const [tokenIds, total] = await mediCrypt.connect(agency).listTokenIdsPaginated(0, 3);
            expect(tokenIds).to.have.length(3);
            expect(total).to.equal(5);
        });
    });

    describe("State Consistency", function () {
        it("Should prevent duplicate whitelisting", async function () {
            await mediCrypt.connect(user1).mint(
                user1.address,
                SAMPLE_URI,
                SAMPLE_NAME,
                SAMPLE_KEY,
                { value: MINT_PRICE }
            );

            // First whitelisting should succeed
            await mediCrypt.connect(user1).whitelistAddress(0, user2.address, "User2", SAMPLE_NAME);

            // Second whitelisting should fail
            await expect(
                mediCrypt.connect(user1).whitelistAddress(0, user2.address, "User2", SAMPLE_NAME)
            ).to.be.revertedWith("Address already whitelisted");
        });

        it("Should prevent duplicate agency addition", async function () {
            await mediCrypt.connect(owner).addAgency(agency.address, "Test Agency");

            await expect(
                mediCrypt.connect(owner).addAgency(agency.address, "Test Agency 2")
            ).to.be.revertedWith("Agency already exists");
        });

        it("Should prevent removing non-existent entities", async function () {
            await expect(
                mediCrypt.connect(owner).removeAgency(agency.address)
            ).to.be.revertedWith("Agency does not exist");

            await expect(
                mediCrypt.connect(owner).removeMedicalProvider(provider.address)
            ).to.be.revertedWith("Provider does not exist");
        });
    });

    describe("Event Emissions", function () {
        it("Should emit TokenMinted event", async function () {
            await expect(
                mediCrypt.connect(user1).mint(
                    user1.address,
                    SAMPLE_URI,
                    SAMPLE_NAME,
                    SAMPLE_KEY,
                    { value: MINT_PRICE }
                )
            ).to.emit(mediCrypt, "TokenMinted")
             .withArgs(user1.address, 0, SAMPLE_NAME);
        });

        it("Should emit AddressWhitelisted event", async function () {
            await mediCrypt.connect(user1).mint(
                user1.address,
                SAMPLE_URI,
                SAMPLE_NAME,
                SAMPLE_KEY,
                { value: MINT_PRICE }
            );

            await expect(
                mediCrypt.connect(user1).whitelistAddress(0, user2.address, "User2", SAMPLE_NAME)
            ).to.emit(mediCrypt, "AddressWhitelisted")
             .withArgs(0, user2.address, "User2");
        });

        it("Should emit AgencyAdded event", async function () {
            await expect(
                mediCrypt.connect(owner).addAgency(agency.address, "Test Agency")
            ).to.emit(mediCrypt, "AgencyAdded")
             .withArgs(agency.address, "Test Agency");
        });
    });

    describe("Token Existence Checks", function () {
        it("Should reject operations on non-existent tokens", async function () {
            await expect(
                mediCrypt.connect(user1).getTokenMetadata(999)
            ).to.be.revertedWith("Token does not exist");

            await expect(
                mediCrypt.connect(user1).whitelistAddress(999, user2.address, "User2", SAMPLE_NAME)
            ).to.be.revertedWith("Token does not exist");

            await expect(
                mediCrypt.connect(user1).editTokenMetadata(
                    999,
                    "new_uri",
                    "new_name",
                    "new_key",
                    { value: MINT_PRICE }
                )
            ).to.be.revertedWith("Token does not exist");
        });
    });

    describe("Payment Security", function () {
        it("Should reject insufficient payment for minting", async function () {
            const insufficientPayment = ethers.parseEther("0.000037");

            await expect(
                mediCrypt.connect(user1).mint(
                    user1.address,
                    SAMPLE_URI,
                    SAMPLE_NAME,
                    SAMPLE_KEY,
                    { value: insufficientPayment }
                )
            ).to.be.revertedWith("Insufficient funds for minting");
        });

        it("Should reject insufficient payment for editing", async function () {
            await mediCrypt.connect(user1).mint(
                user1.address,
                SAMPLE_URI,
                SAMPLE_NAME,
                SAMPLE_KEY,
                { value: MINT_PRICE }
            );

            const insufficientPayment = ethers.parseEther("0.000037");

            await expect(
                mediCrypt.connect(user1).editTokenMetadata(
                    0,
                    "new_uri",
                    "new_name",
                    "new_key",
                    { value: insufficientPayment }
                )
            ).to.be.revertedWith("Insufficient funds for editing");
        });

        it("Should transfer payments to owner", async function () {
            const ownerBalanceBefore = await ethers.provider.getBalance(owner.address);

            await mediCrypt.connect(user1).mint(
                user1.address,
                SAMPLE_URI,
                SAMPLE_NAME,
                SAMPLE_KEY,
                { value: MINT_PRICE }
            );

            const ownerBalanceAfter = await ethers.provider.getBalance(owner.address);
            expect(ownerBalanceAfter - ownerBalanceBefore).to.equal(MINT_PRICE);
        });
    });
});
