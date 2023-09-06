// BondingRepo
// bonds are sold from treasury from minted tokens, no inflation

pragma solidity ^0.8.0;

// Import ERC721 contract from OpenZeppelin library (you'll need to install this via npm)
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract BondingRepo is ERC721Enumerable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    MyToken public token;
    address public owner;

    //TODO!
    uint256 public constant TOKEN_PRICE = 1 ether;
    // total amount of the program
    uint256 public totalAmount;
    // the duration of the program
    uint256 public bondDepoDuration;
    // the duraton of vesting
    uint256 public vestingDuration;

    uint256 public lastBondedDay;
    uint256 public tokensBondedToday;

    struct Bond {
        uint256 totalAmount;
        uint256 bondDate;
        uint256 claimedAmount;
    }

    // Map a unique token ID to its VestingSchedule
    mapping(uint256 => VestingSchedule) public vestingSchedules;

    constructor(
        address _token,
        uint256 _totalAmount,
        uint256 _bondDepoDuration,
        uint256 _vestingDuration
    ) ERC721("BondToken", "BND") {
        token = MyToken(_token);
        owner = msg.sender;
        totalAmount = _totalAmount;
        bondDepoDuration = _bondDepoDuration;
        vestingDuration = _vestingDuration;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    // bond tokens which means acquire tokens at a discount from treasury
    // the discount is statically set
    function bondTokens() public payable {
        uint256 discountedPrice = TOKEN_PRICE -
            (TOKEN_PRICE * getDynamicDiscount()) /
            100;
        uint256 tokensToBond = msg.value / discountedPrice;

        require(tokensToBond <= totalCap, "Exceeds total cap");
        require(tokensToBond > 0, "Not enough Ether sent for bonding");

        totalCap -= tokensToBond;

        Bond memory newBond = Bond({
            totalAmount: tokensToBond,
            bondDate: block.timestamp,
            claimedAmount: 0
        });

        // Mint the NFT for the bond
        _tokenIdCounter.increment();
        uint256 newTokenId = _tokenIdCounter.current();
        _mint(msg.sender, newTokenId);
        bonds[newTokenId] = newBond;
    }

    function claimTokens(uint256 tokenId) public {
        require(ownerOf(tokenId) == msg.sender, "You do not own this bond.");

        Bond storage bond = bonds[tokenId];

        require(
            block.timestamp >= bond.bondDate + bondDuration,
            "Bonding period not over yet."
        );

        uint256 elapsedVestingTime = block.timestamp -
            (bond.bondDate + bondDuration);
        if (elapsedVestingTime > vestingDuration) {
            elapsedVestingTime = vestingDuration; // Cap at vesting duration
        }

        uint256 totalVestableAmount = bond.totalAmount;
        uint256 vestedAmount = (totalVestableAmount * elapsedVestingTime) /
            vestingDuration;
        uint256 claimableAmount = vestedAmount - bond.claimedAmount;

        require(claimableAmount > 0, "No tokens to claim at the moment.");

        bond.claimedAmount += claimableAmount;
        token.transfer(msg.sender, claimableAmount);

        if (bond.claimedAmount == bond.totalAmount) {
            _burn(tokenId); // Optionally burn the NFT when all tokens are claimed
        }
    }

    // TODO!
    function getDynamicDiscount() public view returns (uint256) {
        return 20;
    }
}
