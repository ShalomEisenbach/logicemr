public with sharing class DiagnosticReportService {
    @AuraEnabled
    public static void markReviewed(List<Id> reportIds) {
        if (reportIds == null || reportIds.isEmpty()) {
            return;
        }

        List<DiagnosticReport__c> reports = [
            SELECT Id
            FROM DiagnosticReport__c
            WHERE Id IN :reportIds
        ];
        if (reports.isEmpty()) {
            return;
        }

        Datetime reviewedAt = Datetime.now();
        Id reviewerId = UserInfo.getUserId();
        for (DiagnosticReport__c report : reports) {
            report.Reviewed__c = true;
            report.Reviewed_By__c = reviewerId;
            report.Reviewed_Date__c = reviewedAt;
        }
        update reports;
    }
}
