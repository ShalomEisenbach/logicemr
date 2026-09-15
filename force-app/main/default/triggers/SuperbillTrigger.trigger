trigger SuperbillTrigger on Superbill__c (before update) {
    ClaimSnapshotService.enforceFrozenSnapshots(Trigger.new, Trigger.oldMap);
}
