// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Collection } from "./GenericTokenInterface.sol";

library PolicyStruct {
  struct PoolwidePolicy {
    uint32 earlyReturnMultiplierBP;
    uint32 lateReturnMultiplierBP;
    uint32 maxOverdue;
    uint32 maxCollateralNumPerLoan;
  }

  struct CollateralwidePolicy {
    uint32 aprBP;
    uint32 maxLtvBP;
    uint32 maxDuration;
    uint256 maxFpValuation;
  }

  struct InitPolicy {
    address debtToken;
    PoolwidePolicy poolwidePolicy;
    Collection[] collaterals;
    CollateralwidePolicy[] collateralwidePolicy;
  }
}
