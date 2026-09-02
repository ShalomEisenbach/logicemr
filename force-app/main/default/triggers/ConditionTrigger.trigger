trigger ConditionTrigger on Condition__c(before insert, before update) {
    NameFormatterHandler.format(Trigger.new);
}
