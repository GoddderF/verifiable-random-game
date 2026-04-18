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
