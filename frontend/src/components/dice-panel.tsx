"use client";

import { useEffect, useState } from "react";
import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
  useBlockNumber,
} from "wagmi";
import { parseEther, toHex, type Hex } from "viem";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { diceContract } from "@/lib/contracts";
import { contracts, contractsConfigured, BET_KIND } from "@/lib/contracts/config";
import { diceCommitment, diceVrfContext } from "@/lib/contracts/context";

export function DicePanel() {
  const { address, isConnected } = useAccount();
  const { data: blockNumber } = useBlockNumber({ watch: true });

  const [kind, setKind] = useState(0);
  const [target, setTarget] = useState("4");
  const [ethAmount, setEthAmount] = useState("0.1");
  const [secret, setSecret] = useState("");

  useEffect(() => {
    setSecret(toHex(crypto.getRandomValues(new Uint8Array(32))));
  }, []);
  const [nonce, setNonce] = useState("1");
  const [betIdQuery, setBetIdQuery] = useState("");
  const [vrfHint, setVrfHint] = useState("");

  const { data: revealDelay } = useReadContract({
    ...diceContract,
    functionName: "revealDelayBlocks",
    query: { enabled: contractsConfigured() },
  });

  const { data: commitment } = useReadContract({
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

  const { writeContract, data: txHash, isPending, error: writeError, reset } = useWriteContract();
  const { isLoading: confirming } = useWaitForTransactionReceipt({ hash: txHash });
  const busy = isPending || confirming;

  const commit = () => {
    if (!address) return;
    reset();
    const hash = diceCommitment(
      address,
      kind,
      Number(target),
      secret as Hex,
      BigInt(nonce),
    );
    writeContract({
      ...diceContract,
      functionName: "commitBet",
      args: [hash],
    });
  };

  const revealAndBet = () => {
    reset();
    const amount = parseEther(ethAmount);
    writeContract({
      ...diceContract,
      functionName: "revealAndBet",
      args: [
        secret as Hex,
        BigInt(nonce),
        kind,
        Number(target),
        "0x0000000000000000000000000000000000000000",
        amount,
      ],
      value: amount,
    });
  };

  const showBetVrf = () => {
    const betId = BigInt(betIdQuery || "0");
    if (betId > 0n) setVrfHint(diceVrfContext(contracts.dice, betId));
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>骰子倍率投注</CardTitle>
        <CardDescription>Commit-Reveal 防抢跑 → VRF 掷骰 → 动态赔率派奖</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {!contractsConfigured() && (
          <p className="text-sm text-amber-400">配置 NEXT_PUBLIC_DICE_ADDRESS 等环境变量。</p>
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
            <label className="mb-1 block text-xs text-slate-500">目标点数 (Exact)</label>
            <Input value={target} onChange={(e) => setTarget(e.target.value)} min={1} max={6} type="number" />
          </div>
          <div>
            <label className="mb-1 block text-xs text-slate-500">ETH 赌注</label>
            <Input value={ethAmount} onChange={(e) => setEthAmount(e.target.value)} type="number" step="0.01" />
          </div>
          <div>
            <label className="mb-1 block text-xs text-slate-500">Nonce</label>
            <Input value={nonce} onChange={(e) => setNonce(e.target.value)} />
          </div>
        </div>

        <div>
          <label className="mb-1 block text-xs text-slate-500">Secret (bytes32)</label>
          <Input value={secret} onChange={(e) => setSecret(e.target.value)} className="font-mono text-xs" />
        </div>

        <div className="flex flex-wrap gap-2">
          <Button onClick={commit} disabled={!isConnected || busy}>
            1. Commit
          </Button>
          <Button onClick={revealAndBet} disabled={!isConnected || busy} variant="secondary">
            2. Reveal &amp; Bet
          </Button>
        </div>

        <div className="flex gap-2">
          <Input placeholder="Bet ID" value={betIdQuery} onChange={(e) => setBetIdQuery(e.target.value)} />
          <Button variant="outline" size="sm" onClick={showBetVrf}>
            VRF Context
          </Button>
        </div>
        {vrfHint && <p className="break-all font-mono text-xs text-violet-300">{vrfHint}</p>}

        {writeError && <p className="text-sm text-rose-400">{writeError.message}</p>}
        {txHash && <p className="break-all text-xs text-slate-500">Tx: {txHash}</p>}
      </CardContent>
    </Card>
  );
}
