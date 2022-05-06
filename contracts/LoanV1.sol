// One way of implementation 
// Bugs and flaws // Access Specifiers

pragma solidity ^0.8.11;


import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract LoanV1NFT {

    address public immutable lenderAddress;

    
    address public immutable borrowerAddress;

   
    ERC721 public immutable nftCollection;

    
    uint256 public immutable nftId;


    uint256 public immutable dueDate;

   
    uint256 public immutable rentalPayment;

   
    uint256 public immutable collateral;

    
    uint256 public immutable collateralPayoutPeriod;

   
    uint256 public immutable nullificationTime;

   
    uint256 public rentalStartTime;

  
    uint256 public collectedCollateral;

    
    bool public nftIsDeposited;

    
    bool public ethIsDeposited;

   
    event RentalStarted();
    event NftReturned();
    event PayoutPeriodBegins();
    event PayoutPeriodEnds();

  
    error InsufficientValue();
    error Unauthorized();
    error InvalidState();
    error BadTimeBounds();
    error AlreadyDeposited();
    error NonTokenOwner();

   
    constructor(
        address _lenderAddress,
        address _borrowerAddress,
        address _nftAddress,
        uint256 _nftId,
        uint256 _dueDate,
        uint256 _rentalPayment,
        uint256 _collateral,
        uint256 _collateralPayoutPeriod,
        uint256 _nullificationTime
    ) {

        if (ERC721(_nftAddress).ownerOf(_nftId) != _lenderAddress) revert NonTokenOwner();

        
        if (_borrowerAddress.balance < _rentalPayment + _collateral) revert InsufficientValue();

        
        if (_dueDate < block.timestamp) revert BadTimeBounds();
        
        lenderAddress = payable(_lenderAddress);
        borrowerAddress = payable(_borrowerAddress);
        nftCollection = ERC721(_nftAddress);
        nftId = _nftId;
        dueDate = _dueDate;
        rentalPayment = _rentalPayment;
        collateral = _collateral;
        collateralPayoutPeriod = _collateralPayoutPeriod;
        nullificationTime = _nullificationTime;
    }

  
    function depositNft() external payable {
       
        if (nftIsDeposited) revert AlreadyDeposited();

       
        if (msg.sender != lenderAddress) revert Unauthorized();

        
        if (block.timestamp >= nullificationTime) {
            selfdestruct(payable(borrowerAddress));
        }

        
        if (!ethIsDeposited) {
            nftCollection.safeTransferFrom(msg.sender, address(this), nftId);
            nftIsDeposited = true;
        } else {
            nftCollection.safeTransferFrom(msg.sender, borrowerAddress, nftId);
          
            payable(lenderAddress).transfer(rentalPayment);
            nftIsDeposited = true;
            emit RentalStarted();
            _beginRental();
        }
    }

 
    function depositEth() external payable {
        
        if (ethIsDeposited) revert AlreadyDeposited();

        
        if (msg.sender != borrowerAddress) revert Unauthorized();

        if (msg.value < rentalPayment + collateral) revert InsufficientValue();

        
        if (block.timestamp >= nullificationTime) {
            if (nftCollection.ownerOf(nftId) == address(this)) {
                nftCollection.safeTransferFrom(address(this), lenderAddress, nftId);
            }
            selfdestruct(payable(borrowerAddress));
        }

        
        if (msg.value > rentalPayment + collateral) {
            payable(msg.sender).transfer(msg.value - (rentalPayment + collateral));
        }

        
        if (!nftIsDeposited) {
            
            ethIsDeposited = true;        
        } else { 
            
            payable(lenderAddress).transfer(rentalPayment);
            
            nftCollection.safeTransferFrom(address(this), borrowerAddress, nftId);
            ethIsDeposited = true;
            emit RentalStarted();
            _beginRental();
        }
    }

    
    function withdrawNft() external payable {
        
        if (msg.sender != lenderAddress) revert Unauthorized();

        
        if (!nftIsDeposited || ethIsDeposited) revert InvalidState();

        
        nftCollection.safeTransferFrom(address(this), lenderAddress, nftId);
    }

    
    function withdrawEth() external payable {
       
        if (msg.sender != borrowerAddress) revert Unauthorized();

        
        if (nftIsDeposited || !ethIsDeposited) revert InvalidState();

        
        payable(borrowerAddress).transfer(rentalPayment + collateral);
    }

    
    function returnNft() external {
        
        nftCollection.safeTransferFrom(msg.sender, lenderAddress, nftId);

        
        if (block.timestamp <= dueDate) {
            
            payable(borrowerAddress).transfer(collateral);
        }
        
        else if (block.timestamp > dueDate) {
            
            withdrawCollateral();
            
            payable(borrowerAddress).transfer(address(this).balance);
        }
    }

    
    function withdrawCollateral() public {
        
        if (block.timestamp <= dueDate) revert InvalidState();

        uint256 tardiness = block.timestamp - dueDate;
        uint256 payableAmount;
        if (tardiness >= collateralPayoutPeriod) {
            payableAmount = collateral;
        } else {
            payableAmount = (tardiness * collateral) / collateralPayoutPeriod;
        }

        
        payableAmount -= collectedCollateral;

        
        collectedCollateral += payableAmount;

        if(ethIsDeposited && nftIsDeposited) {
         
            payable(lenderAddress).transfer(payableAmount);
        } else {
           
            payable(borrowerAddress).transfer(address(this).balance);
        }
    }

    
    function _beginRental() internal {
        rentalStartTime = block.timestamp;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}