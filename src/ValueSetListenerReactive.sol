// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractReactive} from "../lib/reactive-lib/src/abstract-base/AbstractReactive.sol";// 引入Reactive合约基础框架
import {IReactive} from "../lib/reactive-lib/src/interfaces/IReactive.sol";  // 引入react执行接口
import {IPayable} from "../lib/reactive-lib/src/interfaces/IPayable.sol";  // Reactive费用支付接口
import {ISystemContract} from "../lib/reactive-lib/src/interfaces/ISystemContract.sol";// 引入系统服务

contract ValueSetListenerReactive is IReactive, AbstractReactive {
    error UnexpectedSource(uint256 chainId, address contractAddress, uint256 topic0);

    uint64 public constant CALLBACK_GAS_LIMIT = 1_000_000;

    uint256 public immutable originChainId;  // 监听的链ID
    uint256 public immutable destinationChainId; // 目标链ID
    address public immutable originContract;    // 监听的合约
    uint256 public immutable expectedTopic0;    // 监听的事件的topic0
    address public immutable destinationContract; // callback的目标合约

    constructor(
        address _service,// Reactive系统服务地址
        uint256 _originChainId,
        uint256 _destinationChainId,
        address _originContract,
        uint256 _expectedTopic0,
        address _destinationContract
    ) payable {
        service = ISystemContract(payable(_service));// 将地址转换为系统服务接口
        vendor = IPayable(payable(_service));  // 设置费用支付接口
        addAuthorizedSender(_service);      // 授权Reactive调用合约
        originChainId = _originChainId;
        destinationChainId = _destinationChainId;
        originContract = _originContract;
        expectedTopic0 = _expectedTopic0;
        destinationContract = _destinationContract;

        // 如果不是在vm环境下部署，自动订阅指定的事件
        if (!vm) {
            service.subscribe(
                _originChainId, _originContract, _expectedTopic0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
            );
        }
    }

    function react(LogRecord calldata logRecord) external vmOnly {
        if (
            logRecord.chain_id != originChainId || logRecord._contract != originContract
                || logRecord.topic_0 != expectedTopic0
        ) {
            revert UnexpectedSource(logRecord.chain_id, logRecord._contract, logRecord.topic_0);
        }
        
        address originalSender = address(uint160(logRecord.topic_1));// 从topic_1中解析出原始事件的发送者地址
        uint256 newValue = logRecord.topic_2; // 从topic_2中解析出事件中的新值
        uint256 originTimestamp = abi.decode(logRecord.data, (uint256));//  从事件数据中解析出事件发生的时间戳

        // 构造跨链回调的payload，调用目标链上的合约的callback函数
        bytes memory payload = abi.encodeWithSignature(
            "callback(address,uint256,address,address,uint256,uint256)",
            address(0),
            logRecord.chain_id,
            logRecord._contract,
            originalSender,
            newValue,
            originTimestamp
        );

        emit Callback(destinationChainId, destinationContract, CALLBACK_GAS_LIMIT, payload);
    }
}
