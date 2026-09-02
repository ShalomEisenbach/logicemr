@IsTest
private class DiagnosticReportPanelControllerTest {
    @IsTest
    static void getReportsReturnsPatientRowsGroupedByReview() {
        Patient__c patient = insertPatient('MRN-DRP-1');
        Patient__c other = insertPatient('MRN-DRP-2');
        DiagnosticReport__c newestUnreviewed = insertReport(
            patient.Id,
            'CBC',
            '58410-2',
            'Laboratory',
            'Final',
            false,
            Datetime.newInstance(2026, 9, 2, 10, 0, 0)
        );
        DiagnosticReport__c reviewed = insertReport(
            patient.Id,
            'CXR',
            '30746-2',
            'Radiology',
            'Final',
            true,
            Datetime.newInstance(2026, 8, 1, 9, 0, 0)
        );
        insertReport(
            other.Id,
            'CMP',
            '24323-8',
            'Laboratory',
            'Preliminary',
            false,
            Datetime.newInstance(2026, 9, 1, 8, 0, 0)
        );

        Test.startTest();
        DiagnosticReportPanelController.ReportListView view = DiagnosticReportPanelController.getReports(
            patient.Id
        );
        DiagnosticReportPanelController.ReportListView blank = DiagnosticReportPanelController.getReports(
            null
        );
        Test.stopTest();

        System.assertEquals(1, view.unreviewedReports.size(), 'Only this patient\'s unreviewed report');
        System.assertEquals(
            newestUnreviewed.Id,
            view.unreviewedReports[0].Id,
            'Unreviewed report Id should match'
        );
        System.assertEquals('58410-2', view.unreviewedReports[0].Report_Code__c, 'Code should be queried');
        System.assertEquals(
            1,
            view.reviewedReports.size(),
            'Only this patient\'s reviewed report should be grouped separately'
        );
        System.assertEquals(reviewed.Id, view.reviewedReports[0].Id, 'Reviewed report Id should match');
        System.assertEquals(0, blank.unreviewedReports.size(), 'Null patient should return no unreviewed reports');
        System.assertEquals(0, blank.reviewedReports.size(), 'Null patient should return no reviewed reports');
    }

    @IsTest
    static void addReportPersistsCodingCategoryStatusAndConclusion() {
        Patient__c patient = insertPatient('MRN-DRP-3');
        Code_Reference__c codeRef = insertCode('LOINC', '4548-4', 'Hemoglobin A1c');
        Datetime effective = Datetime.newInstance(2026, 9, 2, 8, 15, 0);
        Datetime issued = Datetime.newInstance(2026, 9, 2, 10, 30, 0);

        Test.startTest();
        DiagnosticReport__c created = DiagnosticReportPanelController.addReport(
            patient.Id,
            codeRef.Code_System__c,
            codeRef.Code__c,
            codeRef.Display__c,
            codeRef.Id,
            'Laboratory',
            'Preliminary',
            effective,
            issued,
            'A1c 7.2%.'
        );
        Test.stopTest();

        DiagnosticReport__c stored = [
            SELECT
                Patient__c,
                Report_Ref__c,
                Report_Code_System__c,
                Report_Code__c,
                Report_Display__c,
                Category__c,
                Status__c,
                Effective_DateTime__c,
                Issued__c,
                Conclusion__c,
                Reviewed__c
            FROM DiagnosticReport__c
            WHERE Id = :created.Id
        ];
        System.assertEquals(patient.Id, stored.Patient__c, 'Report should belong to the patient');
        System.assertEquals(codeRef.Id, stored.Report_Ref__c, 'Lookup should point at the Code Reference');
        System.assertEquals(codeRef.Code_System__c, stored.Report_Code_System__c, 'Code system should persist');
        System.assertEquals(codeRef.Code__c, stored.Report_Code__c, 'Snapshot code should match the Code Reference');
        System.assertEquals(
            codeRef.Display__c,
            stored.Report_Display__c,
            'Snapshot display should match the Code Reference'
        );
        System.assertEquals('Laboratory', stored.Category__c, 'Category should persist');
        System.assertEquals('Preliminary', stored.Status__c, 'Status should persist');
        System.assertEquals(effective, stored.Effective_DateTime__c, 'Effective datetime should persist');
        System.assertEquals(issued, stored.Issued__c, 'Issued datetime should persist');
        System.assertEquals('A1c 7.2%.', stored.Conclusion__c, 'Conclusion should persist');
        System.assertEquals(false, stored.Reviewed__c, 'New reports should default to unreviewed');
    }

    @IsTest
    static void addReportDefaultsBlankStatusAndRejectsInvalidInput() {
        Patient__c patient = insertPatient('MRN-DRP-4');
        Boolean missingPatient = false;
        Boolean missingDisplay = false;
        Boolean badSystem = false;

        Test.startTest();
        DiagnosticReport__c created = DiagnosticReportPanelController.addReport(
            patient.Id,
            'LOINC',
            '4548-4',
            'Hemoglobin A1c',
            null,
            'Laboratory',
            '',
            null,
            null,
            null
        );
        try {
            DiagnosticReportPanelController.addReport(
                null,
                'LOINC',
                '4548-4',
                'Hemoglobin A1c',
                null,
                'Laboratory',
                'Final',
                null,
                null,
                null
            );
        } catch (AuraHandledException e) {
            missingPatient = true;
        }
        try {
            DiagnosticReportPanelController.addReport(
                patient.Id,
                'LOINC',
                '4548-4',
                '',
                null,
                'Laboratory',
                'Final',
                null,
                null,
                null
            );
        } catch (AuraHandledException e) {
            missingDisplay = true;
        }
        try {
            DiagnosticReportPanelController.addReport(
                patient.Id,
                'CPT',
                '93000',
                'Electrocardiogram, complete',
                null,
                'Laboratory',
                'Final',
                null,
                null,
                null
            );
        } catch (AuraHandledException e) {
            badSystem = true;
        }
        Test.stopTest();

        DiagnosticReport__c stored = [SELECT Status__c FROM DiagnosticReport__c WHERE Id = :created.Id];
        System.assertEquals('Final', stored.Status__c, 'Blank status should default to Final');
        System.assertEquals(true, missingPatient, 'Blank patient Id should be rejected');
        System.assertEquals(true, missingDisplay, 'Blank display should be rejected');
        System.assertEquals(true, badSystem, 'Non LOINC code system should be rejected');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM DiagnosticReport__c WHERE Patient__c = :patient.Id],
            'Rejected adds must not insert extra rows'
        );
    }

    @IsTest
    static void deleteReportsRemovesRowsAndIgnoresBlankIds() {
        Patient__c patient = insertPatient('MRN-DRP-5');
        DiagnosticReport__c first = insertReport(
            patient.Id,
            'CBC',
            '58410-2',
            'Laboratory',
            'Final',
            false,
            Datetime.newInstance(2026, 9, 2, 10, 0, 0)
        );
        DiagnosticReport__c second = insertReport(
            patient.Id,
            'Lipid panel',
            '57698-3',
            'Laboratory',
            'Preliminary',
            false,
            Datetime.newInstance(2026, 8, 15, 11, 0, 0)
        );

        Test.startTest();
        DiagnosticReportPanelController.deleteReports(null);
        DiagnosticReportPanelController.deleteReports(new List<Id>());
        DiagnosticReportPanelController.deleteReports(new List<Id>{ first.Id, second.Id });
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM DiagnosticReport__c WHERE Id IN :new List<Id>{ first.Id, second.Id }],
            'Both reports should be deleted'
        );
    }

    private static Patient__c insertPatient(String mrn) {
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'Reports');
        insert patient;
        return patient;
    }

    private static DiagnosticReport__c insertReport(
        Id patientId,
        String display,
        String code,
        String category,
        String status,
        Boolean reviewed,
        Datetime issued
    ) {
        DiagnosticReport__c report = new DiagnosticReport__c(
            Patient__c = patientId,
            Report_Display__c = display,
            Report_Code_System__c = 'LOINC',
            Report_Code__c = code,
            Category__c = category,
            Status__c = status,
            Reviewed__c = reviewed,
            Issued__c = issued
        );
        insert report;
        return report;
    }

    private static Code_Reference__c insertCode(String codeSystem, String code, String display) {
        Code_Reference__c row = new Code_Reference__c(
            Name = display.left(80),
            Code_System__c = codeSystem,
            Code__c = code,
            Display__c = display,
            Active__c = true
        );
        insert row;
        return row;
    }
}
