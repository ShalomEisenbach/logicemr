trigger CoverageTrigger on Coverage__c(before insert, before update) {
    NameFormatterHandler.format(Trigger.new);
}
