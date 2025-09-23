import { dataSource, log } from "@graphprotocol/graph-ts";
import {
  Deposited as DepositedEvent,
  Withdrawn as WithdrawnEvent,
} from "../generated/USDai/USDai";
import { Deposited, Event, Withdrawn } from "../generated/schema";
import { createEventID } from "./utils";

class EventType {
  static Deposited: string = "Deposited";
  static Withdrawn: string = "Withdrawn";
}

export function handleDeposited(event: DepositedEvent): void {
  const id = createEventID(event);

  log.info("USDai Deposited event network: {}", [dataSource.network()]);

  const eventEntity = new Event(id);
  eventEntity.type = EventType.Deposited;
  eventEntity.contract = event.address;
  eventEntity.account = event.params.caller;
  eventEntity.transactionHash = event.transaction.hash;
  eventEntity.timestamp = event.block.timestamp;

  const depositedEntity = new Deposited(id);
  depositedEntity.contract = event.address;
  depositedEntity.account = event.params.caller;
  depositedEntity.amount = event.params.mintAmount;
  depositedEntity.timestamp = event.block.timestamp;

  depositedEntity.save();

  eventEntity.deposited = id;
  eventEntity.save();

  log.info("Handled USDai Deposited event: {}", [id]);
}

export function handleWithdrawn(event: WithdrawnEvent): void {
  const id = createEventID(event);

  const eventEntity = new Event(id);
  eventEntity.type = EventType.Withdrawn;
  eventEntity.contract = event.address;
  eventEntity.account = event.params.caller;
  eventEntity.transactionHash = event.transaction.hash;
  eventEntity.timestamp = event.block.timestamp;

  const withdrawnEntity = new Withdrawn(id);
  withdrawnEntity.contract = event.address;
  withdrawnEntity.account = event.params.caller;
  withdrawnEntity.amount = event.params.withdrawAmount;
  withdrawnEntity.timestamp = event.block.timestamp;

  withdrawnEntity.save();

  eventEntity.withdrawn = id;
  eventEntity.save();

  log.info("Handled USDai Withdrawn event: {}", [id]);
}
