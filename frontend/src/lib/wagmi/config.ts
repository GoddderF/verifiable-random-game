import { http, createConfig } from "wagmi";
import { sepolia } from "wagmi/chains";
import { injected } from "wagmi/connectors";
import { defineChain } from "viem";

export const anvil = defineChain({
  id: 31337,
  name: "Anvil",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: {
      http: [process.env.NEXT_PUBLIC_RPC_URL ?? "http://127.0.0.1:8545"],
    },
  },
});

const chainId = Number(process.env.NEXT_PUBLIC_CHAIN_ID ?? "31337");
export const activeChain = chainId === sepolia.id ? sepolia : anvil;

export const wagmiConfig = createConfig({
  chains: [activeChain, sepolia],
  connectors: [injected({ target: "metaMask" })],
  transports: {
    [anvil.id]: http(process.env.NEXT_PUBLIC_RPC_URL ?? "http://127.0.0.1:8545"),
    [sepolia.id]: http(),
  },
  ssr: true,
});
