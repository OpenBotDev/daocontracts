//make bonding discretionary or fully automated?

//ownable
contract Treasury {
    ObotToken public token;
    BondingRepo public bondingRepo;
    address public owner;

    constructor() {
        token = new ObotToken();
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    function startBondProgram(uint256 totalAmount) external onlyOwner {
        // Deploy BondingRepo contract
        //   address _token,
        // uint256 _totalCap,
        // uint256 _bondDuration,
        // uint256 _vestingDuration
        bondingRepo = new BondingRepo(token, totalAmount, 10 days);

        // Transfer the specified amount of tokens to the BondingRepo
        require(
            token.transfer(address(bondingRepo), amountToBond),
            "Token transfer failed"
        );
    }
}
