// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

library Slots {
  bytes32 constant BANCOF_ADDRESS = keccak256("BANCOF_ADDRESS");
  bytes32 constant ORACLE_ADDRESS = keccak256("ORACLE_ADDRESS");

  bytes32 constant LENDING_POOL_IMPL = keccak256("LENDING_POOL_IMPL");
  bytes32 constant POLICY_IMPL = keccak256("POLICY_IMPL");
  bytes32 constant TREASURY_IMPL = keccak256("TREASURY_IMPL");
  bytes32 constant BOUND_ERC721_IMPL = keccak256("BOUND_ERC721_IMPL");
  bytes32 constant BOUND_ERC1155_IMPL = keccak256("BOUND_ERC1155_IMPL");

  bytes32 constant INITIAL_FEE = keccak256("INITIAL_FEE");
  bytes32 constant INITIAL_FEE_TOKEN = keccak256("INITIAL_FEE_TOKEN");

  bytes32 constant INTEREST_FEE_BP = keccak256("INTEREST_FEE_BP");

  bytes32 constant BORROW_FEE_BP = keccak256("BORROW_FEE_BP");
  bytes32 constant BNPL_FEE_BP = keccak256("BNPL_FEE_BP");
  bytes32 constant RENEW_FEE_BP = keccak256("RENEW_FEE_BP");
}
