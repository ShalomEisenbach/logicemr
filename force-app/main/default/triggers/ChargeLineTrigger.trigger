trigger ChargeLineTrigger on Charge_Line__c(
  before insert,
  before update,
  before delete
) {
  ClaimIntegrityService.enforceChildChanges(
    Trigger.isDelete ? Trigger.old : Trigger.new,
    Trigger.isUpdate ? Trigger.old : null
  );
  if (!Trigger.isDelete)
    FeeScheduleService.enforceChargeIntegrity(Trigger.new);
}
