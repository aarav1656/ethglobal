// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/proxy/Proxy.sol";
import "../interfaces/IGlobalBeacon.sol";

contract GlobalBeaconProxy is Proxy {
  IGlobalBeacon private immutable beacon;
  bytes32 private immutable slot;
  address private immutable cache;

  constructor(address _beacon, bytes32 _slot) {
    beacon = IGlobalBeacon(_beacon);
    slot = _slot;
    cache = beacon.getCache(_slot);
  }

  function _implementation() internal view override returns (address) {
    return cache.code.length > 0 ? cache : beacon.getAddress(slot);
  }
}
