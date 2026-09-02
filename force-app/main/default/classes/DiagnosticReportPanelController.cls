public with sharing class DiagnosticReportPanelController {
    private static final Integer MAX_RESULTS = 200;
    private static final String STATUS_FINAL = 'Final';
    private static final Set<String> ALLOWED_CODE_SYSTEMS = new Set<String>{ 'LOINC' };

    public class ReportListView {
        @AuraEnabled
        public List<DiagnosticReport__c> unreviewedReports;
        @AuraEnabled
        public List<DiagnosticReport__c> reviewedReports;
    }

    @AuraEnabled(cacheable=true)
    public static ReportListView getReports(Id patientId) {
        ReportListView view = new ReportListView();
        view.unreviewedReports = new List<DiagnosticReport__c>();
        view.reviewedReports = new List<DiagnosticReport__c>();
        if (patientId == null) {
            return view;
        }

        for (DiagnosticReport__c report : queryReports(new Set<Id>{ patientId })) {
            if (report.Reviewed__c == true) {
                view.reviewedReports.add(report);
            } else {
                view.unreviewedReports.add(report);
            }
        }
        return view;
    }

    @AuraEnabled
    public static DiagnosticReport__c addReport(
        Id patientId,
        String codeSystem,
        String code,
        String display,
        Id codeReferenceId,
        String category,
        String status,
        Datetime effectiveDateTime,
        Datetime issuedDateTime,
        String conclusion
    ) {
        if (patientId == null) {
            throw new AuraHandledException('Patient Id is required.');
        }
        if (String.isBlank(display)) {
            throw new AuraHandledException('Report display is required.');
        }
        if (String.isBlank(codeSystem) || !ALLOWED_CODE_SYSTEMS.contains(codeSystem)) {
            throw new AuraHandledException('Code system must be LOINC.');
        }

        DiagnosticReport__c report = new DiagnosticReport__c(
            Patient__c = patientId,
            Report_Ref__c = codeReferenceId,
            Report_Code_System__c = codeSystem,
            Report_Code__c = code,
            Report_Display__c = display,
            Category__c = category,
            Status__c = String.isBlank(status) ? STATUS_FINAL : status,
            Effective_DateTime__c = effectiveDateTime,
            Issued__c = issuedDateTime,
            Conclusion__c = conclusion
        );
        insert report;
        return report;
    }

    @AuraEnabled
    public static void deleteReports(List<Id> reportIds) {
        if (reportIds == null || reportIds.isEmpty()) {
            return;
        }
        delete [SELECT Id FROM DiagnosticReport__c WHERE Id IN :reportIds];
    }

    private static List<DiagnosticReport__c> queryReports(Set<Id> patientIds) {
        return [
            SELECT
                Id,
                Report_Display__c,
                Report_Code__c,
                Report_Code_System__c,
                Category__c,
                Status__c,
                Effective_DateTime__c,
                Issued__c,
                Conclusion__c,
                Reviewed__c,
                Reviewed_Date__c
            FROM DiagnosticReport__c
            WHERE Patient__c IN :patientIds
            ORDER BY Issued__c DESC NULLS LAST, Effective_DateTime__c DESC NULLS LAST, Report_Display__c ASC NULLS LAST
            LIMIT :MAX_RESULTS
        ];
    }
}
