import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function shortenAddress(address: string, chars = 4): string {
  return `${address.slice(0, chars + 2)}…${address.slice(-chars)}`;
}

export function formatEth(value: bigint, decimals = 4): string {
  const s = Number(value) / 1e18;
  if (s === 0) return "0";
  if (s < 0.0001) return "<0.0001";
  return s.toLocaleString(undefined, { maximumFractionDigits: decimals });
}
