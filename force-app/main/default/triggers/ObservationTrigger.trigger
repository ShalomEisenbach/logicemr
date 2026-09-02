trigger ObservationTrigger on Observation__c(before insert, before update) {
    NameFormatterHandler.format(Trigger.new);
}
