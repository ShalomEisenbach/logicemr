@IsTest
private class ClaimReadinessControllerTest {
    @IsTest
    static void finishedEncounterBuildsAndReadiesSuperbill() {
        TestData data = createCompleteEncounter('FINISHED');
        ClaimReadinessController.manageClaimsOverride = true;

        Test.startTest();
        ClaimReadinessController.Workspace initialized = ClaimReadinessController.initializeSuperbill(
            data.encounter.Id
        );

        System.assertNotEquals(null, initialized.superbill, 'Initialization should create a superbill');
        System.assertEquals('Needs Review', initialized.superbill.Status__c, 'New superbill should enter review');
        System.assertEquals(data.patient.Id, initialized.superbill.Patient__c, 'Patient should snapshot from encounter');
        System.assertEquals(data.coverage.Id, initialized.superbill.Coverage__c, 'Primary coverage should be selected');
        System.assertEquals(data.organization.Id, initialized.superbill.Billing_Organization__c, 'Billing org should be selected');
        System.assertEquals(1, initialized.diagnoses.size(), 'Encounter diagnosis should be snapshotted');
        System.assertEquals('J06.9', initialized.diagnoses[0].Diagnosis_Code__c, 'Diagnosis code should snapshot');
        System.assertEquals(1, initialized.charges.size(), 'Completed procedure should create a charge');
        System.assertEquals('99213', initialized.charges[0].Procedure_Code__c, 'Procedure code should snapshot');
        System.assert(initialized.issues.contains('Charge 1: charge amount must be greater than zero.'), 'Missing fee should be surfaced');

        ClaimReadinessController.ChargeInput charge = new ClaimReadinessController.ChargeInput();
        charge.chargeLineId = initialized.charges[0].Id;
        charge.superbillId = initialized.superbill.Id;
        charge.codeSystem = 'CPT';
        charge.code = '99213';
        charge.display = 'Established patient office visit';
        charge.serviceDate = data.serviceDate;
        charge.units = 1;
        charge.chargeAmount = 175;
        charge.diagnosisPointers = '1';

        ClaimReadinessController.Workspace afterCharge = ClaimReadinessController.saveCharge(charge);
        ClaimReadinessController.Workspace ready = ClaimReadinessController.markReady(initialized.superbill.Id);
        Test.stopTest();

        System.assertEquals(0, afterCharge.issues.size(), 'Complete data should pass validation');
        System.assertEquals(175, afterCharge.totalCharges, 'Total should sum charge amounts');
        System.assertEquals('Ready', ready.superbill.Status__c, 'Validated superbill should be ready');
        System.assertEquals(true, ready.ready, 'Workspace should report ready');
        System.assertNotEquals(null, ready.superbill.Ready_Date__c, 'Ready timestamp should be stored');
    }

    @IsTest
    static void validationBlocksIncompleteSuperbill() {
        Patient__c patient = new Patient__c(MRN__c = 'MRN-CLAIM-INCOMPLETE', Last_Name__c = 'Missing');
        insert patient;
        Encounter__c encounter = new Encounter__c(
            Patient__c = patient.Id,
            Status__c = 'In Progress',
            Class__c = 'Outpatient',
            Start__c = Datetime.newInstance(2026, 9, 15, 10, 0, 0)
        );
        insert encounter;
        ClaimReadinessController.manageClaimsOverride = true;

        Test.startTest();
        ClaimReadinessController.Workspace workspace = ClaimReadinessController.initializeSuperbill(encounter.Id);
        Boolean blocked = false;
        try {
            ClaimReadinessController.markReady(workspace.superbill.Id);
        } catch (AuraHandledException e) {
            blocked = true;
        }
        Test.stopTest();

        System.assertEquals(true, blocked, 'Incomplete superbill must not become ready');
        System.assert(workspace.issues.contains('Encounter must be Finished.'), 'Encounter status should be validated');
        System.assert(workspace.issues.contains('At least one signed clinical note is required.'), 'Signed note should be required');
        System.assert(workspace.issues.contains('At least one encounter diagnosis is required.'), 'Diagnosis should be required');
        System.assert(workspace.issues.contains('At least one charge line is required.'), 'Charge should be required');
        System.assertEquals(
            'Needs Review',
            [SELECT Status__c FROM Superbill__c WHERE Id = :workspace.superbill.Id].Status__c,
            'Blocked superbill should remain in review'
        );
    }

    @IsTest
    static void manualChargesCanBeAddedEditedAndDeleted() {
        TestData data = createCompleteEncounter('MANUAL');
        delete [SELECT Id FROM Procedure__c WHERE Encounter__c = :data.encounter.Id];
        ClaimReadinessController.manageClaimsOverride = true;
        ClaimReadinessController.Workspace initialized = ClaimReadinessController.initializeSuperbill(data.encounter.Id);

        ClaimReadinessController.ChargeInput input = new ClaimReadinessController.ChargeInput();
        input.superbillId = initialized.superbill.Id;
        input.codeSystem = 'HCPCS';
        input.code = 'G0439';
        input.display = 'Annual wellness visit';
        input.serviceDate = data.serviceDate;
        input.units = 1;
        input.chargeAmount = 225;
        input.modifiers = '25';
        input.diagnosisPointers = '1';

        Test.startTest();
        ClaimReadinessController.Workspace added = ClaimReadinessController.saveCharge(input);
        input.chargeLineId = added.charges[0].Id;
        input.chargeAmount = 250;
        ClaimReadinessController.Workspace edited = ClaimReadinessController.saveCharge(input);
        ClaimReadinessController.Workspace deleted = ClaimReadinessController.deleteCharge(input.chargeLineId);
        Test.stopTest();

        System.assertEquals(1, added.charges.size(), 'Manual charge should be created');
        System.assertEquals(250, edited.totalCharges, 'Edited charge should update total');
        System.assertEquals(0, deleted.charges.size(), 'Charge should be removable');
    }

    @IsTest
    static void initializationIsIdempotentAndPermissionIsEnforced() {
        TestData data = createCompleteEncounter('IDEMPOTENT');
        ClaimReadinessController.manageClaimsOverride = true;
        ClaimReadinessController.Workspace first = ClaimReadinessController.initializeSuperbill(data.encounter.Id);
        ClaimReadinessController.Workspace second = ClaimReadinessController.initializeSuperbill(data.encounter.Id);

        System.assertEquals(first.superbill.Id, second.superbill.Id, 'Encounter should have one superbill');
        System.assertEquals(1, [SELECT COUNT() FROM Superbill__c WHERE Encounter__c = :data.encounter.Id]);
        System.assertEquals(1, second.diagnoses.size(), 'Diagnosis sync should not duplicate rows');
        System.assertEquals(1, second.charges.size(), 'Procedure sync should not duplicate rows');

        ClaimReadinessController.manageClaimsOverride = false;
        Boolean denied = false;
        try {
            ClaimReadinessController.getWorkspace(data.encounter.Id);
        } catch (AuraHandledException e) {
            denied = true;
        }
        System.assertEquals(true, denied, 'Claims workspace should require the custom permission');
    }

    private static TestData createCompleteEncounter(String suffix) {
        TestData data = new TestData();
        data.serviceDate = Date.newInstance(2026, 9, 15);
        data.patient = new Patient__c(
            MRN__c = 'MRN-CLAIM-' + suffix,
            First_Name__c = 'Jamie',
            Last_Name__c = 'Patient',
            Date_of_Birth__c = Date.newInstance(1985, 5, 12),
            Sex_at_Birth__c = 'Female',
            Street__c = '10 Main St',
            City__c = 'Boston',
            State__c = 'MA',
            Postal_Code__c = '02108',
            Country__c = 'US',
            Status__c = 'Active'
        );
        insert data.patient;
        data.practitioner = new Practitioner__c(
            First_Name__c = 'Pat',
            Last_Name__c = suffix.left(20),
            NPI__c = npiFor(suffix)
        );
        insert data.practitioner;
        data.encounter = new Encounter__c(
            Patient__c = data.patient.Id,
            Practitioner__c = data.practitioner.Id,
            Status__c = 'Finished',
            Class__c = 'Outpatient',
            Start__c = Datetime.newInstance(data.serviceDate, Time.newInstance(9, 0, 0, 0))
        );
        insert data.encounter;
        data.organization = new Organization__c(
            Name = 'Logic Clinic ' + suffix,
            NPI__c = npiFor('ORG-' + suffix),
            EIN__c = '12-3456789',
            Street__c = '100 Clinic Ave',
            City__c = 'Boston',
            State__c = 'MA',
            Postal_Code__c = '02108',
            Country__c = 'US',
            Active__c = true,
            Is_Default_Billing__c = true
        );
        insert data.organization;
        data.payer = new Payer__c(
            Name = 'Test Payer ' + suffix,
            Type__c = 'Commercial',
            Payer_Identifier__c = 'PAYER-' + suffix,
            Active__c = true
        );
        insert data.payer;
        data.coverage = new Coverage__c(
            Patient__c = data.patient.Id,
            Payer__c = data.payer.Id,
            Member_Id__c = 'MEMBER-' + suffix,
            Relationship_to_Subscriber__c = 'Self',
            Subscriber_Name__c = 'Jamie Patient',
            Status__c = 'Active',
            Priority__c = 'Primary',
            Effective_Start__c = data.serviceDate.addMonths(-1),
            Effective_End__c = data.serviceDate.addMonths(1)
        );
        insert data.coverage;
        Condition__c condition = new Condition__c(
            Patient__c = data.patient.Id,
            Encounter__c = data.encounter.Id,
            Category__c = 'Encounter Diagnosis',
            Clinical_Status__c = 'Active',
            Diagnosis_Code_System__c = 'ICD-10',
            Diagnosis_Code__c = 'J06.9',
            Diagnosis_Display__c = 'Acute upper respiratory infection'
        );
        insert condition;
        insert new EncounterDiagnosis__c(
            Encounter__c = data.encounter.Id,
            Condition__c = condition.Id,
            Type__c = 'Principal',
            Rank__c = 1
        );
        insert new ClinicalNote__c(
            Patient__c = data.patient.Id,
            Encounter__c = data.encounter.Id,
            Author__c = data.practitioner.Id,
            Note_Type__c = 'Progress Note',
            Body__c = 'Signed visit note.',
            Status__c = 'Signed',
            Signed_Date__c = Datetime.now()
        );
        insert new Procedure__c(
            Patient__c = data.patient.Id,
            Encounter__c = data.encounter.Id,
            Performer__c = data.practitioner.Id,
            Procedure_Code_System__c = 'CPT',
            Procedure_Code__c = '99213',
            Procedure_Display__c = 'Established patient office visit',
            Status__c = 'Completed',
            Performed_DateTime__c = Datetime.newInstance(data.serviceDate, Time.newInstance(9, 30, 0, 0))
        );
        return data;
    }

    private static String npiFor(String seed) {
        return seed.startsWith('ORG-') ? '1888888875' : '1999999984';
    }

    private class TestData {
        Patient__c patient;
        Practitioner__c practitioner;
        Encounter__c encounter;
        Organization__c organization;
        Payer__c payer;
        Coverage__c coverage;
        Date serviceDate;
    }
}
