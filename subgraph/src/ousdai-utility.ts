import { log } from "@graphprotocol/graph-ts";
import {
  ComposerDepositAndStake as ComposerDepositAndStakeEvent,
  ComposerDeposit as ComposerDepositEvent,
} from "../generated/OUSDaiUtility/OUSDaiUtility";
import {
  ComposerDeposit,
  ComposerDepositAndStake,
  Event,
} from "../generated/schema";
import { createEventID } from "./utils/misc";

class EventType {
  static ComposerDeposit: string = "ComposerDeposit";
  static ComposerDepositAndStake: string = "ComposerDepositAndStake";
}

export function handleComposerDeposit(event: ComposerDepositEvent): void {
  const id = createEventID(event);

  // Create the Event entity
  const eventEntity = new Event(id);
  eventEntity.type = EventType.ComposerDeposit;
  eventEntity.contract = event.address;
  eventEntity.account = event.params.recipient;
  eventEntity.transactionHash = event.transaction.hash;
  eventEntity.timestamp = event.block.timestamp;

  // Create the ComposerDeposit entity
  const composerDepositEntity = new ComposerDeposit(id);
  composerDepositEntity.contract = event.address;
  composerDepositEntity.dstEid = event.params.dstEid;
  composerDepositEntity.depositToken = event.params.depositToken;
  composerDepositEntity.recipient = event.params.recipient;
  composerDepositEntity.depositAmount = event.params.depositAmount;
  composerDepositEntity.usdaiAmount = event.params.usdaiAmount;
  composerDepositEntity.timestamp = event.block.timestamp;
  composerDepositEntity.transactionHash = event.transaction.hash;

  // Save the entities
  composerDepositEntity.save();

  // Link the ComposerDeposit entity to the Event entity
  eventEntity.composerDeposit = id;
  eventEntity.save();

  log.info("Handled OUSDaiUtility ComposerDeposit event: {}", [id]);
}

export function handleComposerDepositAndStake(
  event: ComposerDepositAndStakeEvent
): void {
  const id = createEventID(event);

  // Create the Event entity
  const eventEntity = new Event(id);
  eventEntity.type = EventType.ComposerDepositAndStake;
  eventEntity.contract = event.address;
  eventEntity.account = event.params.recipient;
  eventEntity.transactionHash = event.transaction.hash;
  eventEntity.timestamp = event.block.timestamp;

  // Create the ComposerDepositAndStake entity
  const composerDepositAndStakeEntity = new ComposerDepositAndStake(id);
  composerDepositAndStakeEntity.contract = event.address;
  composerDepositAndStakeEntity.dstEid = event.params.dstEid;
  composerDepositAndStakeEntity.depositToken = event.params.depositToken;
  composerDepositAndStakeEntity.recipient = event.params.recipient;
  composerDepositAndStakeEntity.depositAmount = event.params.depositAmount;
  composerDepositAndStakeEntity.usdaiAmount = event.params.usdaiAmount;
  composerDepositAndStakeEntity.susdaiAmount = event.params.susdaiAmount;
  composerDepositAndStakeEntity.timestamp = event.block.timestamp;
  composerDepositAndStakeEntity.transactionHash = event.transaction.hash;

  // Save the entities
  composerDepositAndStakeEntity.save();

  // Link the ComposerDepositAndStake entity to the Event entity
  eventEntity.composerDepositAndStake = id;
  eventEntity.save();

  log.info("Handled OUSDaiUtility ComposerDepositAndStake event: {}", [id]);
}
