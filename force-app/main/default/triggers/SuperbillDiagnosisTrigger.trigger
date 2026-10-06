trigger SuperbillDiagnosisTrigger on Superbill_Diagnosis__c(
  before insert,
  before update,
  before delete
) {
  ClaimIntegrityService.enforceChildChanges(
    Trigger.isDelete ? Trigger.old : Trigger.new,
    Trigger.isUpdate ? Trigger.old : null
  );
}
