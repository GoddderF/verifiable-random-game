# Verifiable Random Game

Verifiable Random Game 是一个本地可运行的去中心化可验证随机游戏平台 Demo。项目基于 Chainlink VRF 思路提供可验证随机性，支持乐透抽奖与骰子倍率投注两种玩法，并通过统一金库管理 ETH / ERC-20 投注资金。

当前 Demo 使用本地 Anvil 链和 MockVRFCoordinator 运行，适合开发、测试和课堂展示。

---

## 1. 技术栈

| 层级 | 技术 |
|------|------|
| 智能合约 | Solidity >= 0.8.20、Foundry、OpenZeppelin Contracts 5.x、Chainlink VRF |
| 前端 | Next.js App Router、Tailwind CSS、shadcn/ui、wagmi、viem |
| 钱包 | MetaMask 及兼容 EIP-1193 的钱包 |
| 本地链 | Anvil |
| 本地随机数 | MockVRFCoordinator |

---

## 2. 项目结构

```text
verifiable-random-game/
├── contracts/          # Foundry 智能合约
│   ├── src/
│   ├── script/
│   └── test/
├── frontend/           # Next.js 前端
├── docs/               # 架构、安全、Gas 文档
├── scripts/            # 部署与辅助脚本
└── package.json        # 根 Monorepo 配置
```

---

## 3. 环境要求

运行前请先安装：

- Node.js >= 20
- Foundry，包括 `forge`、`cast`、`anvil`
- MetaMask 浏览器插件

检查 Node.js：

```bash
node -v
npm -v
```

检查 Foundry：

```bash
forge --version
cast --version
anvil --version
```

如果 PowerShell 提示 `npm : 无法将“npm”项识别为 cmdlet...`，说明 Node.js 没有正确安装或没有加入系统 PATH。请重新安装 Node.js LTS 版本，并勾选 Add to PATH。

---

## 4. 安装依赖

在项目根目录运行：

```bash
npm install
```

如果合约依赖还没有安装，运行：

```bash
npm run contracts:install
```

---

## 5. 编译与测试合约

在项目根目录运行：

```bash
forge build
forge test
forge coverage --report summary
```

也可以使用 npm 脚本：

```bash
npm run contracts:build
npm run contracts:test
npm run contracts:coverage
```

---

## 6. 启动本地 Anvil 链

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

## 7. 部署合约

打开第二个终端，进入项目根目录。

Git Bash 示例：

```bash
cd /d/verifiable-random-game
```

PowerShell 示例：

```powershell
cd D:\verifiable-random-game
```

运行部署命令：

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

## 8. 配置前端环境变量

确认 `frontend/.env.local` 内容如下：

```env
NEXT_PUBLIC_CHAIN_ID=31337
NEXT_PUBLIC_TREASURY_ADDRESS=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
NEXT_PUBLIC_LOTTERY_ADDRESS=0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
NEXT_PUBLIC_DICE_ADDRESS=0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
NEXT_PUBLIC_ERC20_ADDRESS=0x0000000000000000000000000000000000000000
NEXT_PUBLIC_VRF_COORDINATOR_ADDRESS=0x5FbDB2315678afecb367f032d93F642f64180aa3
```

如果你的部署输出地址和上面不一样，请把 `.env.local` 中对应地址替换成实际部署地址。

注意：修改 `.env.local` 后，需要重新启动前端。

---

## 9. 启动前端

打开第三个终端，在项目根目录运行：

```bash
npm run frontend:dev
```

浏览器访问：

```text
http://localhost:3000
```

---

## 10. 配置 MetaMask

在 MetaMask 中添加本地网络：

```text
Network Name: Anvil
RPC URL: http://127.0.0.1:8545
Chain ID: 31337
Currency Symbol: ETH
```

导入管理员账户私钥：

```text
0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

管理员账户地址应为：

```text
0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266
```

---

## 11. 给测试账户发放本地 ETH

普通用户可以使用 MetaMask 新建账户，也可以导入其他测试账户。

如果普通账户没有 ETH，可以在终端中设置余额：

```bash
cast rpc anvil_setBalance 普通用户地址 0x3635C9ADC5DEA00000 --rpc-url http://127.0.0.1:8545
```

示例：

```bash
cast rpc anvil_setBalance 0x81a5452CAd5C81ACCa0592Ef7007fd6C51d6476C 0x3635C9ADC5DEA00000 --rpc-url http://127.0.0.1:8545
```

查看余额：

```bash
cast balance 普通用户地址 --ether --rpc-url http://127.0.0.1:8545
```

---

# 12. 乐透抽奖 Demo 测试流程

乐透玩法中，管理员负责管理期次，普通用户负责购买彩票。为了避免利益冲突，管理员不能参与乐透购票。

---

## Step 1：管理员开启新一期

使用管理员账户连接 MetaMask。

在“乐透抽奖”页面点击：

```text
开启新一期
```

成功后，当前期次状态应显示为：

```text
Open
```

---

## Step 2：普通用户购买彩票

切换 MetaMask 到普通用户账户。

刷新页面后，输入投注金额，例如：

```text
0.01
```

点击：

```text
购买彩票
```

交易成功后，页面中的奖池和总权重会增加。

---

## Step 3：管理员关闭期次

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

## Step 4：请求 VRF 开奖

管理员点击：

```text
请求 VRF 开奖
```

此时页面会显示 Request ID，状态变为：

```text
Drawing
```

在本地 Anvil 环境下，VRF 证明页面显示 `Pending` 是正常的，因为本地链不会自动完成 Chainlink VRF 回调。

---

## Step 5：触发 Mock 回调

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

# 13. 骰子倍率投注 Demo 测试流程

骰子玩法采用 Commit-Reveal + VRF 的流程：

```text
Commit
→ Reveal & Bet
→ VRF 掷骰
→ Mock 回调
→ 结算结果
```

骰子玩法中，管理员也可以下注，因为骰子没有开启/关闭期次的管理流程。

---

## Step 1：填写下注参数

进入“骰子”页面，填写：

```text
玩法：Exact / Over / Under
目标点数：1-6
ETH 赌注：例如 0.01
Nonce：例如 1
Secret：默认自动生成即可
```

说明：

- `Exact`：猜骰子点数正好等于目标点数。
- `Over`：猜骰子点数大于目标点数。
- `Under`：猜骰子点数小于目标点数。
- `Nonce`：本次下注的编号，用于和 Secret 一起生成 commitment，避免重复提交。

---

## Step 2：Commit

点击：

```text
1. Commit
```

MetaMask 确认交易。

Commit 成功后，需要等待指定区块数，页面会显示：

```text
可揭示下注
```

如果还没到时间，可以等待几秒，或者手动挖块：

```bash
cast rpc evm_mine --rpc-url http://127.0.0.1:8545
```

---

## Step 3：Reveal & Bet & 开奖

当页面显示“可揭示下注”后，点击：

```text
2. Reveal & Bet & 开奖
```

该按钮会先执行 Reveal & Bet。交易成功后，前端会自动解析 Bet ID 和 Request ID，并自动触发 Mock VRF 回调。

MetaMask 可能会连续弹出两次确认：

```text
第一次：Reveal & Bet
第二次：Mock VRF 回调
```

这是正常的，因为本地开奖需要两笔链上交易。

---

## Step 4：查看结果

开奖完成后，页面会显示：

```text
Bet ID
Request ID
骰子点数
是否中奖
派奖金额
```

如果中奖，合约会根据玩法和倍率进行派奖。  
如果未中奖，派奖金额为 `0 wei`。

---

# 14. VRF 证明查询

在乐透或骰子流程中，页面会生成 VRF Context。

切换到“VRF 证明”页面，将 Context 粘贴进去，点击查询，可以查看：

```text
Request ID
VRF 状态
随机数
请求时间
完成时间
```

本地 Anvil 环境下，如果还没有触发 Mock 回调，状态会显示：

```text
Pending
```

触发 Mock 回调后，应变为：

```text
Fulfilled
```

---

# 15. Anvil 重启说明

如果 Anvil 终端关闭后重新启动，本地链状态会清空。

也就是说：

- 默认账户地址通常不变
- 账户余额会恢复到初始状态
- 已部署合约会消失
- 已开启的乐透期次会消失
- 已购买的彩票会消失
- 骰子下注记录会消失
- VRF 状态和开奖结果会消失

所以每次重新启动 Anvil 后，需要重新部署合约：

```bash
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 forge script contracts/script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```

如果重新部署后的合约地址和 `.env.local` 中一致，则不需要修改配置。

如果地址不同，需要更新 `.env.local`，然后重新启动前端。

---

# 16. 常见问题

## Q1：为什么 VRF 状态一直是 Pending？

因为本地 Anvil 不会自动执行 Chainlink VRF 回调。  
需要点击页面上的：

```text
触发 Mock 回调
```

或在骰子页面点击：

```text
Reveal & Bet & 开奖
```

由前端自动触发 Mock 回调。

---

## Q2：为什么普通用户购买彩票失败？

可能原因：

- 当前乐透期次不是 Open 状态
- 普通用户账户没有 ETH
- 输入金额过大
- 当前轮次已经过期
- Anvil 重启后没有重新部署合约

建议先用 `0.01 ETH` 测试。

---

## Q3：为什么管理员不能购买彩票？

管理员负责控制乐透期次和开奖流程。  
为了避免管理员既控制开奖又参与投注造成利益冲突，前端限制管理员不能购买彩票。

---

## Q4：为什么骰子下注后没有立刻开奖？

骰子需要经过 Commit-Reveal 流程。  
必须先 Commit，等待指定区块后，再 Reveal & Bet。  
在本地环境中，Reveal & Bet 后还需要 Mock VRF 回调，当前前端会自动触发。

---

## Q5：为什么 Anvil 重启后页面报错？

Anvil 重启后，之前部署的合约不存在了。  
需要重新部署合约，并确认 `.env.local` 中的合约地址正确。

---

# 17. 简短运行流程总结

```text
启动 Anvil
→ 部署合约
→ 检查 frontend/.env.local
→ 启动前端
→ MetaMask 连接 Anvil 网络
→ 导入管理员账户
→ 使用乐透或骰子功能进行测试
```

乐透测试流程：

```text
管理员开启新一期
→ 普通用户购买彩票
→ 管理员关闭期次
→ 管理员请求 VRF 开奖
→ 管理员触发 Mock 回调
→ 查看中奖结果
```

骰子测试流程：

```text
填写玩法和金额
→ Commit
→ 等待可揭示
→ Reveal & Bet & 开奖
→ 查看骰子点数和派奖结果
```

---

## License

MIT