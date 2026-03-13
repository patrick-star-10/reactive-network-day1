// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractPayer} from "../lib/reactive-lib/src/abstract-base/AbstractPayer.sol"; 
import {IPayable} from "../lib/reactive-lib/src/interfaces/IPayable.sol";

contract DestinationCallbackReceiver is AbstractPayer {
    event CallbackReceived(
        address indexed origin,
        address indexed sender,
        address indexed rvmId,
        uint256 originChainId,
        address originContract,
        address originalSender,
        uint256 newValue,
        uint256 originTimestamp
    );

    address public immutable callbackProxy; // 目标链上负责接收跨链消息的合约地址
    address public immutable authorizedRvmId;  // 只有这个RVM ID发送的消息会被接受，增加安全性

    address public lastOriginalSender;
    uint256 public lastOriginChainId;
    address public lastOriginContract;
    uint256 public mirroredValue;    // 最近一次从原链事件中同步过来的值
    uint256 public lastOriginTimestamp;

    // 仅允许授权的RVM ID调用
    modifier rvmIdOnly(address rvmId) {
        require(authorizedRvmId == address(0) || authorizedRvmId == rvmId, "Authorized RVM ID only");
        _;
    }

    // Reactive callback 接收合约的初始化配置
    constructor(address _callbackProxy) payable {
        callbackProxy = _callbackProxy;
        authorizedRvmId = msg.sender;
        vendor = IPayable(payable(_callbackProxy));
        addAuthorizedSender(_callbackProxy); // 只授权callbackProxy发送消息
    }

    function callback(
        address rvmId,
        uint256 originChainId,
        address originContract,
        address originalSender,
        uint256 newValue,
        uint256 originTimestamp
    ) external authorizedSenderOnly rvmIdOnly(rvmId) {
        lastOriginChainId = originChainId;
        lastOriginContract = originContract;
        lastOriginalSender = originalSender;
        mirroredValue = newValue;
        lastOriginTimestamp = originTimestamp;

        emit CallbackReceived(tx.origin, msg.sender, rvmId, originChainId, originContract, originalSender, newValue, originTimestamp);
    }
}
