// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract OriginEventSource {
    event ValueSet(address indexed sender, uint256 indexed newValue, uint256 emittedAt);

    uint256 public value;

    // 这个函数允许任何人设置一个新的值，并触发ValueSet事件
    function setValue(uint256 newValue) external {
        value = newValue;
        emit ValueSet(msg.sender, newValue, block.timestamp);
    }

    // 计算ValueSet事件的topic0
    function valueSetTopic0() external pure returns (bytes32) {
        return keccak256("ValueSet(address,uint256,uint256)");
    }
}
