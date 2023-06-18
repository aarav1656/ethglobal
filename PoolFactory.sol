// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./interfaces/IGlobalBeacon.sol";
import "./interfaces/IPoolLogic.sol";
import "./interfaces/ITreasuryLogic.sol";
import "./lib/Slots.sol";
import "./lib/PolicyStruct.sol";

contract PoolFactory is ReentrancyGuard {
  struct PoolConfig {
    PolicyStruct.InitPolicy initPolicy;
    address poolAdmin;
    string poolName;
  }

  using SafeERC20 for IERC20;
  using ECDSA for bytes32;

  IGlobalBeacon immutable beacon;
  event PoolCreated(string poolName, address poolAdmin, address pool, address treasury);

  constructor(address _beacon) {
    beacon = IGlobalBeacon(_beacon);
  }

  function deployPool(
    PoolConfig calldata poolConfig,
    address initDepositToken,
    uint256 initDeposit,
    bytes32 r,
    bytes32 vs
  ) external payable nonReentrant {
    require(
      keccak256(abi.encode(poolConfig)).toEthSignedMessageHash().recover(r, vs) ==
        beacon.getAddress(Slots.ORACLE_ADDRESS),
      "Invalid signature"
    );
    address pool = beacon.deployProxy(Slots.LENDING_POOL_IMPL);
    address treasury = beacon.deployProxy(Slots.TREASURY_IMPL);
    IPoolLogic(pool).initialize(poolConfig.initPolicy, poolConfig.poolAdmin, treasury);
    ITreasuryLogic(treasury).initialize(pool, poolConfig.poolAdmin);
    _deployCalculate(initDepositToken, initDeposit, treasury);
    emit PoolCreated(poolConfig.poolName, poolConfig.poolAdmin, pool, treasury);
  }

  function _deployCalculate(address initDepositToken, uint256 initDeposit, address treasury) internal {
    address initialFeeToken = beacon.getAddress(Slots.INITIAL_FEE_TOKEN);
    uint256 initialFee = beacon.getUint256(Slots.INITIAL_FEE);
    uint256 ethNeeded = (initialFeeToken == address(0) ? initialFee : 0) +
      (initDepositToken == address(0) ? initDeposit : 0);
    require(msg.value >= ethNeeded, "insufficient ether");
    if (initialFeeToken == address(0)) {
      _safeTransferEther(beacon.getAddress(Slots.BANCOF_ADDRESS), initialFee);
    } else {
      if (initialFee > 0)
        IERC20(initialFeeToken).safeTransferFrom(msg.sender, beacon.getAddress(Slots.BANCOF_ADDRESS), initialFee);
    }
    if (initDepositToken == address(0)) {
      _safeTransferEther(treasury, initDeposit);
    } else {
      if (initDeposit > 0) IERC20(initDepositToken).safeTransferFrom(msg.sender, treasury, initDeposit);
    }
    _safeTransferEther(msg.sender, msg.value - ethNeeded);
  }

  function _safeTransferEther(address to, uint256 amount) internal {
    if (amount > 0) {
      (bool s, ) = to.call{ value: amount }("");
      require(s);
    }
  }
}
