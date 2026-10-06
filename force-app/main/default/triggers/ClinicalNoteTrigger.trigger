trigger ClinicalNoteTrigger on ClinicalNote__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isDelete) {
    ClinicalNoteIntegrity.beforeDelete(Trigger.old);
  } else {
    ClinicalNoteIntegrity.beforeSave(
      Trigger.new,
      Trigger.isUpdate ? Trigger.oldMap : null
    );
    NameFormatterHandler.format(Trigger.new);
  }
}
