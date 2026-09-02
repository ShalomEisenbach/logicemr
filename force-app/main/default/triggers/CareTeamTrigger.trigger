trigger CareTeamTrigger on CareTeam__c(before insert, before update) {
    NameFormatterHandler.format(Trigger.new);
}
