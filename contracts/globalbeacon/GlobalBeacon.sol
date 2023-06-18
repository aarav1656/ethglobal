// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/StorageSlot.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "./GlobalBeaconProxy.sol";
import "../interfaces/IGlobalBeaconProxyImpl.sol";

error WillNotSelfDestruct();

contract GlobalBeacon is OwnableUpgradeable {
  mapping(bytes32 => address) private cache;
  bytes32 private constant SALT = 0;

  function initialize() public initializer {
    __Ownable_init();
  }

  function getCache(bytes32 slot) external view returns (address) {
    return cache[slot];
  }

  function setUint256(bytes32 slot, uint256 val) public onlyOwner {
    StorageSlot.getUint256Slot(slot).value = val;
  }

  function getUint256(bytes32 slot) public view returns (uint256) {
    return StorageSlot.getUint256Slot(slot).value;
  }

  function setAddress(bytes32 slot, address addr) external onlyOwner {
    if (cache[slot].code.length > 0) {
      IGlobalBeaconProxyImpl(cache[slot]).selfDestructIfCache();
    }
    StorageSlot.getAddressSlot(slot).value = addr;
  }

  function getAddress(bytes32 slot) public view returns (address) {
    return StorageSlot.getAddressSlot(slot).value;
  }

  function writeDefaultMapUint256(bytes32 slot, bytes32 key, uint256 value) external onlyOwner {
    bytes32 overrideSlot = keccak256(abi.encode(slot, key));
    setUint256(overrideSlot, 1);
    setUint256(bytes32(uint256(overrideSlot) + 1), value);
  }
  
  function readDefaultMapUint256(bytes32 slot, bytes32 key) external view returns (uint256) {
    bytes32 overrideSlot = keccak256(abi.encode(slot, key));
    return getUint256(overrideSlot) == 0 ? getUint256(slot) : getUint256(bytes32(uint256(overrideSlot) + 1));
  }

  function deployCache(bytes32 slot) external {
    _validateImplementation(getAddress(slot));
    cache[slot] = Create2.computeAddress(SALT, keccak256(polybeaconImplCloner(slot)));
    Create2.deploy(0, SALT, polybeaconImplCloner(slot));
  }

  function deployProxy(bytes32 slot) external returns (address) {
    return address(new GlobalBeaconProxy(address(this), slot));
  }

  function _validateImplementation(address addr) internal {
    require(addr.code.length != 0);
    IGlobalBeaconProxyImpl beaconImpl = IGlobalBeaconProxyImpl(addr);
    require(beaconImpl.getBeacon() == address(this));
    try beaconImpl.selfDestructIfCache() {} catch (bytes memory error) {
      require(bytes4(error) == WillNotSelfDestruct.selector);
    }
  }
}

function polybeaconImplCloner(bytes32 addressSlot) pure returns (bytes memory ret) {
    ret =
    /* 00 */    hex"6321f8a721"     // push4 0x21f8a721     | getAddress(bytes32)
    /* 05 */    hex"6000"           // push1 0              | 0 getAddress(bytes32)
    /* 07 */    hex"52"             // mstore               |
    /* 08 */    hex"7f0000000000000000000000000000000000000000000000000000000000000000"
                                    // push32 slot -- this will be dynamically replaced with addressSlot
    /*    */    hex"6020"           // push1 32             | 32 slot
    /*    */    hex"52"             // mstore               |
    /* xx */    hex"6020"           // push1 32             | 32
    /* xx */    hex"6000"           // push1 0              | 0 32
    /* xx */    hex"6024"           // push1 36             | 36 0 32
    /* xx */    hex"601c"           // push1 28             | 28 36 0 32
    /* xx */    hex"82"             // dup3                 | 0 28 36 0 32
    /* xx */    hex"33"             // caller               | beacon 0 28 36 0 32
    /* xx */    hex"5a"             // gas                  | gas beacon 0 28 36 0 32
    /* xx */    hex"f1"             // call                 | status
    /* xx */    hex"603f"           // push1 3f             | <ifok> status
    /* xx */    hex"57"             // jumpi                |
    /* xx */    hex"6000"           // push1 0              | 0
    /* xx */    hex"80"             // dup1                 | 0 0
    /* xx */    hex"fd"             // revert               |
    /* 3f */    hex"5b"             // jumpdest <ifok>      |
    /* xx */    hex"6000"           // push1 0              | 0
    /* xx */    hex"51"             // mload                | impl
    /* xx */    hex"6000"           // push1 0              | 0 impl
    /* xx */    hex"81"             // dup2                 | impl 0 impl
    /* xx */    hex"3b"             // extcodesize          | size 0 impl
    /* xx */    hex"81"             // dup2                 | 0 size 0 impl
    /* xx */    hex"80"             // dup1                 | 0 0 size 0 impl
    /* xx */    hex"82"             // dup3                 | size 0 0 size 0 impl
    /* xx */    hex"94"             // swap5                | impl 0 0 size 0 size
    /* xx */    hex"3c"             // extcodecopy          | 0 size
    /* xx */    hex"f3"             // return
    ;
  assembly {
    mstore(add(ret, 41), addressSlot)
  }
}
