// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./PoolPolicy.sol";
import "./boundnft/BoundNFTManager.sol";
import "./lib/Slots.sol";
import "./lib/GenericTokenInterface.sol";
import "./lib/PolicyStruct.sol";
import "./interfaces/ITreasuryLogic.sol";
import "./interfaces/ISeaport.sol";
import "./interfaces/IWETH.sol";

contract PoolLogic is ReentrancyGuardUpgradeable, PoolPolicy, BoundNFTManager, ERC1155Holder, ERC721Holder {
  using SafeERC20 for IERC20;
  using ECDSA for bytes32;
  using GenericTokenInterface for Item;
  using GenericTokenInterface for Collection;

  struct LoanInterestInfo {
    uint32 aprBP;
    uint32 earlyReturnMultiplierBP;
    uint32 lateReturnMultiplierBP;
    uint32 maxOverdue;
  }

  struct Loan {
    address borrower;
    uint128 beginTime;
    uint128 duration;
    address principalToken;
    uint256 principal;
    Collection collateralCollection;
    uint256[] collateralIds;
    uint256[] collateralAmounts;
    uint256[] valuations;
  }

  struct LoanPartialUpdateInfo {
    bytes32 updateLoanHash;
    uint256 principal;
    uint256[] collateralAmounts;
  }

  event Borrowed(LoanInterestInfo interestInfo, bytes32 lastLoanHash, Loan newLoan);
  event Repaid(bool isComplete, bytes32 repayLoanHash, LoanPartialUpdateInfo updateInfo);
  event Liquidated(bytes32 loanHash);
  event Freeze(bool isfrozen);

  bool public frozen;
  ITreasuryLogic public treasury;
  mapping(bytes32 => LoanInterestInfo) public loanInterestInfo;

  constructor(address globalBeacon) GlobalBeaconProxyImpl(globalBeacon, Slots.LENDING_POOL_IMPL) {}

  function initialize(
    PolicyStruct.InitPolicy calldata _initPolicy,
    address _poolAdmin,
    address _treasury
  ) external initializer {
    _transferOwnership(_poolAdmin);
    _setDebtToken(_initPolicy.debtToken);
    _setPoolwidePolicy(_initPolicy.poolwidePolicy);
    _setCollateralsBatch(_initPolicy.collaterals, _initPolicy.collateralwidePolicy);
    treasury = ITreasuryLogic(_treasury);
    frozen = false;
  }

  function borrowPolicyCheck(Loan memory loan) internal view returns (LoanInterestInfo memory) {
    require(
      loan.borrower == msg.sender &&
        loan.collateralIds.length > 0 &&
        loan.collateralIds.length == loan.valuations.length &&
        loan.collateralIds.length == loan.collateralAmounts.length &&
        loan.principal > 0 &&
        loan.duration > 0,
      "Invalid loan term"
    );

    require(loan.beginTime > block.timestamp - 3 minutes, "Request expired");
    require(loan.beginTime < block.timestamp + 3 minutes, "Invalid time");

    require(loan.collateralIds.length <= poolwidePolicy.maxCollateralNumPerLoan, "invalid collateral number");
    uint256 totalValuation = 0;
    for (uint256 i; i < loan.collateralIds.length; ++i) {
      require(
        loan.valuations[i] <= collateralPolicy[loan.collateralCollection.hash()].maxFpValuation &&
          loan.valuations[i] > 0,
        "current floor price exceeds max floor Price Valuation Term"
      );
      totalValuation += loan.valuations[i] * loan.collateralAmounts[i];
    }
    require(totalValuation > 0, "totalValuation must be greater than 0");
    uint256 ltvBP = (loan.principal * 10000) / totalValuation;
    require(ltvBP <= collateralPolicy[loan.collateralCollection.hash()].maxLtvBP, "Principal amount is too large");
    require(
      loan.duration <= collateralPolicy[loan.collateralCollection.hash()].maxDuration,
      "Loan duration is too long"
    );

    return
      LoanInterestInfo({
        aprBP: collateralPolicy[loan.collateralCollection.hash()].aprBP,
        earlyReturnMultiplierBP: poolwidePolicy.earlyReturnMultiplierBP,
        lateReturnMultiplierBP: poolwidePolicy.lateReturnMultiplierBP,
        maxOverdue: poolwidePolicy.maxOverdue
      });
  }

  function borrow(
    bytes memory _newLoan,
    bytes32 _r,
    bytes32 _vs,
    bytes[] memory _maybeLastLoan
  ) external payable nonReentrant {
    require(!frozen, "Pool frozen");
    require(keccak256(_newLoan).toEthSignedMessageHash().recover(_r, _vs) == getOracleAddress(), "Invalid signature");
    Loan memory newLoan = abi.decode(_newLoan, (Loan));
    require(treasury.checkBalance(newLoan.principalToken, newLoan.principal), "Insufficient Treasury Balance");

    LoanInterestInfo memory interestInfo = borrowPolicyCheck(newLoan);
    require(interestInfo.lateReturnMultiplierBP > 0, "apr 0 is not allowed");
    bytes32 loanHash = keccak256(_newLoan);
    require(loanInterestInfo[loanHash].lateReturnMultiplierBP == 0, "Loan already exists");
    uint256 receiveAmount = newLoan.principal;
    uint256 communityShare = 0;
    uint256 developerFee = 0;
    bytes32 lastHash = bytes32(0);
    require(_maybeLastLoan.length <= 1, "invalid lastLoan object");
    if (_maybeLastLoan.length == 1) {
      Loan memory lastLoan = abi.decode(_maybeLastLoan[0], (Loan));
      lastHash = keccak256(_maybeLastLoan[0]);
      require(
        loanInterestInfo[lastHash].lateReturnMultiplierBP != 0 &&
          lastLoan.borrower == newLoan.borrower &&
          lastLoan.principalToken == newLoan.principalToken &&
          lastLoan.collateralCollection.addr == newLoan.collateralCollection.addr &&
          keccak256(abi.encode(lastLoan.collateralIds)) == keccak256(abi.encode(newLoan.collateralIds)) &&
          keccak256(abi.encode(lastLoan.collateralAmounts)) == keccak256(abi.encode(newLoan.collateralAmounts)),
        "invalid lastLoan object"
      );
      (receiveAmount, communityShare, developerFee) = _calculateRenew(newLoan, lastLoan);
    }
    delete loanInterestInfo[lastHash];
    loanInterestInfo[loanHash] = interestInfo;
    if (lastHash == bytes32(0)) {
      GenericTokenInterface.safeBatchTransferFrom(
        msg.sender,
        address(this),
        newLoan.collateralCollection,
        newLoan.collateralIds,
        newLoan.collateralAmounts
      );
      mintBoundNFTs(msg.sender, newLoan.collateralCollection, newLoan.collateralIds, newLoan.collateralAmounts);
    }
    if (receiveAmount > 0) {
      treasury.lendOut(newLoan.principalToken, msg.sender, receiveAmount);
    }
    uint256 principalFee = ((lastHash != bytes32(0) ? getRenewFeeBP() : getBorrowFeeBP()) * newLoan.principal) / 10000;
    _takeMoney(newLoan.principalToken, communityShare, developerFee + principalFee, true, msg.value);
    emit Borrowed(interestInfo, lastHash, newLoan);
  }

  function bnpl(
    bytes memory _bnplLoanHash,
    bytes memory _orderInfoHash,
    bytes32 _r,
    bytes32 _vs
  ) external payable nonReentrant {
    require(!frozen, "Pool frozen");
    require(
      keccak256(_bnplLoanHash).toEthSignedMessageHash().recover(_r, _vs) == getOracleAddress(),
      "invalid signature"
    );
    Loan memory bnplLoan = abi.decode(_bnplLoanHash, (Loan));
    require(treasury.checkBalance(bnplLoan.principalToken, bnplLoan.principal), "Insufficient Treasury Balance");

    LoanInterestInfo memory interestInfo = borrowPolicyCheck(bnplLoan);
    require(interestInfo.lateReturnMultiplierBP > 0, "apr 0 is not allowed");

    bytes32 loanHash = keccak256(_bnplLoanHash);
    require(loanInterestInfo[loanHash].lateReturnMultiplierBP == 0, "Loan already exists");
    loanInterestInfo[loanHash] = interestInfo;

    (ISeaport.BasicOrderParameters memory orderParams, address marketPlace, uint256 orderValue) = abi.decode(
      _orderInfoHash,
      (ISeaport.BasicOrderParameters, address, uint256)
    );
    require(orderParams.offerToken == bnplLoan.collateralCollection.addr, "invalid offerToken");
    require(orderParams.offerIdentifier == bnplLoan.collateralIds[0], "invalid offerIdentifier");

    treasury.lendOut(bnplLoan.principalToken, address(this), bnplLoan.principal);
    if (bnplLoan.principalToken != address(0)) {
      IWETH(bnplLoan.principalToken).withdraw(bnplLoan.principal);
    }
    ISeaport(marketPlace).fulfillBasicOrder_efficient_6GL6yc{ value: orderValue }(orderParams);

    mintBoundNFTs(msg.sender, bnplLoan.collateralCollection, bnplLoan.collateralIds, bnplLoan.collateralAmounts);
    _takeMoney(
      bnplLoan.principalToken,
      0,
      (getBnplFeeBP() * bnplLoan.principal) / 10000,
      true,
      msg.value + bnplLoan.principal - orderValue
    );
    emit Borrowed(interestInfo, bytes32(0), bnplLoan);
  }

  function calculateRenew(Loan memory loan, Loan memory lastLoan) external view returns (uint256, uint256) {
    (uint256 receiveAmount, uint256 communityShare, uint256 developerFee) = _calculateRenew(loan, lastLoan);
    return (receiveAmount, communityShare + developerFee);
  }

  function _calculateRenew(Loan memory loan, Loan memory lastLoan) internal view returns (uint256, uint256, uint256) {
    (uint256 communityShare, uint256 developerFee) = _calculateDebt(
      loanInterestInfo[keccak256(abi.encode(lastLoan))],
      lastLoan.beginTime,
      lastLoan.duration,
      lastLoan.principal
    );
    if (communityShare < loan.principal) {
      return (loan.principal - communityShare, 0, developerFee);
    } else {
      return (0, communityShare - loan.principal, developerFee);
    }
  }

  function _calculateRepaidLoan_inplace(
    Loan memory loan,
    uint256[] memory repayAmounts
  ) internal pure returns (bool completeRepay, uint256 partialPrincipal) {
    completeRepay = true;
    uint256 totalValuations;
    uint256 repayValuations;
    for (uint256 i; i < loan.collateralIds.length; ++i) {
      completeRepay = completeRepay && loan.collateralAmounts[i] == repayAmounts[i];
      repayValuations += loan.valuations[i] * repayAmounts[i];
      totalValuations += loan.valuations[i] * loan.collateralAmounts[i];
      loan.collateralAmounts[i] -= repayAmounts[i];
    }
    partialPrincipal = (loan.principal * repayValuations) / totalValuations;
    loan.principal -= partialPrincipal;
  }

  function _calculateDebt(
    LoanInterestInfo memory interestInfo,
    uint256 beginTime,
    uint256 duration,
    uint256 principal
  ) internal view returns (uint256 treasuryShare, uint256 developerFee) {
    uint256 timeElapsed = beginTime < block.timestamp ? block.timestamp - beginTime : 0;
    uint256 penalty = timeElapsed < duration
      ? ((interestInfo.aprBP * interestInfo.earlyReturnMultiplierBP) / 10000) * (duration - timeElapsed)
      : ((interestInfo.aprBP * interestInfo.lateReturnMultiplierBP) / 10000) * (timeElapsed - duration);
    uint256 totalInterest = (principal * (interestInfo.aprBP * timeElapsed + penalty)) / (10000 * 365 days);
    developerFee = (totalInterest * getInterestFeeBP()) / 10000;
    treasuryShare = principal + totalInterest - developerFee;
  }

  function repay(Loan[] memory loans, uint256[][] memory repayAmountsArray) external payable nonReentrant {
    uint256 remainMsgValue = msg.value;
    for (uint256 i; i < loans.length; ++i) {
      uint256 usedMsgValue = _repayPartial(loans[i], repayAmountsArray[i], i == (loans.length - 1), remainMsgValue);
      remainMsgValue -= usedMsgValue;
    }
  }

  function _repayPartial(
    Loan memory loan,
    uint256[] memory repayAmounts,
    bool isLast,
    uint256 remainMsgValue
  ) internal returns (uint256) {
    require(msg.sender == loan.borrower, "You cannot repay other's loan");
    bytes32 repayLoanHash = keccak256(abi.encode(loan));
    LoanInterestInfo memory interestInfo = loanInterestInfo[repayLoanHash];
    require(interestInfo.lateReturnMultiplierBP > 0, "Loan does not exist");
    require(loan.beginTime + loan.duration + interestInfo.maxOverdue > block.timestamp, "to late repayment");
    (bool completeRepay, uint256 partialPrincipal) = _calculateRepaidLoan_inplace(loan, repayAmounts);
    (uint256 treasuryShare, uint256 developerFee) = _calculateDebt(
      interestInfo,
      loan.beginTime,
      loan.duration,
      partialPrincipal
    );
    require(treasuryShare + developerFee > 0, "No principal to repay");
    delete loanInterestInfo[repayLoanHash];
    burnBoundNFTs(msg.sender, loan.collateralCollection, loan.collateralIds, repayAmounts);
    GenericTokenInterface.safeBatchTransferFrom(
      address(this),
      msg.sender,
      loan.collateralCollection,
      loan.collateralIds,
      repayAmounts
    );
    if (completeRepay) {
      emit Repaid(true, repayLoanHash, LoanPartialUpdateInfo(repayLoanHash, loan.principal, loan.collateralAmounts));
    } else {
      loanInterestInfo[keccak256(abi.encode(loan))] = interestInfo;
      emit Repaid(
        false,
        repayLoanHash,
        LoanPartialUpdateInfo(keccak256(abi.encode(loan)), loan.principal, loan.collateralAmounts)
      );
    }
    return _takeMoney(loan.principalToken, treasuryShare, developerFee, isLast, remainMsgValue);
  }

  function liquidate(Loan[] memory loans, address transferTo) external nonReentrant onlyOwner {
    for (uint256 i; i < loans.length; ++i) {
      _liquidate(loans[i], transferTo);
    }
  }

  function _liquidate(Loan memory loan, address transferTo) internal {
    bytes32 loanHash = keccak256(abi.encode(loan));
    require(loanInterestInfo[loanHash].lateReturnMultiplierBP > 0, "Loan does not exist");
    require(
      loan.beginTime + loan.duration + loanInterestInfo[loanHash].maxOverdue < block.timestamp,
      "Can't liquidate yet"
    );

    delete loanInterestInfo[loanHash];
    emit Liquidated(loanHash);

    burnBoundNFTs(loan.borrower, loan.collateralCollection, loan.collateralIds, loan.collateralAmounts);
    GenericTokenInterface.safeBatchTransferFrom(
      address(this),
      transferTo,
      loan.collateralCollection,
      loan.collateralIds,
      loan.collateralAmounts
    );
  }

  function _takeMoney(
    address token,
    uint256 treasuryShare,
    uint256 developerFee,
    bool isLast,
    uint256 remainMsgValue
  ) internal returns (uint256) {
    if (token == address(0)) {
      require(remainMsgValue >= treasuryShare + developerFee, "insufficient ether");
      _safeTransferEther(address(treasury), treasuryShare);
      _safeTransferEther(getBancofAddress(), developerFee);
      if (isLast) {
        _safeTransferEther(msg.sender, remainMsgValue - (treasuryShare + developerFee));
      }
      return treasuryShare + developerFee;
    } else {
      if (treasuryShare > 0) IERC20(token).safeTransferFrom(msg.sender, address(treasury), treasuryShare);
      if (developerFee > 0) IERC20(token).safeTransferFrom(msg.sender, getBancofAddress(), developerFee);
      if (isLast) {
        _safeTransferEther(msg.sender, remainMsgValue);
      }
      return 0;
    }
  }

  function _safeTransferEther(address to, uint256 amount) internal {
    if (amount > 0) {
      (bool s, ) = to.call{ value: amount }("");
      require(s);
    }
  }

  function freeze(bool b) external {
    require(msg.sender == getBancofAddress() || msg.sender == owner(), "should be bancof or poolOwner");
    frozen = b;
    emit Freeze(b);
  }

  receive() external payable {}
}
