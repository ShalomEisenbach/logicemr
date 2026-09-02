trigger ImmunizationTrigger on Immunization__c(before insert, before update) {
    NameFormatterHandler.format(Trigger.new);
}
