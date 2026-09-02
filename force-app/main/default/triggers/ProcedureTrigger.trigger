trigger ProcedureTrigger on Procedure__c(before insert, before update) {
    NameFormatterHandler.format(Trigger.new);
}
