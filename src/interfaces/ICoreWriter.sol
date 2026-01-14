
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ICoreWriter {
  event RawAction(address indexed user, bytes data);

  function sendRawAction(bytes calldata data) external;
}