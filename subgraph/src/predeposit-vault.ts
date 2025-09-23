import { Deposited as DepositedEvent } from "../generated/PredepositVault/PredepositVault";

import { Predeposit } from "../generated/schema";

export function handlePredepositVaultDeposit(event: DepositedEvent): void {
  const id = event.transaction.hash.concatI32(event.logIndex.toI32());

  const vaultPredepositEntity = new Predeposit(id);

  vaultPredepositEntity.depositType = event.params.depositType;
  vaultPredepositEntity.depositToken = event.params.depositToken;
  vaultPredepositEntity.depositor = event.params.depositor;
  vaultPredepositEntity.recipient = event.params.recipient;
  vaultPredepositEntity.amount = event.params.amount;
  vaultPredepositEntity.dstEid = event.params.dstEid;
  vaultPredepositEntity.timestamp = event.block.timestamp;
  vaultPredepositEntity.transactionHash = event.transaction.hash;

  vaultPredepositEntity.save();
}
