@IsTest
private class PatientClaimsControllerTest {
    @IsTest
    static void listsPatientSuperbillsWithChargeTotals() {
        Patient__c patient = new Patient__c(
            MRN__c = 'MRN-PATIENT-CLAIMS',
            First_Name__c = 'Jamie',
            Last_Name__c = 'Patient',
            Date_of_Birth__c = Date.newInstance(1985, 5, 12)
        );
        insert patient;

        Date serviceDate = Date.newInstance(2026, 9, 15);
        Encounter__c encounter = new Encounter__c(
            Patient__c = patient.Id,
            Status__c = 'Finished',
            Class__c = 'Outpatient',
            Start__c = Datetime.newInstance(serviceDate, Time.newInstance(9, 0, 0, 0))
        );
        insert encounter;

        Superbill__c superbill = new Superbill__c(
            Encounter__c = encounter.Id,
            Encounter_Key__c = String.valueOf(encounter.Id),
            Patient__c = patient.Id,
            Date_of_Service__c = serviceDate,
            Status__c = 'Ready'
        );
        insert superbill;
        insert new List<Charge_Line__c>{
            new Charge_Line__c(Superbill__c = superbill.Id, Units__c = 1, Charge_Amount__c = 125),
            new Charge_Line__c(Superbill__c = superbill.Id, Units__c = 1, Charge_Amount__c = 65),
            new Charge_Line__c(Superbill__c = superbill.Id, Units__c = 1)
        };

        PatientClaimsController.manageClaimsOverride = true;
        Test.startTest();
        List<PatientClaimsController.ClaimSummary> summaries =
            PatientClaimsController.getPatientSuperbills(patient.Id);
        Test.stopTest();

        System.assertEquals(1, summaries.size(), 'Patient should have one superbill');
        System.assertEquals(superbill.Id, summaries[0].id, 'Summary should identify the superbill');
        System.assertEquals(encounter.Id, summaries[0].encounterId, 'Summary should link the encounter');
        System.assertEquals(serviceDate, summaries[0].dateOfService, 'Summary should include service date');
        System.assertEquals(190, summaries[0].totalCharges, 'Summary should total non-null charges');
    }

    @IsTest
    static void enforcesPermissionAndPatientId() {
        PatientClaimsController.manageClaimsOverride = false;
        Boolean denied = false;
        try {
            PatientClaimsController.getPatientSuperbills(UserInfo.getUserId());
        } catch (AuraHandledException e) {
            denied = true;
        }
        System.assert(denied, 'Patient claims should require claims permission');

        PatientClaimsController.manageClaimsOverride = true;
        Boolean missingPatientRejected = false;
        try {
            PatientClaimsController.getPatientSuperbills(null);
        } catch (AuraHandledException e) {
            missingPatientRejected = true;
        }
        System.assert(missingPatientRejected, 'Patient Id should be required');
    }
}
