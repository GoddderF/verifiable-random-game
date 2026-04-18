const chainId = Number(process.env.NEXT_PUBLIC_CHAIN_ID ?? "31337");

export const displayChain =
  chainId === 11_155_111 ? { name: "Sepolia", id: chainId } : { name: "Anvil", id: chainId };
