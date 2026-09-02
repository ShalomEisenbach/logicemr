@IsTest
private class CatalogLinkBackfillBatchTest {
    @IsTest
    static void linksMatchingCodesAndLogsUnmatched() {
        Patient__c patient = insertPatient('MRN-CL-1');
        Code_Reference__c diabetes = insertCode('ICD-10', 'E11.9', 'Type 2 diabetes mellitus');
        Code_Reference__c alreadyLinked = insertCode('ICD-10', 'I10', 'Essential hypertension');

        Condition__c unmatched = insertCondition(patient.Id, 'ICD-10', 'R07.9', 'Chest tightness', null);
        Condition__c toLink = insertCondition(patient.Id, 'ICD-10', 'E11.9', 'Type 2 diabetes', null);
        Condition__c linked = insertCondition(patient.Id, 'ICD-10', 'I10', 'Hypertension', alreadyLinked.Id);

        Test.startTest();
        Database.executeBatch(
            new CatalogLinkBackfillBatch(
                'Condition__c',
                'Diagnosis_Code_System__c',
                'Diagnosis_Code__c',
                'Diagnosis_Ref__c'
            ),
            50
        );
        Test.stopTest();

        Map<Id, Condition__c> stored = new Map<Id, Condition__c>(
            [
                SELECT Diagnosis_Ref__c, Diagnosis_Code__c
                FROM Condition__c
                WHERE Id IN :new List<Id>{ unmatched.Id, toLink.Id, linked.Id }
            ]
        );
        System.assertEquals(
            diabetes.Id,
            stored.get(toLink.Id).Diagnosis_Ref__c,
            'Snapshot code E11.9 should link to the matching Code Reference'
        );
        System.assertEquals(
            null,
            stored.get(unmatched.Id).Diagnosis_Ref__c,
            'Unknown snapshot codes should stay unlinked'
        );
        System.assertEquals(
            alreadyLinked.Id,
            stored.get(linked.Id).Diagnosis_Ref__c,
            'Rows that already have a lookup should be left alone'
        );
        System.assertNotEquals(null, CatalogLinkBackfillBatch.lastSummary, 'finish should record a summary');
        System.assert(
            CatalogLinkBackfillBatch.lastSummary.contains('updated=1'),
            'Only the unmatched-but-cataloged row should update: ' + CatalogLinkBackfillBatch.lastSummary
        );
        System.assert(
            CatalogLinkBackfillBatch.lastSummary.contains('ICD-10::R07.9'),
            'Unmatched codes should be logged in the summary: ' + CatalogLinkBackfillBatch.lastSummary
        );
    }

    @IsTest
    static void logsRowsThatHaveCodeButNoSystem() {
        Patient__c patient = insertPatient('MRN-CL-2');
        Condition__c noSystem = insertCondition(patient.Id, null, 'E11.9', 'Diabetes', null);
        CatalogLinkBackfillBatch batch = new CatalogLinkBackfillBatch(
            'Condition__c',
            'Diagnosis_Code_System__c',
            'Diagnosis_Code__c',
            'Diagnosis_Ref__c'
        );
        List<SObject> scope = [
            SELECT Id, Diagnosis_Code_System__c, Diagnosis_Code__c, Diagnosis_Ref__c
            FROM Condition__c
            WHERE Id = :noSystem.Id
        ];

        Test.startTest();
        batch.execute(null, scope);
        Test.stopTest();

        System.assertEquals(0, batch.updatedCount, 'A code without a system cannot match the catalog');
        System.assertEquals(1, batch.unmatchedCount, 'Missing system should count as unmatched');
        System.assertEquals(
            null,
            [SELECT Diagnosis_Ref__c FROM Condition__c WHERE Id = :noSystem.Id].Diagnosis_Ref__c,
            'Lookup should stay null when Code System is blank'
        );
    }

    @IsTest
    static void executeIsSafeForEmptyScope() {
        CatalogLinkBackfillBatch batch = new CatalogLinkBackfillBatch(
            'Condition__c',
            'Diagnosis_Code_System__c',
            'Diagnosis_Code__c',
            'Diagnosis_Ref__c'
        );

        Test.startTest();
        batch.execute(null, null);
        batch.execute(null, new List<SObject>());
        Test.stopTest();

        System.assertEquals(0, batch.updatedCount, 'Empty scope should update no rows');
        System.assertEquals(0, batch.unmatchedCount, 'Empty scope should log no unmatched codes');
    }

    @IsTest
    static void startRejectsUnknownObject() {
        Boolean threw = false;

        try {
            Test.startTest();
            Database.executeBatch(
                new CatalogLinkBackfillBatch(
                    'NotARealObject__c',
                    'Diagnosis_Code_System__c',
                    'Diagnosis_Code__c',
                    'Diagnosis_Ref__c'
                ),
                1
            );
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
            System.assert(
                e.getMessage().contains('not available'),
                'Unknown object should fail start: ' + e.getMessage()
            );
        }

        System.assertEquals(true, threw, 'Batch start should reject an unresolved object API name');
    }

    @IsTest
    static void startRejectsUnknownField() {
        Boolean threw = false;

        try {
            Test.startTest();
            Database.executeBatch(
                new CatalogLinkBackfillBatch(
                    'Condition__c',
                    'Not_A_Field__c',
                    'Diagnosis_Code__c',
                    'Diagnosis_Ref__c'
                ),
                1
            );
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
            System.assert(
                e.getMessage().contains('fields are not available'),
                'Unknown field should fail start: ' + e.getMessage()
            );
        }

        System.assertEquals(true, threw, 'Batch start should reject an unresolved snapshot field');
    }

    private static Patient__c insertPatient(String mrn) {
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'Catalog');
        insert patient;
        return patient;
    }

    private static Condition__c insertCondition(
        Id patientId,
        String codeSystem,
        String code,
        String display,
        Id diagnosisRefId
    ) {
        Condition__c condition = new Condition__c(
            Patient__c = patientId,
            Diagnosis_Code_System__c = codeSystem,
            Diagnosis_Code__c = code,
            Diagnosis_Display__c = display,
            Diagnosis_Ref__c = diagnosisRefId,
            Category__c = 'Problem List Item',
            Clinical_Status__c = 'Active'
        );
        insert condition;
        return condition;
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
