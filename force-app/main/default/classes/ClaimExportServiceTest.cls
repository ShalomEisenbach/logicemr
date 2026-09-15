@IsTest
private class ClaimExportServiceTest {
    @IsTest
    static void buildsCanonicalClaimOnlyFromFrozenSnapshots() {
        TestData data = createReadyClaim();

        data.patient.First_Name__c = 'Changed Source';
        update data.patient;

        Test.startTest();
        VendorNeutralClaim claim = ClaimExportService.build(data.superbill.Id);
        String payload = ClaimExportService.serialize(data.superbill.Id);
        Test.stopTest();

        System.assertEquals('1.0', claim.schemaVersion);
        System.assertEquals('professional', claim.claimType);
        System.assertEquals('USD', claim.currencyCode);
        System.assertEquals('Frozen', claim.patient.name.first, 'Export must use the patient snapshot');
        System.assertEquals('Subscriber', claim.subscriber.name.last);
        System.assertEquals('PAYER-EXPORT', claim.payer.identifier);
        System.assertEquals('1999999984', claim.renderingProvider.npi);
        System.assertEquals('123456789', claim.billingProvider.taxIdentifier, 'EIN should normalize to digits');
        System.assertEquals(1, claim.diagnoses.size());
        System.assertEquals('J06.9', claim.diagnoses[0].code);
        System.assertEquals(1, claim.serviceLines.size());
        System.assertEquals(new List<String>{ '25', '59' }, claim.serviceLines[0].modifiers);
        System.assertEquals(new List<Integer>{ 1 }, claim.serviceLines[0].diagnosisPointers);
        System.assertEquals(200, claim.totalCharge);
        System.assert(payload.contains('"schemaVersion" : "1.0"'));
        System.assert(payload.contains('"first" : "Frozen"'));
        System.assert(!payload.contains('Changed Source'), 'Live source changes must not leak into exports');
    }

    @IsTest
    static void controllerRequiresPermissionAndFrozenStatus() {
        TestData data = createReadyClaim();
        ClaimExportController.manageClaimsOverride = false;
        Boolean denied = false;
        try {
            ClaimExportController.getCanonicalJson(data.superbill.Id);
        } catch (AuraHandledException e) {
            denied = true;
        }
        System.assertEquals(true, denied, 'Export endpoint should require claims permission');

        ClaimExportController.manageClaimsOverride = true;
        data.superbill.Status__c = 'Needs Review';
        update data.superbill;
        Boolean reviewBlocked = false;
        try {
            ClaimExportController.getCanonicalJson(data.superbill.Id);
        } catch (AuraHandledException e) {
            reviewBlocked = true;
        }
        System.assertEquals(true, reviewBlocked, 'Claims still in review must not export');
    }

    @IsTest
    static void malformedFrozenLinesAreRejected() {
        TestData data = createReadyClaim();
        Charge_Line__c line = [SELECT Id, Diagnosis_Pointers__c FROM Charge_Line__c WHERE Superbill__c = :data.superbill.Id LIMIT 1];
        line.Diagnosis_Pointers__c = '2';
        update line;

        Boolean blocked = false;
        try {
            ClaimExportService.build(data.superbill.Id);
        } catch (AuraHandledException e) {
            blocked = true;
        }
        System.assertEquals(true, blocked, 'Invalid frozen diagnosis pointers must block export');
    }

    private static TestData createReadyClaim() {
        TestData data = new TestData();
        Date serviceDate = Date.newInstance(2026, 9, 15);
        data.patient = new Patient__c(
            MRN__c = 'MRN-EXPORT', First_Name__c = 'Live', Last_Name__c = 'Patient',
            Date_of_Birth__c = Date.newInstance(1990, 1, 2), Sex_at_Birth__c = 'Female',
            Street__c = '1 Live St', City__c = 'Boston', State__c = 'MA', Postal_Code__c = '02108'
        );
        insert data.patient;
        Practitioner__c practitioner = new Practitioner__c(
            First_Name__c = 'Pat', Last_Name__c = 'Provider', NPI__c = '1999999984',
            Taxonomy_Code__c = '207Q00000X'
        );
        insert practitioner;
        Organization__c organization = new Organization__c(
            Name = 'Live Clinic', NPI__c = '1888888875', EIN__c = '12-3456789',
            Taxonomy_Code__c = '261QP2300X', Street__c = '100 Live Ave', City__c = 'Boston',
            State__c = 'MA', Postal_Code__c = '02108', Active__c = true
        );
        insert organization;
        Payer__c payer = new Payer__c(
            Name = 'Live Payer', Type__c = 'Commercial', Payer_Identifier__c = 'LIVE-PAYER', Active__c = true
        );
        insert payer;
        Coverage__c coverage = new Coverage__c(
            Patient__c = data.patient.Id, Payer__c = payer.Id, Member_Id__c = 'LIVE-MEMBER',
            Relationship_to_Subscriber__c = 'Self', Status__c = 'Active', Priority__c = 'Primary'
        );
        insert coverage;
        Encounter__c encounter = new Encounter__c(
            Patient__c = data.patient.Id, Practitioner__c = practitioner.Id, Status__c = 'Finished',
            Class__c = 'Outpatient', Start__c = Datetime.newInstance(serviceDate, Time.newInstance(9, 0, 0, 0))
        );
        insert encounter;

        data.superbill = new Superbill__c(
            Encounter__c = encounter.Id,
            Encounter_Key__c = String.valueOf(encounter.Id),
            Patient__c = data.patient.Id,
            Coverage__c = coverage.Id,
            Rendering_Practitioner__c = practitioner.Id,
            Billing_Organization__c = organization.Id,
            Date_of_Service__c = serviceDate,
            Status__c = 'Ready',
            Ready_Date__c = Datetime.now(),
            Snapshot_Refreshed_At__c = Datetime.now(),
            Snapshot_Version__c = 3,
            Patient_First_Name__c = 'Frozen',
            Patient_Last_Name__c = 'Patient',
            Patient_Date_of_Birth__c = Date.newInstance(1990, 1, 2),
            Patient_Sex__c = 'Female',
            Patient_Street__c = '1 Snapshot St',
            Patient_City__c = 'Boston',
            Patient_State__c = 'MA',
            Patient_Postal_Code__c = '02108',
            Patient_Country__c = 'US',
            Subscriber_First_Name__c = 'Frozen',
            Subscriber_Last_Name__c = 'Subscriber',
            Subscriber_Date_of_Birth__c = Date.newInstance(1980, 5, 6),
            Subscriber_Sex__c = 'Male',
            Subscriber_Relationship__c = 'Spouse',
            Subscriber_Member_Id__c = 'MEMBER-EXPORT',
            Subscriber_Group_Number__c = 'GROUP-1',
            Subscriber_Street__c = '2 Snapshot St',
            Subscriber_City__c = 'Boston',
            Subscriber_State__c = 'MA',
            Subscriber_Postal_Code__c = '02109',
            Subscriber_Country__c = 'US',
            Coverage_Effective_Start__c = serviceDate.addYears(-1),
            Coverage_Effective_End__c = serviceDate.addYears(1),
            Payer_Name__c = 'Frozen Payer',
            Payer_Identifier__c = 'PAYER-EXPORT',
            Rendering_Provider_Name__c = 'Frozen Rendering Provider',
            Rendering_Provider_NPI__c = '1999999984',
            Rendering_Provider_Taxonomy__c = '207Q00000X',
            Billing_Provider_Name__c = 'Frozen Billing Clinic',
            Billing_Provider_NPI__c = '1888888875',
            Billing_Provider_EIN__c = '12-3456789',
            Billing_Provider_Taxonomy__c = '261QP2300X',
            Billing_Provider_Street__c = '100 Snapshot Ave',
            Billing_Provider_City__c = 'Boston',
            Billing_Provider_State__c = 'MA',
            Billing_Provider_Postal_Code__c = '02108',
            Billing_Provider_Country__c = 'US'
        );
        insert data.superbill;
        insert new Superbill_Diagnosis__c(
            Superbill__c = data.superbill.Id, Sequence__c = 1, Diagnosis_Type__c = 'Principal',
            Diagnosis_Code_System__c = 'ICD-10', Diagnosis_Code__c = 'J06.9',
            Diagnosis_Display__c = 'Acute upper respiratory infection'
        );
        insert new Charge_Line__c(
            Superbill__c = data.superbill.Id, Procedure_Code_System__c = 'CPT',
            Procedure_Code__c = '99213', Procedure_Display__c = 'Office visit',
            Service_Date__c = serviceDate, Units__c = 2, Applied_Unit_Rate__c = 100,
            Charge_Amount__c = 200, Modifiers__c = '25,59', Diagnosis_Pointers__c = '1',
            Rate_Source__c = 'Frozen contract rate', Rate_Override__c = false
        );
        return data;
    }

    private class TestData {
        Patient__c patient;
        Superbill__c superbill;
    }
}
