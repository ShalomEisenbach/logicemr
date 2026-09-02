trigger ClinicalNoteTrigger on ClinicalNote__c(before insert, before update) {
    NameFormatterHandler.format(Trigger.new);
}
