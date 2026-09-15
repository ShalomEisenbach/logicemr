trigger ChargeLineTrigger on Charge_Line__c(before insert, before update) {
    FeeScheduleService.enforceChargeIntegrity(Trigger.new);
}
