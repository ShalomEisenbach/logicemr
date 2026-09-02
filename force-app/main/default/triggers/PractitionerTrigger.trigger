trigger PractitionerTrigger on Practitioner__c(before insert, before update) {
    NameFormatterHandler.format(Trigger.new);
}
