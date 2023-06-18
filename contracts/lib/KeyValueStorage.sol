// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/StorageSlot.sol";

abstract contract KeyValueStorage {
  function _setUint256(bytes32 slot, uint256 val) internal {
    StorageSlot.getUint256Slot(slot).value = val;
  }

  function _getUint256(bytes32 slot) internal view returns (uint256) {
    return StorageSlot.getUint256Slot(slot).value;
  }

  function _setAddress(bytes32 slot, address addr) internal {
    StorageSlot.getAddressSlot(slot).value = addr;
  }

  function _getAddress(bytes32 slot) internal view returns (address) {
    return StorageSlot.getAddressSlot(slot).value;
  }
}
