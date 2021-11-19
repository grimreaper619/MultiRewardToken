//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract Vesting {

    using SafeMath for uint256;

    IERC20 public Token;

    mapping (address => uint16) public allocations;

    struct VestingStage {
        uint256 date;
        uint256 tokensUnlockedPercentage;
    }

    VestingStage[] public stages;

    uint256 public vestingStartTimestamp;

    uint256 public initialTokensBalance;

    uint256 public tokensSent;

    event Withdraw(uint256 amount, uint256 timestamp);

    modifier onlyWithdrawAddress () {
        require(allocations[msg.sender] > 0,"No allocation!");
        _;
    }

    /**
     * We are filling vesting stages array right when the contract is deployed.
     *
     * @param startTime Starting time of vesting in unix timestamp
     * @param unlockPerMonth Percentage unlocked per month (With extra zero for precision)
     * @param token Address of DreamToken that will be locked on contract.
     * @param users Addresses of benefactors
     * @param allocation Allocation for each benefactor (% value with extra zero. If 10%, give value 100)
     * 
     */
    constructor (uint256 startTime, uint8 unlockPerMonth, 
            IERC20 token, address[] memory users, uint8[] memory allocation) 
    {
        Token = token;
        vestingStartTimestamp = startTime;

        for(uint8 j = 0; j < users.length; j++){
            allocations[users[j]] = allocation[j];
        }
        
        uint256 month = 30 days;
        uint8 i;
        while(i*unlockPerMonth < 1000){
            stages.push(
                VestingStage({
                    date: vestingStartTimestamp + (i * month),
                    tokensUnlockedPercentage: i * unlockPerMonth
                })
            );
            i++;
        }

        stages.push(
                VestingStage({
                    date: vestingStartTimestamp + (i * month),
                    tokensUnlockedPercentage: 1000 //Fix Rounding 
                })
            );
    }

    /**
     * Main method for withdraw tokens from vesting.
     */
    function withdrawTokens() onlyWithdrawAddress external {
        // Setting initial tokens balance on a first withdraw.
        if (initialTokensBalance == 0) {
            setInitialTokensBalance();
        }
        uint256 tokensToSend = getAvailableTokensToWithdraw().mul(allocations[msg.sender]).div(1000);

        sendTokens(tokensToSend,msg.sender);
    }

    /**
     * Set initial tokens balance when making the first withdrawal.
     */
    function setInitialTokensBalance () private {
        initialTokensBalance = Token.balanceOf(address(this));
    }

    /**
     * Send tokens to withdrawAddress.
     * 
     * @param tokensToSend Amount of tokens will be sent.
     * @param receiver Recepient of token
     */
    function sendTokens (uint256 tokensToSend, address receiver) private {
        if (tokensToSend > 0) {
            // Updating tokens sent counter
            tokensSent = tokensSent.add(tokensToSend);
            // Sending allowed tokens amount
            Token.transfer(receiver, tokensToSend);
            // Raising event
            emit Withdraw(tokensToSend, block.timestamp);
        }
    }

    /**
     * Calculate tokens available for withdrawal.
     *
     * @param tokensUnlockedPercentage Percent of tokens that are allowed to be sent.
     *
     * @return Amount of tokens that can be sent according to provided percentage.
     */
    function getTokensAmountAllowedToWithdraw (uint256 tokensUnlockedPercentage) private view returns (uint256) {
        uint256 totalTokensAllowedToWithdraw = initialTokensBalance.mul(tokensUnlockedPercentage).div(1000);
        uint256 unsentTokensAmount = totalTokensAllowedToWithdraw.sub(tokensSent);
        return unsentTokensAmount;
    }

    /**
     * Get tokens unlocked percentage on current stage.
     * 
     * @return Percent of tokens allowed to be sent.
     */
    function getTokensUnlockedPercentage () private view returns (uint256) {
        uint256 allowedPercent;
        
        for (uint8 i = 0; i < stages.length; i++) {
            if (block.timestamp >= stages[i].date) {
                allowedPercent = stages[i].tokensUnlockedPercentage;
            }
        }
        
        return allowedPercent;
    }
    
    function getAvailableTokensToWithdraw () public view returns (uint256 tokensToSend) {
        uint256 tokensUnlockedPercentage = getTokensUnlockedPercentage();
        // In the case of stuck tokens we allow the withdrawal of them all after vesting period ends.
        if (tokensUnlockedPercentage >= 1000) {
            tokensToSend = Token.balanceOf(address(this));
        } else {
            tokensToSend = getTokensAmountAllowedToWithdraw(tokensUnlockedPercentage);
        }
    }

    function getStageAttributes (uint8 index) public view returns (uint256 date, uint256 tokensUnlockedPercentage) {
        return (stages[index].date, stages[index].tokensUnlockedPercentage);
    }
}