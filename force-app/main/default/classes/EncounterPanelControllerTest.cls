@IsTest
private class EncounterPanelControllerTest {
    @IsTest
    static void getEncountersReturnsNewestFirstWithExpectedShape() {
        Patient__c patient = insertPatient('MRN-ENC-1');
        Patient__c otherPatient = insertPatient('MRN-ENC-2');
        Practitioner__c attending = insertPractitioner('Jordan', 'Lee');

        Datetime olderStart = Datetime.newInstance(2024, 1, 15, 9, 0, 0);
        Datetime newerStart = Datetime.newInstance(2024, 6, 2, 14, 30, 0);

        Encounter__c older = insertEncounter(
            patient.Id,
            'Finished',
            'Inpatient',
            olderStart,
            attending.Id
        );
        Encounter__c newer = insertEncounter(
            patient.Id,
            'In Progress',
            'Outpatient',
            newerStart,
            attending.Id
        );
        insertEncounter(otherPatient.Id, 'Planned', 'Virtual', newerStart, null);

        Test.startTest();
        List<Encounter__c> results = EncounterPanelController.getEncounters(patient.Id);
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Should return only this patient\'s encounters');
        System.assertEquals(newer.Id, results[0].Id, 'Newest Start__c should be first');
        System.assertEquals(older.Id, results[1].Id, 'Older encounter should be second');
        System.assertEquals(true, String.isNotBlank(results[0].Name), 'Name should be populated');
        System.assertEquals('In Progress', results[0].Status__c, 'Status__c should be populated');
        System.assertEquals('Outpatient', results[0].Class__c, 'Class__c should be populated');
        System.assertEquals(newerStart, results[0].Start__c, 'Start__c should be populated');
        System.assertEquals(attending.Id, results[0].Practitioner__c, 'Attending lookup should be populated');
        System.assertEquals(
            'Jordan',
            results[0].Practitioner__r.First_Name__c,
            'Attending first name should be queried'
        );
        System.assertEquals(
            'Lee',
            results[0].Practitioner__r.Last_Name__c,
            'Attending last name should be queried'
        );
    }

    @IsTest
    static void getEncountersReturnsEmptyForBlankOrUnrelatedPatient() {
        Patient__c patient = insertPatient('MRN-ENC-3');

        Test.startTest();
        List<Encounter__c> blankId = EncounterPanelController.getEncounters(null);
        List<Encounter__c> none = EncounterPanelController.getEncounters(patient.Id);
        Test.stopTest();

        System.assertEquals(0, blankId.size(), 'Null patient Id should return no rows');
        System.assertEquals(0, none.size(), 'A patient with no encounters should return no rows');
    }

    @IsTest
    static void createEncounterPersistsRequiredAndOptionalFields() {
        Patient__c patient = insertPatient('MRN-ENC-4');
        Practitioner__c attending = insertPractitioner('Elena', 'Vasquez');
        Datetime startTime = Datetime.newInstance(2026, 9, 2, 13, 0, 0);
        Datetime endTime = Datetime.newInstance(2026, 9, 2, 14, 0, 0);

        Test.startTest();
        Encounter__c created = EncounterPanelController.createEncounter(
            patient.Id,
            'Outpatient',
            'Arrived',
            startTime,
            endTime,
            attending.Id,
            'Clinic A',
            'Follow-up'
        );
        Test.stopTest();

        Encounter__c stored = [
            SELECT
                Patient__c,
                Class__c,
                Status__c,
                Start__c,
                End__c,
                Practitioner__c,
                Location_Name__c,
                Reason__c
            FROM Encounter__c
            WHERE Id = :created.Id
        ];
        System.assertEquals(patient.Id, stored.Patient__c, 'Encounter should belong to the patient');
        System.assertEquals('Outpatient', stored.Class__c, 'Class should persist');
        System.assertEquals('Arrived', stored.Status__c, 'Status should persist');
        System.assertEquals(startTime, stored.Start__c, 'Start should persist');
        System.assertEquals(endTime, stored.End__c, 'End should persist');
        System.assertEquals(attending.Id, stored.Practitioner__c, 'Attending should persist');
        System.assertEquals('Clinic A', stored.Location_Name__c, 'Location should persist');
        System.assertEquals('Follow-up', stored.Reason__c, 'Chief complaint should persist');
    }

    @IsTest
    static void createEncounterDefaultsStatusAndStartAndRejectsInvalid() {
        Patient__c patient = insertPatient('MRN-ENC-5');
        Boolean missingPatient = false;
        Boolean missingClass = false;
        Boolean wrongClass = false;
        Boolean wrongStatus = false;
        Boolean endBeforeStart = false;

        Test.startTest();
        Encounter__c created = EncounterPanelController.createEncounter(
            patient.Id,
            'Virtual',
            null,
            null,
            null,
            null,
            null,
            null
        );
        try {
            EncounterPanelController.createEncounter(null, 'Outpatient', null, null, null, null, null, null);
        } catch (AuraHandledException e) {
            missingPatient = true;
        }
        try {
            EncounterPanelController.createEncounter(patient.Id, null, null, null, null, null, null, null);
        } catch (AuraHandledException e) {
            missingClass = true;
        }
        try {
            EncounterPanelController.createEncounter(patient.Id, 'Home', null, null, null, null, null, null);
        } catch (AuraHandledException e) {
            wrongClass = true;
        }
        try {
            EncounterPanelController.createEncounter(
                patient.Id,
                'Outpatient',
                'Unknown',
                null,
                null,
                null,
                null,
                null
            );
        } catch (AuraHandledException e) {
            wrongStatus = true;
        }
        try {
            EncounterPanelController.createEncounter(
                patient.Id,
                'Outpatient',
                'Planned',
                Datetime.newInstance(2026, 9, 2, 14, 0, 0),
                Datetime.newInstance(2026, 9, 2, 13, 0, 0),
                null,
                null,
                null
            );
        } catch (AuraHandledException e) {
            endBeforeStart = true;
        }
        Test.stopTest();

        Encounter__c stored = [
            SELECT Status__c, Start__c, Class__c
            FROM Encounter__c
            WHERE Id = :created.Id
        ];
        System.assertEquals('Planned', stored.Status__c, 'Blank status should default to Planned');
        System.assertEquals('Virtual', stored.Class__c, 'Class should persist on the defaulted insert');
        System.assertEquals(true, stored.Start__c != null, 'Blank start should default to now');
        System.assertEquals(true, missingPatient, 'Blank patient Id should be rejected');
        System.assertEquals(true, missingClass, 'Blank class should be rejected');
        System.assertEquals(true, wrongClass, 'Unknown class should be rejected');
        System.assertEquals(true, wrongStatus, 'Unknown status should be rejected');
        System.assertEquals(true, endBeforeStart, 'End before start should be rejected');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Encounter__c WHERE Patient__c = :patient.Id],
            'Rejected creates must not insert extra rows'
        );
    }

    @IsTest
    static void deleteEncountersRemovesRowsAndIgnoresBlankIds() {
        Patient__c patient = insertPatient('MRN-ENC-DEL');
        Encounter__c first = insertEncounter(
            patient.Id,
            'Finished',
            'Outpatient',
            Datetime.newInstance(2026, 7, 22, 10, 0, 0),
            null
        );
        Encounter__c second = insertEncounter(
            patient.Id,
            'Finished',
            'Virtual',
            Datetime.newInstance(2026, 1, 15, 9, 0, 0),
            null
        );

        Test.startTest();
        EncounterPanelController.deleteEncounters(null);
        EncounterPanelController.deleteEncounters(new List<Id>());
        EncounterPanelController.deleteEncounters(new List<Id>{ first.Id, second.Id });
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Encounter__c WHERE Id IN :new List<Id>{ first.Id, second.Id }],
            'Both encounters should be deleted'
        );
    }

    private static Patient__c insertPatient(String mrn) {
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'Chart');
        insert patient;
        return patient;
    }

    private static Practitioner__c insertPractitioner(String firstName, String lastName) {
        Practitioner__c practitioner = new Practitioner__c(
            First_Name__c = firstName,
            Last_Name__c = lastName
        );
        insert practitioner;
        return practitioner;
    }

    private static Encounter__c insertEncounter(
        Id patientId,
        String status,
        String encounterClass,
        Datetime startTime,
        Id attendingId
    ) {
        Encounter__c encounter = new Encounter__c(
            Patient__c = patientId,
            Status__c = status,
            Class__c = encounterClass,
            Start__c = startTime,
            Practitioner__c = attendingId
        );
        insert encounter;
        return encounter;
    }
}
