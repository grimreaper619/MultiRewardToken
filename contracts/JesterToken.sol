// SPDX-License-Identifier: MIT

pragma solidity ^0.8.8;

import "./misc/DividendPayingToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./math/IterableMapping.sol";
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import "./misc/LotteryTracker.sol";

contract JesterToken is ERC20, Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 public uniswapV2Router;
    address public  uniswapV2Pair;

    bool private swapping;
    bool private isAlreadyCalled;
    bool private isLotteryActive;
    bool private isTradingEnabled;

    JesterDividendTracker public dividendTracker;
    LotteryTracker public lotteryTracker;

    address private constant deadWallet = address(0xdead);

    uint256 public swapTokensAtAmount = 2 * 10**6 * 10**18;
    uint256 public dailyLimit = 5 * 10**5 * 10**18;

    mapping(address => uint256) private lastSoldTime;
    mapping(address => uint256) private soldTokenin24Hrs;
    
    mapping(address => bool) public _isExcludedFromWhale;

    uint8 public rewardsFee = 30;
    uint8 public liquidityFee = 10;
    uint8 public marketingFee = 15;
    uint8 public devFee = 15;
    uint8 public charityFee = 10;
    uint16 public lotteryFee = 30;
    uint16 public totalFees = rewardsFee + liquidityFee + marketingFee + lotteryFee + devFee + charityFee;

    address payable public _marketingWallet = payable(address(0x123));
    address payable public _devWallet = payable(address(0x456));
    address payable public _charityWallet = payable(address(0x789));


    // use by default 300,000 gas to process auto-claiming dividends
    uint256 public gasForProcessing = 300000;

     // exlcude from fees and max transaction amount
    mapping (address => bool) private _isExcludedFromFees;


    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping (address => bool) public automatedMarketMakerPairs;

    event UpdateDividendTracker(address indexed newAddress, address indexed oldAddress);

    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);

    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event LiquidityWalletUpdated(address indexed newLiquidityWallet, address indexed oldLiquidityWallet);

    event GasForProcessingUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    event SendDividends(uint256 amount);
    event SendLottery(uint256 amount);

    event SendWalletFees(uint256 marketingShare, 
        uint256 devShare, 
        uint256 charityShare);

    event ProcessedDividendTracker(
    	uint256 iterations,
    	uint256 claims,
        uint256 lastProcessedIndex,
    	bool indexed automatic,
    	uint256 gas,
    	address indexed processor
    );

    modifier onlyLottery{
        require(msg.sender == address(lotteryTracker),"Only lottery contract");
        _;
    }

    constructor() ERC20("Jester TOKEN", "JEST") {

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);


         // Create a uniswap pair for this new token
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        dividendTracker = new JesterDividendTracker(address(uniswapV2Router));
        lotteryTracker = new LotteryTracker();

        _setAutomatedMarketMakerPair(_uniswapV2Pair, true);

        // exclude from receiving dividends
        dividendTracker.excludeFromDividends(address(dividendTracker));
        dividendTracker.excludeFromDividends(address(this));
        dividendTracker.excludeFromDividends(owner());
        dividendTracker.excludeFromDividends(deadWallet);
        dividendTracker.excludeFromDividends(address(_uniswapV2Router));
        dividendTracker.excludedFromDividends(address(lotteryTracker));

        lotteryTracker.excludedFromWeekly(uniswapV2Pair);
        lotteryTracker.excludedFromWeekly(deadWallet);
        lotteryTracker.excludedFromWeekly(address(this));

        // exclude from paying fees or having max transaction amount
        excludeFromFees(owner(), true);
        excludeFromFees(_marketingWallet, true);
        excludeFromFees(_devWallet, true);
        excludeFromFees(_charityWallet, true);
        excludeFromFees(address(this), true);
        excludeFromFees(address(dividendTracker),true);

        /*
            _mint is an internal function in ERC20.sol that is only called here,
            and CANNOT be called ever again
        */
        _mint(owner(), 1 * 10**9 * 10**18);
    }

    receive() external payable {

  	}

    function updateDividendTracker(address newAddress) public onlyOwner {
        require(newAddress != address(dividendTracker), "Jester: The dividend tracker already has that address");

        JesterDividendTracker newDividendTracker = JesterDividendTracker(payable(newAddress));

        require(newDividendTracker.owner() == address(this), "Jester: The new dividend tracker must be owned by the Jester token contract");

        newDividendTracker.excludeFromDividends(address(newDividendTracker));
        newDividendTracker.excludeFromDividends(address(this));
        newDividendTracker.excludeFromDividends(owner());
        newDividendTracker.excludeFromDividends(address(uniswapV2Router));

        emit UpdateDividendTracker(newAddress, address(dividendTracker));

        dividendTracker = newDividendTracker;
    }

    function updateUniswapV2Router(address newAddress) public onlyOwner {
        require(newAddress != address(uniswapV2Router), "Jester: The router already has that address");
        emit UpdateUniswapV2Router(newAddress, address(uniswapV2Router));
        uniswapV2Router = IUniswapV2Router02(newAddress);
        address _uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
            .createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Pair = _uniswapV2Pair;
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(_isExcludedFromFees[account] != excluded, "Jester: Account is already excluded");
        _isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded) public onlyOwner {
        for(uint256 i = 0; i < accounts.length; i++) {
            _isExcludedFromFees[accounts[i]] = excluded;
        }

        emit ExcludeMultipleAccountsFromFees(accounts, excluded);
    }

    function setTrading(bool value) external onlyOwner{
        isTradingEnabled = value;
    }

    function setDailyLimit(uint256 value) external onlyOwner{
        dailyLimit = value;
    }

    function setSwapAtAmount(uint256 value) external onlyOwner{
        swapTokensAtAmount = value;
    }

    function setWallets(address marketing, address dev, address charity) external onlyOwner{
        _marketingWallet = payable(marketing);
        _devWallet = payable(dev);
        _charityWallet = payable(charity);
    }

    function setrewardsFee(uint8 value) external onlyOwner{
        rewardsFee = value;
        totalFees = rewardsFee + liquidityFee + marketingFee + lotteryFee + devFee + charityFee;
    }

    function setLiquidityFee(uint8 value) external onlyOwner{
        liquidityFee = value;
        totalFees = rewardsFee + liquidityFee + marketingFee + lotteryFee + devFee + charityFee;
    }

    function setWalletFees(uint8 marketing, uint8 dev, uint8 charity) external onlyOwner{
        marketingFee = marketing;
        devFee = dev;
        charityFee = charity;
        totalFees = rewardsFee + liquidityFee + marketingFee + lotteryFee + devFee + charityFee;

    }

    function setLotteryState(bool value) external onlyOwner {
        isLotteryActive = value;
    }

    function setLotteryFee(uint8 _lotteryFee) external onlyOwner{
        lotteryFee = _lotteryFee;
        totalFees = rewardsFee + liquidityFee + marketingFee + lotteryFee + devFee + charityFee;

    }

    function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
        require(pair != uniswapV2Pair, "Jester: The PancakeSwap pair cannot be removed from automatedMarketMakerPairs");

        _setAutomatedMarketMakerPair(pair, value);
    }
    
    function excludeFromWhale(address account, bool value) external onlyOwner{
        _isExcludedFromWhale[account] = value;
    }


    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(automatedMarketMakerPairs[pair] != value, "Jester: Automated market maker pair is already set to that value");
        automatedMarketMakerPairs[pair] = value;

        if(value) {
            dividendTracker.excludeFromDividends(pair);
        }

        emit SetAutomatedMarketMakerPair(pair, value);
    }


    function updateGasForProcessing(uint256 newValue) public onlyOwner {
        require(newValue >= 200000 && newValue <= 500000, "Jester: gasForProcessing must be between 200,000 and 500,000");
        emit GasForProcessingUpdated(newValue, gasForProcessing);
        gasForProcessing = newValue;
    }

    function claimStuckTokens(address _token) external onlyOwner {
        if (_token == address(0x0)) {
            payable(owner()).transfer(address(this).balance);
            return;
        }
        IERC20 erc20token = IERC20(_token);
        uint256 balance = erc20token.balanceOf(address(this));
        erc20token.transfer(owner(), balance);
    }

    function updateClaimWait(uint256 claimWait) external onlyOwner {
        dividendTracker.updateClaimWait(claimWait);
    }

    function getClaimWait() external view returns(uint256) {
        return dividendTracker.claimWait();
    }

    function getTotalDividendsDistributed() external view returns (uint256) {
        return dividendTracker.totalDividendsDistributed();
    }

    function isExcludedFromFees(address account) public view returns(bool) {
        return _isExcludedFromFees[account];
    }

    function withdrawableDividendOf(address account) public view returns(uint256) {
    	return dividendTracker.withdrawableDividendOf(account);
  	}

	function dividendTokenBalanceOf(address account) public view returns (uint256) {
		return dividendTracker.balanceOf(account);
	}

	function excludeFromDividends(address account) external onlyOwner{
	    dividendTracker.excludeFromDividends(account);
	}

    // 0 - BNB dividend
    // 1 - BTC dividend
    // 2 - Native Token dividend 
    function setClaimMode(uint8 value) external {
        require(value < 3,"Invalid mode");
	    dividendTracker.setClaimMode(msg.sender,value); 
	}

    function excludeFromWeekly(address account) external onlyOwner{
	    lotteryTracker.excludeFromWeekly(account);
	}

	
	function setMinValues(uint256 _weekly) external onlyOwner {
	    lotteryTracker.setMinValues(_weekly);
	}

    function getAccountDividendsInfo(address account)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        return dividendTracker.getAccount(account);
    }

	function getAccountDividendsInfoAtIndex(uint256 index)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
    	return dividendTracker.getAccountAtIndex(index);
    }

	function processDividendTracker(uint256 gas) external {
		(uint256 iterations, uint256 claims, uint256 lastProcessedIndex) = dividendTracker.process(gas);
		emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, false, gas, tx.origin);
    }

    function claim() external {
		dividendTracker.processAccount(payable(msg.sender), false);
    }

    function getLastProcessedIndex() external view returns(uint256) {
    	return dividendTracker.getLastProcessedIndex();
    }

    function getNumberOfDividendTokenHolders() external view returns(uint256) {
        return dividendTracker.getNumberOfTokenHolders();
    }


    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if(amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

		uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if( canSwap &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            from != owner() &&
            to != owner()
        ) {
            swapping = true;

            contractTokenBalance = swapTokensAtAmount.div(10);

            uint256 feeTokens = contractTokenBalance.mul(marketingFee + devFee + charityFee).div(totalFees);
            swapAndSendToFee(feeTokens);

            uint256 swapTokens = contractTokenBalance.mul(liquidityFee).div(totalFees);
            swapAndLiquify(swapTokens);

            uint256 sellTokens = balanceOf(address(this));
            swapAndSendDividendsAndLottery(sellTokens);

            swapping = false;
        }


        bool takeFee = !swapping;

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if(_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        if(takeFee) {
            require(isTradingEnabled,"Trading not enabled yet");

            if(automatedMarketMakerPairs[to] && !_isExcludedFromWhale[from]){
                if(block.timestamp - lastSoldTime[from] > 1 days){
                    lastSoldTime[from] = block.timestamp;
                    soldTokenin24Hrs[from] = 0;
                }
                
                require(soldTokenin24Hrs[from] + amount <= dailyLimit,
                        "Token amount exceeds daily limit");

                soldTokenin24Hrs[from] = soldTokenin24Hrs[from].add(amount);
            }

        	uint256 fees = amount.mul(totalFees).div(1000);

        	amount = amount.sub(fees);

            super._transfer(from, address(this), fees);
        }

        super._transfer(from, to, amount);

        try dividendTracker.setBalance(payable(from), balanceOf(from)) {} catch {}
        try dividendTracker.setBalance(payable(to), balanceOf(to)) {} catch {}

        try lotteryTracker.setAccount(payable(from), balanceOf(from), true) {} catch {}
        try lotteryTracker.setAccount(payable(to), balanceOf(to), false) {} catch {}

        if(isLotteryActive){
            if(block.timestamp >= lotteryTracker.lastWeeklyDistributed() + 7 days){
                if(!isAlreadyCalled){
                    lotteryTracker.getRandomNumber();
                    isAlreadyCalled = true;
                }else{
                    try lotteryTracker.pickWeeklyWinners() {isAlreadyCalled = false;} catch {}
                }
            
            }
        }

        if(!swapping) {
	    	uint256 gas = gasForProcessing;

	    	try dividendTracker.process(gas) returns (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) {
	    		emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, true, gas, tx.origin);
	    	}
	    	catch {

	    	}
        }
    }

    function swapAndSendToFee(uint256 tokens) private  {

        uint256 initialBalance = address(this).balance;
        swapTokensForEth(tokens);
        uint256 newBalance = address(this).balance.sub(initialBalance);

        uint16 total = marketingFee + devFee + charityFee;

        uint256 marketingShare = newBalance.mul(marketingFee).div(total);
        uint256 devShare = newBalance.mul(devFee).div(total);
        uint256 charityShare = newBalance.mul(charityFee).div(total);

        _marketingWallet.transfer(marketingShare);
        _devWallet.transfer(devShare);
        _charityWallet.transfer(charityShare);

        emit SendWalletFees(marketingShare, devShare, charityShare);
    }

    function swapAndSendDividendsAndLottery(uint256 tokens) private{
        uint256 initialBalance = address(this).balance;
        swapTokensForEth(tokens);
        uint256 dividends = address(this).balance.sub(initialBalance);

        uint256 lottery = dividends.mul(lotteryFee).div(lotteryFee + rewardsFee);
        dividends = dividends.sub(lottery);

        (bool dividendSuccess,) = address(dividendTracker).call{value: dividends}("");
 
        if(dividendSuccess) {
   	 		emit SendDividends(dividends);
        }

        (bool lotterySuccess,) = address(lotteryTracker).call{value: lottery}("");

        if(lotterySuccess) {
            emit SendLottery(lottery);
        }

    }

    function swapAndLiquify(uint256 tokens) private {
       // split the contract balance into halves
        uint256 half = tokens.div(2);
        uint256 otherHalf = tokens.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }


    function swapTokensForEth(uint256 tokenAmount) private {


        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );

    }


    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {

        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(0),
            block.timestamp
        );

    }

}

contract JesterDividendTracker is Ownable, DividendPayingToken {
    using SafeMath for uint256;
    using SafeMathInt for int256;
    using IterableMapping for IterableMapping.Map;

    IterableMapping.Map private tokenHoldersMap;
    uint256 public lastProcessedIndex;

    mapping (address => uint8) public choiceOfUser;

    mapping (address => bool) public excludedFromDividends;

    mapping (address => uint256) public lastClaimTimes;

    uint256 public claimWait;
    uint256 public immutable minimumTokenBalanceForDividends;

    event ExcludeFromDividends(address indexed account);
    event ClaimWaitUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event Claim(address indexed account, uint256 amount, bool indexed automatic);

    constructor(address router) DividendPayingToken("Jester_Dividen_Tracker", 
            "Jester_Dividend_Tracker",router, msg.sender) {
    	claimWait = 3600;
        minimumTokenBalanceForDividends = 20000 * (10**18); //must hold 20000+ tokens
    }

    function _transfer(address, address, uint256) internal pure override {
        require(false, "Jester_Dividend_Tracker: No transfers allowed");
    }

    function withdrawDividend(uint8 val) public pure override {
        val = 0;
        require(false, "Jester_Dividend_Tracker: withdrawDividend disabled. Use the 'claim' function on the main Jester contract.");
    }

    function excludeFromDividends(address account) external onlyOwner {
    	require(!excludedFromDividends[account]);
    	excludedFromDividends[account] = true;

    	_setBalance(account, 0);
    	tokenHoldersMap.remove(account);

    	emit ExcludeFromDividends(account);
    }

    function updateClaimWait(uint256 newClaimWait) external onlyOwner {
        require(newClaimWait >= 3600 && newClaimWait <= 86400, "Jester_Dividend_Tracker: claimWait must be updated to between 1 and 24 hours");
        require(newClaimWait != claimWait, "Jester_Dividend_Tracker: Cannot update claimWait to same value");
        emit ClaimWaitUpdated(newClaimWait, claimWait);
        claimWait = newClaimWait;
    }

    function getLastProcessedIndex() external view returns(uint256) {
    	return lastProcessedIndex;
    }

    function getNumberOfTokenHolders() external view returns(uint256) {
        return tokenHoldersMap.keys.length;
    }



    function getAccount(address _account)
        public view returns (
            address account,
            int256 index,
            int256 iterationsUntilProcessed,
            uint256 withdrawableDividends,
            uint256 totalDividends,
            uint256 lastClaimTime,
            uint256 nextClaimTime,
            uint256 secondsUntilAutoClaimAvailable) {
        account = _account;

        index = tokenHoldersMap.getIndexOfKey(account);

        iterationsUntilProcessed = -1;

        if(index >= 0) {
            if(uint256(index) > lastProcessedIndex) {
                iterationsUntilProcessed = index.sub(int256(lastProcessedIndex));
            }
            else {
                uint256 processesUntilEndOfArray = tokenHoldersMap.keys.length > lastProcessedIndex ?
                                                        tokenHoldersMap.keys.length.sub(lastProcessedIndex) :
                                                        0;


                iterationsUntilProcessed = index.add(int256(processesUntilEndOfArray));
            }
        }


        withdrawableDividends = withdrawableDividendOf(account);
        totalDividends = accumulativeDividendOf(account);

        lastClaimTime = lastClaimTimes[account];

        nextClaimTime = lastClaimTime > 0 ?
                                    lastClaimTime.add(claimWait) :
                                    0;

        secondsUntilAutoClaimAvailable = nextClaimTime > block.timestamp ?
                                                    nextClaimTime.sub(block.timestamp) :
                                                    0;
    }

    function getAccountAtIndex(uint256 index)
        public view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
    	if(index >= tokenHoldersMap.size()) {
            return (0x0000000000000000000000000000000000000000, -1, -1, 0, 0, 0, 0, 0);
        }

        address account = tokenHoldersMap.getKeyAtIndex(index);

        return getAccount(account);
    }

    function canAutoClaim(uint256 lastClaimTime) private view returns (bool) {
    	if(lastClaimTime > block.timestamp)  {
    		return false;
    	}

    	return block.timestamp.sub(lastClaimTime) >= claimWait;
    }

    function setBalance(address payable account, uint256 newBalance) external onlyOwner {
    	if(excludedFromDividends[account]) {
    		return;
    	}

    	if(newBalance >= minimumTokenBalanceForDividends) {
            _setBalance(account, newBalance);
    		tokenHoldersMap.set(account, newBalance);
    	}
    	else {
            _setBalance(account, 0);
    		tokenHoldersMap.remove(account);
    	}

    	processAccount(account, true);
    }

    function setClaimMode(address user, uint8 val) external onlyOwner {
        choiceOfUser[user] = val;
    }

    function process(uint256 gas) public returns (uint256, uint256, uint256) {
    	uint256 numberOfTokenHolders = tokenHoldersMap.keys.length;

    	if(numberOfTokenHolders == 0) {
    		return (0, 0, lastProcessedIndex);
    	}

    	uint256 _lastProcessedIndex = lastProcessedIndex;

    	uint256 gasUsed = 0;

    	uint256 gasLeft = gasleft();

    	uint256 iterations = 0;
    	uint256 claims = 0;

    	while(gasUsed < gas && iterations < numberOfTokenHolders) {
    		_lastProcessedIndex++;

    		if(_lastProcessedIndex >= tokenHoldersMap.keys.length) {
    			_lastProcessedIndex = 0;
    		}

    		address account = tokenHoldersMap.keys[_lastProcessedIndex];

    		if(canAutoClaim(lastClaimTimes[account])) {
    			if(processAccount(payable(account), true)) {
    				claims++;
    			}
    		}

    		iterations++;

    		uint256 newGasLeft = gasleft();

    		if(gasLeft > newGasLeft) {
    			gasUsed = gasUsed.add(gasLeft.sub(newGasLeft));
    		}

    		gasLeft = newGasLeft;
    	}

    	lastProcessedIndex = _lastProcessedIndex;

    	return (iterations, claims, lastProcessedIndex);
    }

    function processAccount(address payable account, bool automatic) public onlyOwner returns (bool) {
        uint256 amount = _withdrawDividendOfUser(account,choiceOfUser[account]);

    	if(amount > 0) {
    		lastClaimTimes[account] = block.timestamp;
            emit Claim(account, amount, automatic);
    		return true;
    	}

    	return false;
    }
}

