const loan = artifacts.require('LoanNFT');

contract('LoanNFT', () =>{
    it('Should Create A Loan', async () =>{
        const contract = await loan.deployed();
        const create = await contract.createLoanRequest("0x4ED83a6b924661eC9A0908845bfdBA3A01da67C0", 1, "1000000000000000000", "1100000000000000000" ,20, 1);
        console.log(create);
    })
})