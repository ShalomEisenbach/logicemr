trigger PatientTrigger on Patient__c(before insert, before update) {
    NameFormatterHandler.format(Trigger.new);
}
