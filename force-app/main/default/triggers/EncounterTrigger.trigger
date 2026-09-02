trigger EncounterTrigger on Encounter__c(before insert, before update) {
    NameFormatterHandler.format(Trigger.new);
}
