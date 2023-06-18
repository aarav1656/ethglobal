// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IGlobalBeaconProxyImpl {
  function getBeacon() external view returns (address);

  function selfDestructIfCache() external;
}
