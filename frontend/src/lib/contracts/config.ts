import type { Address } from "viem";

const zero = "0x0000000000000000000000000000000000000000" as Address;

export const contracts = {
  treasury: (process.env.NEXT_PUBLIC_TREASURY_ADDRESS ?? zero) as Address,
  lottery: (process.env.NEXT_PUBLIC_LOTTERY_ADDRESS ?? zero) as Address,
  dice: (process.env.NEXT_PUBLIC_DICE_ADDRESS ?? zero) as Address,
  erc20: (process.env.NEXT_PUBLIC_ERC20_ADDRESS ?? zero) as Address,
  vrfCoordinator: (process.env.NEXT_PUBLIC_VRF_COORDINATOR_ADDRESS ?? zero) as Address,
};

export function contractsConfigured(): boolean {
  return (
    contracts.treasury !== zero &&
    contracts.lottery !== zero &&
    contracts.dice !== zero
  );
}

export function mockVrfConfigured(): boolean {
  return contracts.vrfCoordinator !== zero;
}

export const ROUND_STATUS = ["Open", "Closed", "Drawing", "Settled"] as const;

export const VRF_STATUS = [
  "None",
  "Pending",
  "Fulfilled",
  "Failed",
  "Superseded",
] as const;

export const BET_KIND = ["Exact", "Over", "Under"] as const;