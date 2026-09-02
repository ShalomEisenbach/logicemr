trigger CareTeamMemberTrigger on CareTeamMember__c(
    before insert,
    before update,
    after insert,
    after update,
    after delete,
    after undelete
) {
    if (Trigger.isBefore) {
        NameFormatterHandler.format(Trigger.new);
    } else {
        CareTeamMemberSharingHandler.handle(Trigger.new, Trigger.old);
    }
}
