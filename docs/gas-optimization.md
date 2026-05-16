# Gas 优化文档

本文档分析 **Verifiable Random Game** 智能合约的 Gas 消耗特征、主要热点、已采用的优化手段，以及后续可改进方向。与 [architecture.md](./architecture.md)、[contracts.md](./contracts.md) 配套阅读。

---

## 1. 概述

| 项目 | 说明 |
|------|------|
| **Solidity** | `0.8.28`（`contracts/foundry.toml`） |
| **编译优化** | `optimizer = true`，`optimizer_runs = 200` |
| **IR 管道** | `via_ir = false`（默认 solc 优化路径） |
| **EVM** | `paris` |
| **Gas 主要来源** | 存储读写（SSTORE/SLOAD）、外部调用（CALL）、VRF 回调、动态数组 |

本项目的 Gas 成本可划分为三类：

1. **用户直接支付**：`buyTickets`、`commitBet`、`revealAndBet` 等 `external` 交易。
2. **VRF 订阅支付**：`fulfillRandomWords` 回调消耗 `callbackGasLimit` 内的 Gas（由 Chainlink 订阅/LINK 承担，本地 Mock 由测试账户模拟）。
3. **管理员/运维**：`openRound`、`closeRound`、`requestDraw` 等低频操作。

---

## 2. 测量方法

### 2.1 Foundry Gas Report

在项目根目录或 `contracts/` 下执行（需已安装 Foundry）：

```bash
forge test --gas-report
```

或使用 npm 脚本：

```bash
npm run contracts:test -- --gas-report
```

输出包含各合约、各函数的 **min / avg / max / median** Gas，便于对比优化前后。

### 2.2 单次交易 Gas

```bash
forge test --match-test test_buyTicketsAndDrawWinner -vvvv
```

在 trace 中查看具体 `CALL` 与 `SSTORE` 开销。

### 2.3 不变量 / 模糊测试下的 Gas

```bash
forge test --match-path test/invariant/ -vv
```

关注金库 `depositBet` / `payoutWinner` 在大量随机操作后的平均 Gas。

### 2.4 部署 Gas

```bash
forge script script/Deploy.s.sol --sig "run()" --fork-url http://127.0.0.1:8545
```

部署成本与 `optimizer_runs` 相关：`200` 在**部署体积**与**运行时 Gas** 之间折中；若回调路径极热，可尝试 `optimizer_runs = 1000` 做 A/B 对比。

---

## 3. 编译与部署层优化（已启用）

| 配置 | 当前值 | 作用 |
|------|--------|------|
| `optimizer` | `true` | 开启 solc 优化器，降低运行时 opcode |
| `optimizer_runs` | `200` | 偏向略小的字节码；适合多函数、多路径的合约集 |
| `via_ir` | `false` | 编译更快；若需极致优化可试验 `via_ir = true` + 高 `optimizer_runs` |

**建议**：上线前对 `LotteryRaffle._onRandomWordsFulfilled` 与 `DiceGame._onRandomWordsFulfilled` 做一轮 `optimizer_runs ∈ {200, 1000, 10000}` 的 Gas Report 对比，选回调 Gas 最低且字节码可接受的配置。

---

## 4. 各合约 Gas 特征

### 4.1 GameTreasury

| 函数 | 相对成本 | 说明 |
|------|----------|------|
| `depositBet` (ETH) | 低～中 | 一次 `SSTORE` 增池 + 限额检查 + 事件 |
| `depositBet` (ERC-20) | 中～高 | 额外 `transferFrom`（~20k+ Gas） |
| `payoutWinner` (ETH) | 中 | 池扣减 + `call` 转 ETH + 事件 |
| `payoutWinner` (ERC-20) | 中～高 | `safeTransfer` 外部调用 |
| `withdrawFees` | 中 | `nonReentrant` + 转出 |
| `view` 函数 | 极低 | 纯 `SLOAD` |

**已采用的写法**

- `houseEdgeBps` 等配置用单次 `SLOAD` 计算 `fee`。
- `grossAmount == 0` 时 `payoutWinner` 早退，避免无效存储与转账。
- ETH 路径避免 ERC-20 的 `transferFrom`/`approve` 开销。

**可优化点**

| 优化 | 预期收益 | 说明 |
|------|----------|------|
| 将 `houseEdgeBps` 缓存到 `uint16` 并打包存储 | 小幅 | 与其他 admin 配置共槽，减少冷存储写入 |
| 批量 `payoutWinner`（多赢家场景） | 中 | 当前乐透仅单赢家，暂非刚需 |
| 用 `call` + 限制 gas 的 ETH 转账 | 视情况 | 已用 `call`；注意接收方为合约时的 fallback Gas |

---

### 4.2 VRFGameBase

| 函数 / 路径 | 相对成本 | 说明 |
|-------------|----------|------|
| `_requestRandomness` | 高 | 外部调用 `VRFCoordinator.requestRandomWords` |
| `fulfillRandomWords` | 高 | 写入 `VRFProofRecord` + 存储 `randomWords` 数组 |
| `__vrfCallbackTrampoline` | 中 | **额外一次 external call**（`this.`），为 `try/catch` 隔离游戏逻辑 |
| `getVRFRecordByContext` | 中（view） | 无请求时分配空 `uint256[]` 内存 |
| `retryVRF` | 高 | 更新旧记录 + 新 VRF 请求 |

**设计权衡（Gas vs 安全）**

```solidity
try this.__vrfCallbackTrampoline(...) { ... } catch { ... }
```

- **代价**：相对 `internal` 直接调用，增加约 **~2,600+ Gas**（`CALL` 固定成本 + 参数编码）。
- **收益**：游戏回调 `revert` 时不会使整个 VRF 交付失败，可标记 `VRFStatus.Failed` 并重试。
- **结论**：Demo/生产均建议保留；若确定游戏逻辑永不 revert，可改为 `internal` 调用以省 Gas（不推荐）。

**`callbackGasLimit` 调参**（`Deploy.s.sol` 当前 `500_000`）

| 游戏 | 回调主要工作 | 建议 |
|------|--------------|------|
| `DiceGame` | O(1) 结算 + 可选 `payoutWinner` | 可显著低于乐透；实测后设 `150_000`～`250_000` 量级 |
| `LotteryRaffle` | **O(n) 扫票** + `payoutWinner` | 随 `ticketCount` 线性增长；`n=100` 时需留足余量 |

过低会导致 VRF 回调 OOG，记录为 `Failed` 并需 `retryVRF`（再次消耗 Gas）。

---

### 4.3 LotteryRaffle — 主要热点

#### 4.3.1 购票 `buyTicketsWithETH` / `_buyTickets`

| 操作 | Gas 因素 |
|------|----------|
| `_tickets[roundId].push(Ticket)` | 动态数组 `push`：首次写槽 ~20k，后续 ~5k+（warm） |
| `round.totalWeight` / `poolAmount` | 各一次 `SSTORE`（warm 后较便宜） |
| `treasury.depositBet` | 跨合约 `CALL` + 金库存储 |

**已优化**

- `Ticket` 使用 `address` + `uint96`，**单槽 32 字节打包**（`20 + 12 = 32`），每笔票只占 1 个存储槽（加数组长度槽摊销）。
- 投注额即权重，避免额外 `weight` 计算存储。

#### 4.3.2 开奖回调 `_onRandomWordsFulfilled` — **O(n) 瓶颈**

```solidity
for (uint256 i = 0; i < tickets.length; i++) {
    accumulated += tickets[i].weight;
    if (winningPoint < accumulated) { ... }
}
```

| 参票数 n | 近似额外 Gas（仅循环体，不含 VRF/派彩） |
|----------|----------------------------------------|
| 10 | ~30k～50k |
| 100 | ~300k～500k |
| 1000 | **可能超过区块 Gas 上限** |

每项迭代：`SLOAD` 票权重 + 累加 + 条件判断。票存储在 **连续动态数组** 中，无默克尔证明，无法 O(log n) 查找。

**这是本项目最大的 Gas 优化议题**（见 §6.1）。

#### 4.3.3 `Round` 结构体存储

当前 `Round` 含多个 `uint256` 字段，部分 `uint64` 可打包：

| 字段 | 类型 | 打包建议 |
|------|------|----------|
| `startTime`, `endTime` | `uint64` | 与 `RoundStatus`（`uint8`）共占 1 槽 |
| `paymentToken` | `address` | 单独 1 槽 |
| `totalWeight`, `poolAmount`, … | `uint256` | 各 1 槽 |

重构打包可减少 `openRound` / 结算时的冷 `SSTORE`，节省约 **1～2 万 Gas/轮次**（视字段更新数量而定）。

---

### 4.4 DiceGame

| 函数 | 相对成本 | 说明 |
|------|----------|------|
| `commitBet` | 低 | 单 mapping 写入 `Commitment` |
| `revealAndBet` | 中～高 | `keccak256` + 多字段 `ActiveBet` 存储 + `depositBet` + `_requestRandomness` |
| `_onRandomWordsFulfilled` | 低～中 | O(1)；中奖时 `payoutWinner` |

**已优化**

- `_isWinner` 为 `pure`，无存储访问。
- 倍率为 `constant`，编译期内联。
- 未中奖路径仅 `emit`，不调用金库。

**可优化点**

| 优化 | 说明 |
|------|------|
| 打包 `ActiveBet` | `address` + `address` + `uint96 amount` + `BetKind` + `target` + `settled` 可压缩至 2～3 槽 |
| 合并 `commit` + `reveal` 为单笔（牺牲抗 MEV） | 省一次交易固定成本（~21k），但失去 Commit-Reveal 设计目标 |
| ERC-20 路径：游戏合约持币再 `deposit` | 当前 `transferFrom` + `forceApprove` 两次外部调用；可改为用户直接 `approve` 金库并由金库拉款（需改接口） |

---

## 5. 跨合约调用链 Gas

### 5.1 乐透购票（ETH）

```text
用户 EOA
  → LotteryRaffle.buyTicketsWithETH  (push ticket, 更新 round)
    → GameTreasury.depositBet        (池 += amount, 事件)
```

固定开销 ≈ **2× 合约调用** + **1× 动态数组 push** + **2～3× round 字段 SSTORE**。

### 5.2 乐透开奖（VRF 回调）

```text
VRF Coordinator
  → VRFGameBase.fulfillRandomWords   (写 proof, emit)
    → __vrfCallbackTrampoline          (external self-call)
      → LotteryRaffle._onRandomWordsFulfilled  (O(n) 循环)
        → GameTreasury.payoutWinner    (可选, CALL + ETH/ERC20)
```

回调 Gas = VRF 基础 + trampoline + **O(n)** + 派彩。

### 5.3 骰子完整流程

```text
commitBet          (~1 次冷存储)
  … 等待 N 区块 …
revealAndBet       (存储 ActiveBet + depositBet + requestVRF)
  … VRF …
_onRandomWordsFulfilled  (O(1), 中奖 + payout)
```

两笔交易的设计意图是安全；Gas 上比单笔下注高约 **一次交易的 21k+ 固定成本**。

---

## 6. 推荐优化方案（按优先级）

### 6.1 高优先级：乐透 O(n) → O(log n) 或 O(1)

| 方案 | 思路 | Gas 影响 | 复杂度 |
|------|------|----------|--------|
| **累积权重 Fenwick 树 / 线段树** | 链上维护前缀和，按 `winningPoint` 二分查找赢家 | 查找 O(log n)；构建/更新需额外结构 | 高 |
| **分桶 + 子区间** | 按权重范围分桶，先选桶再桶内扫描 | 平均优于 O(n) | 中 |
| **链下索引 + 链上 Merkle 证明** | 只验证赢家票在 Merkle 树中 | 回调 O(log n)；需可信索引或用户提交证明 | 高 |
| **限制每轮最大票数 `maxTickets`** | 硬顶 n，保证回调不超 `callbackGasLimit` | 不降低单次成本，但防止 OOG | 低 |

**Demo 阶段建议**：增加 `maxTicketsPerRound`（如 200）并在 `requestDraw` 前检查，配合调低/调高 `callbackGasLimit`。

### 6.2 中优先级：存储与类型

1. **打包 `Round`、`Commitment`、`ActiveBet`**（见 §4.3.3、§4.4）。
2. **`immutable` / `constant`**：已用于 `treasury`、`VRF` 参数；保持。
3. **自定义错误**（已用 `error` 而非 `require(string)`）：省部署与 revert Gas。
4. **`calldata` vs `memory`**：对外数组参数优先 `calldata`（当前 VRF 回调由协调器传入 `memory`，无法在消费者侧改）。

### 6.3 中优先级：VRF 与事件

1. **按实测设置 `callbackGasLimit`**，避免长期 `500_000` 浪费订阅额度。
2. **精简事件 indexed 字段**：减少 log Gas（每条 LOG 约 375+ / topic）。
3. **`getVRFRecordByContext` 无记录时**：避免 `new uint256[](0)`，可返回固定空数组引用或拆分 view（仅省 `eth_call` Gas）。

### 6.4 低优先级：路径合并

| 项 | 说明 |
|----|------|
| ETH 专用入口 | 已有 `buyTicketsWithETH`，避免 ERC-20 分支判断 |
| 批量购票 | `buyTickets(uint256[] amounts)` 摊薄每笔 21k 交易固定成本（前端仍可按笔发 tx） |
| 关闭 + 开奖合并 | `closeAndRequestDraw` 省一次交易（需权衡权限与流程清晰度） |

---

## 7. 已实现的 Gas 友好实践（清单）

- [x] Solidity **0.8** 内置溢出检查，无需 SafeMath。
- [x] **自定义 `error`** 替代字符串 revert。
- [x] **`immutable`**：`treasury`、VRF 配置。
- [x] **`constant`**：骰子倍率、`NATIVE_TOKEN`、`MAX_HOUSE_EDGE_BPS`。
- [x] **`Ticket` 单槽打包**（`address` + `uint96`）。
- [x] **金库 CEI**：先改 `_poolBalances` 再 `_transferOut`。
- [x] **`ReentrancyGuard`**：仅在外部资金出口使用，避免过度修饰 view。
- [x] **编译器优化** `optimizer_runs = 200`。
- [x] **Dice 未中奖早退**：不调用 `payoutWinner`。
- [x] **`payoutWinner(0)` 早退**。

---

## 8. 前端与用户侧 Gas 提示

| 行为 | 建议 |
|------|------|
| 乐透购票 | 优先 ETH 路径，少一次 `approve` 交易 |
| 骰子 | `commit` 与 `reveal` 分两笔；`revealDelayBlocks` 越小等待越短，但抗 MEV 越弱 |
| 批量操作 | 避免单轮极多小额票（链上 O(n) 开奖） |
| Gas 预估 | 使用 MetaMask / viem `estimateGas`，乐透开奖回调需用 **simulate + 票数** 估算 |

---

## 9. 优化验证清单

优化合并前建议执行：

```bash
forge test
forge test --gas-report > gas-report-before.txt
# 应用优化后
forge test --gas-report > gas-report-after.txt
```

对比关注函数：

| 合约 | 函数 |
|------|------|
| `LotteryRaffle` | `buyTicketsWithETH`, `_onRandomWordsFulfilled`（多票场景） |
| `DiceGame` | `revealAndBet`, `_onRandomWordsFulfilled` |
| `GameTreasury` | `depositBet`, `payoutWinner` |
| `VRFGameBase` | `retryVRF` |

乐透测试应覆盖 **n = 1, 10, 50** 票三种 `ticketCount`，绘制 Gas ~ n 曲线，验证 O(n) 斜率。

---

## 10. 已知局限与路线图

| 阶段 | 内容 |
|------|------|
| **当前 Demo** | O(n) 乐透开奖；`callbackGasLimit = 500_000` 偏保守；`via_ir = false` |
| **短期** | 增加 `maxTicketsPerRound`；按实测下调 VRF gas limit |
| **中期** | `Round` / `ActiveBet` 存储打包；Gas Report 纳入 CI |
| **长期** | Merkle / 线段树权重查找；`via_ir` + 高 `optimizer_runs` 专项测试 |
