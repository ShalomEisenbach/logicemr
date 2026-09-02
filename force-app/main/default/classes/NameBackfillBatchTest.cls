@IsTest
private class NameBackfillBatchTest {
    @IsTest
    static void recomposesStalePatientAndConditionNames() {
        Patient__c patient = new Patient__c(
            MRN__c = 'MRN-NB-1',
            First_Name__c = 'Jane',
            Last_Name__c = 'Smith',
            Date_of_Birth__c = Date.newInstance(1980, 5, 12)
        );
        insert patient;
        Condition__c condition = new Condition__c(
            Patient__c = patient.Id,
            Diagnosis_Display__c = 'Chest tightness',
            Diagnosis_Code__c = 'R07.9',
            Category__c = 'Problem List Item',
            Clinical_Status__c = 'Active'
        );
        insert condition;

        Patient__c stalePatient = [
            SELECT Id, First_Name__c, Last_Name__c, Date_of_Birth__c, Name
            FROM Patient__c
            WHERE Id = :patient.Id
        ];
        stalePatient.Name = 'STALE-PATIENT';
        Condition__c staleCondition = [
            SELECT Id, Diagnosis_Display__c, Diagnosis_Code__c, Name
            FROM Condition__c
            WHERE Id = :condition.Id
        ];
        staleCondition.Name = 'STALE-CONDITION';

        Test.startTest();
        new NameBackfillBatch('Patient__c').execute(null, new List<SObject>{ stalePatient });
        Database.executeBatch(new NameBackfillBatch('Condition__c'), 50);
        Test.stopTest();

        Patient__c refreshedPatient = [SELECT Name FROM Patient__c WHERE Id = :patient.Id];
        Condition__c refreshedCondition = [SELECT Name FROM Condition__c WHERE Id = :condition.Id];
        System.assertEquals(
            'Smith, Jane (1980-05-12)',
            refreshedPatient.Name,
            'Patient Name should be recomposed from local tokens'
        );
        System.assertEquals(
            'Chest tightness R07.9',
            refreshedCondition.Name,
            'Condition Name should be recomposed by the batch query'
        );
        System.assertNotEquals(null, NameBackfillBatch.lastSummary, 'finish should record a summary');
        System.assert(
            NameBackfillBatch.lastSummary.contains('Condition__c'),
            'Summary should name the object that was batched: ' + NameBackfillBatch.lastSummary
        );
        System.assert(
            NameBackfillBatch.lastSummary.contains('updated='),
            'Summary should include an updated count: ' + NameBackfillBatch.lastSummary
        );
    }

    @IsTest
    static void executeIsSafeForEmptyScope() {
        NameBackfillBatch batch = new NameBackfillBatch('Patient__c');

        Test.startTest();
        batch.execute(null, null);
        batch.execute(null, new List<SObject>());
        Test.stopTest();

        System.assertEquals(0, batch.updatedCount, 'Empty scope should update no rows');
    }

    @IsTest
    static void startRejectsUnknownObject() {
        Boolean threw = false;

        try {
            Test.startTest();
            Database.executeBatch(new NameBackfillBatch('NotARealObject__c'), 1);
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
    static void startRejectsBlankObject() {
        Boolean threw = false;

        try {
            Test.startTest();
            Database.executeBatch(new NameBackfillBatch(null), 1);
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
            System.assert(
                e.getMessage().contains('not available'),
                'Blank object should fail start: ' + e.getMessage()
            );
        }

        System.assertEquals(true, threw, 'Batch start should reject a blank object API name');
    }
}
