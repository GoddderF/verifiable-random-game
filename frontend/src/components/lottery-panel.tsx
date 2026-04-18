"use client";

import { useMemo, useState } from "react";
import {
  useAccount,
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
import { contracts, contractsConfigured, ROUND_STATUS } from "@/lib/contracts/config";
import { lotteryVrfContext } from "@/lib/contracts/context";
import { formatEth } from "@/lib/utils";

export function LotteryPanel() {
  const { address, isConnected } = useAccount();
  const [ethAmount, setEthAmount] = useState("0.01");
  const [vrfContextHint, setVrfContextHint] = useState<string>("");

  const { data: roundId } = useReadContract({
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

  const { data: pendingRollover } = useReadContract({
    ...lotteryContract,
    functionName: "pendingRollover",
    query: { enabled: contractsConfigured() },
  });

  const { data: ethPool } = useReadContract({
    ...treasuryContract,
    functionName: "getPoolBalance",
    args: ["0x0000000000000000000000000000000000000000"],
    query: { enabled: contractsConfigured() },
  });

  const round = roundData as
    | readonly [bigint, bigint, number, `0x${string}`, bigint, bigint, bigint, bigint, `0x${string}`, bigint, bigint]
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
    };
  }, [round]);

  const { writeContract, data: txHash, isPending, error: writeError, reset } = useWriteContract();
  const { isLoading: confirming } = useWaitForTransactionReceipt({ hash: txHash });

  const busy = isPending || confirming;

  const buyEth = () => {
    reset();
    writeContract({
      ...lotteryContract,
      functionName: "buyTicketsWithETH",
      value: parseEther(ethAmount),
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
              <div className="sm:col-span-2">
                <Badge variant="muted">{ROUND_STATUS[parsed.status] ?? "—"}</Badge>
              </div>
            </>
          )}
        </div>

        {parsed && parsed.status === 0 && <Countdown endTimestamp={parsed.endTime} />}

        <div className="flex flex-col gap-2 sm:flex-row sm:items-end">
          <div className="flex-1">
            <label className="mb-1 block text-xs text-slate-500">投注 ETH</label>
            <Input value={ethAmount} onChange={(e) => setEthAmount(e.target.value)} type="number" min="0" step="0.001" />
          </div>
          <Button onClick={buyEth} disabled={!isConnected || busy || !contractsConfigured()}>
            购买彩票
          </Button>
        </div>

        <div className="flex flex-wrap gap-2">
          <Button variant="secondary" size="sm" onClick={closeRound} disabled={!isConnected || busy || id === 0n}>
            关闭期次
          </Button>
          <Button variant="secondary" size="sm" onClick={requestDraw} disabled={!isConnected || busy || id === 0n}>
            请求 VRF 开奖
          </Button>
          <Button variant="outline" size="sm" onClick={() => refetchRound()}>
            刷新
          </Button>
          <Button variant="outline" size="sm" onClick={showContext}>
            显示 VRF Context
          </Button>
        </div>

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
      <p className="font-mono text-sm text-slate-100">{value}</p>
    </div>
  );
}
