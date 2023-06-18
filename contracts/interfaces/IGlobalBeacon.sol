// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IGlobalBeacon {
  function getCache(bytes32 slot) external view returns (address);

  function getUint256(bytes32 slot) external view returns (uint256);

  function getAddress(bytes32 slot) external view returns (address);

  function readDefaultMapUint256(bytes32 slot, bytes32 key) external view returns (uint256);

  function deployProxy(bytes32 slot) external returns (address);
}
