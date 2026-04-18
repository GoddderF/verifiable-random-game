"use client";

import { useState } from "react";
import { useReadContract } from "wagmi";
import { type Hex, isHex } from "viem";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { lotteryContract, diceContract } from "@/lib/contracts";
import { VRF_STATUS } from "@/lib/contracts/config";
import { contractsConfigured } from "@/lib/contracts/config";

type Game = "lottery" | "dice";

export function VrfProofPanel() {
  const [game, setGame] = useState<Game>("lottery");
  const [context, setContext] = useState("");
  const [queryContext, setQueryContext] = useState<Hex | undefined>();

  const contract = game === "lottery" ? lotteryContract : diceContract;

  const { data, isFetching, refetch } = useReadContract({
    ...contract,
    functionName: "getVRFRecordByContext",
    args: queryContext ? [queryContext] : undefined,
    query: { enabled: Boolean(queryContext && contractsConfigured()) },
  });

  const record = data as
    | {
        requestId: bigint;
        context: Hex;
        randomWords: readonly bigint[];
        status: number;
        requestedAt: bigint;
        fulfilledAt: bigint;
        retryCount: number;
        supersededByRequestId: bigint;
      }
    | undefined;

  const lookup = () => {
    if (!isHex(context, { strict: false })) return;
    setQueryContext(context as Hex);
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>VRF 证明查询</CardTitle>
        <CardDescription>按 context 查询 RequestID、随机数与状态（链上只读）</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {!contractsConfigured() && (
          <p className="text-sm text-amber-400">请在 .env.local 中配置合约地址后刷新页面。</p>
        )}
        <div className="flex gap-2">
          <Button size="sm" variant={game === "lottery" ? "default" : "secondary"} onClick={() => setGame("lottery")}>
            乐透
          </Button>
          <Button size="sm" variant={game === "dice" ? "default" : "secondary"} onClick={() => setGame("dice")}>
            骰子
          </Button>
        </div>
        <Input
          placeholder="0x… context (bytes32)"
          value={context}
          onChange={(e) => setContext(e.target.value)}
        />
        <Button onClick={lookup} disabled={!contractsConfigured()}>
          查询
        </Button>
        {queryContext && (
          <Button variant="outline" size="sm" onClick={() => refetch()}>
            刷新
          </Button>
        )}
        {isFetching && <p className="text-sm text-slate-400">加载中…</p>}
        {record && (
          <div className="space-y-2 rounded-lg border border-slate-800 bg-slate-950/60 p-4 text-sm">
            <Row label="Request ID" value={record.requestId.toString()} />
            <Row label="Status" value={VRF_STATUS[record.status] ?? String(record.status)} />
            <Row label="Retry count" value={String(record.retryCount)} />
            <Row label="Requested at" value={new Date(Number(record.requestedAt) * 1000).toLocaleString()} />
            {record.fulfilledAt > 0n && (
              <Row label="Fulfilled at" value={new Date(Number(record.fulfilledAt) * 1000).toLocaleString()} />
            )}
            {record.supersededByRequestId > 0n && (
              <Row label="Superseded by" value={record.supersededByRequestId.toString()} />
            )}
            <div>
              <span className="text-slate-500">Random words: </span>
              <code className="block break-all text-xs text-violet-300">
                {record.randomWords.length
                  ? record.randomWords.map((w) => w.toString()).join(", ")
                  : "—"}
              </code>
            </div>
            <Badge variant={record.status === 2 ? "success" : record.status === 3 ? "destructive" : "muted"}>
              {VRF_STATUS[record.status]}
            </Badge>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-4">
      <span className="text-slate-500">{label}</span>
      <span className="font-mono text-slate-200">{value}</span>
    </div>
  );
}
