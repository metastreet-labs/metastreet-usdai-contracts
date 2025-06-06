import { BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";

export function bytesFromBigInt(bigInt: BigInt): Bytes {
  return Bytes.fromByteArray(Bytes.fromBigInt(bigInt));
}

export function createEventID(event: ethereum.Event): string {
  return event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
}
