"use client";

import { useMemo, useState } from "react";
import {
  useAccount,
  usePublicClient,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { parseEther } from "viem";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Countdown } from "@/components/countdown";
import { lotteryContract, treasuryContract } from "@/lib/contracts";
import {
  contracts,
  contractsConfigured,
  mockVrfConfigured,
  ROUND_STATUS,
} from "@/lib/contracts/config";
import { lotteryVrfContext } from "@/lib/contracts/context";
import { formatEth } from "@/lib/utils";

const ETH_TOKEN = "0x0000000000000000000000000000000000000000" as const;

const mockVrfCoordinatorAbi = [
  {
    type: "function",
    name: "fulfillRandomWordsAuto",
    stateMutability: "nonpayable",
    inputs: [{ name: "requestId", type: "uint256" }],
    outputs: [],
  },
] as const;

export function LotteryPanel() {
  const { address, isConnected } = useAccount();
  const publicClient = usePublicClient();

  const [ethAmount, setEthAmount] = useState("0.01");
  const [roundDurationMinutes, setRoundDurationMinutes] = useState("5");
  const [vrfContextHint, setVrfContextHint] = useState<string>("");

  const { data: owner } = useReadContract({
    ...lotteryContract,
    functionName: "owner",
    query: { enabled: contractsConfigured() },
  });

  const isAdmin =
    Boolean(address) &&
    Boolean(owner) &&
    address?.toLowerCase() === String(owner).toLowerCase();

  const { data: roundId, refetch: refetchRoundId } = useReadContract({
    ...lotteryContract,
    functionName: "currentRoundId",
    query: { enabled: contractsConfigured() },
  });

  const id = (roundId as bigint | undefined) ?? 0n;

  const { data: roundData, refetch: refetchRound } = useReadContract({
    ...lotteryContract,
    functionName: "rounds",
    args: id > 0n ? [id] : undefined,
    query: { enabled: contractsConfigured() && id > 0n },
  });

  const { data: pendingRollover, refetch: refetchPendingRollover } = useReadContract({
    ...lotteryContract,
    functionName: "pendingRollover",
    query: { enabled: contractsConfigured() },
  });

  const { data: ethPool, refetch: refetchEthPool } = useReadContract({
    ...treasuryContract,
    functionName: "getPoolBalance",
    args: [ETH_TOKEN],
    query: { enabled: contractsConfigured() },
  });

  const round = roundData as
    | readonly [
        bigint,
        bigint,
        number,
        `0x${string}`,
        bigint,
        bigint,
        bigint,
        bigint,
        `0x${string}`,
        bigint,
        bigint
      ]
    | undefined;

  const parsed = useMemo(() => {
    if (!round) return null;

    return {
      startTime: round[0],
      endTime: round[1],
      status: round[2],
      paymentToken: round[3],
      totalWeight: round[4],
      poolAmount: round[5],
      rolloverIn: round[6],
      winner: round[8],
      winnerPayout: round[9],
      vrfRequestId: round[10],
    };
  }, [round]);

  const { writeContract, data: txHash, isPending, error: writeError, reset } = useWriteContract();
  const { isLoading: confirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash });

  const busy = isPending || confirming;

  const canBuyTicket =
    isConnected &&
    contractsConfigured() &&
    parsed?.status === 0 &&
    !busy &&
    !isAdmin;

  const refreshAll = () => {
    refetchRoundId();
    refetchRound();
    refetchPendingRollover();
    refetchEthPool();
  };

  const buyEth = () => {
    reset();

    if (isAdmin) {
      alert("管理员不能参与购买彩票。");
      return;
    }

    if (!ethAmount || Number(ethAmount) <= 0) {
      alert("请输入正确的投注金额");
      return;
    }

    writeContract({
      ...lotteryContract,
      functionName: "buyTicketsWithETH",
      value: parseEther(ethAmount),
    });
  };

  const openRound = async () => {
    reset();

    const minutes = Number(roundDurationMinutes);

    if (!minutes || minutes <= 0) {
      alert("请输入正确的期次持续时间");
      return;
    }

    if (!publicClient) {
      alert("无法读取当前链上区块时间，请检查钱包网络。");
      return;
    }

    const latestBlock = await publicClient.getBlock();
    const startTime = latestBlock.timestamp;
    const endTime = startTime + BigInt(Math.floor(minutes * 60));

    writeContract({
      ...lotteryContract,
      functionName: "openRound",
      args: [startTime, endTime, ETH_TOKEN],
    });
  };

  const closeRound = () => {
    reset();

    writeContract({
      ...lotteryContract,
      functionName: "closeRound",
      args: [id],
    });
  };

  const requestDraw = () => {
    reset();

    writeContract({
      ...lotteryContract,
      functionName: "requestDraw",
      args: [id],
    });
  };

  const fulfillMockVrf = () => {
    reset();

    if (!parsed || parsed.vrfRequestId === 0n) {
      alert("当前没有可回调的 VRF Request ID，请先请求 VRF 开奖。");
      return;
    }

    writeContract({
      address: contracts.vrfCoordinator,
      abi: mockVrfCoordinatorAbi,
      functionName: "fulfillRandomWordsAuto",
      args: [parsed.vrfRequestId],
    });
  };

  const showContext = () => {
    if (id > 0n) {
      setVrfContextHint(lotteryVrfContext(contracts.lottery, id));
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>乐透抽奖</CardTitle>
        <CardDescription>时间窗口内投注，结束后 VRF 加权开奖，奖金滚存至下期</CardDescription>
      </CardHeader>

      <CardContent className="space-y-4">
        {!contractsConfigured() && (
          <p className="text-sm text-amber-400">配置 NEXT_PUBLIC_LOTTERY_ADDRESS 等环境变量。</p>
        )}

        <div className="grid gap-3 sm:grid-cols-2">
          <Stat label="当前期次" value={id.toString()} />
          <Stat label="待滚存" value={formatEth((pendingRollover as bigint) ?? 0n)} />
          <Stat label="金库 ETH" value={formatEth((ethPool as bigint) ?? 0n)} />

          {parsed && (
            <>
              <Stat label="奖池" value={formatEth(parsed.poolAmount)} />
              <Stat label="总权重" value={formatEth(parsed.totalWeight)} />

              <div className="sm:col-span-2 flex flex-wrap items-center gap-2">
                <Badge variant="muted">{ROUND_STATUS[parsed.status] ?? "—"}</Badge>

                {parsed.vrfRequestId > 0n && (
                  <Badge variant="outline">Request ID: {parsed.vrfRequestId.toString()}</Badge>
                )}
              </div>

              {parsed.winner !== ETH_TOKEN && (
                <>
                  <Stat label="中奖地址" value={parsed.winner} />
                  <Stat label="中奖金额" value={formatEth(parsed.winnerPayout)} />
                </>
              )}
            </>
          )}
        </div>

        {parsed && parsed.status === 0 && <Countdown endTimestamp={parsed.endTime} />}

        <div className="space-y-2">
          <div className="flex flex-col gap-2 sm:flex-row sm:items-end">
            <div className="flex-1">
              <label className="mb-1 block text-xs text-slate-500">投注 ETH</label>
              <Input
                value={ethAmount}
                onChange={(e) => setEthAmount(e.target.value)}
                type="number"
                min="0"
                step="0.001"
                disabled={isAdmin}
              />
            </div>

            <Button onClick={buyEth} disabled={!canBuyTicket}>
              购买彩票
            </Button>
          </div>

          {isAdmin && (
            <p className="text-xs text-amber-400">
              当前钱包是管理员账户。为避免利益冲突，管理员不能参与购买彩票。
            </p>
          )}

          {!isAdmin && parsed && parsed.status !== 0 && (
            <p className="text-xs text-amber-400">
              当前期次不是 Open 状态，暂时不能购买彩票。请等待管理员开启新一期。
            </p>
          )}

          {!isConnected && (
            <p className="text-xs text-slate-500">
              请先连接钱包后再参与投注。
            </p>
          )}
        </div>

        <div className="flex flex-wrap gap-2">
          <Button variant="outline" size="sm" onClick={refreshAll}>
            刷新
          </Button>
        </div>

        {isAdmin && (
          <div className="rounded-lg border border-violet-800/60 bg-violet-950/20 p-4">
            <div className="mb-3">
              <p className="text-sm font-semibold text-violet-200">管理员操作</p>
              <p className="mt-1 text-xs text-slate-500">
                管理员只负责期次管理和 VRF 流程，不参与购买彩票。
              </p>
            </div>

            <div className="mb-3 flex flex-col gap-2 sm:flex-row sm:items-end">
              <div className="flex-1">
                <label className="mb-1 block text-xs text-slate-500">新一期持续时间（分钟）</label>
                <Input
                  value={roundDurationMinutes}
                  onChange={(e) => setRoundDurationMinutes(e.target.value)}
                  type="number"
                  min="1"
                  step="1"
                />
              </div>

              <Button
                variant="secondary"
                size="sm"
                onClick={openRound}
                disabled={!isConnected || busy || !contractsConfigured()}
              >
                开启新一期
              </Button>
            </div>

            <div className="flex flex-wrap gap-2">
              <Button
                variant="secondary"
                size="sm"
                onClick={closeRound}
                disabled={!isConnected || busy || id === 0n}
              >
                关闭期次
              </Button>

              <Button
                variant="secondary"
                size="sm"
                onClick={requestDraw}
                disabled={!isConnected || busy || id === 0n}
              >
                请求 VRF 开奖
              </Button>

              <Button
                variant="secondary"
                size="sm"
                onClick={fulfillMockVrf}
                disabled={
                  !isConnected ||
                  busy ||
                  !mockVrfConfigured() ||
                  !parsed ||
                  parsed.vrfRequestId === 0n ||
                  parsed.status !== 2
                }
              >
                触发 Mock 回调
              </Button>

              <Button variant="outline" size="sm" onClick={showContext} disabled={id === 0n}>
                显示 VRF Context
              </Button>
            </div>

            {!mockVrfConfigured() && (
              <p className="mt-2 text-xs text-amber-400">
                还没有配置 NEXT_PUBLIC_VRF_COORDINATOR_ADDRESS，无法触发 Mock 回调。
              </p>
            )}
          </div>
        )}

        {!isAdmin && isConnected && (
          <p className="text-xs text-slate-500">
            当前钱包是普通用户账户，只显示投注和查询功能。
          </p>
        )}

        {vrfContextHint && (
          <p className="break-all font-mono text-xs text-violet-300">
            Context: {vrfContextHint}
            <span className="mt-1 block text-slate-500">复制到「VRF 证明查询」面板</span>
          </p>
        )}

        {writeError && <p className="text-sm text-rose-400">{writeError.message}</p>}

        {txHash && (
          <p className="break-all text-xs text-slate-500">
            Tx: {txHash}
            {confirming && " (确认中…)"}
            {isSuccess && " (已确认)"}
          </p>
        )}
      </CardContent>
    </Card>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg border border-slate-800 bg-slate-950/50 px-3 py-2">
      <p className="text-xs text-slate-500">{label}</p>
      <p className="break-all font-mono text-sm text-slate-100">{value}</p>
    </div>
  );
}