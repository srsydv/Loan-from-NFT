//Taken from different OpenSource Project

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract LoanV2NFT is IERC721Receiver, Pausable, Ownable {

    event LoansUpdated();

    using SafeMath for uint;

    enum Status { PENDING, ACTIVE, CANCELLED, ENDED, DEFAULTED }

    struct LoanRequest {
        uint loanID;
        address payable lender;
        address payable borrower;
        address smartContractAddressOfNFT;
        uint tokenIdNFT;
        uint loanAmount;
        uint interestAmount;
        uint singlePeriodTime;
        uint maximumInterestPeriods;
        uint endLoanTimeStamp;
        Status status;
    }

    address public manager;

    uint public totalLoanRequests;


    mapping(uint => LoanRequest) public allLoanRequests;

    modifier isValidLoanID(uint loanID) {
        require(
            loanID < totalLoanRequests,
            "Loan ID is invalid."
        );
        _;
    }

    modifier onlyManager() { // Modifier
        require(
            msg.sender == manager,
            "Only leasing manager can call this."
        );
        _;
    }

    constructor() {
        manager = msg.sender;
        totalLoanRequests = 0;
    }

    function pauseLoans() public onlyManager {
        _pause();
    }

    function unPauseLoans() public onlyManager {
        _unpause();
    }

    function createLoanRequest(address smartContractAddressOfNFT,
                                uint tokenIdNFT,
                                uint loanAmount,
                                uint interestAmount,
                                uint singlePeriodTime,
                                uint maximumInterestPeriods) public whenNotPaused {
        require(singlePeriodTime <= 31 days, "A single period can have a maximum of one month.");
        require(interestAmount < 2*loanAmount, "Interest must be lower than 2 * principal of the loan.");
        require(maximumInterestPeriods <= 12, "Maximum interest periods are 12.");
        require(maximumInterestPeriods > 0, "Maximum interest period cannot be 0.");

        IERC721 currentNFT = IERC721(smartContractAddressOfNFT);
        require(currentNFT.getApproved(tokenIdNFT) == address(this), "Transfer has to be approved first");

        LoanRequest storage loanRequest =  allLoanRequests[totalLoanRequests];
        loanRequest.loanID = totalLoanRequests;
        loanRequest.lender = payable (address(0x0));
        loanRequest.borrower = payable(msg.sender);
        loanRequest.smartContractAddressOfNFT = smartContractAddressOfNFT;
        loanRequest.tokenIdNFT = tokenIdNFT;
        loanRequest.loanAmount = loanAmount;
        loanRequest.interestAmount = interestAmount;
        loanRequest.singlePeriodTime = singlePeriodTime;
        loanRequest.maximumInterestPeriods = maximumInterestPeriods;
        loanRequest.status = Status.PENDING;
        totalLoanRequests = SafeMath.add(totalLoanRequests, 1);

        currentNFT.safeTransferFrom(msg.sender, address(this), tokenIdNFT);
        emit LoansUpdated();
    }

    function acceptLoanRequest(uint loanID) payable public isValidLoanID(loanID) whenNotPaused {
        require(allLoanRequests[loanID].status == Status.PENDING, "Status is not PENDING for loan.");
        require(allLoanRequests[loanID].borrower != msg.sender, "Invalid operation. You cannot underwrite your own loan.");

        uint sumForLoan = allLoanRequests[loanID].loanAmount - allLoanRequests[loanID].interestAmount;
        require(msg.value >= sumForLoan, "Not enough Ether sent to function to underwrite loan.");

        allLoanRequests[loanID].maximumInterestPeriods = allLoanRequests[loanID].maximumInterestPeriods - 1;

        allLoanRequests[loanID].lender = payable(msg.sender);
        allLoanRequests[loanID].status = Status.ACTIVE;
        allLoanRequests[loanID].endLoanTimeStamp = SafeMath.add(block.timestamp, allLoanRequests[loanID].singlePeriodTime);


        uint ourSHARE = sumForLoan.mul(25).div(1000);
        allLoanRequests[loanID].borrower.transfer(sumForLoan - ourSHARE);
        emit LoansUpdated();

 
    }

    function extendLoanRequest(uint loanID) payable public isValidLoanID(loanID) whenNotPaused {
        require(allLoanRequests[loanID].status == Status.ACTIVE, "Status is not ACTIVE for loan");
        require(allLoanRequests[loanID].borrower == msg.sender, "Only the borrower can call this function.");
        require(allLoanRequests[loanID].maximumInterestPeriods > 0, "The maximum number of extensions to the loan has been reached.");
        require(msg.value >= allLoanRequests[loanID].interestAmount, "Not enough Ether sent to the function to extend loan.");


        allLoanRequests[loanID].maximumInterestPeriods = allLoanRequests[loanID].maximumInterestPeriods - 1;
        allLoanRequests[loanID].endLoanTimeStamp = SafeMath.add(allLoanRequests[loanID].endLoanTimeStamp, allLoanRequests[loanID].singlePeriodTime);

        allLoanRequests[loanID].lender.transfer(allLoanRequests[loanID].interestAmount);
        emit LoansUpdated();
    }

    function endLoanRequest(uint loanID) payable public isValidLoanID(loanID) {
        require(allLoanRequests[loanID].status == Status.ACTIVE, "Status is not ACTIVE to end loan.");
        require((msg.sender == allLoanRequests[loanID].lender  &&
                block.timestamp >= allLoanRequests[loanID].endLoanTimeStamp) || msg.sender == allLoanRequests[loanID].borrower,
                "Unable to end loan.");

        if (msg.sender == allLoanRequests[loanID].borrower) {
            require(msg.value >= allLoanRequests[loanID].loanAmount, "The principal amount of the loan was not sent.");
            allLoanRequests[loanID].status = Status.ENDED;
            allLoanRequests[loanID].lender.transfer(allLoanRequests[loanID].loanAmount);
            
        } else {
            allLoanRequests[loanID].status = Status.DEFAULTED;
        }

        
        IERC721 currentNFT = IERC721(allLoanRequests[loanID].smartContractAddressOfNFT);
        currentNFT.approve(msg.sender, allLoanRequests[loanID].tokenIdNFT);
        currentNFT.transferFrom(address(this), msg.sender, allLoanRequests[loanID].tokenIdNFT);
        emit LoansUpdated();
    }

    function cancelLoanRequest(uint loanID) public isValidLoanID(loanID) {
        require(allLoanRequests[loanID].status == Status.PENDING, "Status is not PENDING to cancel loan request");
        require(msg.sender == allLoanRequests[loanID].borrower);

        allLoanRequests[loanID].status = Status.CANCELLED;

        IERC721 currentNFT = IERC721(allLoanRequests[loanID].smartContractAddressOfNFT);
        currentNFT.approve(msg.sender, allLoanRequests[loanID].tokenIdNFT);
        currentNFT.transferFrom(address(this), msg.sender, allLoanRequests[loanID].tokenIdNFT);
        emit LoansUpdated();
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