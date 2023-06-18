// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../globalbeacon/GlobalBeaconProxyImpl.sol";
import "../lib/GenericTokenInterface.sol";
import "../lib/KeyValueStorage.sol";
import "./BoundNFT.sol";

abstract contract BoundNFTManager is GlobalBeaconProxyImpl, KeyValueStorage {
  bytes32 private constant namespace = keccak256("contract BoundNFTManager");

  using GenericTokenInterface for Item;
  using GenericTokenInterface for Collection;

  event BoundNFTCreated(address originAddress, address boundNftAddress);

  function _deployBoundNFTContract(Collection memory coll) private returns (BoundNFT) {
    bytes32 slot;
    if (coll.spec == Spec.erc721) {
      slot = Slots.BOUND_ERC721_IMPL;
    } else if (coll.spec == Spec.erc1155) {
      slot = Slots.BOUND_ERC1155_IMPL;
    } else {
      revert("Unsupported NFT specification");
    }
    BoundNFT bnft = BoundNFT(deployProxy(slot));
    _setAddress(keccak256(abi.encode(namespace, coll.hash())), address(bnft));
    bnft.initialize(coll.addr);
    emit BoundNFTCreated(coll.addr, address(bnft));
    return bnft;
  }

  function _getBoundNFTContract(Collection memory coll) private returns (BoundNFT) {
    BoundNFT boundNFT = BoundNFT(_getAddress(keccak256(abi.encode(namespace, coll.hash()))));
    if (address(boundNFT) == address(0)) {
      return _deployBoundNFTContract(coll);
    } else {
      return boundNFT;
    }
  }

  function mintBoundNFTs(
    address to,
    Collection memory collection,
    uint256[] memory ids,
    uint256[] memory amounts
  ) internal {
    for (uint256 i = 0; i < ids.length; ++i) {
      if (amounts[i] > 0) {
        _getBoundNFTContract(collection).mint(to, ids[i], amounts[i]);
      }
    }
  }

  function burnBoundNFTs(
    address from,
    Collection memory collection,
    uint256[] memory ids,
    uint256[] memory amounts
  ) internal {
    for (uint256 i = 0; i < ids.length; ++i) {
      if (amounts[i] > 0) {
        _getBoundNFTContract(collection).burn(from, ids[i], amounts[i]);
      }
    }
  }
}
