trigger AllergyIntoleranceTrigger on AllergyIntolerance__c(
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
    AllergyReviewService.invalidate(
      Trigger.isDelete ? null : Trigger.new,
      Trigger.isInsert || Trigger.isUndelete ? null : Trigger.old
    );
  }
}
