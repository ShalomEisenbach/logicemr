trigger ObservationTrigger on Observation__c(
  before insert,
  before update,
  after insert,
  after update,
  after delete
) {
  if (Trigger.isBefore) {
    ClinicalResultIntegrity.beforeObservations(
      Trigger.new,
      Trigger.isUpdate ? Trigger.oldMap : null
    );
    NameFormatterHandler.format(Trigger.new);
  } else if (Trigger.isDelete) {
    ClinicalResultIntegrity.afterDeletedObservations(Trigger.old);
  } else {
    ClinicalResultIntegrity.afterObservations(
      Trigger.new,
      Trigger.isUpdate ? Trigger.oldMap : null
    );
  }
}
