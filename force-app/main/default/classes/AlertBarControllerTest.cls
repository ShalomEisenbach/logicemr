@IsTest
private class AlertBarControllerTest {
    @IsTest
    static void resolvePatientIdReturnsPatientAndEncounterPatient() {
        Patient__c patient = insertPatient('MRN-AB-1');
        Encounter__c encounter = insertEncounter(patient.Id);
        Patient__c other = insertPatient('MRN-AB-2');
        Encounter__c orphaned = insertEncounter(other.Id);
        Id orphanedId = orphaned.Id;
        delete orphaned;

        Test.startTest();
        Id fromPatient = AlertBarController.resolvePatientId(patient.Id);
        Id fromEncounter = AlertBarController.resolvePatientId(encounter.Id);
        Id fromNull = AlertBarController.resolvePatientId(null);
        Id fromUser = AlertBarController.resolvePatientId(UserInfo.getUserId());
        Id fromMissingEncounter = AlertBarController.resolvePatientId(orphanedId);
        Test.stopTest();

        System.assertEquals(patient.Id, fromPatient, 'Patient Id should resolve to itself');
        System.assertEquals(patient.Id, fromEncounter, 'Encounter should resolve to its Patient__c');
        System.assertEquals(null, fromNull, 'Null record Id should resolve to null');
        System.assertEquals(null, fromUser, 'Non-patient records should not resolve');
        System.assertEquals(null, fromMissingEncounter, 'Missing encounter should resolve to null');
    }

    @IsTest
    static void getActiveAllergiesReturnsActiveRowsForPatientAndEncounter() {
        Patient__c patient = insertPatient('MRN-AB-3');
        Patient__c other = insertPatient('MRN-AB-4');
        Encounter__c encounter = insertEncounter(patient.Id);
        AllergyIntolerance__c high = insertAllergy(patient.Id, 'Active', 'Penicillin', 'High');
        insertAllergy(patient.Id, 'Active', 'Cashew', 'Low');
        insertAllergy(patient.Id, 'Inactive', 'Codeine', 'High');
        insertAllergy(other.Id, 'Active', 'Latex', 'High');

        Test.startTest();
        List<AllergyIntolerance__c> byPatient = AlertBarController.getActiveAllergies(patient.Id);
        List<AllergyIntolerance__c> byEncounter = AlertBarController.getActiveAllergies(encounter.Id);
        List<AllergyIntolerance__c> blank = AlertBarController.getActiveAllergies(null);
        List<AllergyIntolerance__c> unsupported = AlertBarController.getActiveAllergies(UserInfo.getUserId());
        Test.stopTest();

        System.assertEquals(2, byPatient.size(), 'Active allergies for the patient should be returned');
        System.assertEquals(2, byEncounter.size(), 'Encounter context should return the same patient allergies');
        System.assertEquals(0, blank.size(), 'Null record Id should return no allergies');
        System.assertEquals(0, unsupported.size(), 'Unsupported record types should return no allergies');
        System.assertEquals(high.Id, byPatient[0].Id, 'High criticality should sort first');
        System.assertEquals('High', byPatient[0].Criticality__c, 'Criticality should be queried');
        System.assertEquals('Penicillin', byPatient[0].Allergen_Display__c, 'Display should be queried');
        System.assertEquals(byPatient[0].Id, byEncounter[0].Id, 'Patient and encounter queries should match');
        System.assertEquals(byPatient[1].Id, byEncounter[1].Id, 'Both active allergies should match by encounter');
    }

    @IsTest
    static void getActiveAllergiesReturnsEmptyWhenPatientHasNone() {
        Patient__c patient = insertPatient('MRN-AB-5');
        Encounter__c encounter = insertEncounter(patient.Id);

        Test.startTest();
        List<AllergyIntolerance__c> byPatient = AlertBarController.getActiveAllergies(patient.Id);
        List<AllergyIntolerance__c> byEncounter = AlertBarController.getActiveAllergies(encounter.Id);
        Test.stopTest();

        System.assertEquals(0, byPatient.size(), 'Patient with no allergies should return empty');
        System.assertEquals(0, byEncounter.size(), 'Encounter of a patient with no allergies should return empty');
    }

    private static Patient__c insertPatient(String mrn) {
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'AlertBar');
        insert patient;
        return patient;
    }

    private static Encounter__c insertEncounter(Id patientId) {
        Encounter__c encounter = new Encounter__c(
            Patient__c = patientId,
            Status__c = 'In Progress',
            Class__c = 'Outpatient',
            Start__c = Datetime.newInstance(2024, 3, 1, 9, 0, 0)
        );
        insert encounter;
        return encounter;
    }

    private static AllergyIntolerance__c insertAllergy(
        Id patientId,
        String status,
        String display,
        String criticality
    ) {
        AllergyIntolerance__c allergy = new AllergyIntolerance__c(
            Patient__c = patientId,
            Clinical_Status__c = status,
            Allergen_Display__c = display,
            Type__c = 'Allergy',
            Category__c = 'Medication',
            Criticality__c = criticality
        );
        insert allergy;
        return allergy;
    }
}
