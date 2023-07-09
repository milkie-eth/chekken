// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ChekkenNFT is ERC721URIStorage, Ownable {
    struct Chekken {
        uint256 attack;
        uint256 defense;
        uint256 health;
        uint256 flurry;
        uint256 agility;
        uint256 bravery;
    }

    uint256 public nextTokenId = 0;
    uint256 public mintingFee = 0 ether;
    uint256 public maxTokensPerWallet = 20;
    string public baseImageURL = "https://yourwebsite.com/images/";

    mapping(uint256 => Chekken) public chekkens;
    mapping(address => uint256) public walletTokenCount;

    constructor() ERC721("Chekken", "CHK") {}

    function setMintingFee(uint256 newFee) external onlyOwner {
        mintingFee = newFee;
    }

    function setMaxTokensPerWallet(uint256 newMax) external onlyOwner {
        maxTokensPerWallet = newMax;
    }

    function setBaseImageURL(string calldata newBaseURL) external onlyOwner {
        baseImageURL = newBaseURL;
    }

    function mint() external payable {
        require(msg.value >= mintingFee, "Insufficient ETH to cover minting fee");
        require(walletTokenCount[msg.sender] < maxTokensPerWallet, "Reached max tokens per wallet");

        // Generate random traits for the new chekken
        uint256 attack = (uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, nextTokenId))) % 20) + 10;
        uint256 defense = (uint256(keccak256(abi.encodePacked(block.difficulty, msg.sender, nextTokenId))) % 20) + 10;
        uint256 health = (uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender, nextTokenId))) % 50) + 50;
        uint256 flurry = (uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender, nextTokenId, "flurry"))) % 10) + 1;
        uint256 agility = (uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender, nextTokenId, "agility"))) % 10) + 1;
        uint256 bravery = 0;

        chekkens[nextTokenId] = Chekken({
            attack: attack,
            defense: defense,
            health: health,
            flurry: flurry,
            agility: agility,
            bravery: bravery
        });

        walletTokenCount[msg.sender] += 1;

        // Generate the metadata URI
        string memory tokenURI = string(abi.encodePacked(
            '{"name": "Chekken #', 
            Strings.toString(nextTokenId),
            '", "description": "This is a Chekken.", "image": "', 
            baseImageURL, 
            Strings.toString(nextTokenId), 
            '.png", "attributes": [{"trait_type": "Attack", "value": ', 
            Strings.toString(attack),
            '}, {"trait_type": "Defense", "value": ', 
            Strings.toString(defense), 
            '}, {"trait_type": "Health", "value": ', 
            Strings.toString(health),
            '}, {"trait_type": "Flurry", "value": ', 
            Strings.toString(flurry), 
            '}, {"trait_type": "Agility", "value": ', 
            Strings.toString(agility), 
            '}, {"trait_type": "Bravery", "value": ', 
            Strings.toString(bravery), 
            '}]}'
        ));
        
        // Mint the token
        _mint(msg.sender, nextTokenId);
        _setTokenURI(nextTokenId, tokenURI);
        
        nextTokenId++;
    }

    function increaseBravery(uint256 tokenId) external onlyOwner {
        chekkens[tokenId].bravery++;
    }
}