# Verifiable Random Game

去中心化可验证公平游戏平台。基于 **Chainlink VRF** 提供可验证随机性，支持乐透抽奖与骰子倍率投注两种玩法，并统一管理 ETH / ERC-20 投注金库。

## 技术栈

| 层级 | 技术 |
|------|------|
| 智能合约 | Solidity ≥0.8.20、Foundry、OpenZeppelin Contracts 5.x、Chainlink VRF |
| 前端 | Next.js (App Router)、Tailwind CSS、shadcn/ui、wagmi、viem |
| 钱包 | MetaMask 及兼容 EIP-1193 的钱包 |

## 项目结构

```
verifiable-random-game/
├── contracts/          # Foundry 智能合约
│   ├── src/
│   └── test/
├── frontend/           # Next.js 前端
├── docs/               # 架构、安全、Gas 文档
├── scripts/            # 部署与辅助脚本
└── package.json        # 根 Monorepo 配置
```

## 前置要求

- [Node.js](https://nodejs.org/) ≥ 20（安装后需勾选 **Add to PATH**，并重启终端）
- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast, anvil)
- MetaMask 浏览器扩展

### 常见问题：`npm` 无法识别

PowerShell 报错 `npm : 无法将“npm”项识别为 cmdlet...` 表示 **Node.js 未安装或未加入系统 PATH**（与项目代码无关）。

**Windows 修复步骤：**

1. 从 [https://nodejs.org/](https://nodejs.org/) 安装 LTS 版本（≥ 20）。
2. 安装向导中勾选 **Add to PATH**。
3. **关闭并重新打开**终端，执行 `node -v` 与 `npm -v` 确认可用。
4. 再在项目根目录运行 `npm install`。

> **说明**：Step 2 智能合约开发仅依赖 **Foundry (`forge`)**，不依赖 npm。前端与根目录脚本在 Step 4 才需要 npm。

## 快速启动

### 1. 安装依赖

```bash
# 根目录 npm 工作区
npm install

# Foundry 合约库 (OpenZeppelin, Chainlink, forge-std)
npm run contracts:install
```

### 2. 编译与测试合约

在项目根目录（推荐，依赖位于 `lib/`）：

```bash
forge build
forge test
forge coverage --report summary
```

或在 `contracts/` 子目录：

```bash
npm run contracts:build
npm run contracts:test
npm run contracts:coverage   # 目标：行覆盖率 ≥ 80%
```

### 3. 启动前端

```bash
cp frontend/.env.example frontend/.env.local
# 编辑 frontend/.env.local，填入已部署的合约地址

npm install
npm run frontend:dev
```

访问 [http://localhost:3000](http://localhost:3000)。

前端功能：MetaMask 连接、乐透投注与倒计时、骰子 Commit-Reveal、VRF RequestID / 随机数证明查询。

## 核心能力（规划）

- **可验证随机性**：Chainlink VRF Request-Response 异步回调，含失败重试与 Proof / RequestID 查询
- **乐透抽奖**：时间窗口投注、VRF 开奖、无人中奖资金滚存
- **骰子游戏**：VRF 骰点、动态赔率派奖
- **金库**：ETH + ERC-20、House Edge、最小/最大投注限制
- **公平性**：Commit-Reveal / 区块延迟、CEI 防重入

## 文档

- [系统架构](docs/architecture.md)
- [安全分析](docs/security-analysis.md)
- [Gas 优化](docs/gas-optimization.md)

## 许可证

MIT


# Verifiable Random Game

Verifiable Random Game 是一个本地可运行的去中心化随机游戏平台 Demo。  
当前主要演示基于 Mock VRF 的乐透抽奖功能，包括：

- 管理员开启新一期
- 普通用户购买彩票
- 管理员关闭期次
- 管理员请求 VRF 开奖
- 管理员触发 Mock VRF 回调
- 页面显示中奖地址和中奖金额

本 Demo 使用本地 Anvil 链运行，适合开发和演示使用。

---

## 1. 环境要求

运行项目前，请先安装：

- Node.js >= 20
- Foundry，包括 `forge`、`cast`、`anvil`
- MetaMask 浏览器插件

检查 Foundry 是否安装成功：

```bash
forge --version
cast --version
anvil --version
```

检查 Node.js 是否安装成功：

```bash
node -v
npm -v
```

---

## 2. 安装依赖

在项目根目录运行：

```bash
npm install
```

如果合约依赖还没有安装，可以运行：

```bash
npm run contracts:install
```

---

## 3. 启动本地 Anvil 链

打开第一个终端，运行：

```bash
anvil
```

该终端不要关闭。

默认本地链信息：

```text
RPC URL: http://127.0.0.1:8545
Chain ID: 31337
Currency Symbol: ETH
```

Anvil 默认第 0 个账户作为管理员账户：

```text
Address:
0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266

Private Key:
0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

---

## 4. 部署合约

打开第二个终端，进入项目根目录。

如果是 Git Bash：

```bash
cd /d/verifiable-random-game
```

如果是 PowerShell，可以根据自己的项目路径进入，例如：

```powershell
cd D:\verifiable-random-game
```

然后运行部署命令：

```bash
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 forge script contracts/script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```

部署成功后，正常会输出类似地址：

```text
MockVRFCoordinator: 0x5FbDB2315678afecb367f032d93F642f64180aa3
GameTreasury      : 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
LotteryRaffle     : 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
DiceGame          : 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
```

---

## 5. 配置前端环境变量

确认 `frontend/.env.local` 文件内容如下：

```env
NEXT_PUBLIC_CHAIN_ID=31337
NEXT_PUBLIC_TREASURY_ADDRESS=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
NEXT_PUBLIC_LOTTERY_ADDRESS=0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
NEXT_PUBLIC_DICE_ADDRESS=0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
NEXT_PUBLIC_ERC20_ADDRESS=0x0000000000000000000000000000000000000000
NEXT_PUBLIC_VRF_COORDINATOR_ADDRESS=0x5FbDB2315678afecb367f032d93F642f64180aa3
```

如果你部署出来的合约地址和上面不一样，请把 `.env.local` 中的地址替换成实际部署输出的地址。

---

## 6. 启动前端

打开第三个终端，进入项目根目录后运行：

```bash
npm run frontend:dev
```

然后在浏览器访问：

```text
http://localhost:3000
```

---

## 7. 配置 MetaMask

在 MetaMask 中添加本地网络：

```text
Network Name: Anvil
RPC URL: http://127.0.0.1:8545
Chain ID: 31337
Currency Symbol: ETH
```

然后导入管理员账户私钥：

```text
0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

管理员账户地址应为：

```text
0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266
```

管理员账户用于管理游戏流程，不能购买彩票。

---

## 8. 准备普通用户账户

普通用户可以使用 MetaMask 新建账户，也可以导入其他测试账户。

如果普通用户账户没有 ETH，可以在终端中执行：

```bash
cast rpc anvil_setBalance 普通用户地址 0x3635C9ADC5DEA00000 --rpc-url http://127.0.0.1:8545
```

例如：

```bash
cast rpc anvil_setBalance 0x81a5452CAd5C81ACCa0592Ef7007fd6C51d6476C 0x3635C9ADC5DEA00000 --rpc-url http://127.0.0.1:8545
```

查看余额：

```bash
cast balance 普通用户地址 --ether --rpc-url http://127.0.0.1:8545
```

---

## 9. 乐透 Demo 测试流程

### Step 1：管理员开启新一期

使用管理员账户连接 MetaMask。

在页面的“乐透抽奖”区域中点击：

```text
开启新一期
```

开启成功后，当前期次状态应显示为：

```text
Open
```

---

### Step 2：普通用户购买彩票

切换 MetaMask 到普通用户账户。

刷新页面后，输入投注金额，例如：

```text
0.01
```

然后点击：

```text
购买彩票
```

交易成功后，页面中的奖池和总权重会增加。

---

### Step 3：管理员关闭期次

切换回管理员账户。

等待倒计时结束后，点击：

```text
关闭期次
```

如果不想等待，可以在终端中快进 Anvil 时间：

```bash
cast rpc evm_increaseTime 300 --rpc-url http://127.0.0.1:8545
cast rpc evm_mine --rpc-url http://127.0.0.1:8545
```

然后回到页面点击“刷新”，再点击“关闭期次”。

---

### Step 4：请求 VRF 开奖

管理员点击：

```text
请求 VRF 开奖
```

此时页面会出现 Request ID，状态会变为：

```text
Drawing
```

VRF 证明查询中显示 `Pending` 是正常的，因为本地 Anvil 不会自动完成 VRF 回调。

---

### Step 5：触发 Mock 回调

管理员点击：

```text
触发 Mock 回调
```

该操作会调用本地 `MockVRFCoordinator`，模拟 Chainlink VRF 返回随机数。

然后点击：

```text
刷新
```

状态应变为：

```text
Settled
```

页面会显示中奖地址和中奖金额。

---

## 10. 角色说明

### 管理员

管理员账户是合约 owner，主要功能包括：

- 开启新一期
- 关闭期次
- 请求 VRF 开奖
- 触发 Mock 回调
- 显示 VRF Context

为了避免利益冲突，管理员不能购买彩票。

### 普通用户

普通用户主要功能包括：

- 购买彩票
- 查看当前期次
- 查看奖池
- 查看中奖结果

普通用户看不到管理员操作按钮。

---

## 11. Anvil 重启说明

如果 Anvil 终端关闭后重新启动，本地链状态会清空。

也就是说：

- 账户地址通常不变
- 合约需要重新部署
- 已开启的期次会消失
- 已购买彩票记录会消失
- VRF 状态和开奖结果会消失

所以每次重新启动 Anvil 后，需要重新执行：

```bash
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 forge script contracts/script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```

如果重新部署后的合约地址和 `.env.local` 中一致，则不需要修改配置。

如果地址不同，需要更新 `.env.local`，然后重新启动前端。

---

## 12. 常见问题

### Q1：为什么 VRF 状态一直是 Pending？

本地 Anvil 不会自动执行 Chainlink VRF 回调。  
管理员需要手动点击：

```text
触发 Mock 回调
```

---

### Q2：为什么普通用户购买彩票失败？

可能原因：

- 当前期次不是 Open 状态
- 普通用户账户没有 ETH
- 输入金额过大
- 当前轮次已经过期
- Anvil 重启后没有重新部署合约

建议先用 `0.01 ETH` 测试。

---

### Q3：为什么管理员不能购买彩票？

管理员负责控制期次和开奖流程。  
为了避免管理员既控制开奖又参与投注造成利益冲突，前端限制管理员不能购买彩票。

---

### Q4：为什么 Anvil 重启后页面报错？

Anvil 重启后，之前部署的合约不存在了。  
需要重新部署合约，并确认 `.env.local` 中的合约地址正确。

---

## 13. 简短测试流程总结

```text
启动 Anvil
→ 部署合约
→ 启动前端
→ MetaMask 连接管理员账户
→ 管理员开启新一期
→ 切换普通用户购买彩票
→ 切回管理员关闭期次
→ 请求 VRF 开奖
→ 触发 Mock 回调
→ 刷新查看中奖结果
```
