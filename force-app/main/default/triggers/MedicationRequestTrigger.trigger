trigger MedicationRequestTrigger on MedicationRequest__c(before insert, before update) {
    NameFormatterHandler.format(Trigger.new);
}
