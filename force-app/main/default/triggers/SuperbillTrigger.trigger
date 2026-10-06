trigger SuperbillTrigger on Superbill__c(before update, before delete) {
  if (Trigger.isDelete) {
    ClaimIntegrityService.enforceSuperbillDeletes(Trigger.old);
  } else {
    ClaimSnapshotService.enforceFrozenSnapshots(Trigger.new, Trigger.oldMap);
    ClaimIntegrityService.enforceSuperbillUpdates(Trigger.new, Trigger.oldMap);
  }
}
