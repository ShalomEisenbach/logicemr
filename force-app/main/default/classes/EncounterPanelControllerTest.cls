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
