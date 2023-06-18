// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../lib/PolicyStruct.sol";

interface IPoolLogic {
  function initialize(PolicyStruct.InitPolicy calldata initPolicy, address poolAdmin, address treasury) external;
}
