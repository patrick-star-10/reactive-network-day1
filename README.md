# Reactive Event-to-Callback Demo

这个仓库展示了一个最小的 Reactive Network 跨链闭环：

1. 源链合约在 Base Sepolia 上发出业务事件
2. Reactive Lasna 上的监听合约订阅该事件并执行 `react(...)`
3. 监听合约发出 `Callback(...)`
4. Ethereum Sepolia 上的目标合约接收 callback 并更新本地状态

项目使用 Foundry 构建，并直接依赖官方 `reactive-lib`。库源码位于 `lib/reactive-lib`。

## 架构概览

项目由三份合约组成：

- `OriginEventSource`
  运行在源链。负责接收外部调用、修改本地 `value`，并发出 `ValueSet(address,uint256,uint256)` 事件。
- `ValueSetListenerReactive`
  运行在 Reactive Network。负责订阅源链事件，在 `react(LogRecord)` 中解析事件内容，并将其编码成 callback payload 发往目标链。
- `DestinationCallbackReceiver`
  运行在目标链。负责接收 callback proxy 的调用，校验来源后更新目标链状态。

对应目录：

- `src/OriginEventSource.sol`
- `src/ValueSetListenerReactive.sol`
- `src/DestinationCallbackReceiver.sol`
- `scripts/`
- `lib/reactive-lib/`

## 事件流

完整执行路径如下：

1. 用户在源链调用 `OriginEventSource.setValue(uint256)`
2. 源链合约更新 `value`，并发出 `ValueSet(sender, newValue, block.timestamp)`
3. Reactive 合约在构造函数里通过系统合约 `subscribe(...)` 订阅这类事件
4. Reactive VM 收到对应日志后调用 `ValueSetListenerReactive.react(LogRecord)`
5. `react(...)` 校验来源链、来源合约和 `topic0`
6. `react(...)` 从日志中提取 `sender`、`newValue`、`timestamp`
7. Reactive 合约发出 `Callback(destinationChainId, destinationContract, gasLimit, payload)`
8. 目标链 callback proxy 调用 `DestinationCallbackReceiver.callback(...)`
9. 目标链合约写入同步后的状态，并发出 `CallbackReceived(...)`

## 实现原理

### OriginEventSource

这个合约是最简单的事件源：

- `setValue(uint256 newValue)` 更新本地状态
- 同时发出 `ValueSet(address indexed sender, uint256 indexed newValue, uint256 emittedAt)`
- `valueSetTopic0()` 提供事件签名哈希，方便部署或校验时使用

它只负责产生业务事件，不关心 Reactive Network 或目标链逻辑。

### ValueSetListenerReactive

这个合约是 Reactive 侧的桥接逻辑核心：

- 继承官方 `AbstractReactive`
- 在构造阶段设置：
  - `originChainId`
  - `destinationChainId`
  - `originContract`
  - `expectedTopic0`
  - `destinationContract`
- 通过 `service.subscribe(...)` 向系统合约注册订阅

当 `react(LogRecord)` 被调用时，它会：

- 确认事件来自预期链和预期合约
- 校验 `topic0` 是否匹配 `ValueSet(address,uint256,uint256)`
- 从日志里解析出：
  - 原始调用者地址
  - 新的数值
  - 源链时间戳
- 将这些字段编码成：

```solidity
callback(address,uint256,address,address,uint256,uint256)
```

- 最后发出官方 `Callback(...)` 事件，交由 callback proxy 在目标链执行

### DestinationCallbackReceiver

这个合约是目标链上的状态接收器：

- 继承官方 `AbstractPayer`
- 只允许 callback proxy 调用
- 只接受授权的 `rvmId`
- 在 `callback(...)` 中更新：
  - `lastOriginChainId`
  - `lastOriginContract`
  - `lastOriginalSender`
  - `mirroredValue`
  - `lastOriginTimestamp`
- 发出 `CallbackReceived(...)` 作为链上证明

这个合约同时保留 `pay(uint256)` / `coverDebt()` 所依赖的支付能力，用于 callback 成本结算。

## 关键设计点

### 1. 监听的是哪一个事件

监听目标是源链上的：

```solidity
ValueSet(address,uint256,uint256)
```

也就是：

- 谁触发了源链更新
- 更新后的值是多少
- 该事件发出时的时间戳

### 2. 目标链执行的是哪一个回调

目标链最终执行的是：

```solidity
callback(address,uint256,address,address,uint256,uint256)
```

其中第一个参数 `rvmId` 必须预留给 Reactive Network 注入。

### 3. callback 改变了什么

成功回调后，目标链会更新：

- `lastOriginChainId`
- `lastOriginContract`
- `lastOriginalSender`
- `mirroredValue`
- `lastOriginTimestamp`

### 4. callback 资金如何处理

目标链 callback 执行依赖 callback proxy 侧的余额记录。这个项目的脚本采用：

```bash
depositTo(destinationContract)
```

而不是直接给目标合约裸转账。

## 脚本说明

仓库提供了一组最小部署脚本：

- `scripts/deploy_origin.sh`
  部署 `OriginEventSource`
- `scripts/deploy_destination.sh`
  部署 `DestinationCallbackReceiver`
- `scripts/deploy_reactive.sh`
  部署 `ValueSetListenerReactive`
- `scripts/fund_and_trigger.sh`
  通过 callback proxy 给目标合约充值，并在源链触发一次事件
- `scripts/check_destination.sh`
  查询目标链同步后的状态

公共逻辑在 `scripts/common.sh` 中，包括：

- `.env` 读取
- 私钥解析
- 本地 `solc` 路径处理
- 部署结果写回 `.env`

## 环境参数

当前已验证的网络组合是：

- Origin: `Base Sepolia (84532)`
- Reactive: `Reactive Lasna (5318007)`
- Destination: `Ethereum Sepolia (11155111)`

当前使用的关键网络参数：

- System contract: `0x0000000000000000000000000000000000fffFfF`
- Callback proxy: `0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA`

私钥和 RPC 配置放在本地 `.env` 中，`.env` 不应提交到版本库。

## 编译

```bash
forge build --no-auto-detect --use ./tools/solc-0.8.20
```

仓库内置了 `tools/solc-0.8.20`，用于绕开当前环境里 Foundry 自动安装 `solc` 的兼容性问题。

## 部署顺序

按下面顺序执行即可：

```bash
./scripts/deploy_origin.sh
./scripts/deploy_destination.sh
./scripts/deploy_reactive.sh
./scripts/fund_and_trigger.sh
./scripts/check_destination.sh
```

## 已验证结果

当前仓库已经验证过一组可工作的部署：

- OriginEventSource: `0x57A372A1C2cfCEf2C5be589c95f4aF1Ccd5412Ae`
- ValueSetListenerReactive: `0xbC2592E0686b6900AD382CA6Ae9A01Dc3b412498`
- DestinationCallbackReceiver: `0x32Bf10b95fE7bd489b3255E7839153E281d40Ee9`

最终目标链状态：

- `lastOriginalSender = 0x791DdA64Ce022269244647699C071dea2cf0fa82`
- `lastOriginChainId = 84532`
- `lastOriginContract = 0x57A372A1C2cfCEf2C5be589c95f4aF1Ccd5412Ae`
- `mirroredValue = 44`
- `lastOriginTimestamp = 1773111520`

更完整的部署地址、交易哈希和浏览器证明见 [SUBMISSION_BRIEF.md](/Users/wx/Desktop/Reactive-learning/SUBMISSION_BRIEF.md)。
