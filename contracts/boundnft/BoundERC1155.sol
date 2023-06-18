// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/interfaces/IERC1155MetadataURI.sol";
import "../globalbeacon/GlobalBeaconProxyImpl.sol";
import "./BoundNFT.sol";

contract BoundERC1155 is BoundNFT, GlobalBeaconProxyImpl, OwnableUpgradeable {
  address public original;

  mapping(uint256 => mapping(address => uint256)) private _balances;

  event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

  constructor(address globalBeacon) GlobalBeaconProxyImpl(globalBeacon, Slots.BOUND_ERC1155_IMPL) {}

  function supportsInterface(bytes4 interfaceId) external view returns (bool) {
    return IERC165(original).supportsInterface(interfaceId);
  }

  function uri(uint256 id) external view returns (string memory) {
    return IERC1155MetadataURI(original).uri(id);
  }

  function initialize(address _original) external initializer {
    original = _original;
    __Ownable_init();
  }

  function mint(address to, uint256 id, uint256 amount) external onlyOwner {
    _balances[id][to] += amount;
    emit TransferSingle(msg.sender, address(0), to, id, amount);
  }

  function burn(address from, uint256 id, uint256 amount) external onlyOwner {
    _balances[id][from] -= amount;
    emit TransferSingle(msg.sender, from, address(0), id, amount);
  }

  function balanceOf(address account, uint256 id) external view returns (uint256) {
    require(account != address(0), "ERC1155: address zero is not a valid owner");
    return _balances[id][account];
  }

  function balanceOfBatch(address[] memory accounts, uint256[] memory ids) external view returns (uint256[] memory) {
    require(accounts.length == ids.length, "ERC1155: accounts and ids length mismatch");
    uint256[] memory batchBalances = new uint256[](accounts.length);
    for (uint256 i = 0; i < accounts.length; ++i) {
      require(accounts[i] != address(0), "ERC1155: address zero is not a valid owner");
      batchBalances[i] = _balances[ids[i]][accounts[i]];
    }
    return batchBalances;
  }

  function isApprovedForAll(address, address) external pure returns (bool) {
    return false;
  }
}
