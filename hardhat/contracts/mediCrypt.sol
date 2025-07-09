// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title MediCrypt
 * @dev NFT-based medical record management system with encryption and access controls
 * @author MediCrypt Team
 * @notice This contract manages encrypted medical records as NFTs with granular access control
 */
contract MediCrypt is Ownable, ERC721Enumerable, ReentrancyGuard, Pausable {
    using Strings for uint256;

    // =============================================================
    //                           CONSTANTS
    // =============================================================
    
    uint256 public constant MAX_BATCH_SIZE = 100;
    uint256 public constant MINT_FEE = 0.000038 ether;
    uint256 public constant EDIT_FEE = 0.000038 ether;
    string public constant VERSION = "1.0.0";

    // =============================================================
    //                            STORAGE
    // =============================================================
    
    uint256 public nextTokenId;
    
    struct NFTMetadata {
        string nftURI;
        string nftName;
        string encryptionKey;
        uint256 createdAt;
        uint256 lastModified;
    }

    // Core mappings
    mapping(uint256 => NFTMetadata) private _tokenMetadata;
    mapping(uint256 => mapping(address => bool)) private _whitelist;
    mapping(uint256 => mapping(address => string)) private _whitelistNames;
    mapping(uint256 => address[]) private _whitelistedAddresses;
    mapping(address => uint256[]) private _whitelistedTokens;
    mapping(address => string[]) private _whitelistedTokenNames;
    
    // Provider and agency mappings
    mapping(address => string) private _medicalProviders;
    mapping(address => string) private _agencies;
    address[] private _medicalProviderAddresses;
    address[] private _agencyAddresses;

    // =============================================================
    //                            ERRORS
    // =============================================================
    
    error InsufficientFunds(uint256 required, uint256 provided);
    error InvalidAddress();
    error EmptyString(string fieldName);
    error TokenNotFound(uint256 tokenId);
    error NotTokenOwner(uint256 tokenId, address caller);
    error NotWhitelisted(uint256 tokenId, address caller);
    error AlreadyWhitelisted(uint256 tokenId, address addr);
    error NotWhitelistedAddress(uint256 tokenId, address addr);
    error ProviderNotExists(address provider);
    error ProviderAlreadyExists(address provider);
    error AgencyNotExists(address agency);
    error AgencyAlreadyExists(address agency);
    error Unauthorized(address caller);
    error BatchSizeExceeded(uint256 requested, uint256 max);
    error OffsetOutOfBounds(uint256 offset, uint256 total);
    error TransferFailed();

    // =============================================================
    //                            EVENTS
    // =============================================================
    
    event TokenMinted(
        address indexed to, 
        uint256 indexed tokenId, 
        string nftName, 
        uint256 timestamp
    );
    
    event TokenMetadataUpdated(
        uint256 indexed tokenId, 
        address indexed updater, 
        uint256 timestamp
    );
    
    event AddressWhitelisted(
        uint256 indexed tokenId, 
        address indexed whitelistedAddress, 
        string name,
        uint256 timestamp
    );
    
    event AddressRemovedFromWhitelist(
        uint256 indexed tokenId, 
        address indexed removedAddress,
        uint256 timestamp
    );
    
    event MedicalProviderAdded(
        address indexed provider, 
        string name,
        uint256 timestamp
    );
    
    event MedicalProviderRemoved(
        address indexed provider,
        uint256 timestamp
    );
    
    event AgencyAdded(
        address indexed agency, 
        string name,
        uint256 timestamp
    );
    
    event AgencyRemoved(
        address indexed agency,
        uint256 timestamp
    );

    event EmergencyPause(address indexed by, uint256 timestamp);
    event EmergencyUnpause(address indexed by, uint256 timestamp);

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================
    
    /**
     * @dev Initializes the MediCrypt contract
     * @param _owner Initial owner of the contract
     */
    constructor(address _owner) 
        ERC721("MediCryptedRecord", "MDR") 
        Ownable(_owner) 
    {
        if (_owner == address(0)) revert InvalidAddress();
    }

    // =============================================================
    //                      CORE FUNCTIONALITY
    // =============================================================
    
    /**
     * @notice Mints a new medical record NFT
     * @dev Requires payment of MINT_FEE
     * @param ownerWalletAddress Address that will own the NFT
     * @param nftURI IPFS URI for the NFT metadata
     * @param nftName Human-readable name for the NFT
     * @param encryptionKey Encryption key for the medical data
     */
    function mint(
        address ownerWalletAddress, 
        string calldata nftURI, 
        string calldata nftName, 
        string calldata encryptionKey
    ) 
        external 
        payable 
        nonReentrant 
        whenNotPaused 
    {
        if (msg.value < MINT_FEE) {
            revert InsufficientFunds(MINT_FEE, msg.value);
        }
        if (ownerWalletAddress == address(0)) revert InvalidAddress();
        if (bytes(nftURI).length == 0) revert EmptyString("nftURI");
        if (bytes(nftName).length == 0) revert EmptyString("nftName");
        if (bytes(encryptionKey).length == 0) revert EmptyString("encryptionKey");

        uint256 currentTokenId = nextTokenId;
        uint256 timestamp = block.timestamp;
        
        _safeMint(ownerWalletAddress, currentTokenId);
        
        _tokenMetadata[currentTokenId] = NFTMetadata({
            nftURI: nftURI,
            nftName: nftName,
            encryptionKey: encryptionKey,
            createdAt: timestamp,
            lastModified: timestamp
        });
        
        nextTokenId++;
        
        _transferFunds(msg.value);
        
        emit TokenMinted(ownerWalletAddress, currentTokenId, nftName, timestamp);
    }

    /**
     * @notice Retrieves metadata for a specific token
     * @dev Only accessible by token owner, whitelisted addresses, or agencies
     * @param tokenId The ID of the token
     * @return nftURI IPFS URI for the NFT
     * @return nftName Human-readable name
     * @return encryptionKey Encryption key for the data
     * @return createdAt Timestamp when token was created
     * @return lastModified Timestamp when token was last modified
     */
    function getTokenMetadata(uint256 tokenId) 
        external 
        view 
        onlyTokenOwnerOrWhitelistedOrAgency(tokenId) 
        returns (
            string memory nftURI, 
            string memory nftName, 
            string memory encryptionKey,
            uint256 createdAt,
            uint256 lastModified
        ) 
    {
        NFTMetadata memory metadata = _tokenMetadata[tokenId];
        return (
            metadata.nftURI, 
            metadata.nftName, 
            metadata.encryptionKey,
            metadata.createdAt,
            metadata.lastModified
        );
    }

    /**
     * @notice Updates metadata for an existing token
     * @dev Only accessible by token owner or whitelisted addresses
     * @param tokenId The ID of the token to update
     * @param nftURI New IPFS URI
     * @param nftName New name
     * @param encryptionKey New encryption key
     */
    function editTokenMetadata(
        uint256 tokenId, 
        string calldata nftURI, 
        string calldata nftName, 
        string calldata encryptionKey
    ) 
        external 
        payable 
        nonReentrant 
        whenNotPaused
        onlyWhitelisted(tokenId) 
    {
        if (msg.value < EDIT_FEE) {
            revert InsufficientFunds(EDIT_FEE, msg.value);
        }
        if (bytes(nftURI).length == 0) revert EmptyString("nftURI");
        if (bytes(nftName).length == 0) revert EmptyString("nftName");
        if (bytes(encryptionKey).length == 0) revert EmptyString("encryptionKey");

        uint256 timestamp = block.timestamp;
        NFTMetadata storage metadata = _tokenMetadata[tokenId];
        
        metadata.nftURI = nftURI;
        metadata.nftName = nftName;
        metadata.encryptionKey = encryptionKey;
        metadata.lastModified = timestamp;
        
        _transferFunds(msg.value);
        
        emit TokenMetadataUpdated(tokenId, msg.sender, timestamp);
    }

    // =============================================================
    //                    WHITELIST MANAGEMENT
    // =============================================================
    
    /**
     * @notice Adds an address to the whitelist for a specific token
     * @param tokenId The token ID
     * @param walletAddress Address to whitelist
     * @param name Human-readable name for the whitelisted address
     * @param nftName Name of the NFT (for tracking purposes)
     */
    function whitelistAddress(
        uint256 tokenId, 
        address walletAddress, 
        string calldata name, 
        string calldata nftName
    ) 
        external 
        onlyTokenOwner(tokenId) 
        whenNotPaused
    {
        if (walletAddress == address(0)) revert InvalidAddress();
        if (bytes(name).length == 0) revert EmptyString("name");
        if (bytes(nftName).length == 0) revert EmptyString("nftName");
        if (_whitelist[tokenId][walletAddress]) {
            revert AlreadyWhitelisted(tokenId, walletAddress);
        }

        _whitelist[tokenId][walletAddress] = true;
        _whitelistNames[tokenId][walletAddress] = name;
        _whitelistedTokens[walletAddress].push(tokenId);
        _whitelistedTokenNames[walletAddress].push(nftName);
        _whitelistedAddresses[tokenId].push(walletAddress);
        
        emit AddressWhitelisted(tokenId, walletAddress, name, block.timestamp);
    }

    /**
     * @notice Removes an address from the whitelist for a specific token
     * @param tokenId The token ID
     * @param walletAddress Address to remove from whitelist
     * @param nftName Name of the NFT (for tracking purposes)
     */
    function removeWhitelistedAddress(
        uint256 tokenId, 
        address walletAddress, 
        string calldata nftName
    ) 
        external 
        onlyTokenOwner(tokenId) 
        whenNotPaused
    {
        if (!_whitelist[tokenId][walletAddress]) {
            revert NotWhitelistedAddress(tokenId, walletAddress);
        }
        
        _whitelist[tokenId][walletAddress] = false;
        
        // Remove from arrays efficiently
        _removeFromTokenArray(_whitelistedTokens[walletAddress], tokenId);
        _removeFromStringArray(_whitelistedTokenNames[walletAddress], nftName);
        _removeFromAddressArray(_whitelistedAddresses[tokenId], walletAddress);

        delete _whitelistNames[tokenId][walletAddress];
        
        emit AddressRemovedFromWhitelist(tokenId, walletAddress, block.timestamp);
    }

    // =============================================================
    //                    PROVIDER MANAGEMENT
    // =============================================================
    
    /**
     * @notice Adds a medical provider
     * @param walletAddress Provider's wallet address
     * @param name Provider's name
     */
    function addMedicalProvider(address walletAddress, string calldata name) 
        external 
        onlyOwner 
        whenNotPaused
    {
        if (walletAddress == address(0)) revert InvalidAddress();
        if (bytes(name).length == 0) revert EmptyString("name");
        
        if (bytes(_medicalProviders[walletAddress]).length != 0) {
            revert ProviderAlreadyExists(walletAddress);
        }
        
        _medicalProviders[walletAddress] = name;
        _medicalProviderAddresses.push(walletAddress);
        
        emit MedicalProviderAdded(walletAddress, name, block.timestamp);
    }

    /**
     * @notice Removes a medical provider
     * @param walletAddress Provider's wallet address
     */
    function removeMedicalProvider(address walletAddress) 
        external 
        onlyOwner 
        whenNotPaused
    {
        if (bytes(_medicalProviders[walletAddress]).length == 0) {
            revert ProviderNotExists(walletAddress);
        }
        
        delete _medicalProviders[walletAddress];
        _removeFromAddressArray(_medicalProviderAddresses, walletAddress);
        
        emit MedicalProviderRemoved(walletAddress, block.timestamp);
    }

    // =============================================================
    //                     AGENCY MANAGEMENT
    // =============================================================
    
    /**
     * @notice Adds an agency
     * @param walletAddress Agency's wallet address
     * @param name Agency's name
     */
    function addAgency(address walletAddress, string calldata name) 
        external 
        onlyOwner 
        whenNotPaused
    {
        if (walletAddress == address(0)) revert InvalidAddress();
        if (bytes(name).length == 0) revert EmptyString("name");
        if (bytes(_agencies[walletAddress]).length != 0) {
            revert AgencyAlreadyExists(walletAddress);
        }
        
        _agencies[walletAddress] = name;
        _agencyAddresses.push(walletAddress);
        
        emit AgencyAdded(walletAddress, name, block.timestamp);
    }

    /**
     * @notice Removes an agency
     * @param walletAddress Agency's wallet address
     */
    function removeAgency(address walletAddress) 
        external 
        onlyOwner 
        whenNotPaused
    {
        if (bytes(_agencies[walletAddress]).length == 0) {
            revert AgencyNotExists(walletAddress);
        }
        
        delete _agencies[walletAddress];
        _removeFromAddressArray(_agencyAddresses, walletAddress);
        
        emit AgencyRemoved(walletAddress, block.timestamp);
    }

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================
    
    /**
     * @notice Gets all owned token names for a specific address
     * @param walletAddress The wallet address to query
     * @return names Array of token names
     */
    function getAllOwnedTokenNames(address walletAddress) 
        external 
        view
        onlySpecifiedOwner(walletAddress)
        returns (string[] memory names) 
    {
        uint256 balance = balanceOf(walletAddress);
        names = new string[](balance);

        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(walletAddress, i);
            names[i] = _tokenMetadata[tokenId].nftName;
        }
    }

    /**
     * @notice Gets all owned token IDs for a specific address
     * @param walletAddress The wallet address to query
     * @return ids Array of token IDs
     */
    function getAllOwnedTokenIds(address walletAddress) 
        external 
        view
        onlySpecifiedOwner(walletAddress) 
        returns (uint256[] memory ids) 
    {
        uint256 balance = balanceOf(walletAddress);
        ids = new uint256[](balance);

        for (uint256 i = 0; i < balance; i++) {
            ids[i] = tokenOfOwnerByIndex(walletAddress, i);
        }
    }

    /**
     * @notice Gets all whitelisted token names for a specific address
     * @param walletAddress The wallet address to query
     * @return nftNames Array of whitelisted token names
     */
    function getAllWhitelistedTokenNames(address walletAddress) 
        external 
        view
        onlySpecifiedOwner(walletAddress)
        returns (string[] memory nftNames) 
    {
        return _whitelistedTokenNames[walletAddress];
    }

    /**
     * @notice Gets all whitelisted token IDs for a specific address
     * @param walletAddress The wallet address to query
     * @return tokenIds Array of whitelisted token IDs
     */
    function getAllWhitelistedTokenIds(address walletAddress) 
        external 
        view
        onlySpecifiedOwner(walletAddress)
        returns (uint256[] memory tokenIds) 
    {
        return _whitelistedTokens[walletAddress];
    }

    /**
     * @notice Gets whitelisted addresses and names for a specific token
     * @param tokenId The token ID to query
     * @return walletAddresses Array of whitelisted addresses
     * @return names Array of corresponding names
     */
    function getWhitelistedAddressesAndNames(uint256 tokenId)
        external
        view
        onlyTokenOwner(tokenId)
        returns (address[] memory walletAddresses, string[] memory names)
    {
        uint256 count = 0;
        
        // Count active whitelisted addresses
        for (uint256 i = 0; i < _whitelistedAddresses[tokenId].length; i++) {
            if (_whitelist[tokenId][_whitelistedAddresses[tokenId][i]]) {
                count++;
            }
        }
        
        walletAddresses = new address[](count);
        names = new string[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < _whitelistedAddresses[tokenId].length; i++) {
            address addr = _whitelistedAddresses[tokenId][i];
            if (_whitelist[tokenId][addr]) {
                walletAddresses[index] = addr;
                names[index] = _whitelistNames[tokenId][addr];
                index++;
            }
        }
    }

    /**
     * @notice Lists all token IDs (agencies only)
     * @return ids Array of all token IDs
     */
    function listAllTokenIds() 
        external 
        view 
        onlyAgency 
        returns (uint256[] memory ids) 
    {
        uint256 totalTokens = totalSupply();
        if (totalTokens > MAX_BATCH_SIZE) {
            revert BatchSizeExceeded(totalTokens, MAX_BATCH_SIZE);
        }
        
        ids = new uint256[](totalTokens);
        for (uint256 i = 0; i < totalTokens; i++) {
            ids[i] = tokenByIndex(i);
        }
    }

    /**
     * @notice Lists all token names (agencies only)
     * @return names Array of all token names
     */
    function listAllTokenNames() 
        external 
        view 
        onlyAgency 
        returns (string[] memory names) 
    {
        uint256 totalTokens = totalSupply();
        if (totalTokens > MAX_BATCH_SIZE) {
            revert BatchSizeExceeded(totalTokens, MAX_BATCH_SIZE);
        }
        
        names = new string[](totalTokens);
        for (uint256 i = 0; i < totalTokens; i++) {
            uint256 tokenId = tokenByIndex(i);
            names[i] = _tokenMetadata[tokenId].nftName;
        }
    }

    /**
     * @notice Lists token IDs with pagination (agencies only)
     * @param offset Starting index
     * @param limit Number of items to return
     * @return ids Array of token IDs
     * @return total Total number of tokens
     */
    function listTokenIdsPaginated(uint256 offset, uint256 limit) 
        external 
        view 
        onlyAgency 
        returns (uint256[] memory ids, uint256 total) 
    {
        uint256 totalTokens = totalSupply();
        if (limit > MAX_BATCH_SIZE) {
            revert BatchSizeExceeded(limit, MAX_BATCH_SIZE);
        }
        if (offset >= totalTokens) {
            revert OffsetOutOfBounds(offset, totalTokens);
        }
        
        uint256 end = offset + limit;
        if (end > totalTokens) {
            end = totalTokens;
        }
        
        uint256 length = end - offset;
        ids = new uint256[](length);
        
        for (uint256 i = 0; i < length; i++) {
            ids[i] = tokenByIndex(offset + i);
        }
        
        return (ids, totalTokens);
    }

    // Provider and agency view functions
    function isMedicalProvider(address walletAddress) external view returns (bool) {
        return bytes(_medicalProviders[walletAddress]).length > 0;
    }

    function isAgency(address walletAddress) external view returns (bool) {
        return bytes(_agencies[walletAddress]).length > 0;
    }

    function listMedicalProviderAddresses() external view onlyOwner returns (address[] memory) {
        return _medicalProviderAddresses;
    }

    function listMedicalProviderNames() external view onlyOwner returns (string[] memory names) {
        names = new string[](_medicalProviderAddresses.length);
        for (uint256 i = 0; i < _medicalProviderAddresses.length; i++) {
            names[i] = _medicalProviders[_medicalProviderAddresses[i]];
        }
    }

    function listAgencyAddresses() external view onlyOwner returns (address[] memory) {
        return _agencyAddresses;
    }

    function listAgencyNames() external view onlyOwner returns (string[] memory names) {
        names = new string[](_agencyAddresses.length);
        for (uint256 i = 0; i < _agencyAddresses.length; i++) {
            names[i] = _agencies[_agencyAddresses[i]];
        }
    }

    // =============================================================
    //                    EMERGENCY FUNCTIONS
    // =============================================================
    
    /**
     * @notice Pauses the contract in case of emergency
     * @dev Only callable by owner
     */
    function pause() external onlyOwner {
        _pause();
        emit EmergencyPause(msg.sender, block.timestamp);
    }

    /**
     * @notice Unpauses the contract
     * @dev Only callable by owner
     */
    function unpause() external onlyOwner {
        _unpause();
        emit EmergencyUnpause(msg.sender, block.timestamp);
    }

    /**
     * @notice Emergency withdrawal function
     * @dev Only callable by owner, works even when paused
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) return;
        
        (bool success, ) = payable(owner()).call{value: balance}("");
        if (!success) revert TransferFailed();
    }

    // =============================================================
    //                    INTERNAL FUNCTIONS
    // =============================================================
    
    /**
     * @dev Transfers funds to the contract owner
     * @param amount Amount to transfer
     */
    function _transferFunds(uint256 amount) internal {
        (bool success, ) = payable(owner()).call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /**
     * @dev Removes an element from a uint256 array
     */
    function _removeFromTokenArray(uint256[] storage array, uint256 element) internal {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == element) {
                array[i] = array[array.length - 1];
                array.pop();
                break;
            }
        }
    }

    /**
     * @dev Removes an element from a string array
     */
    function _removeFromStringArray(string[] storage array, string memory element) internal {
        for (uint256 i = 0; i < array.length; i++) {
            if (keccak256(bytes(array[i])) == keccak256(bytes(element))) {
                array[i] = array[array.length - 1];
                array.pop();
                break;
            }
        }
    }

    /**
     * @dev Removes an element from an address array
     */
    function _removeFromAddressArray(address[] storage array, address element) internal {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == element) {
                array[i] = array[array.length - 1];
                array.pop();
                break;
            }
        }
    }

    // =============================================================
    //                        MODIFIERS
    // =============================================================
    
    modifier onlyTokenOwner(uint256 tokenId) {
        if (!_exists(tokenId)) revert TokenNotFound(tokenId);
        if (ownerOf(tokenId) != msg.sender) {
            revert NotTokenOwner(tokenId, msg.sender);
        }
        _;
    }

    modifier onlyTokenOwnerOrWhitelistedOrAgency(uint256 tokenId) {
        if (!_exists(tokenId)) revert TokenNotFound(tokenId);
        if (!(ownerOf(tokenId) == msg.sender || 
              _whitelist[tokenId][msg.sender] || 
              bytes(_agencies[msg.sender]).length > 0)) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    modifier onlySpecifiedOwner(address walletAddress) {
        if (walletAddress != msg.sender) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    modifier onlyWhitelisted(uint256 tokenId) {
        if (!_exists(tokenId)) revert TokenNotFound(tokenId);
        if (!(ownerOf(tokenId) == msg.sender || _whitelist[tokenId][msg.sender])) {
            revert NotWhitelisted(tokenId, msg.sender);
        }
        _;
    }

    modifier onlyAgency() {
        if (bytes(_agencies[msg.sender]).length == 0) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    // =============================================================
    //                     OVERRIDE FUNCTIONS
    // =============================================================
    
    /**
     * @dev Returns the token URI for a given token ID
     * @param tokenId The token ID
     * @return The token URI
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (!_exists(tokenId)) revert TokenNotFound(tokenId);
        return _tokenMetadata[tokenId].nftURI;
    }

    /**
     * @dev Override to add pausable functionality
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /**
     * @dev Returns contract version
     * @return Version string
     */
    function version() external pure returns (string memory) {
        return VERSION;
    }
}