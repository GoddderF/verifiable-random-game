import { WalletConnect } from "@/components/wallet-connect";
import { LotteryPanel } from "@/components/lottery-panel";
import { DicePanel } from "@/components/dice-panel";
import { VrfProofPanel } from "@/components/vrf-proof-panel";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { displayChain } from "@/lib/chain-display";

export default function HomePage() {
  return (
    <main className="mx-auto min-h-screen max-w-6xl px-4 py-10">
      <header className="mb-10 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <p className="text-sm font-medium uppercase tracking-widest text-violet-400">Chainlink VRF</p>
          <h1 className="mt-1 text-3xl font-bold tracking-tight text-white sm:text-4xl">
            Verifiable Random Game
          </h1>
          <p className="mt-2 max-w-xl text-slate-400">
            可验证公平的乐透与骰子平台 · 网络: {displayChain.name} (id {displayChain.id})
          </p>
        </div>
        <WalletConnect />
      </header>

      <Tabs defaultValue="lottery" className="w-full">
        <TabsList className="grid w-full max-w-md grid-cols-3">
          <TabsTrigger value="lottery">乐透</TabsTrigger>
          <TabsTrigger value="dice">骰子</TabsTrigger>
          <TabsTrigger value="vrf">VRF 证明</TabsTrigger>
        </TabsList>
        <TabsContent value="lottery">
          <LotteryPanel />
        </TabsContent>
        <TabsContent value="dice">
          <DicePanel />
        </TabsContent>
        <TabsContent value="vrf">
          <VrfProofPanel />
        </TabsContent>
      </Tabs>

      <footer className="mt-16 border-t border-slate-800 pt-6 text-center text-xs text-slate-500">
        部署合约后，复制 <code className="text-violet-400">frontend/.env.example</code> 为{" "}
        <code className="text-violet-400">.env.local</code> 并填入地址。
      </footer>
    </main>
  );
}
