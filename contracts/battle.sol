pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "https://github.com/milkie-eth/chekken/blob/37f5beb22b7e5f1b003861c80924e8e721db7442/contracts/nft.sol";  // Import the ChekkenNFT contract

contract NFTBattle is Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    struct NFT {
        address owner;
        uint256 tokenId;
        uint256 bonusAttack;
    }

    mapping (uint256 => NFT) public stakedNFTs;
    mapping (uint256 => NFT) public deadChekkens;
    mapping (uint256 => uint256) public stakedERC20s;

    uint256 public revivalFee;

    ERC20 public erc20Token;

    event BattleResult(address winner, address loser, uint256 winningTokenId, uint256 losingTokenId);
    event AttackEvent(uint256 attackerTokenId, uint256 defenderTokenId, uint256 damageDealt, uint256 remainingHealth);
    event Revived(uint256 tokenId, address owner);

    ChekkenNFT public chekkenNFT;

    constructor(address _chekkenNFT, address _erc20Token) {
        chekkenNFT = ChekkenNFT(_chekkenNFT);
        erc20Token = ERC20(_erc20Token);
    }

    function stakeNFT(uint256 tokenId) public {
        require(msg.sender == chekkenNFT.ownerOf(tokenId), "You are not the owner of this NFT");

        chekkenNFT.transferFrom(msg.sender, address(this), tokenId);

        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();
        stakedNFTs[newTokenId] = NFT(msg.sender, tokenId, 0);
    }

    function stakeERC20(address erc20Address, uint256 tokenId, uint256 amount) public {
        require(stakedNFTs[tokenId].owner == msg.sender, "You must stake an NFT first");

        ERC20 erc20Token = ERC20(erc20Address);
        erc20Token.transferFrom(msg.sender, address(this), amount);

        stakedERC20s[tokenId] += amount;
    }

    function battle(uint256 userTokenId, uint256 opponentTokenId) public {
        require(stakedNFTs[userTokenId].owner == msg.sender, "You are not the owner of this NFT");

        // Get Chekken stats from the NFT contract
        ChekkenNFT.Chekken memory userChekken = chekkenNFT.chekkens(userTokenId);
        ChekkenNFT.Chekken memory opponentChekken = chekkenNFT.chekkens(opponentTokenId);

        // Determine who attacks first based on agility and bravery
        bool userAttacks = (userChekken.agility * userChekken.bravery) > (opponentChekken.agility * opponentChekken.bravery);

        // Calculate the bonus attack based on staked ERC20 tokens
        uint256 bonusAttack = stakedERC20s[userTokenId] / 1000;
        if (bonusAttack > 20) {
            bonusAttack = 20;
        }

        // Set the bonus attack power for the user's chekken
        stakedNFTs[userTokenId].bonusAttack = bonusAttack;

        // Battle simulation
        while (userChekken.health > 0 && opponentChekken.health > 0) {
            uint256 damage;
            if (userAttacks) {
                damage = getDamage(userChekken.attack + bonusAttack, opponentChekken.defense);
                opponentChekken.health -= damage;
                userAttacks = false;
                emit AttackEvent(userTokenId, opponentTokenId, damage, opponentChekken.health);
            } else {
                damage = getDamage(opponentChekken.attack, userChekken.defense);
                userChekken.health -= damage;
                userAttacks = true;
                emit AttackEvent(opponentTokenId, userTokenId, damage, userChekken.health);
            }
        }

        // Determine the winner based on remaining health
        uint256 winnerTokenId = userChekken.health > opponentChekken.health ? userTokenId : opponentTokenId;
        uint256 loserTokenId = userChekken.health > opponentChekken.health ? opponentTokenId : userTokenId;

        concludeBattle(winnerTokenId, loserTokenId);
    }

    function getDamage(uint256 attack, uint256 defense) private pure returns (uint256) {
        return attack > defense ? attack - defense : 0;
    }

    function concludeBattle(uint256 winnerTokenId, uint256 loserTokenId) private {
        NFT memory loserChekken = stakedNFTs[loserTokenId];

        // Transfer the NFT and ERC20 tokens to the winner
        chekkenNFT.transferFrom(address(this), winnerChekken.owner, winnerTokenId);
        erc20Token.transfer(winnerChekken.owner, stakedERC20s[winnerTokenId]);

        // Transfer the NFT and ERC20 tokens to the contract for the loser
        chekkenNFT.transferFrom(winnerChekken.owner, address(this), loserTokenId);
        erc20Token.transferFrom(loserChekken.owner, address(this), stakedERC20s[loserTokenId]);

        // Add the loser's chekken to the deadChekkens mapping
        deadChekkens[loserTokenId] = NFT(loserChekken.owner, loserTokenId, 0);

        emit BattleResult(winnerChekken.owner, loserChekken.owner, winnerTokenId, loserTokenId);
    }

    function setRevivalFee(uint256 _revivalFee) public onlyOwner {
        revivalFee = _revivalFee;
    }

    function reviveChekken(uint256 tokenId) public {
        NFT memory deadChekken = deadChekkens[tokenId];
        require(msg.sender == deadChekken.owner, "You are not the owner of this chekken");
        require(erc20Token.balanceOf(msg.sender) >= revivalFee, "Insufficient balance to revive the chekken");

        erc20Token.transferFrom(msg.sender, address(this), revivalFee);

        chekkenNFT.increaseBravery(tokenId);

        chekkenNFT.transferFrom(address(this), msg.sender, tokenId);
        emit Revived(tokenId, msg.sender);
    }

    function getBonusAttackPower(uint256 tokenId) public view returns (uint256) {
        return stakedNFTs[tokenId].bonusAttack;
    }
}
