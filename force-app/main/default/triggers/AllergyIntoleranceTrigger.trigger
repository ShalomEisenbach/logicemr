trigger AllergyIntoleranceTrigger on AllergyIntolerance__c(before insert, before update) {
    NameFormatterHandler.format(Trigger.new);
}
