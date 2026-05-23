"use client";

import { useEffect, useMemo, useState } from "react";
import {
  useAccount,
  useBlockNumber,
  useReadContract,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import { decodeEventLog, parseEther, toHex, type Hex } from "viem";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { diceContract } from "@/lib/contracts";
import {
  contracts,
  contractsConfigured,
  mockVrfConfigured,
  BET_KIND,
} from "@/lib/contracts/config";
import { diceCommitment, diceVrfContext } from "@/lib/contracts/context";

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

export function DicePanel() {
  const { address, isConnected } = useAccount();
  const { data: blockNumber } = useBlockNumber({ watch: true });

  const [kind, setKind] = useState(0);
  const [target, setTarget] = useState("4");
  const [ethAmount, setEthAmount] = useState("0.01");
  const [secret, setSecret] = useState("");
  const [nonce, setNonce] = useState("1");

  const [betIdQuery, setBetIdQuery] = useState("");
  const [vrfHint, setVrfHint] = useState("");
  const [statusHint, setStatusHint] = useState("");

  const [lastAction, setLastAction] = useState<"commit" | "reveal" | "mock" | null>(null);
  const [pendingMockRequestId, setPendingMockRequestId] = useState<bigint | null>(null);
  const [autoMockSent, setAutoMockSent] = useState(false);

  useEffect(() => {
    setSecret(toHex(crypto.getRandomValues(new Uint8Array(32))));
  }, []);

  const { data: revealDelay } = useReadContract({
    ...diceContract,
    functionName: "revealDelayBlocks",
    query: { enabled: contractsConfigured() },
  });

  const { data: commitment, refetch: refetchCommitment } = useReadContract({
    ...diceContract,
    functionName: "commitments",
    args: address ? [address] : undefined,
    query: { enabled: contractsConfigured() && Boolean(address) },
  });

  const commitBlock = commitment
    ? (commitment as readonly [Hex, bigint, boolean])[1]
    : undefined;

  const blocksUntilReveal =
    commitBlock !== undefined && revealDelay !== undefined && blockNumber !== undefined
      ? Math.max(0, Number(commitBlock) + Number(revealDelay as bigint) - Number(blockNumber))
      : null;

  const currentBetId = useMemo(() => {
    try {
      const value = BigInt(betIdQuery || "0");
      return value > 0n ? value : 0n;
    } catch {
      return 0n;
    }
  }, [betIdQuery]);

  const currentVrfContext = useMemo(() => {
    if (currentBetId <= 0n) return undefined;
    return diceVrfContext(contracts.dice, currentBetId);
  }, [currentBetId]);

  const { data: activeRequestId, refetch: refetchActiveRequestId } = useReadContract({
    ...diceContract,
    functionName: "getActiveRequestId",
    args: currentVrfContext ? [currentVrfContext] : undefined,
    query: {
      enabled: contractsConfigured() && Boolean(currentVrfContext),
    },
  });

  const { data: betData, refetch: refetchBet } = useReadContract({
    ...diceContract,
    functionName: "bets",
    args: currentBetId > 0n ? [currentBetId] : undefined,
    query: {
      enabled: contractsConfigured() && currentBetId > 0n,
    },
  });

  const parsedBet = betData
    ? (betData as readonly [`0x${string}`, `0x${string}`, bigint, number, number, boolean])
    : undefined;

  const {
    writeContract,
    data: txHash,
    isPending,
    error: writeError,
    reset,
  } = useWriteContract();

  const {
    data: receipt,
    isLoading: confirming,
    isSuccess,
  } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  const busy = isPending || confirming;

  const canCommit =
    isConnected &&
    contractsConfigured() &&
    !busy;

  const canReveal =
    isConnected &&
    contractsConfigured() &&
    !busy &&
    blocksUntilReveal === 0;

  const canManualMockFulfill =
    isConnected &&
    contractsConfigured() &&
    mockVrfConfigured() &&
    !busy &&
    currentBetId > 0n &&
    activeRequestId !== undefined &&
    (activeRequestId as bigint) > 0n &&
    parsedBet !== undefined &&
    parsedBet[5] === false;

  useEffect(() => {
    if (!receipt || !isSuccess || lastAction !== "reveal") return;

    let revealedBetId: bigint | null = null;
    let revealedRequestId: bigint | null = null;

    for (const log of receipt.logs) {
      if (log.address.toLowerCase() !== diceContract.address.toLowerCase()) {
        continue;
      }

      try {
        const decoded = decodeEventLog({
          abi: diceContract.abi,
          data: log.data,
          topics: log.topics,
        });

        if (decoded.eventName === "BetRevealed") {
          revealedBetId = decoded.args.betId as bigint;
        }

        if (decoded.eventName === "VRFRequested") {
          revealedRequestId = decoded.args.requestId as bigint;
        }
      } catch {
        // Ignore unrelated logs.
      }
    }

    if (revealedBetId) {
      const context = diceVrfContext(contracts.dice, revealedBetId);

      setBetIdQuery(revealedBetId.toString());
      setVrfHint(context);
      setStatusHint(
        `Reveal & Bet 成功，Bet ID = ${revealedBetId.toString()}。正在准备触发 Mock 回调。`
      );

      refetchActiveRequestId();
      refetchBet();
      refetchCommitment();
    }

    if (revealedRequestId && mockVrfConfigured() && !autoMockSent) {
      setPendingMockRequestId(revealedRequestId);
      setAutoMockSent(true);
      setLastAction("mock");

      writeContract({
        address: contracts.vrfCoordinator,
        abi: mockVrfCoordinatorAbi,
        functionName: "fulfillRandomWordsAuto",
        args: [revealedRequestId],
      });
    }
  }, [
    receipt,
    isSuccess,
    lastAction,
    autoMockSent,
    writeContract,
    refetchActiveRequestId,
    refetchBet,
    refetchCommitment,
  ]);

  useEffect(() => {
    if (!receipt || !isSuccess || lastAction !== "mock") return;

    for (const log of receipt.logs) {
      if (log.address.toLowerCase() !== diceContract.address.toLowerCase()) {
        continue;
      }

      try {
        const decoded = decodeEventLog({
          abi: diceContract.abi,
          data: log.data,
          topics: log.topics,
        });

        if (decoded.eventName === "DiceRollSettled") {
          const betId = decoded.args.betId as bigint;
          const roll = decoded.args.roll as number;
          const payout = decoded.args.payout as bigint;
          const won = decoded.args.won as boolean;

          setStatusHint(
            `开奖完成：Bet ID = ${betId.toString()}，骰子点数 = ${roll.toString()}，结果 = ${
              won ? "中奖" : "未中奖"
            }，派奖 = ${payout.toString()} wei。`
          );

          refetchActiveRequestId();
          refetchBet();
          refetchCommitment();
          break;
        }
      } catch {
        // Ignore unrelated logs.
      }
    }
  }, [
    receipt,
    isSuccess,
    lastAction,
    refetchActiveRequestId,
    refetchBet,
    refetchCommitment,
  ]);

  const commit = () => {
    if (!address) return;

    if (!secret || !secret.startsWith("0x")) {
      alert("Secret 格式不正确。");
      return;
    }

    reset();
    setLastAction("commit");
    setStatusHint("");
    setPendingMockRequestId(null);
    setAutoMockSent(false);

    const hash = diceCommitment(
      address,
      kind,
      Number(target),
      secret as Hex,
      BigInt(nonce)
    );

    writeContract({
      ...diceContract,
      functionName: "commitBet",
      args: [hash],
    });
  };

  const revealBetAndAutoDraw = () => {
    if (!ethAmount || Number(ethAmount) <= 0) {
      alert("请输入正确的 ETH 赌注金额。");
      return;
    }

    if (!target || Number(target) < 1 || Number(target) > 6) {
      alert("目标点数必须在 1 到 6 之间。");
      return;
    }

    if (!nonce || Number(nonce) < 0) {
      alert("请输入正确的 Nonce。");
      return;
    }

    reset();
    setLastAction("reveal");
    setStatusHint("");
    setPendingMockRequestId(null);
    setAutoMockSent(false);

    const amount = parseEther(ethAmount);

    writeContract({
      ...diceContract,
      functionName: "revealAndBet",
      args: [
        secret as Hex,
        BigInt(nonce),
        kind,
        Number(target),
        ETH_TOKEN,
        amount,
      ],
      value: amount,
    });
  };

  const showBetVrf = () => {
    const betId = currentBetId;

    if (betId <= 0n) {
      alert("请先输入或生成 Bet ID。");
      return;
    }

    setVrfHint(diceVrfContext(contracts.dice, betId));
    refetchActiveRequestId();
  };

  const fulfillMockVrfManually = () => {
    const requestId =
      pendingMockRequestId ??
      (activeRequestId !== undefined ? (activeRequestId as bigint) : 0n);

    if (!requestId || requestId === 0n) {
      alert("当前没有可回调的 VRF Request ID。请先完成 Reveal & Bet。");
      return;
    }

    reset();
    setLastAction("mock");

    writeContract({
      address: contracts.vrfCoordinator,
      abi: mockVrfCoordinatorAbi,
      functionName: "fulfillRandomWordsAuto",
      args: [requestId],
    });
  };

  const refreshDiceState = () => {
    refetchCommitment();
    refetchActiveRequestId();
    refetchBet();
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>骰子倍率投注</CardTitle>
        <CardDescription>
          Commit-Reveal 防抢跑 → VRF 掷骰 → 动态赔率派奖
        </CardDescription>
      </CardHeader>

      <CardContent className="space-y-4">
        {!contractsConfigured() && (
          <p className="text-sm text-amber-400">
            配置 NEXT_PUBLIC_DICE_ADDRESS 等环境变量。
          </p>
        )}

        {isConnected && (
          <p className="text-xs text-slate-500">
            当前钱包可以参与骰子下注。Commit 后等待指定区块，再点击 Reveal & Bet & 开奖。
          </p>
        )}

        {blocksUntilReveal !== null && (
          <Badge variant={blocksUntilReveal === 0 ? "success" : "warning"}>
            {blocksUntilReveal === 0
              ? "可揭示下注"
              : `还需 ${blocksUntilReveal} 个区块后可揭示`}
          </Badge>
        )}

        <div className="grid gap-3 sm:grid-cols-2">
          <div>
            <label className="mb-1 block text-xs text-slate-500">玩法</label>
            <select
              className="h-10 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 text-sm"
              value={kind}
              onChange={(e) => setKind(Number(e.target.value))}
            >
              {BET_KIND.map((k, i) => (
                <option key={k} value={i}>
                  {k}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="mb-1 block text-xs text-slate-500">目标点数</label>
            <Input
              value={target}
              onChange={(e) => setTarget(e.target.value)}
              min={1}
              max={6}
              type="number"
            />
          </div>

          <div>
            <label className="mb-1 block text-xs text-slate-500">ETH 赌注</label>
            <Input
              value={ethAmount}
              onChange={(e) => setEthAmount(e.target.value)}
              type="number"
              step="0.01"
            />
          </div>

          <div>
            <label className="mb-1 block text-xs text-slate-500">Nonce</label>
            <Input
              value={nonce}
              onChange={(e) => setNonce(e.target.value)}
            />
          </div>
        </div>

        <div>
          <label className="mb-1 block text-xs text-slate-500">Secret (bytes32)</label>
          <Input
            value={secret}
            onChange={(e) => setSecret(e.target.value)}
            className="font-mono text-xs"
          />
        </div>

        <div className="flex flex-wrap gap-2">
          <Button onClick={commit} disabled={!canCommit}>
            1. Commit
          </Button>

          <Button onClick={revealBetAndAutoDraw} disabled={!canReveal} variant="secondary">
            2. Reveal &amp; Bet &amp; 开奖
          </Button>

          <Button variant="outline" size="sm" onClick={refreshDiceState}>
            刷新
          </Button>
        </div>

        <div className="flex gap-2">
          <Input
            placeholder="Bet ID"
            value={betIdQuery}
            onChange={(e) => setBetIdQuery(e.target.value)}
          />

          <Button variant="outline" size="sm" onClick={showBetVrf}>
            VRF Context
          </Button>
        </div>

        {currentBetId > 0n && (
          <div className="rounded-lg border border-slate-800 bg-slate-950/50 px-3 py-2 text-xs text-slate-300">
            <p>当前 Bet ID：{currentBetId.toString()}</p>

            {activeRequestId !== undefined && (
              <p>Request ID：{(activeRequestId as bigint).toString()}</p>
            )}

            {parsedBet && (
              <p>
                下注状态：{parsedBet[5] ? "已结算" : "等待 VRF 回调 / 未结算"}
              </p>
            )}
          </div>
        )}

        {vrfHint && (
          <p className="break-all font-mono text-xs text-violet-300">
            {vrfHint}
            <span className="mt-1 block text-slate-500">
              可复制到「VRF 证明」页面查询。
            </span>
          </p>
        )}

        <div className="flex flex-wrap gap-2">
          <Button
            variant="secondary"
            size="sm"
            onClick={fulfillMockVrfManually}
            disabled={!canManualMockFulfill}
          >
            手动触发 Mock 回调
          </Button>
        </div>

        {!mockVrfConfigured() && (
          <p className="text-xs text-amber-400">
            还没有配置 NEXT_PUBLIC_VRF_COORDINATOR_ADDRESS，无法触发 Mock 回调。
          </p>
        )}

        {statusHint && <p className="text-sm text-emerald-400">{statusHint}</p>}

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