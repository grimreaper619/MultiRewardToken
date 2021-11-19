// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../math/IterableMapping.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LotteryTracker is Ownable,VRFConsumerBase {

    using SafeMath for uint256;
    using IterableMapping for IterableMapping.Map;

    IterableMapping.Map private weeklyHoldersMap;

    mapping (address => bool) public excludedFromWeekly;

    mapping(address => uint256) private lastSoldTime; 

    uint256 public lastWeeklyDistributed;

    uint256 private minTokenBalForWeekly = 10000 * 10**18;

    uint256 weeklyAmount;

    bytes32 internal keyHash;
    uint256 internal fee;
    
    uint256 public randomResult;
    uint256 private oldResult;

    event WeeklyLotteryWinners(address[10] winners,uint256 Amount);
    event MonthlyLotteryWinners(address[3] winners,uint256 Amount);
    event UltimateLotteryWinners(address winner,uint256 Amount);
    
    /**
     * Constructor inherits VRFConsumerBase
     * 
     * Network: BSC Testnet
     * Chainlink VRF Coordinator address: 0xa555fC018435bef5A13C6c6870a9d4C11DEC329C
     * LINK token address               : 0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06
     * Key Hash: 0xcaf3c3727e033261d383b315559476f48034c13b18f8cafed4d871abe5049186
     */

    constructor() 
        VRFConsumerBase(
            0xa555fC018435bef5A13C6c6870a9d4C11DEC329C, // VRF Coordinator
            0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06  // LINK Token
        )
    {
        keyHash = 0xcaf3c3727e033261d383b315559476f48034c13b18f8cafed4d871abe5049186;
        fee = 0.1 * 10 ** 18; // 0.1 LINK (Varies by network)
        lastWeeklyDistributed = block.timestamp;
    }

    receive() external payable {
        setLottery();
    }

    function setLottery() public payable {
        weeklyAmount = weeklyAmount.add(msg.value);
    }

    function getRandomNumber() public onlyOwner returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK - fill contract with faucet");
        return requestRandomness(keyHash, fee);
    }

    /**
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        randomResult = randomness;
        requestId = 0;
    }

    function excludeFromWeekly(address account) external onlyOwner {
    	excludedFromWeekly[account] = true;

    	weeklyHoldersMap.remove(account);

    }

    
    function setMinValues(uint256 weekly) external onlyOwner {
        minTokenBalForWeekly = weekly;
    }

    function pickWeeklyWinners() public {
        require(randomResult != oldResult,"Update random number first");

        uint256 tempRandom;
        uint256 holderCount = weeklyHoldersMap.keys.length;
        address[10] memory winners;
        address winner;
        uint8 winnerCount = 0;

        while(winnerCount < 10){
            winner = weeklyHoldersMap.getKeyAtIndex(randomResult.mod(holderCount));
            if(block.timestamp.sub(lastSoldTime[winner]) >= 7 days){
                winners[winnerCount] = winner;
                winnerCount++;
                payable(winner).transfer(weeklyAmount.div(10));
            }
            tempRandom = uint(keccak256(abi.encodePacked(randomResult, block.timestamp, winnerCount)));
            randomResult = tempRandom;
        }

        lastWeeklyDistributed = block.timestamp;
        oldResult = randomResult;
        weeklyAmount = 0;

        emit WeeklyLotteryWinners(winners,weeklyAmount.div(10));
    }

    function setAccount(address payable account, uint256 newBalance, bool isFrom) external onlyOwner {

    	if(newBalance >= minTokenBalForWeekly) {
            if(excludedFromWeekly[account]) {
    		    return;
    	    }
    		weeklyHoldersMap.set(account, newBalance);
    	}
    	else {
    		weeklyHoldersMap.remove(account);
    	}

        if(isFrom){
            lastSoldTime[account] = block.timestamp;
        }

    }

}