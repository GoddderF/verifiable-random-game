import type { Abi, Address } from "viem";
import lotteryAbi from "@/lib/abis/LotteryRaffle.json";
import diceAbi from "@/lib/abis/DiceGame.json";
import treasuryAbi from "@/lib/abis/GameTreasury.json";
import { contracts } from "./config";

export { contracts };

export const lotteryContract = {
  address: contracts.lottery,
  abi: lotteryAbi as Abi,
} as const;

export const diceContract = {
  address: contracts.dice,
  abi: diceAbi as Abi,
} as const;

export const treasuryContract = {
  address: contracts.treasury,
  abi: treasuryAbi as Abi,
} as const;

const erc20Abi = [
  {
    type: "function",
    name: "approve",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ type: "bool" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "allowance",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "decimals",
    inputs: [],
    outputs: [{ type: "uint8" }],
    stateMutability: "view",
  },
] as const satisfies Abi;

export function erc20Contract(token: Address) {
  return { address: token, abi: erc20Abi } as const;
}
