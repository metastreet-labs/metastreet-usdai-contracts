import {PreDeposit} from '../generated/schema'
import { Deposited as DepositedEvent } from "../generated/DepositVault/DepositVault";


export function handlePreDepositVaultDeposit(event: DepositedEvent): void {
  const id = event.transaction.hash.concatI32(event.logIndex.toI32())

  const vaultDepositEntity = new PreDeposit(id);

  vaultDepositEntity.depositType = event.params.depositType;
  vaultDepositEntity.depositToken = event.params.depositToken;
  vaultDepositEntity.depositor = event.params.depositor;
  vaultDepositEntity.recipient = event.params.recipient;
  vaultDepositEntity.amount = event.params.amount;
  vaultDepositEntity.dstEid = event.params.dstEid;
  vaultDepositEntity.timestamp = event.block.timestamp;
  vaultDepositEntity.transactionHash = event.transaction.hash;

  vaultDepositEntity.save();
}
