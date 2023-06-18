// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./lib/GenericTokenInterface.sol";
import "./lib/Slots.sol";
import "./lib/PolicyStruct.sol";

abstract contract PoolPolicy is OwnableUpgradeable {
  using GenericTokenInterface for Item;
  using GenericTokenInterface for Collection;

  event DebtTokenSet(address debtToken);
  event PoolwidePolicySet(PolicyStruct.PoolwidePolicy poolwidePolicy);
  event CollateralSet(Collection collateral, PolicyStruct.CollateralwidePolicy collateralwidePolicy, bool isAdd);

  PolicyStruct.PoolwidePolicy public poolwidePolicy;
  mapping(bytes32 => PolicyStruct.CollateralwidePolicy) collateralPolicy;
  address public debtToken;

  function setAllPolicy(
    PolicyStruct.PoolwidePolicy calldata _poolwidePolicy,
    Collection[] calldata _collaterals,
    PolicyStruct.CollateralwidePolicy[] calldata _collateralwidePolicy
  ) external onlyOwner {
    _setPoolwidePolicy(_poolwidePolicy);
    _setCollateralsBatch(_collaterals, _collateralwidePolicy);
  }

  function _setDebtToken(address _debtToken) internal {
    debtToken = _debtToken;
    emit DebtTokenSet(_debtToken);
  }

  function setPoolwidePolicy(PolicyStruct.PoolwidePolicy calldata _poolwidePolicy) external onlyOwner {
    _setPoolwidePolicy(_poolwidePolicy);
  }

  function _setPoolwidePolicy(PolicyStruct.PoolwidePolicy calldata _poolwidePolicy) internal {
    poolwidePolicy = _poolwidePolicy;
    emit PoolwidePolicySet(_poolwidePolicy);
  }

  function setCollateralsBatch(
    Collection[] calldata _collaterals,
    PolicyStruct.CollateralwidePolicy[] calldata _collateralwidePolicy
  ) external onlyOwner {
    _setCollateralsBatch(_collaterals, _collateralwidePolicy);
  }

  function _setCollateralsBatch(
    Collection[] calldata _collaterals,
    PolicyStruct.CollateralwidePolicy[] calldata _collateralwidePolicy
  ) internal {
    require(_collaterals.length == _collateralwidePolicy.length, "invalid collateral setting parameter");
    for (uint256 i = 0; i < _collaterals.length; ++i) {
      _setCollateral(_collaterals[i], _collateralwidePolicy[i]);
    }
  }

  function _setCollateral(
    Collection calldata _collateral,
    PolicyStruct.CollateralwidePolicy calldata _collateralwidePolicy
  ) private {
    collateralPolicy[_collateral.hash()] = _collateralwidePolicy;
    emit CollateralSet(_collateral, _collateralwidePolicy, true);
  }

  function delCollateralsBatch(Collection[] calldata _collaterals) external onlyOwner {
    for (uint256 i = 0; i < _collaterals.length; ++i) {
      delete collateralPolicy[_collaterals[i].hash()];
      emit CollateralSet(_collaterals[i], PolicyStruct.CollateralwidePolicy(0, 0, 0, 0), false);
    }
  }
}
