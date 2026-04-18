"use client";

import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { activeChain } from "@/lib/wagmi/config";
import { shortenAddress } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";

export function WalletConnect() {
  const { address, isConnected, chain } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();

  const wrongChain = isConnected && chain?.id !== activeChain.id;

  if (!isConnected) {
    const connector = connectors[0];
    return (
      <Button
        onClick={() => connector && connect({ connector, chainId: activeChain.id })}
        disabled={isPending || !connector}
      >
        {isPending ? "连接中…" : "连接 MetaMask"}
      </Button>
    );
  }

  return (
    <div className="flex flex-wrap items-center gap-2">
      {wrongChain && (
        <Button size="sm" variant="destructive" onClick={() => switchChain({ chainId: activeChain.id })}>
          切换到 {activeChain.name}
        </Button>
      )}
      <Badge variant={wrongChain ? "warning" : "success"}>{chain?.name ?? "Unknown"}</Badge>
      <Badge variant="muted">{shortenAddress(address!)}</Badge>
      <Button size="sm" variant="secondary" onClick={() => disconnect()}>
        断开
      </Button>
    </div>
  );
}
