// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract MediCrypt is Ownable, ERC721Enumerable {
    uint256 public nextTokenId;

    struct NFTMetadata {
        string nftURI;
        string nftName;
        string encryptionKey;
    }

    // Mapping from token ID to metadata
    mapping(uint256 => NFTMetadata) private _tokenMetadata;

    // Mapping from token ID to a set of whitelisted addresses and their names
    mapping(uint256 => mapping(address => bool)) private _whitelist;
    mapping(uint256 => mapping(address => string)) private _whitelistNames;

    // Array of whitelisted addresses for each token ID
    mapping(uint256 => address[]) private _whitelistedAddresses;

    // Mapping from address to list of whitelisted token IDs
    mapping(address => uint256[]) private _whitelistedTokens;

    // Mapping from address to list of whitelisted token names
    mapping(address => string[]) private _whitelistedTokenNames;

    // Mapping from address to medical provider names
    mapping(address => string) private _medicalProviders;
    address[] private _medicalProviderAddresses;

    // Mapping for agencies with associated names
    mapping(address => string) private _agencies;
    address[] private _agencyAddresses;

    constructor() ERC721("MediCryptedRecord", "MDR") Ownable(0x3fcc9F262124D96B48e03CC3683462C08049384E) {}

    function mint(
        address ownerWalletAddress, 
        string memory nftURI, 
        string memory nftName, 
        string memory encryptionKey
    ) public payable {
        require(msg.value >= 0.000038 ether, "Insufficient funds for minting");

        _safeMint(ownerWalletAddress, nextTokenId);
        _tokenMetadata[nextTokenId] = NFTMetadata(nftURI, nftName, encryptionKey);
        nextTokenId++;
        payable(owner()).transfer(msg.value);
    }

    function getTokenMetadata(uint256 tokenId) 
        public 
        view 
        onlyTokenOwnerOrWhitelistedOrAgency(tokenId) 
        returns (string memory nftURI, string memory nftName, string memory encryptionKey) 
    {
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
    ) public payable onlyWhitelisted(tokenId) {
        require(msg.value >= 0.000038 ether, "Insufficient funds for minting");

        _tokenMetadata[tokenId] = NFTMetadata(nftURI, nftName, encryptionKey);
        payable(owner()).transfer(msg.value);
    }

    function whitelistAddress(uint256 tokenId, address walletAddress, string memory name, string memory nftName) public onlyTokenOwner(tokenId) {
        _whitelist[tokenId][walletAddress] = true;
        _whitelistNames[tokenId][walletAddress] = name;
        _whitelistedTokens[walletAddress].push(tokenId);
        _whitelistedTokenNames[walletAddress].push(nftName);
        _whitelistedAddresses[tokenId].push(walletAddress);
    }

    function removeWhitelistedAddress(uint256 tokenId, address walletAddress, string memory nftName) public onlyTokenOwner(tokenId) {
        _whitelist[tokenId][walletAddress] = false;
        
        // Remove tokenId from _whitelistedTokens[walletAddress]
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
        returns (address[] memory walletAddressess, string[] memory names)
    {
        uint256 count = _whitelistedAddresses[tokenId].length;
        walletAddressess = new address[](count);
        names = new string[](count);

        for (uint256 i = 0; i < count; i++) {
            address addr = _whitelistedAddresses[tokenId][i];
            if (_whitelist[tokenId][addr]) {
                walletAddressess[i] = addr;
                names[i] = _whitelistNames[tokenId][addr];
            }
        }

        return (walletAddressess, names);
    }

    function addMedicalProvider(address walletAddress, string memory name) public onlyOwner {
        if(bytes(_medicalProviders[walletAddress]).length == 0){
            _medicalProviderAddresses.push(walletAddress);
        }
        _medicalProviders[walletAddress] = name;
    }

    function removeMedicalProvider(address walletAddress) public onlyOwner {
        delete _medicalProviders[walletAddress];
        // Remove provider from _medicalProviderAddresses array
        for (uint256 i = 0; i < _medicalProviderAddresses.length; i++) {
            if (_medicalProviderAddresses[i] == walletAddress) {
                _medicalProviderAddresses[i] = _medicalProviderAddresses[_medicalProviderAddresses.length - 1];
                _medicalProviderAddresses.pop();
                break;
            }
        }
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
        if(bytes(_agencies[walletAddress]).length == 0) {
            _agencies[walletAddress] = name;
            _agencyAddresses.push(walletAddress);
        }
    }

    // Function to remove an agency address from the Agencies map
    function removeAgency(address walletAddress) public onlyOwner {
        if(bytes(_agencies[walletAddress]).length != 0) {
            delete _agencies[walletAddress];
            for (uint256 i = 0; i < _agencyAddresses.length; i++) {
                if (_agencyAddresses[i] == walletAddress) {
                    _agencyAddresses[i] = _agencyAddresses[_agencyAddresses.length - 1];
                    _agencyAddresses.pop();
                    break;
                }
            }
        }
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
        ids = new uint256[](totalTokens);

        for (uint256 i = 0; i < totalTokens; i++) {
            ids[i] = tokenByIndex(i);
        }

        return ids;
    }

    function listAllTokenNames() public view onlyAgency returns (string[] memory names) {
    uint256 totalTokens = totalSupply();
    names = new string[](totalTokens);

    for (uint256 i = 0; i < totalTokens; i++) {
        uint256 tokenId = tokenByIndex(i);
        names[i] = _tokenMetadata[tokenId].nftName;
    }

    return names;
}

    function isAgency(address walletAddress) public view returns (bool) {
        return bytes(_agencies[walletAddress]).length > 0;
    }
    
    modifier onlyTokenOwner(uint256 tokenId) {
        require(ownerOf(tokenId) == msg.sender, "Caller is not the owner");
        _;
    }

    modifier onlyTokenOwnerOrWhitelistedOrAgency(uint256 tokenId) {
        require(ownerOf(tokenId) == msg.sender || _whitelist[tokenId][msg.sender] || isAgency(msg.sender), "Caller is not the owner or whitelisted or agency");
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