trigger ServiceRequestTrigger on ServiceRequest__c(before insert, before update) {
    NameFormatterHandler.format(Trigger.new);
}
