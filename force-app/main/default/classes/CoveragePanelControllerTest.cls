@IsTest
private class CoveragePanelControllerTest {
    @IsTest
    static void getCoveragesReturnsPatientRowsWithPayerAndDates() {
        Patient__c patient = insertPatient('MRN-COV-1');
        Patient__c other = insertPatient('MRN-COV-2');
        Payer__c aetna = insertPayer('Aetna');
        Payer__c medicaid = insertPayer('State Medicaid');
        Coverage__c primary = insertCoverage(
            patient.Id,
            aetna.Id,
            'M-100',
            'Gold PPO',
            'Primary',
            'Active',
            Date.newInstance(2026, 1, 1),
            Date.newInstance(2026, 12, 31)
        );
        insertCoverage(
            patient.Id,
            medicaid.Id,
            'M-200',
            'Medicaid',
            'Secondary',
            'Inactive',
            Date.newInstance(2025, 1, 1),
            Date.newInstance(2025, 12, 31)
        );
        insertCoverage(other.Id, aetna.Id, 'M-999', 'Other Plan', 'Primary', 'Active', null, null);

        Test.startTest();
        List<CoveragePanelController.CoverageRow> rows = CoveragePanelController.getCoverages(patient.Id);
        List<CoveragePanelController.CoverageRow> blank = CoveragePanelController.getCoverages(null);
        Test.stopTest();

        System.assertEquals(2, rows.size(), 'Should return both coverages for this patient');
        System.assertEquals(primary.Id, rows[0].coverage.Id, 'Primary active coverage should sort first');
        System.assertEquals(aetna.Id, rows[0].coverage.Payer__c, 'Payer lookup should be queried');
        System.assertEquals('Aetna', rows[0].coverage.Payer__r.Name, 'Payer name should be queried');
        System.assertEquals(
            'Gold PPO (Coverage) - Active',
            rows[0].coverage.Name,
            'Coverage Name should compose plan, patient, and status'
        );
        System.assertEquals('M-100', rows[0].coverage.Member_Id__c, 'Member Id should be queried');
        System.assertEquals('Gold PPO', rows[0].coverage.Plan_Name__c, 'Plan name should be queried');
        System.assertEquals(
            Date.newInstance(2026, 1, 1),
            rows[0].coverage.Effective_Start__c,
            'Start date should be queried'
        );
        System.assertEquals(0, rows[0].idCardFiles.size(), 'Coverage without files should return an empty ID card list');
        System.assertEquals(null, rows[0].latestEligibilityStatus, 'Coverage without checks should have no eligibility status');
        System.assertEquals(0, blank.size(), 'Null patient should return no coverages');
    }

    @IsTest
    static void getCoveragesReturnsLatestEligibilityStatusPerCoverage() {
        Patient__c patient = insertPatient('MRN-COV-ELIG');
        Payer__c aetna = insertPayer('Aetna');
        Coverage__c primary = insertCoverage(
            patient.Id,
            aetna.Id,
            'M-ELIG',
            'Gold PPO',
            'Primary',
            'Active',
            Date.newInstance(2026, 1, 1),
            Date.newInstance(2026, 12, 31)
        );
        Coverage__c secondary = insertCoverage(
            patient.Id,
            aetna.Id,
            'M-ELIG-2',
            'Dental',
            'Secondary',
            'Active',
            Date.newInstance(2026, 1, 1),
            null
        );
        insert new List<Eligibility_Check__c>{
            new Eligibility_Check__c(
                Patient__c = patient.Id,
                Coverage__c = primary.Id,
                Status__c = 'Inactive',
                Checked_Date__c = Datetime.now().addDays(-2)
            ),
            new Eligibility_Check__c(
                Patient__c = patient.Id,
                Coverage__c = primary.Id,
                Status__c = 'Active',
                Checked_Date__c = Datetime.now().addHours(-1)
            )
        };

        Test.startTest();
        List<CoveragePanelController.CoverageRow> rows = CoveragePanelController.getCoverages(patient.Id);
        Test.stopTest();

        CoveragePanelController.CoverageRow primaryRow;
        CoveragePanelController.CoverageRow secondaryRow;
        for (CoveragePanelController.CoverageRow row : rows) {
            if (row.coverage.Id == primary.Id) {
                primaryRow = row;
            } else if (row.coverage.Id == secondary.Id) {
                secondaryRow = row;
            }
        }
        System.assertEquals('Active', primaryRow.latestEligibilityStatus, 'Newest check status should be returned');
        System.assertNotEquals(null, primaryRow.latestEligibilityChecked, 'Newest checked date should be returned');
        System.assertEquals(null, secondaryRow.latestEligibilityStatus, 'Coverage without checks should have no status');
    }

    @IsTest
    static void saveCoverageInsertsThenUpdatesWithoutChangingPatient() {
        Patient__c patient = insertPatient('MRN-COV-3');
        Patient__c other = insertPatient('MRN-COV-4');
        Payer__c aetna = insertPayer('Aetna');
        Payer__c cigna = insertPayer('Cigna');

        Test.startTest();
        Coverage__c created = CoveragePanelController.saveCoverage(
            null,
            patient.Id,
            aetna.Id,
            'M-300',
            'GRP-1',
            'Silver',
            'Medical',
            'Self',
            'Ada Lovelace',
            null,
            Date.newInstance(2026, 3, 1),
            Date.newInstance(2026, 9, 1),
            'Primary'
        );
        System.assertEquals('Active', created.Status__c, 'New coverage should default to Active');
        Coverage__c updated = CoveragePanelController.saveCoverage(
            created.Id,
            other.Id,
            cigna.Id,
            'M-301',
            'GRP-2',
            'Bronze',
            'Dental',
            'Spouse',
            'John Lovelace',
            'Draft',
            Date.newInstance(2026, 4, 1),
            Date.newInstance(2026, 10, 1),
            'Secondary'
        );
        CoveragePanelController.saveCoverage(
            created.Id,
            patient.Id,
            cigna.Id,
            'M-301',
            'GRP-2',
            'Bronze',
            'Dental',
            'Spouse',
            'John Lovelace',
            '',
            Date.newInstance(2026, 4, 1),
            Date.newInstance(2026, 10, 1),
            'Secondary'
        );
        Test.stopTest();

        Coverage__c stored = [
            SELECT
                Patient__c,
                Payer__c,
                Member_Id__c,
                Group_Number__c,
                Plan_Name__c,
                Type__c,
                Relationship_to_Subscriber__c,
                Subscriber_Name__c,
                Status__c,
                Effective_Start__c,
                Effective_End__c,
                Priority__c
            FROM Coverage__c
            WHERE Id = :created.Id
        ];
        System.assertEquals(created.Id, updated.Id, 'Update should return the same coverage');
        System.assertEquals(patient.Id, stored.Patient__c, 'Update must not reparent the coverage');
        System.assertEquals(cigna.Id, stored.Payer__c, 'Payer should update');
        System.assertEquals('M-301', stored.Member_Id__c, 'Member Id should update');
        System.assertEquals('GRP-2', stored.Group_Number__c, 'Group number should update');
        System.assertEquals('Bronze', stored.Plan_Name__c, 'Plan name should update');
        System.assertEquals('Dental', stored.Type__c, 'Type should update');
        System.assertEquals('Spouse', stored.Relationship_to_Subscriber__c, 'Relationship should update');
        System.assertEquals('John Lovelace', stored.Subscriber_Name__c, 'Subscriber should update');
        System.assertEquals('Draft', stored.Status__c, 'Status should update');
        System.assertEquals(Date.newInstance(2026, 4, 1), stored.Effective_Start__c, 'Start should update');
        System.assertEquals('Secondary', stored.Priority__c, 'Priority should update');
    }

    @IsTest
    static void saveCoverageRejectsInvalidInput() {
        Patient__c patient = insertPatient('MRN-COV-5');
        Payer__c payer = insertPayer('Aetna');
        Boolean missingPatient = false;
        Boolean missingPayer = false;
        Boolean badDates = false;
        Boolean badType = false;
        Boolean badStatus = false;
        Boolean badRelationship = false;
        Boolean badPriority = false;
        Boolean missingRow = false;

        Test.startTest();
        try {
            CoveragePanelController.saveCoverage(
                null,
                null,
                payer.Id,
                'M-1',
                null,
                null,
                'Medical',
                null,
                null,
                'Active',
                null,
                null,
                'Primary'
            );
        } catch (AuraHandledException e) {
            missingPatient = true;
        }
        try {
            CoveragePanelController.saveCoverage(
                null,
                patient.Id,
                null,
                'M-1',
                null,
                null,
                'Medical',
                null,
                null,
                'Active',
                null,
                null,
                'Primary'
            );
        } catch (AuraHandledException e) {
            missingPayer = true;
        }
        try {
            CoveragePanelController.saveCoverage(
                null,
                patient.Id,
                payer.Id,
                'M-1',
                null,
                null,
                'Medical',
                null,
                null,
                'Active',
                Date.newInstance(2026, 6, 1),
                Date.newInstance(2026, 1, 1),
                'Primary'
            );
        } catch (AuraHandledException e) {
            badDates = true;
        }
        try {
            CoveragePanelController.saveCoverage(
                null,
                patient.Id,
                payer.Id,
                'M-1',
                null,
                null,
                'Life',
                null,
                null,
                'Active',
                null,
                null,
                'Primary'
            );
        } catch (AuraHandledException e) {
            badType = true;
        }
        try {
            CoveragePanelController.saveCoverage(
                null,
                patient.Id,
                payer.Id,
                'M-1',
                null,
                null,
                'Medical',
                null,
                null,
                'Unknown',
                null,
                null,
                'Primary'
            );
        } catch (AuraHandledException e) {
            badStatus = true;
        }
        try {
            CoveragePanelController.saveCoverage(
                null,
                patient.Id,
                payer.Id,
                'M-1',
                null,
                null,
                'Medical',
                'Guardian',
                null,
                'Active',
                null,
                null,
                'Primary'
            );
        } catch (AuraHandledException e) {
            badRelationship = true;
        }
        try {
            CoveragePanelController.saveCoverage(
                null,
                patient.Id,
                payer.Id,
                'M-1',
                null,
                null,
                'Medical',
                'Self',
                null,
                'Active',
                null,
                null,
                'Quaternary'
            );
        } catch (AuraHandledException e) {
            badPriority = true;
        }
        try {
            CoveragePanelController.saveCoverage(
                patient.Id,
                patient.Id,
                payer.Id,
                'M-1',
                null,
                null,
                'Medical',
                null,
                null,
                'Active',
                null,
                null,
                'Primary'
            );
        } catch (AuraHandledException e) {
            missingRow = true;
        }
        Test.stopTest();

        System.assertEquals(true, missingPatient, 'Blank patient Id should be rejected');
        System.assertEquals(true, missingPayer, 'Blank payer should be rejected');
        System.assertEquals(true, badDates, 'End before start should be rejected');
        System.assertEquals(true, badType, 'Invalid type should be rejected');
        System.assertEquals(true, badStatus, 'Invalid status should be rejected');
        System.assertEquals(true, badRelationship, 'Invalid relationship should be rejected');
        System.assertEquals(true, badPriority, 'Invalid priority should be rejected');
        System.assertEquals(true, missingRow, 'Unknown coverage Id should be rejected');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Coverage__c WHERE Patient__c = :patient.Id],
            'Rejected saves must not insert rows'
        );
    }

    @IsTest
    static void inactivateCoveragesUpdatesNonInactiveRowsInOneCall() {
        Patient__c patient = insertPatient('MRN-COV-6');
        Payer__c payer = insertPayer('Aetna');
        Coverage__c first = insertCoverage(patient.Id, payer.Id, 'M-1', 'Plan A', 'Primary', 'Active', null, null);
        Coverage__c second = insertCoverage(patient.Id, payer.Id, 'M-2', 'Plan B', 'Secondary', 'Draft', null, null);
        Coverage__c alreadyInactive = insertCoverage(
            patient.Id,
            payer.Id,
            'M-3',
            'Plan C',
            'Tertiary',
            'Inactive',
            null,
            null
        );

        Test.startTest();
        CoveragePanelController.inactivateCoverages(null);
        CoveragePanelController.inactivateCoverages(new List<Id>());
        CoveragePanelController.inactivateCoverages(new List<Id>{ first.Id, second.Id, alreadyInactive.Id });
        Test.stopTest();

        Map<Id, Coverage__c> stored = new Map<Id, Coverage__c>(
            [
                SELECT Status__c
                FROM Coverage__c
                WHERE Id IN :new List<Id>{ first.Id, second.Id, alreadyInactive.Id }
            ]
        );
        System.assertEquals('Inactive', stored.get(first.Id).Status__c, 'Active row should inactivate');
        System.assertEquals('Inactive', stored.get(second.Id).Status__c, 'Draft row should inactivate');
        System.assertEquals('Inactive', stored.get(alreadyInactive.Id).Status__c, 'Inactive row should stay Inactive');
    }

    @IsTest
    static void idCardFileLabelReplaceAndDelete() {
        Patient__c patient = insertPatient('MRN-COV-7');
        Payer__c payer = insertPayer('Aetna');
        Coverage__c coverage = insertCoverage(patient.Id, payer.Id, 'M-7', 'Gold', 'Primary', 'Active', null, null);
        Id firstFront = insertLinkedFile(coverage.Id, 'front-old.jpg');
        Id secondFront = insertLinkedFile(coverage.Id, 'front-new.jpg');
        Id backId = insertLinkedFile(coverage.Id, 'back.jpg');

        Test.startTest();
        CoveragePanelController.labelIdCardFile(coverage.Id, firstFront, 'Front');
        CoveragePanelController.labelIdCardFile(coverage.Id, secondFront, 'Front');
        CoveragePanelController.labelIdCardFile(coverage.Id, backId, 'Back');
        List<CoveragePanelController.CoverageRow> labeled = CoveragePanelController.getCoverages(patient.Id);
        CoveragePanelController.deleteIdCardFile(coverage.Id, backId);
        List<CoveragePanelController.CoverageRow> afterDelete = CoveragePanelController.getCoverages(patient.Id);
        Boolean missingIds = false;
        Boolean badSide = false;
        Boolean missingFile = false;
        try {
            CoveragePanelController.labelIdCardFile(null, secondFront, 'Front');
        } catch (AuraHandledException e) {
            missingIds = true;
        }
        try {
            CoveragePanelController.labelIdCardFile(coverage.Id, secondFront, 'Side');
        } catch (AuraHandledException e) {
            badSide = true;
        }
        try {
            CoveragePanelController.deleteIdCardFile(coverage.Id, firstFront);
        } catch (AuraHandledException e) {
            missingFile = true;
        }
        Test.stopTest();

        System.assertEquals(1, labeled.size(), 'Should return the patient coverage');
        System.assertEquals(2, labeled[0].idCardFiles.size(), 'Replacing front should leave one front and one back');
        Set<String> sides = new Set<String>();
        Set<Id> labeledIds = new Set<Id>();
        for (CoveragePanelController.IdCardFile file : labeled[0].idCardFiles) {
            sides.add(file.side);
            labeledIds.add(file.contentDocumentId);
            System.assertEquals(true, file.isImage, 'jpg ID card files should be marked as images');
        }
        System.assertEquals(true, sides.contains('Front'), 'Front file should be labeled');
        System.assertEquals(true, sides.contains('Back'), 'Back file should be labeled');
        System.assertEquals(true, labeledIds.contains(secondFront), 'Latest front upload should remain');
        System.assertEquals(false, labeledIds.contains(firstFront), 'Replaced front file should be removed');
        System.assertEquals(1, afterDelete[0].idCardFiles.size(), 'Delete should remove the back file');
        System.assertEquals(
            'Front',
            afterDelete[0].idCardFiles[0].side,
            'Remaining file after delete should be the front'
        );
        System.assertEquals(true, missingIds, 'Blank coverage Id should be rejected');
        System.assertEquals(true, badSide, 'Invalid side should be rejected');
        System.assertEquals(true, missingFile, 'Already replaced file should not delete');
    }

    private static Patient__c insertPatient(String mrn) {
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'Coverage');
        insert patient;
        return patient;
    }

    private static Payer__c insertPayer(String payerName) {
        Payer__c payer = new Payer__c(Name = payerName, Type__c = 'Commercial', Active__c = true);
        insert payer;
        return payer;
    }

    private static Coverage__c insertCoverage(
        Id patientId,
        Id payerId,
        String memberId,
        String planName,
        String priority,
        String status,
        Date startDate,
        Date endDate
    ) {
        Coverage__c coverage = new Coverage__c(
            Patient__c = patientId,
            Payer__c = payerId,
            Member_Id__c = memberId,
            Plan_Name__c = planName,
            Type__c = 'Medical',
            Priority__c = priority,
            Status__c = status,
            Effective_Start__c = startDate,
            Effective_End__c = endDate
        );
        insert coverage;
        return coverage;
    }

    private static Id insertLinkedFile(Id coverageId, String fileName) {
        ContentVersion version = new ContentVersion(
            Title = fileName,
            PathOnClient = fileName,
            VersionData = Blob.valueOf('id-card'),
            FirstPublishLocationId = coverageId
        );
        insert version;
        return [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ]
        .ContentDocumentId;
    }
}
