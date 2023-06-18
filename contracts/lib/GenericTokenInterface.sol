// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

enum Spec {
  invaild,
  eth,
  erc20,
  erc721,
  erc1155 /*, cryptopunk, cryptokitty */
}

struct Collection {
  address addr;
  Spec spec;
}

struct Item {
  Collection collection;
  uint256 id;
}

library GenericTokenInterface {
  using SafeERC20 for IERC20;

  function hash(Item memory item) internal pure returns (bytes32) {
    return keccak256(abi.encode(item));
  }

  function hash(Collection memory coll) internal pure returns (bytes32) {
    return keccak256(abi.encode(coll));
  }

  function equals(Collection memory a, Collection memory b) internal pure returns (bool) {
    return a.addr == b.addr && a.spec == b.spec;
  }

  function equals(Item memory a, Item memory b) internal pure returns (bool) {
    return a.id == b.id && equals(a.collection, b.collection);
  }

  function balanceOf(Item memory item, address addr) internal view returns (uint256) {
    Spec spec = item.collection.spec;
    address contr = item.collection.addr;

    if (spec == Spec.eth && contr == address(0)) {
      return addr.balance;
    } else if (spec == Spec.erc20 && item.id == 0) {
      return IERC20(contr).balanceOf(addr);
    } else if (spec == Spec.erc721) {
      return IERC721(contr).ownerOf(item.id) == addr ? 1 : 0;
    } else if (spec == Spec.erc1155) {
      return IERC1155(contr).balanceOf(addr, item.id);
    } else {
      revert("invalid collection");
    }
  }

  function safeTransferFrom(address from, address to, Item memory item, uint256 value) internal {
    Spec spec = item.collection.spec;
    address contr = item.collection.addr;
    require(value != 0, "amount cannot be zero");

    if (spec == Spec.erc20 && item.id == 0) {
      IERC20(contr).safeTransferFrom(from, to, value);
    } else if (spec == Spec.erc721) {
      require(value == 1, "invalid amount");
      IERC721(contr).safeTransferFrom(from, to, item.id);
    } else if (spec == Spec.erc1155) {
      IERC1155(contr).safeTransferFrom(from, to, item.id, value, "");
    } else {
      revert("invalid collection");
    }
  }

  function safeBatchTransferFrom(
    address from,
    address to,
    Collection memory collection,
    uint256[] memory ids,
    uint256[] memory amounts
  ) internal {
    Spec spec = collection.spec;
    address contr = collection.addr;
    if (spec == Spec.erc721) {
      for (uint256 i = 0; i < ids.length; ++i) {
        if (amounts[i] > 0) {
          IERC721(contr).safeTransferFrom(from, to, ids[i]);
        }
      }
    } else if (spec == Spec.erc1155) {
      IERC1155(contr).safeBatchTransferFrom(from, to, ids, amounts, "");
    } else {
      revert("invalid collection");
    }
  }
}
