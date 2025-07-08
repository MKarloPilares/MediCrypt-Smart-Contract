// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract MediCrypt is Ownable, ERC721Enumerable, ReentrancyGuard {
    uint256 public nextTokenId;
    uint256 public constant MAX_BATCH_SIZE = 100;

    struct NFTMetadata {
        string nftURI;
        string nftName;
        string encryptionKey;
    }

    mapping(uint256 => NFTMetadata) private _tokenMetadata;

    mapping(uint256 => mapping(address => bool)) private _whitelist;
    mapping(uint256 => mapping(address => string)) private _whitelistNames;

    mapping(uint256 => address[]) private _whitelistedAddresses;

    mapping(address => uint256[]) private _whitelistedTokens;

    mapping(address => string[]) private _whitelistedTokenNames;

    mapping(address => string) private _medicalProviders;
    address[] private _medicalProviderAddresses;

    mapping(address => string) private _agencies;
    address[] private _agencyAddresses;
    event TokenMinted(address indexed to, uint256 indexed tokenId, string nftName);
    event TokenMetadataUpdated(uint256 indexed tokenId, address indexed updater);
    event AddressWhitelisted(uint256 indexed tokenId, address indexed whitelistedAddress, string name);
    event AddressRemovedFromWhitelist(uint256 indexed tokenId, address indexed removedAddress);
    event MedicalProviderAdded(address indexed provider, string name);
    event MedicalProviderRemoved(address indexed provider);
    event AgencyAdded(address indexed agency, string name);
    event AgencyRemoved(address indexed agency);

    constructor() ERC721("MediCryptedRecord", "MDR") Ownable(0x3fcc9F262124D96B48e03CC3683462C08049384E) {}

    function mint(
        address ownerWalletAddress, 
        string memory nftURI, 
        string memory nftName, 
        string memory encryptionKey
    ) public payable nonReentrant {
        require(msg.value >= 0.000038 ether, "Insufficient funds for minting");
        require(ownerWalletAddress != address(0), "Invalid owner address");
        require(bytes(nftURI).length > 0, "NFT URI cannot be empty");
        require(bytes(nftName).length > 0, "NFT name cannot be empty");
        require(bytes(encryptionKey).length > 0, "Encryption key cannot be empty");

        uint256 currentTokenId = nextTokenId;
        _safeMint(ownerWalletAddress, currentTokenId);
        _tokenMetadata[currentTokenId] = NFTMetadata(nftURI, nftName, encryptionKey);
        nextTokenId++;
        
        (bool success, ) = payable(owner()).call{value: msg.value}("");
        require(success, "Transfer failed");
        
        emit TokenMinted(ownerWalletAddress, currentTokenId, nftName);
    }

    function getTokenMetadata(uint256 tokenId) 
        public 
        view 
        onlyTokenOwnerOrWhitelistedOrAgency(tokenId) 
        returns (string memory nftURI, string memory nftName, string memory encryptionKey) 
    {
        require(_exists(tokenId), "Token does not exist");
        NFTMetadata memory metadata = _tokenMetadata[tokenId];
        return (metadata.nftURI, metadata.nftName, metadata.encryptionKey);
    }

    function getAllOwnedTokenNames(address walletAddress) 
        public 
        view
        onlySpecifiedOwner(walletAddress)
        returns (string[] memory names) 
    {
        uint256 balance = balanceOf(walletAddress);

        string[] memory nftNames = new string[](balance);

        // Get names of owned tokens
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(walletAddress, i);
            nftNames[i] = _tokenMetadata[tokenId].nftName;
        }

        return nftNames;
    }

    function getAllOwnedTokenIds(address walletAddress) 
        public 
        view
        onlySpecifiedOwner(walletAddress) 
        returns (uint256[] memory ids) 
    {
        uint256 balance = balanceOf(walletAddress);
        uint256[] memory tokenIds = new uint[](balance);

        // Get IDs of owned tokens
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(walletAddress, i);
            tokenIds[i] = tokenId;
        }

        return tokenIds;
    }
    function editTokenMetadata(
        uint256 tokenId, 
        string memory nftURI, 
        string memory nftName, 
        string memory encryptionKey
    ) public payable nonReentrant onlyWhitelisted(tokenId) {
        require(msg.value >= 0.000038 ether, "Insufficient funds for editing");
        require(_exists(tokenId), "Token does not exist");
        require(bytes(nftURI).length > 0, "NFT URI cannot be empty");
        require(bytes(nftName).length > 0, "NFT name cannot be empty");
        require(bytes(encryptionKey).length > 0, "Encryption key cannot be empty");

        _tokenMetadata[tokenId] = NFTMetadata(nftURI, nftName, encryptionKey);
        
        (bool success, ) = payable(owner()).call{value: msg.value}("");
        require(success, "Transfer failed");
        
        emit TokenMetadataUpdated(tokenId, msg.sender);
    }

    function whitelistAddress(uint256 tokenId, address walletAddress, string memory name, string memory nftName) public onlyTokenOwner(tokenId) {
        require(_exists(tokenId), "Token does not exist");
        require(walletAddress != address(0), "Invalid wallet address");
        require(bytes(name).length > 0, "Name cannot be empty");
        require(bytes(nftName).length > 0, "NFT name cannot be empty");
        require(!_whitelist[tokenId][walletAddress], "Address already whitelisted");

        _whitelist[tokenId][walletAddress] = true;
        _whitelistNames[tokenId][walletAddress] = name;
        _whitelistedTokens[walletAddress].push(tokenId);
        _whitelistedTokenNames[walletAddress].push(nftName);
        _whitelistedAddresses[tokenId].push(walletAddress);
        
        emit AddressWhitelisted(tokenId, walletAddress, name);
    }

    function removeWhitelistedAddress(uint256 tokenId, address walletAddress, string memory nftName) public onlyTokenOwner(tokenId) {
        require(_exists(tokenId), "Token does not exist");
        require(_whitelist[tokenId][walletAddress], "Address not whitelisted");
        
        _whitelist[tokenId][walletAddress] = false;
        
        // Remove tokenId from _whitelistedTokens[walletAddress] - more efficient removal
        uint256[] storage tokenList = _whitelistedTokens[walletAddress];
        for (uint256 i = 0; i < tokenList.length; i++) {
            if (tokenList[i] == tokenId) {
                tokenList[i] = tokenList[tokenList.length - 1];
                tokenList.pop();
                break;
            }
        }
        
        // Remove nft name from _whitelistedTokenNames[walletAddress]
        string[] storage nameList = _whitelistedTokenNames[walletAddress];
        for (uint256 i = 0; i < nameList.length; i++) {
            if (keccak256(bytes(nameList[i])) == keccak256(bytes(nftName))) {
                nameList[i] = nameList[nameList.length - 1];
                nameList.pop();
                break;
            }
        }

        // Remove user from _whitelistedAddresses[tokenId]
        address[] storage addressList = _whitelistedAddresses[tokenId];
        for (uint256 i = 0; i < addressList.length; i++) {
            if (addressList[i] == walletAddress) {
                addressList[i] = addressList[addressList.length - 1];
                addressList.pop();
                break;
            }
        }

        delete _whitelistNames[tokenId][walletAddress];
        emit AddressRemovedFromWhitelist(tokenId, walletAddress);
    }

    function getAllWhitelistedTokenNames(address walletAddress) 
        public 
        view
        onlySpecifiedOwner(walletAddress)
        returns (string[] memory nftNames) 
    {
        return _whitelistedTokenNames[walletAddress];
    }

    function getAllWhitelistedTokenIds(address walletAddress) 
        public 
        view
        onlySpecifiedOwner(walletAddress)
        returns (uint256[] memory tokenIds) 
    {
        return _whitelistedTokens[walletAddress];
    }

    function getWhitelistedAddressesAndNames(uint256 tokenId)
        public
        view
        onlyTokenOwner(tokenId)
        returns (address[] memory walletAddresses, string[] memory names)
    {
        require(_exists(tokenId), "Token does not exist");
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

        return (walletAddresses, names);
    }

    function addMedicalProvider(address walletAddress, string memory name) public onlyOwner {
        require(walletAddress != address(0), "Invalid wallet address");
        require(bytes(name).length > 0, "Name cannot be empty");
        
        if(bytes(_medicalProviders[walletAddress]).length == 0){
            _medicalProviderAddresses.push(walletAddress);
        }
        _medicalProviders[walletAddress] = name;
        emit MedicalProviderAdded(walletAddress, name);
    }

    function removeMedicalProvider(address walletAddress) public onlyOwner {
        require(bytes(_medicalProviders[walletAddress]).length > 0, "Provider does not exist");
        
        delete _medicalProviders[walletAddress];
        
        // Remove provider from _medicalProviderAddresses array
        for (uint256 i = 0; i < _medicalProviderAddresses.length; i++) {
            if (_medicalProviderAddresses[i] == walletAddress) {
                _medicalProviderAddresses[i] = _medicalProviderAddresses[_medicalProviderAddresses.length - 1];
                _medicalProviderAddresses.pop();
                break;
            }
        }
        emit MedicalProviderRemoved(walletAddress);
    }

    function isMedicalProvider(address walletAddress) public view returns (bool) {
        return bytes(_medicalProviders[walletAddress]).length > 0;
    }

    function listMedicalProviderAddresses() public view onlyOwner returns (address[] memory addresses) {
        uint256 count = _medicalProviderAddresses.length;
        addresses = new address[](count);

        for (uint256 i = 0; i < count; i++) {
            addresses[i] = _medicalProviderAddresses[i];
        }

        return addresses;
    }

    function listMedicalProviderNames() public view onlyOwner returns (string[] memory names) {
        uint256 count = _medicalProviderAddresses.length;
        names = new string[](count);

        for (uint256 i = 0; i < count; i++) {
            address provider = _medicalProviderAddresses[i];
            names[i] = _medicalProviders[provider];
        }

        return names;
    }

    // Function to add an agency address with its name to the Agencies map
    function addAgency(address walletAddress, string memory name) public onlyOwner {
        require(walletAddress != address(0), "Invalid wallet address");
        require(bytes(name).length > 0, "Name cannot be empty");
        require(bytes(_agencies[walletAddress]).length == 0, "Agency already exists");
        
        _agencies[walletAddress] = name;
        _agencyAddresses.push(walletAddress);
        emit AgencyAdded(walletAddress, name);
    }

    // Function to remove an agency address from the Agencies map
    function removeAgency(address walletAddress) public onlyOwner {
        require(bytes(_agencies[walletAddress]).length > 0, "Agency does not exist");
        
        delete _agencies[walletAddress];
        for (uint256 i = 0; i < _agencyAddresses.length; i++) {
            if (_agencyAddresses[i] == walletAddress) {
                _agencyAddresses[i] = _agencyAddresses[_agencyAddresses.length - 1];
                _agencyAddresses.pop();
                break;
            }
        }
        emit AgencyRemoved(walletAddress);
    }

    function listAgencyAddresses() public view onlyOwner returns (address[] memory addresses) {
        uint256 count = _agencyAddresses.length;
        addresses = new address[](count);

        for (uint256 i = 0; i < count; i++) {
            addresses[i] = _agencyAddresses[i];
        }

        return addresses;
    }

    function listAgencyNames() public view onlyOwner returns (string[] memory names) {
        uint256 count = _agencyAddresses.length;
        names = new string[](count);

        for (uint256 i = 0; i < count; i++) {
            address agency = _agencyAddresses[i];
            names[i] = _agencies[agency];
        }

        return names;
    }

    // Function to list all token IDs accessible only by agencies
    function listAllTokenIds() public view onlyAgency returns (uint256[] memory ids) {
        uint256 totalTokens = totalSupply();
        require(totalTokens <= MAX_BATCH_SIZE, "Too many tokens, use pagination");
        
        ids = new uint256[](totalTokens);
        for (uint256 i = 0; i < totalTokens; i++) {
            ids[i] = tokenByIndex(i);
        }
        return ids;
    }

    function listAllTokenNames() public view onlyAgency returns (string[] memory names) {
        uint256 totalTokens = totalSupply();
        require(totalTokens <= MAX_BATCH_SIZE, "Too many tokens, use pagination");
        
        names = new string[](totalTokens);
        for (uint256 i = 0; i < totalTokens; i++) {
            uint256 tokenId = tokenByIndex(i);
            names[i] = _tokenMetadata[tokenId].nftName;
        }
        return names;
    }

    // Add pagination functions for large datasets
    function listTokenIdsPaginated(uint256 offset, uint256 limit) public view onlyAgency returns (uint256[] memory ids, uint256 total) {
        uint256 totalTokens = totalSupply();
        require(limit <= MAX_BATCH_SIZE, "Limit too high");
        require(offset < totalTokens, "Offset out of bounds");
        
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

    function isAgency(address walletAddress) public view returns (bool) {
        return bytes(_agencies[walletAddress]).length > 0;
    }
    
    modifier onlyTokenOwner(uint256 tokenId) {
        require(_exists(tokenId), "Token does not exist");
        require(ownerOf(tokenId) == msg.sender, "Caller is not the owner");
        _;
    }

    modifier onlyTokenOwnerOrWhitelistedOrAgency(uint256 tokenId) {
        require(_exists(tokenId), "Token does not exist");
        require(
            ownerOf(tokenId) == msg.sender || 
            _whitelist[tokenId][msg.sender] || 
            isAgency(msg.sender), 
            "Caller is not the owner or whitelisted or agency"
        );
        _;
    }

    modifier onlySpecifiedOwner(address walletAddress) {
        require(walletAddress == msg.sender, "Caller has no permission");
        _;
    }

    // Modifier to check if the caller is whiteListed for an NFT
    modifier onlyWhitelisted(uint256 tokenId) {
        require(ownerOf(tokenId) == msg.sender ||_whitelist[tokenId][msg.sender], "Caller is not the owner or whitelisted");
        _;
        
    }

    // Modifier to check if the caller is an agency
    modifier onlyAgency() {
        require(bytes(_agencies[msg.sender]).length > 0, "Caller is not an agency");
        _;
    }

}