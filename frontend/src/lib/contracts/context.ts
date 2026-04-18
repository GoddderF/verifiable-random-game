import { encodeAbiParameters, keccak256, type Address } from "viem";

export function lotteryVrfContext(lottery: Address, roundId: bigint) {
  return keccak256(
    encodeAbiParameters(
      [{ type: "string" }, { type: "address" }, { type: "uint256" }],
      ["LOTTERY_ROUND", lottery, roundId],
    ),
  );
}

export function diceVrfContext(dice: Address, betId: bigint) {
  return keccak256(
    encodeAbiParameters(
      [{ type: "string" }, { type: "address" }, { type: "uint256" }],
      ["DICE_BET", dice, betId],
    ),
  );
}

export function diceCommitment(
  player: Address,
  kind: number,
  target: number,
  secret: `0x${string}`,
  nonce: bigint,
) {
  return keccak256(
    encodeAbiParameters(
      [
        { type: "address" },
        { type: "uint8" },
        { type: "uint8" },
        { type: "bytes32" },
        { type: "uint256" },
      ],
      [player, kind, target, secret, nonce],
    ),
  );
}
