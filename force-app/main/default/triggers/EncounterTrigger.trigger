trigger EncounterTrigger on Encounter__c(
  before insert,
  before update,
  after insert,
  after update
) {
  if (Trigger.isBefore) {
    EncounterCompletionService.beforeSave(
      Trigger.new,
      Trigger.isUpdate ? Trigger.oldMap : null
    );
    NameFormatterHandler.format(Trigger.new);
  } else {
    EncounterCompletionService.afterSave(
      Trigger.new,
      Trigger.isUpdate ? Trigger.oldMap : null
    );
  }
}
