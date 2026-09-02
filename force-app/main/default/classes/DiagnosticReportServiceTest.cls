@IsTest
private class DiagnosticReportServiceTest {
    @IsTest
    static void markReviewedSetsReviewFieldsInBulk() {
        Patient__c patient = insertPatient('MRN-DR-REV-1');
        List<DiagnosticReport__c> reports = new List<DiagnosticReport__c>{
            new DiagnosticReport__c(
                Patient__c = patient.Id,
                Report_Display__c = 'CBC',
                Status__c = 'Preliminary'
            ),
            new DiagnosticReport__c(
                Patient__c = patient.Id,
                Report_Display__c = 'CMP',
                Status__c = 'Final'
            )
        };
        insert reports;

        reports = [
            SELECT Reviewed__c, Reviewed_By__c, Reviewed_Date__c
            FROM DiagnosticReport__c
            WHERE Id IN :reports
        ];
        System.assertEquals(false, reports[0].Reviewed__c, 'New reports should default to unreviewed');
        System.assertEquals(null, reports[0].Reviewed_By__c, 'Unreviewed reports should have no reviewer');
        System.assertEquals(null, reports[0].Reviewed_Date__c, 'Unreviewed reports should have no review date');

        Datetime beforeReview = Datetime.now().addSeconds(-1);
        Test.startTest();
        DiagnosticReportService.markReviewed(new List<Id>{ reports[0].Id, reports[1].Id });
        Test.stopTest();
        Datetime afterReview = Datetime.now().addSeconds(1);

        List<DiagnosticReport__c> reviewed = [
            SELECT Reviewed__c, Reviewed_By__c, Reviewed_Date__c
            FROM DiagnosticReport__c
            WHERE Id IN :reports
        ];
        System.assertEquals(2, reviewed.size(), 'Both reports should be updated in one call');
        for (DiagnosticReport__c report : reviewed) {
            System.assertEquals(true, report.Reviewed__c, 'Reviewed should be set');
            System.assertEquals(
                UserInfo.getUserId(),
                report.Reviewed_By__c,
                'Reviewed By should be the current user'
            );
            System.assertNotEquals(null, report.Reviewed_Date__c, 'Reviewed Date should be stamped');
            System.assert(
                report.Reviewed_Date__c >= beforeReview && report.Reviewed_Date__c <= afterReview,
                'Reviewed Date should be now'
            );
        }
    }

    @IsTest
    static void markReviewedIgnoresNullAndEmptySets() {
        Patient__c patient = insertPatient('MRN-DR-REV-2');
        DiagnosticReport__c report = new DiagnosticReport__c(
            Patient__c = patient.Id,
            Report_Display__c = 'TSH',
            Status__c = 'Final'
        );
        insert report;

        Test.startTest();
        DiagnosticReportService.markReviewed(null);
        DiagnosticReportService.markReviewed(new List<Id>());
        DiagnosticReportService.markReviewed(new List<Id>{ null });
        Test.stopTest();

        DiagnosticReport__c stored = [
            SELECT Reviewed__c, Reviewed_By__c, Reviewed_Date__c
            FROM DiagnosticReport__c
            WHERE Id = :report.Id
        ];
        System.assertEquals(false, stored.Reviewed__c, 'Null or empty Id sets should not mark a report reviewed');
        System.assertEquals(null, stored.Reviewed_By__c, 'Null or empty Id sets should not set a reviewer');
        System.assertEquals(null, stored.Reviewed_Date__c, 'Null or empty Id sets should not set a review date');
    }

    private static Patient__c insertPatient(String mrn) {
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'Reports');
        insert patient;
        return patient;
    }
}
