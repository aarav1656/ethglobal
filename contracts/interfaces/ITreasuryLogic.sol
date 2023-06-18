// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface ITreasuryLogic {
  function initialize(address pool, address poolAdmin) external;

  function checkBalance(address token, uint256 amount) external view returns (bool);

  function lendOut(address token, address to, uint256 amount) external;
}
