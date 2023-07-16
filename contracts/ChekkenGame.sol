// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ChekkenNFT is ERC721URIStorage, Ownable {
    using Strings for uint256;
    using Counters for Counters.Counter;

    struct Chekken {
        uint256 strength;
        uint256 stamina;
    }

    struct NFT {
        address owner;
        uint256 tokenId;
    }

    uint256 public nextTokenId = 1;
    uint256 public mintingFee = 0 ether;
    uint256 public maxTokensPerWallet = 20;
    string public baseURI = "https://chekken.com/tinkies/";

    uint256 public constant maxSupply = 100;
    uint256 private constant baseHealth = 100;
    uint256 private reviveFee;
    address private treasuryAddress = 0x31d41e78BcE91fdb07FEadfCBAEDD67F43EdE387;
    ERC20 erc20Token = ERC20(0x2c435AE914dBcD397F057079b14383aa8FC45c78);

    mapping(uint256 => Chekken) public chekkens;
    mapping(address => uint256) public walletTokenCount;
    mapping(uint256 => uint256) private stakedERC20s;
    mapping(uint256 => bool) private isDead;
    mapping(uint256 => NFT) public stakedNFTs;
    mapping(uint256 => uint256) public deadSince;

    event BattleResult(address winner, address loser, uint256 winningTokenId, uint256 losingTokenId);
    event MintDetails(address indexed minter, uint256 indexed tokenId, uint256 strength, uint256 stamina);
    event AttackEvent(uint256 attackerTokenId, uint256 defenderTokenId, uint256 damageDealt, uint256 remainingHealth);

    constructor(uint256 _reviveFee) ERC721("Chekken", "CHK") {
        reviveFee = _reviveFee;
    }

    function mint() external payable {
        require(nextTokenId < maxSupply, "Maximum supply reached");
        require(msg.value >= mintingFee, "Insufficient ETH to cover minting fee");
        require(walletTokenCount[msg.sender] < maxTokensPerWallet, "Reached max tokens per wallet");

        // Generate strength trait for the new chekken
        uint256 strength = getRandomTrait();

        // Generate stamina trait based on the strength trait, ensuring it's always lower
        uint256 stamina = strength * 70 / 100;

        chekkens[nextTokenId] = Chekken({
            strength: strength,
            stamina: stamina
        });

        walletTokenCount[msg.sender] += 1;

        // Generate the metadata URI
        string memory tokenURI = generateTokenURI(nextTokenId);

        // Mint the token
        _mint(msg.sender, nextTokenId);
        _setTokenURI(nextTokenId, tokenURI);

        // Emit MintDetails event
        emit MintDetails(msg.sender, nextTokenId, strength, stamina);

        nextTokenId++;
    }

    function stakeERC20(uint256 tokenId, uint256 amount) external {
        require(_isApprovedOrOwner(msg.sender, tokenId), "You must be owner or approved to stake ERC20");
        erc20Token.transferFrom(msg.sender, address(this), amount);

        stakedERC20s[tokenId] += amount;
    }

    function battle(uint256 userTokenId, uint256 opponentTokenId, uint256 boostAmount) external {
        require(_isApprovedOrOwner(msg.sender, userTokenId), "You are not the owner of this NFT");

        // Get Chekken stats
        Chekken memory userChekken = chekkens[userTokenId];
        Chekken memory opponentChekken = chekkens[opponentTokenId];

        // Set health to 100 for each Chekken
        uint256 userChekkenHealth = baseHealth;
        uint256 opponentChekkenHealth = baseHealth;

        // If a boost amount is provided, transfer the boost tokens from the user to the contract and increase strength
        if (boostAmount > 0) {
            erc20Token.transferFrom(msg.sender, address(this), boostAmount);
            userChekken.strength += boostAmount / 10;
        }

        // Battle simulation
        while (userChekkenHealth > 0 && opponentChekkenHealth > 0) {
            uint256 damage;

            // User Chekken attacks first
            damage = getDamage(userChekken.strength, opponentChekken.stamina);
            opponentChekkenHealth = opponentChekkenHealth > damage ? opponentChekkenHealth - damage : 0;
            emit AttackEvent(userTokenId, opponentTokenId, damage, opponentChekkenHealth);

            if (opponentChekkenHealth == 0) break; // If opponent Chekken is dead, stop the battle

            // Opponent Chekken counterattacks
            damage = getDamage(opponentChekken.strength, userChekken.stamina);
            userChekkenHealth = userChekkenHealth > damage ? userChekkenHealth - damage : 0;
            emit AttackEvent(opponentTokenId, userTokenId, damage, userChekkenHealth);
        }

        // Determine the winner based on remaining health
        uint256 winnerTokenId = userChekkenHealth > 0 ? userTokenId : opponentTokenId;
        uint256 loserTokenId = userChekkenHealth > 0 ? opponentTokenId : userTokenId;
        
        concludeBattle(winnerTokenId, loserTokenId);
    }

    function revive(uint256 tokenId) external {
        require(isDead[tokenId], "Chekken not dead");
        require(erc20Token.balanceOf(msg.sender) >= reviveFee, "Insufficient ERC20 tokens for revive fee");
        require(block.timestamp > deadSince[tokenId] + 1 days || _isApprovedOrOwner(msg.sender, tokenId), "Only the owner can revive within 24 hours");

        // Transfer the revive fee
        erc20Token.transferFrom(msg.sender, address(this), reviveFee);

        // Revive and return the chekken
        isDead[tokenId] = false;
        _transfer(address(this), msg.sender, tokenId);

        // Clear the death timestamp
        deadSince[tokenId] = 0;
    }

    function concludeBattle(uint256 winnerTokenId, uint256 loserTokenId) private {
        address winner = ownerOf(winnerTokenId);
        address loser = ownerOf(loserTokenId);
        uint256 winnerStake = stakedERC20s[winnerTokenId];
        uint256 loserStake = stakedERC20s[loserTokenId];

        // Compute the treasury fee (10% of total stakes)
        uint256 totalStake = winnerStake + loserStake;
        uint256 treasuryFee = totalStake / 10;

        // Send the stakes to the winner minus the treasury fee
        uint256 winnerAmount = totalStake - treasuryFee;
        erc20Token.transfer(winner, winnerAmount);
        erc20Token.transfer(treasuryAddress, treasuryFee);

        // Return the NFT to the winner
        _transfer(address(this), winner, winnerTokenId);

        // Clear the staked amounts
        stakedERC20s[winnerTokenId] = 0;
        stakedERC20s[loserTokenId] = 0;

        // Set the loser's chekken as dead
        isDead[loserTokenId] = true;
        deadSince[loserTokenId] = block.timestamp;

        // Emit battle result event
        emit BattleResult(winner, loser, winnerTokenId, loserTokenId);
    }

    function getDamage(uint256 tokenId, uint256 opponentTokenId) private view returns (uint256) {
        uint256 strength = chekkens[tokenId].strength;
        uint256 stamina = chekkens[opponentTokenId].stamina;

        // Boost strength with staked ERC20 tokens at a 1:10 ratio
        strength += stakedERC20s[tokenId] / 10;

        return strength >= stamina ? strength - stamina : 0;
    }

    function getRandomTrait() internal view returns (uint256) {
        uint256 randomNumber = uint256(
            keccak256(
                abi.encodePacked(
                    blockhash(block.number - 1),
                    block.coinbase,
                    block.timestamp,
                    block.difficulty,
                    nextTokenId
                )
            )
        );

        // Generate trait within the range of 10 and 30
        uint256 traitValue = (randomNumber % 20) + 10;

        return traitValue;
    }

    function generateTokenURI(uint256 tokenId) internal view returns (string memory) {
        return string(abi.encodePacked(baseURI, tokenId.toString(), ".json"));
    }

    function getChekken(uint256 tokenId) public view returns (Chekken memory) {
        return chekkens[tokenId];
    }

    function stakeNFT(uint256 tokenId) public {
        require(msg.sender == ownerOf(tokenId), "You are not the owner of this NFT");
        require(!isDead[tokenId], "You cannot stake a dead Chekken");
        
        transferFrom(msg.sender, address(this), tokenId);
        stakedNFTs[tokenId] = NFT(msg.sender, tokenId);
    }

    function retreat(uint256 tokenId) public {
        require(msg.sender == stakedNFTs[tokenId].owner, "You are not the owner of this NFT");
        transferFrom(address(this), msg.sender, tokenId);
        delete stakedNFTs[tokenId];
    }

    function withdrawEther() external onlyOwner {
        uint balance = address(this).balance;
        payable(owner()).transfer(balance);
    }

    function withdrawERC20(address tokenContractAddress) external onlyOwner {
        ERC20 tokenContract = ERC20(tokenContractAddress);
        uint256 balance = tokenContract.balanceOf(address(this));
        tokenContract.transfer(owner(), balance);
    }

    function getBonusStrength(uint256 tokenId) public view returns (uint256) {
        return stakedERC20s[tokenId] / 10;
    }
}