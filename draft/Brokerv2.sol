// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "./lib/IUniswapV2Router02.sol";

// broker trades on users behalf
// the purpose of the broker is to separate between custodial funds and trading operations

contract Broker {
    //WETH address not static because of crosschain
    address public WETH_ADDRESS;
    //router address not static because of crosschain
    //need to consider cross exchange case later
    address public unirouterAddress;
    IUniswapV2Router02 public immutable uniswapV2Router;

    //keep track of user ETH deposits
    mapping(address => uint256) public ethBalances;
    //keep track of token deposits
    mapping(address => mapping(address => uint256)) public tokenBalances;

    event Deposited(address indexed user, uint256 amount);
    event TokenDeposited(address indexed user, address token, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event TokenWithdrawn(address indexed user, address token, uint256 amount);

    // Mapping from original account to delegate account
    mapping(address => address) public delegates;

    constructor(address _wethAddress, address _unirouterAddress) {
        owner = msg.sender;
        unirouterAddress = _unirouterAddress;
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            unirouterAddress
        );
        WETH_ADDRESS = _wethAddress;
    }

    // set a trader delegate
    function setTraderDelegate(address delegate) external {
        require(msg.sender != delegate, "can not set to self");
        delegates[msg.sender] = delegate;
        //emit DelegateChanged(msg.sender, delegate);
    }

    // Deposit ETH into the contract
    function deposit() external payable {
        ethBalances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    // Withdraw ETH from the contract
    function withdraw(uint256 amount) external {
        require(ethBalances[msg.sender] >= amount, "Insufficient ETH balance");
        ethBalances[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
        emit Withdrawn(msg.sender, amount);
    }

    //deposit admin?

    // Deposit ERC20 tokens into the contract
    function depositToken(address tokenAddress, uint256 amount) external {
        IERC20 token = IERC20(tokenAddress);
        require(
            token.transferFrom(msg.sender, address(this), amount),
            "Token transfer failed"
        );
        tokenBalances[tokenAddress][msg.sender] += amount;
        emit TokenDeposited(msg.sender, tokenAddress, amount);
    }

    // Withdraw ERC20 tokens from the contract
    function withdrawToken(address tokenAddress, uint256 amount) external {
        require(
            tokenBalances[tokenAddress][msg.sender] >= amount,
            "Insufficient token balance"
        );
        tokenBalances[tokenAddress][msg.sender] -= amount;
        IERC20(tokenAddress).transfer(msg.sender, amount);
        emit TokenWithdrawn(msg.sender, tokenAddress, amount);
    }

    // This function ensures that there is a delegate set for the given user
    // and that the current caller is the delegate of the user.
    function _effectiveDelegate(address user) internal view returns (address) {
        require(delegates[user] != address(0), "Delegate not set");
        require(
            delegates[user] == msg.sender,
            "Not authorized to trade for user"
        );
        return delegates[user];
    }

    function calculateRequiredETH(
        uint amountOut,
        address tokenAddress
    ) internal view returns (uint) {
        // Placeholder logic
        // You might want to call Uniswap's getAmountsIn or another appropriate function to get a good estimate
        // For now, we'll return a mock value
        return amountOut / 100;
    }

    function brokerSwapETHForExactTokens(
        uint ethIn,
        uint amountOut,
        address tokenAddress,
        //address[] calldata path,
        uint deadline
    ) external {
        //need to be careful with any calculations which effect the PnL of the broker/master contract
        //preferrable are user vault which are like seggregated accounts. however these cost gas.
        address trader = _effectiveDelegate(msg.sender);

        //problematic if this calculation is wrong there could be attack vectors
        uint estimatedEthRequired = calculateRequiredETH(
            amountOut,
            tokenAddress
        );
        //add 20% for security margin
        estimatedEthRequired = (estimatedEthRequired * 120) / 100;

        // need to check we have enough ETH to trade
        //msg.value doesnt matter
        require(
            ethBalances[trader] >= estimatedEthRequired,
            "Insufficient ETH balance"
        );

        // Deduct the ETH from the trader's balance
        //require(ethBalances[trader] >= msg.value, "Insufficient ETH balance");
        //ethBalances[trader] -= msg.value;

        // Dynamically generate the path
        address[] memory path = new address[](2);
        path[0] = WETH_ADDRESS;
        path[1] = tokenAddress;

        // Ensure the path is correct
        // require(
        //     path[0] == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
        //     "First address must be ETH"
        // );

        // Forward the call to Uniswap
        uniswapRouter.swapETHForExactTokens{value: ethIn}(
            amountOut,
            path,
            trader,
            deadline
        );
    }
}
