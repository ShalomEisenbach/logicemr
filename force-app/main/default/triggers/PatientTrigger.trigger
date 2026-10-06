trigger PatientTrigger on Patient__c(before insert, before update) {
  NameFormatterHandler.format(Trigger.new);
  AllergyReviewService.validatePatients(
    Trigger.new,
    Trigger.isUpdate ? Trigger.oldMap : null
  );
}
