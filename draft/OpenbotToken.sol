//TODO
//renounceTreasurySet

//double check etra fee mechanism
//make extra fee turnoffable
// in case an early buyers transfers we need to copy over the tag
//name and symbol
//transferDelayEnabled removed

// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

//TODO header here

import "./lib/Openzeppelin/Context.sol";
import "./lib/Openzeppelin/Ownable.sol";
import "./lib/Openzeppelin/IERC20.sol";
import "./lib/Openzeppelin/IERC20Metadata.sol";
import "./lib/Openzeppelin/ERC20.sol";
import "./lib/IUniswapV2Factory.sol";
import "./lib/IUniswapV2Pair.sol";
import "./lib/IUniswapV2Router02.sol";

contract OpenBotToken is ERC20, Ownable {
    // --- variables ---
    //the total supply of the token
    uint256 private _totalSupply = 1_000_000_000 * 1e18;
    // buy and sell fee, can only ever be reduced (5%)
    // unlike previous tax token contracts we collect only one fee
    // and the treasury decides how to use it
    // buy and sell are symmetric
    uint256 public txFeesPc = 5;
    // maximum to buy and sell during boostrap (1%)
    uint256 public maxTransactionAmount = 10_000_000 * 1e18;
    // maximum to hold during boostrap (1%)
    uint256 public maxWallet = 10_000_000 * 1e18;

    //TODO! need to able to make it renounceable just in case
    // associated treasury where fees go to
    // initally this will be just a wallet but adjust to a smart contract
    address public treasuryAddress;
    address public constant unirouterAddress =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    // as an extreme case because treasury is better to be upgradeable
    bool public treasurySetNotRevoked = true;

    // AutomatedMarketMaking pairs
    mapping(address => bool) public ammPairs;

    //the limits of boostrap are on/off
    bool public bootstrapLimitsOn = true;
    // extra boostrap fee, allow it to set off just in case
    bool takeExtraFee = true;
    // variable to check if amm pair was set by owner because token doesnt create the pair
    bool public ammSet = false;
    // is trading active
    bool public tradingActive = false;
    // launch of the token
    uint256 public launchTime;
    //bool if maxlimit is on, the max holding amount
    bool public maxLimitOn = true;
    //bool if maxTxlimit is on, the max transfer amount
    bool public maxTxLimitOn = true;
    // the period which is considered boostrap phase
    // early buyers deserve the upside for taking risk, but
    // uniswap curve adjusts too slowly. early buyers during this period will be tagged
    uint256 public constant earlyEnterPeriod = 5 days;
    // to hold last Transfers temporarily during launch
    mapping(address => uint256) private _holderLastTransferTimestamp;
    // track buyers during bootstrap phase, count the first purchase only
    // in case an early buyers transfers we need to copy over the tag
    mapping(address => uint256) private _firstTransferTimestamp;
    // is liqudity added
    bool public liqudityadded = false;

    // exlcude from fees
    mapping(address => bool) public _isExcludedFromFees;
    // exlcude from max transaction amount
    mapping(address => bool) public _isExcludedMaxTxAmount;

    // --- events ---
    event ExcludeFromFees(address indexed account, bool isExcluded);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event treasuryUpdated(address indexed _addr, address indexed oldAddress);

    constructor() ERC20("XXX", "XXX") {
        //treasury is set to deployer at start which then points it to treasury later
        treasuryAddress = msg.sender;
        //mint 100%, no inflation, no premine
        _mint(msg.sender, _totalSupply);

        // exclude from paying fees or having max transaction amount
        //TODO! double check unirouter not excluded from fees
        excludeFromMaxTx(unirouterAddress, true);

        excludeFromMaxTx(owner(), true);
        excludeFromMaxTx(treasuryAddress, true);
        //excludeFromMaxTx(address(this), true);
        excludeFromMaxTx(address(0xdead), true);

        excludeFromFees(owner(), true);
        excludeFromFees(treasuryAddress, true);
        //excludeFromFees(address(this), true);
        excludeFromFees(address(0xdead), true);
    }

    //dont allow send ETH
    //receive() external payable {}

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function startTrading() external onlyOwner {
        require(ammSet, "AMM pair not set yet");
        require(liqudityadded, "Liquidity not added yet");
        tradingActive = true;
        launchTime = block.timestamp;
    }

    function setAMM(address addrs, bool isamm) public onlyOwner {
        ammPairs[addrs] = isamm;
        ammSet = true;
        excludeFromMaxTx(addrs, true);
    }

    function excludeFromMaxTx(address _addr, bool _excluded) public onlyOwner {
        _isExcludedMaxTxAmount[_addr] = _excluded;
    }

    function removeLimits() external onlyOwner {
        bootstrapLimitsOn = false;
    }

    function removeMaxLimitOn() external onlyOwner {
        maxLimitOn = false;
    }

    function removeMaxTxLimitOn() external onlyOwner {
        maxTxLimitOn = false;
    }

    //fees can only be adjusted downwards
    function setFees(uint256 newFee) external onlyOwner {
        require(newFee <= txFeesPc, "tax can only decrease");
        txFeesPc = newFee;
    }

    function setMaxWalletAmount(uint256 _newval) external onlyOwner {
        require(_newval >= 5_000_000 * 1e18, "Can not set lower than 0.5%");
        maxWallet = _newval;
    }

    function setMaxTxAmount(uint256 _newval) external onlyOwner {
        require(_newval >= 5_000_000 * 1e18, "Can not set lower than 0.5%");
        maxTransactionAmount = _newval;
    }

    // set extra boostrap fee
    function setBootstrapFee(bool set) external onlyOwner {
        takeExtraFee = set;
    }

    function setTreasurySetNotRevoked() external onlyOwner {
        treasurySetNotRevoked = false;
    }

    function setTreasuryWallet(address _addr) external onlyOwner {
        require(treasurySetNotRevoked, "Treasury set is revoked");
        emit treasuryUpdated(_addr, treasuryAddress);
        treasuryAddress = _addr;
    }

    function isBuy(address from, address to) internal view returns (bool) {
        return ammPairs[from] && !_isExcludedMaxTxAmount[to];
    }

    function isSell(address from, address to) internal view returns (bool) {
        return ammPairs[to] && !_isExcludedMaxTxAmount[from];
    }

    function isWithinMaxTxLimit(uint256 amount) internal view returns (bool) {
        return maxTxLimitOn && (amount <= maxTransactionAmount);
    }

    function isWithinMaxWalletLimit(
        address to,
        uint256 amount
    ) internal view returns (bool) {
        return maxLimitOn && (amount + balanceOf(to) <= maxWallet);
    }

    // extra fees during boostrap
    // calculated as number of days x 1%, backwards from 40
    function calcExtraFee(address sender) public view returns (uint256) {
        uint256 extraFeesPc = 0; // initialize extraFeesPc to zero

        // Check if address is tagged
        if (_firstTransferTimestamp[sender] > 0) {
            uint256 daysSinceLaunch = (block.timestamp - launchTime) /
                (60 * 60 * 24);
            if (daysSinceLaunch < 40) {
                extraFeesPc = 40 - daysSinceLaunch;
            }
        }

        return extraFeesPc;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address.");
        require(to != address(0), "ERC20: transfer to the zero address.");
        require(amount > 0, "CANT TRANSFER 0");

        //--- boostrap phase ----
        if (bootstrapLimitsOn) {
            if (from != owner() && to != owner()) {
                if (!tradingActive) {
                    require(
                        _isExcludedFromFees[from] || _isExcludedFromFees[to],
                        "Trading is not active!"
                    );
                }
            }

            // when buy
            if (isBuy(from, to)) {
                require(
                    isWithinMaxTxLimit(amount),
                    "Buy transfer amount > maxTransactionAmount!"
                );
                require(
                    isWithinMaxWalletLimit(to, amount),
                    "Max wallet exceeded"
                );

                //TODO double check
                // mark early buy as long as earlyEnterPeriod is active
                if (block.timestamp < launchTime + earlyEnterPeriod) {
                    // mark only if hasn't been marked before
                    if (_firstTransferTimestamp[msg.sender] == 0) {
                        _firstTransferTimestamp[msg.sender] = block.timestamp;
                    }
                }
            }
            // when sell
            else if (isSell(from, to)) {
                require(
                    isWithinMaxTxLimit(amount),
                    "Sell transfer amount > maxTransactionAmount!"
                );
                //no need test for isWithinMaxWalletLimit
            }
            //normal transfer
            else if (!_isExcludedMaxTxAmount[to]) {
                require(
                    isWithinMaxWalletLimit(to, amount),
                    "Max wallet exceeded"
                );

                // TODO double check
                // track transfers firstTransferTimestamp and apply marking
                if (_firstTransferTimestamp[msg.sender] > 0) {
                    //copy the tag from the account where tokens sent to
                    _firstTransferTimestamp[to] = _firstTransferTimestamp[from];
                }
            }
        }

        //bool takeFee = true;
        bool excludeFee = _isExcludedFromFees[from] || _isExcludedFromFees[to];

        uint256 fees = 0;
        uint256 extraFeesPc = 0;

        // only take fees on buys/sells, do not take on wallet transfers

        if (!excludeFee) {
            if (takeExtraFee) {
                //TODO tx.origin?
                // address is tagged
                extraFeesPc = calcExtraFee(from);
            }

            // on sell
            if (ammPairs[to] || ammPairs[from]) {
                fees = (amount * (txFeesPc + extraFeesPc)) / 100;
            }

            // transfer fees to treasury which governs expending or reusing it
            if (fees > 0) {
                super._transfer(from, treasuryAddress, fees);
            }

            amount -= fees;
        }

        super._transfer(from, to, amount);
    }

    //function renounceTreasury
}
