import { log } from "@graphprotocol/graph-ts";
import {
  Deposit as DepositEvent,
  Withdraw as WithdrawEvent,
} from "../generated/sUSDai/StakedUSDai";
import { Deposited, Event, Withdrawn } from "../generated/schema";
import { createEventID } from "./utils/misc";

class EventType {
  static Deposit: string = "Deposit";
  static Withdraw: string = "Withdraw";
}

export function handleDeposit(event: DepositEvent): void {
  const id = createEventID(event);

  const eventEntity = new Event(id);
  eventEntity.type = EventType.Deposit;
  eventEntity.contract = event.address;
  eventEntity.account = event.params.sender;
  eventEntity.transactionHash = event.transaction.hash;
  eventEntity.timestamp = event.block.timestamp;

  const depositedEntity = new Deposited(id);
  depositedEntity.contract = event.address;
  depositedEntity.account = event.params.sender;
  depositedEntity.amount = event.params.shares;
  depositedEntity.timestamp = event.block.timestamp;

  depositedEntity.save();

  eventEntity.deposited = id;
  eventEntity.save();

  log.info("Handled sUSDai Deposit event: {}", [id]);
}

export function handleWithdraw(event: WithdrawEvent): void {
  const id = createEventID(event);

  const eventEntity = new Event(id);
  eventEntity.type = EventType.Withdraw;
  eventEntity.contract = event.address;
  eventEntity.account = event.params.sender;
  eventEntity.transactionHash = event.transaction.hash;
  eventEntity.timestamp = event.block.timestamp;

  const withdrawnEntity = new Withdrawn(id);
  withdrawnEntity.contract = event.address;
  withdrawnEntity.account = event.params.sender;
  withdrawnEntity.amount = event.params.assets;
  withdrawnEntity.timestamp = event.block.timestamp;

  withdrawnEntity.save();

  eventEntity.withdrawn = id;
  eventEntity.save();

  log.info("Handled sUSDai Withdraw event: {}", [id]);
}
