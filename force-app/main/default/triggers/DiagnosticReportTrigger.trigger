trigger DiagnosticReportTrigger on DiagnosticReport__c(
  before insert,
  before update,
  after insert,
  after update
) {
  if (Trigger.isBefore) {
    ClinicalResultIntegrity.beforeReports(
      Trigger.new,
      Trigger.isUpdate ? Trigger.oldMap : null
    );
    NameFormatterHandler.format(Trigger.new);
  } else {
    ClinicalResultIntegrity.afterReports(Trigger.new);
  }
}
