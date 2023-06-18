// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "../globalbeacon/GlobalBeaconProxyImpl.sol";
import "./BoundNFT.sol";

contract BoundERC721 is BoundNFT, GlobalBeaconProxyImpl, OwnableUpgradeable {
  address public original;

  mapping(uint256 => address) private _owners;
  mapping(address => uint256) private _balances;

  event Transfer(address indexed from, address indexed to, uint256 indexed id);

  constructor(address globalBeacon) GlobalBeaconProxyImpl(globalBeacon, Slots.BOUND_ERC721_IMPL) {}

  function supportsInterface(bytes4 interfaceId) external view returns (bool) {
    return IERC165(original).supportsInterface(interfaceId);
  }

  function symbol() external view returns (string memory) {
    return IERC721Metadata(original).symbol();
  }

  function name() external view returns (string memory) {
    return IERC721Metadata(original).name();
  }

  function tokenURI(uint256 id) external view returns (string memory) {
    return IERC721Metadata(original).tokenURI(id);
  }

  function _exists(uint256 id) internal view returns (bool) {
    return _owners[id] != address(0);
  }

  function initialize(address _original) external initializer {
    original = _original;
    __Ownable_init();
  }

  function mint(address to, uint256 id, uint256 amount) external onlyOwner {
    require(!_exists(id), "ERC721: token already minted");
    require(amount == 1, "Cannot mint more than 1");
    unchecked {
      _balances[to] += 1;
    }
    _owners[id] = to;
    emit Transfer(address(0), to, id);
  }

  function burn(address from, uint256 id, uint256 amount) external onlyOwner {
    address owner = _owners[id];
    require(owner == from, "Wrong owner");
    require(amount == 1, "Cannot burn more than 1");
    unchecked {
      _balances[owner] -= 1;
    }
    delete _owners[id];
    emit Transfer(owner, address(0), id);
  }

  function balanceOf(address owner) external view returns (uint256) {
    require(owner != address(0), "ERC721: address zero is not a valid owner");
    return _balances[owner];
  }

  function ownerOf(uint256 id) external view returns (address) {
    address owner = _owners[id];
    require(owner != address(0), "ERC721: invalid token ID");
    return owner;
  }

  function isApprovedForAll(address, address) external pure returns (bool) {
    return false;
  }

  function getApproved(uint256) external pure returns (address) {
    return address(0);
  }
}
