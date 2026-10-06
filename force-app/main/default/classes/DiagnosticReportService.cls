public with sharing class DiagnosticReportService {
  @AuraEnabled
  public static void markReviewed(List<Id> reportIds) {
    if (reportIds == null || reportIds.isEmpty()) {
      return;
    }
    if (
      !DiagnosticReport__c.SObjectType.getDescribe().isUpdateable() ||
      !DiagnosticReport__c.Reviewed__c.getDescribe().isUpdateable()
    ) {
      String message = 'Reviewing results requires permission to update diagnostic reports and their review status.';
      AuraHandledException error = new AuraHandledException(message);
      error.setMessage(message);
      throw error;
    }

    List<DiagnosticReport__c> reports = [
      SELECT Id
      FROM DiagnosticReport__c
      WHERE Id IN :reportIds
    ];
    if (reports.isEmpty()) {
      return;
    }

    for (DiagnosticReport__c report : reports) {
      report.Reviewed__c = true;
    }
    // The before trigger stamps review provenance after the user-mode access check.
    update as user reports;
  }
}
