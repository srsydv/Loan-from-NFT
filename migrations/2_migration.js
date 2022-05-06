const loan = artifacts.require("LoanNFT");

module.exports = function (deployer) {
  deployer.deploy(loan);
};