trigger MedicationAdministrationTrigger on MedicationAdministration__c(before insert, before update) {
    NameFormatterHandler.format(Trigger.new);
}
