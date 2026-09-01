trigger CareTeamMemberTrigger on CareTeamMember__c(
    after insert,
    after update,
    after delete,
    after undelete
) {
    CareTeamMemberSharingHandler.handle(Trigger.new, Trigger.old);
}
