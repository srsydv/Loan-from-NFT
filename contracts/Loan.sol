pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LoanNFT is IERC721Receiver, Ownable,Pausable {


    // Internel Logic to remove abstract error
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    using SafeMath for uint;

    enum Status { PENDING, ACTIVE, CANCELLED, ENDED, DEFAULTED }

    struct Loan {
        uint loanID;
        address payable lender;
        address payable borrower;
        address smartContractAddressOfNFT;
        uint tokenIdNFT;
        uint loanAmount;
        uint interestAmount;
        uint totalTimePeriod;
        uint maxTimePeriod;
        uint endLoanTimeStamp;
        Status status;
    }

    event LoanDataOnCreate(address from , uint256 loanId, uint loanAmount, uint interestAmount, uint totalTime, uint extendTimePeriod, Status status);
    event LoanDataOnAccept(address from , uint256 loanId, uint loanAmount, uint interestAmount, uint endLoanTimeStamp, Status status);
    event LoanDataOnExtend(uint loanId, uint endLoanTimeStamp, Status status);
    event LoanDataOnEnd(uint loanId, Status status);
    event LoanDataOnCancel(uint loanId, Status status);

    address public manager;

    uint public totalLoan;
    mapping(uint => Loan) public allLoanRequests;

    address public constant creatorWallet = 0x21609292bd28e3EdF76b6f52F34636C7974DDBB8;

    // Added modifiers to secure

    modifier isValidLoanID(uint loanID) {
        require(
            loanID < totalLoan,
            "Loan ID is invalid."
        );
        _;
    }

    modifier onlyManager() { // Modifier
        require(
            msg.sender == manager,
            "Only manager can call this."
        );
        _;
    }

    constructor() {
        manager = msg.sender;
        totalLoan = 0;
    }

    // Saw this implementation to pause/unpause the functions


    function pauseLoans() public onlyManager {
        _pause();
    }

    function unPauseLoans() public onlyManager {
        _unpause();
    }

    function createLoan(address smartContractAddressOfNFT,uint tokenIdNFT,uint loanAmount,uint interestAmount,uint totalTimePeriod,uint maxTimePeriod) public whenNotPaused {
        require(totalTimePeriod <= 31 days, "A single period can have a maximum of one month.");
        require(maxTimePeriod <= 15 days, "Maximum interest periods are 15.");
        require(maxTimePeriod > 0 days, "Maximum interest period cannot be 0.");

        IERC721 currentNFT = IERC721(smartContractAddressOfNFT);
        require(currentNFT.getApproved(tokenIdNFT) == address(this), "Transfer has to be approved first");

        Loan storage loanRequest =  allLoanRequests[totalLoan];
        loanRequest.loanID = totalLoan;
        loanRequest.lender = payable (address(0x0));
        loanRequest.borrower = payable(msg.sender);
        loanRequest.smartContractAddressOfNFT = smartContractAddressOfNFT;
        loanRequest.tokenIdNFT = tokenIdNFT;
        loanRequest.loanAmount = loanAmount;
        loanRequest.interestAmount = interestAmount;
        loanRequest.totalTimePeriod = totalTimePeriod;
        loanRequest.maxTimePeriod = maxTimePeriod;
        loanRequest.status = Status.PENDING;
        emit LoanDataOnCreate(msg.sender, totalLoan,loanRequest.loanAmount,loanRequest.interestAmount,loanRequest.totalTimePeriod,loanRequest.maxTimePeriod,loanRequest.status);
        totalLoan = SafeMath.add(totalLoan, 1);

        currentNFT.safeTransferFrom(msg.sender, address(this), tokenIdNFT);
        
    }

    function acceptLoan(uint loanID) payable public isValidLoanID(loanID) whenNotPaused {
        require(allLoanRequests[loanID].status == Status.PENDING, "Status is not PENDING for loan.");
        require(allLoanRequests[loanID].borrower != msg.sender, "Invalid operation. You cannot underwrite your own loan.");

        uint sumForLoan = allLoanRequests[loanID].loanAmount;
        require(msg.value >= sumForLoan, "Not enough Ether sent to function to underwrite loan.");

        allLoanRequests[loanID].maxTimePeriod = allLoanRequests[loanID].maxTimePeriod - 1;

        allLoanRequests[loanID].lender = payable(msg.sender);
        allLoanRequests[loanID].status = Status.ACTIVE;
        allLoanRequests[loanID].endLoanTimeStamp = SafeMath.add(block.timestamp, allLoanRequests[loanID].totalTimePeriod);

        uint ourShare = sumForLoan.mul(25).div(1000); // taking 2.5% to pandora's acc
        address payable pandoraAcc = payable(creatorWallet);
        pandoraAcc.transfer(ourShare);
        emit LoanDataOnAccept(allLoanRequests[loanID].lender, loanID, allLoanRequests[loanID].loanAmount, allLoanRequests[loanID].interestAmount, allLoanRequests[loanID].endLoanTimeStamp, allLoanRequests[loanID].status);
        allLoanRequests[loanID].borrower.transfer(sumForLoan - ourShare);
    }

    function extendLoan(uint loanID) payable public isValidLoanID(loanID) whenNotPaused {
        require(allLoanRequests[loanID].status == Status.ACTIVE, "Status is not ACTIVE for loan");
        require(allLoanRequests[loanID].borrower == msg.sender, "Only the borrower can call this function.");
        require(allLoanRequests[loanID].maxTimePeriod > 0, "The maximum number of extensions to the loan has been reached.");
        // require(msg.value >= allLoanRequests[loanID].interestAmount, "Not enough Ether sent to the function to extend loan.");


        allLoanRequests[loanID].maxTimePeriod = allLoanRequests[loanID].maxTimePeriod - 1;
        allLoanRequests[loanID].endLoanTimeStamp = SafeMath.add(allLoanRequests[loanID].endLoanTimeStamp, allLoanRequests[loanID].totalTimePeriod);
        emit LoanDataOnExtend(loanID, allLoanRequests[loanID].endLoanTimeStamp, allLoanRequests[loanID].status);

        // allLoanRequests[loanID].lender.transfer(allLoanRequests[loanID].interestAmount);
    }

    function endLoan(uint loanID) payable public isValidLoanID(loanID) {
        require(allLoanRequests[loanID].status == Status.ACTIVE, "Status is not ACTIVE to end loan.");
        require((msg.sender == allLoanRequests[loanID].lender  && block.timestamp >= allLoanRequests[loanID].endLoanTimeStamp) || msg.sender == allLoanRequests[loanID].borrower,
                "Unable to end loan.");

        if (msg.sender == allLoanRequests[loanID].borrower) {
            uint sum = allLoanRequests[loanID].loanAmount + allLoanRequests[loanID].interestAmount;
            require(msg.value >= sum, "The principal amount of the loan was not sent.");
            allLoanRequests[loanID].status = Status.ENDED;
            allLoanRequests[loanID].lender.transfer(allLoanRequests[loanID].loanAmount);
            
        } else {
            allLoanRequests[loanID].status = Status.DEFAULTED;
        }

        IERC721 currentNFT = IERC721(allLoanRequests[loanID].smartContractAddressOfNFT);
        currentNFT.approve(msg.sender, allLoanRequests[loanID].tokenIdNFT);
        emit LoanDataOnEnd(loanID, allLoanRequests[loanID].status);
        currentNFT.transferFrom(address(this), msg.sender, allLoanRequests[loanID].tokenIdNFT);
    }
    function cancelLoan(uint loanID) public isValidLoanID(loanID) {
        require(allLoanRequests[loanID].status == Status.PENDING, "Status is not PENDING to cancel loan request");
        require(msg.sender == allLoanRequests[loanID].borrower);

        allLoanRequests[loanID].status = Status.CANCELLED;

        IERC721 currentNFT = IERC721(allLoanRequests[loanID].smartContractAddressOfNFT);
        currentNFT.approve(msg.sender, allLoanRequests[loanID].tokenIdNFT);
        emit LoanDataOnCancel(loanID, allLoanRequests[loanID].status);
        currentNFT.transferFrom(address(this), msg.sender, allLoanRequests[loanID].tokenIdNFT);
    }
}