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
        System.assertEquals('11', initialized.superbill.Place_of_Service_Code__c, 'Outpatient encounters should default to office');
        System.assertEquals(data.organization.Id, initialized.superbill.Billing_Organization__c, 'Billing org should be selected');
        System.assertEquals('Jamie', initialized.superbill.Patient_First_Name__c, 'Patient demographics should snapshot');
        System.assertEquals('Jamie', initialized.superbill.Subscriber_First_Name__c, 'Self coverage should snapshot patient as subscriber');
        System.assertEquals('MEMBER-' + 'FINISHED', initialized.superbill.Subscriber_Member_Id__c, 'Member ID should snapshot');
        System.assertEquals('CI', initialized.superbill.Claim_Filing_Code__c, 'Commercial filing code should be derived');
        System.assertEquals('Pat', initialized.superbill.Rendering_Provider_First_Name__c, 'Rendering first name should snapshot');
        System.assertEquals(data.practitioner.NPI__c, initialized.superbill.Rendering_Provider_NPI__c, 'Rendering NPI should snapshot');
        System.assertEquals(data.organization.EIN__c, initialized.superbill.Billing_Provider_EIN__c, 'Billing EIN should snapshot');
        System.assertEquals(1, initialized.superbill.Snapshot_Version__c, 'First snapshot should be version one');
        System.assertEquals(1, initialized.diagnoses.size(), 'Encounter diagnosis should be snapshotted');
        System.assertEquals('J06.9', initialized.diagnoses[0].Diagnosis_Code__c, 'Diagnosis code should snapshot');
        System.assertEquals(1, initialized.charges.size(), 'Completed procedure should create a charge');
        System.assertEquals('99213', initialized.charges[0].Procedure_Code__c, 'Procedure code should snapshot');
        System.assertEquals(175, initialized.charges[0].Charge_Amount__c, 'Procedure should be priced automatically');
        System.assertEquals(data.officeRate.Id, initialized.charges[0].Fee_Schedule_Rate__c, 'Rate source should be stored');
        System.assertEquals(false, initialized.charges[0].Rate_Override__c, 'Scheduled rate is not an override');
        ClaimReadinessController.Workspace updated = ClaimReadinessController.updateClaimDetails(initialized.superbill.Id, '22');
        ClaimReadinessController.Workspace ready = ClaimReadinessController.markReady(updated.superbill.Id);
        Test.stopTest();

        System.assertEquals(0, initialized.issues.size(), 'Complete priced data should pass validation');
        System.assertEquals(175, initialized.totalCharges, 'Total should sum charge amounts');
        System.assertEquals('Ready', ready.superbill.Status__c, 'Validated superbill should be ready');
        System.assertEquals('22', ready.superbill.Place_of_Service_Code__c, 'Billing should control place of service');
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
        input.modifiers = '25';
        input.diagnosisPointers = '1';

        Test.startTest();
        ClaimReadinessController.Workspace added = ClaimReadinessController.saveCharge(input);
        input.chargeLineId = added.charges[0].Id;
        input.units = 2;
        ClaimReadinessController.Workspace repriced = ClaimReadinessController.saveCharge(input);
        input.chargeAmount = 250;
        input.rateOverride = true;
        input.overrideReason = 'Approved contract exception';
        FeeScheduleService.overrideRatesOverride = true;
        ClaimReadinessController.Workspace edited = ClaimReadinessController.saveCharge(input);
        ClaimReadinessController.Workspace deleted = ClaimReadinessController.deleteCharge(input.chargeLineId);
        Test.stopTest();

        System.assertEquals(1, added.charges.size(), 'Manual charge should be created');
        System.assertEquals(225, added.totalCharges, 'Manual CPT/HCPCS line should use the fee schedule');
        System.assertEquals(450, repriced.totalCharges, 'Line amount should equal the unit rate times units');
        System.assertEquals(250, edited.totalCharges, 'Edited charge should update total');
        System.assertEquals(true, edited.charges[0].Rate_Override__c, 'Approved change should be identified as an override');
        System.assertEquals('Approved contract exception', edited.charges[0].Override_Reason__c, 'Reason should be retained');
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

    @IsTest
    static void effectiveDatedRateAndExpiredRateAreHandled() {
        TestData currentData = createCompleteEncounter('EFFECTIVE');
        currentData.officeRate.Effective_End__c = currentData.serviceDate.addDays(-1);
        update currentData.officeRate;
        Fee_Schedule_Rate__c replacement = new Fee_Schedule_Rate__c(
            Fee_Schedule__c = currentData.feeSchedule.Id,
            Procedure_Code_System__c = 'CPT',
            Procedure_Code__c = '99213',
            Rate_Amount__c = 190,
            Effective_Start__c = currentData.serviceDate,
            Active__c = true
        );
        insert replacement;
        ClaimReadinessController.manageClaimsOverride = true;

        ClaimReadinessController.Workspace current = ClaimReadinessController.initializeSuperbill(
            currentData.encounter.Id
        );
        System.assertEquals(190, current.charges[0].Charge_Amount__c, 'The rate effective on the DOS should win');
        System.assertEquals(replacement.Id, current.charges[0].Fee_Schedule_Rate__c, 'Selected source should be stored');

        TestData expiredData = createCompleteEncounter('EXPIRED');
        expiredData.officeRate.Effective_End__c = expiredData.serviceDate.addDays(-1);
        update expiredData.officeRate;
        ClaimReadinessController.Workspace expired = ClaimReadinessController.initializeSuperbill(
            expiredData.encounter.Id
        );
        System.assertEquals(null, expired.charges[0].Charge_Amount__c, 'Expired rate must not price the charge');
        System.assert(
            expired.issues.contains('Charge 1: fee schedule rate is expired for the service date.'),
            'Claim readiness should distinguish an expired rate'
        );

        TestData missingData = createCompleteEncounter('MISSING');
        missingData.feeSchedule.Active__c = false;
        update missingData.feeSchedule;
        ClaimReadinessController.Workspace missing = ClaimReadinessController.initializeSuperbill(
            missingData.encounter.Id
        );
        System.assert(
            missing.issues.contains('Charge 1: no applicable payer or self-pay fee schedule rate was found.'),
            'Claim readiness should identify a missing rate'
        );
    }

    @IsTest
    static void selfPaySchedulePricesSelfPayCoverage() {
        TestData data = createCompleteEncounter('SELFPAY');
        data.payer.Type__c = 'Self-Pay';
        update data.payer;
        Fee_Schedule__c selfPaySchedule = new Fee_Schedule__c(
            Name = 'Standard Self Pay',
            Schedule_Type__c = 'Self-Pay',
            Priority__c = 10,
            Active__c = true
        );
        insert selfPaySchedule;
        Fee_Schedule_Rate__c selfPayRate = new Fee_Schedule_Rate__c(
            Fee_Schedule__c = selfPaySchedule.Id,
            Procedure_Code_System__c = 'CPT',
            Procedure_Code__c = '99213',
            Rate_Amount__c = 95,
            Effective_Start__c = data.serviceDate.addMonths(-1),
            Active__c = true
        );
        insert selfPayRate;
        ClaimReadinessController.manageClaimsOverride = true;

        ClaimReadinessController.Workspace workspace = ClaimReadinessController.initializeSuperbill(data.encounter.Id);

        System.assertEquals(95, workspace.charges[0].Charge_Amount__c, 'Self-pay coverage should use self-pay pricing');
        System.assertEquals(selfPayRate.Id, workspace.charges[0].Fee_Schedule_Rate__c, 'Self-pay source should be retained');
    }

    @IsTest
    static void rateOverrideRequiresPermissionAndReason() {
        TestData data = createCompleteEncounter('OVERRIDE');
        ClaimReadinessController.manageClaimsOverride = true;
        ClaimReadinessController.Workspace initialized = ClaimReadinessController.initializeSuperbill(data.encounter.Id);
        ClaimReadinessController.ChargeInput input = new ClaimReadinessController.ChargeInput();
        input.chargeLineId = initialized.charges[0].Id;
        input.superbillId = initialized.superbill.Id;
        input.codeSystem = 'CPT';
        input.code = '99213';
        input.display = 'Established patient office visit';
        input.serviceDate = data.serviceDate;
        input.units = 1;
        input.chargeAmount = 200;
        input.rateOverride = true;
        input.diagnosisPointers = '1';

        FeeScheduleService.overrideRatesOverride = false;
        Boolean permissionDenied = false;
        try {
            input.overrideReason = 'Requested adjustment';
            ClaimReadinessController.saveCharge(input);
        } catch (AuraHandledException e) {
            permissionDenied = true;
        }
        System.assertEquals(true, permissionDenied, 'A dedicated permission should control rate overrides');

        FeeScheduleService.overrideRatesOverride = true;
        input.overrideReason = null;
        Boolean reasonRequired = false;
        try {
            ClaimReadinessController.saveCharge(input);
        } catch (AuraHandledException e) {
            reasonRequired = true;
        }
        System.assertEquals(true, reasonRequired, 'A changed amount should require an override reason');
    }

    @IsTest
    static void directChargeEditCannotBypassRateControl() {
        TestData data = createCompleteEncounter('DIRECT');
        ClaimReadinessController.manageClaimsOverride = true;
        ClaimReadinessController.Workspace initialized = ClaimReadinessController.initializeSuperbill(data.encounter.Id);
        Charge_Line__c charge = initialized.charges[0];
        charge.Charge_Amount__c = 999;
        FeeScheduleService.overrideRatesOverride = false;

        Boolean blocked = false;
        try {
            update charge;
        } catch (DmlException e) {
            blocked = true;
        }

        System.assertEquals(true, blocked, 'The charge trigger should reject a direct unsanctioned amount edit');
    }

    @IsTest
    static void dependentSnapshotsRefreshDuringReviewAndFreezeWhenReady() {
        TestData data = createCompleteEncounter('DEPENDENT');
        data.coverage.Relationship_to_Subscriber__c = 'Spouse';
        data.coverage.Subscriber_First_Name__c = 'Taylor';
        data.coverage.Subscriber_Last_Name__c = 'Policyholder';
        data.coverage.Subscriber_Date_of_Birth__c = Date.newInstance(1982, 3, 4);
        data.coverage.Subscriber_Sex__c = 'Male';
        data.coverage.Subscriber_Street__c = '20 Subscriber Way';
        data.coverage.Subscriber_City__c = 'Boston';
        data.coverage.Subscriber_State__c = 'MA';
        data.coverage.Subscriber_Postal_Code__c = '02109';
        data.coverage.Subscriber_Country__c = 'US';
        update data.coverage;
        ClaimReadinessController.manageClaimsOverride = true;

        ClaimReadinessController.Workspace initialized = ClaimReadinessController.initializeSuperbill(data.encounter.Id);
        System.assertEquals('Taylor', initialized.superbill.Subscriber_First_Name__c, 'Dependent first name should snapshot from coverage');
        System.assertEquals('Policyholder', initialized.superbill.Subscriber_Last_Name__c, 'Dependent last name should snapshot from coverage');
        System.assertEquals(0, initialized.issues.size(), 'A complete dependent subscriber should be ready-capable');

        data.coverage.Subscriber_First_Name__c = 'Updated';
        update data.coverage;
        ClaimReadinessController.Workspace refreshed = ClaimReadinessController.refreshClaimSnapshots(initialized.superbill.Id);
        System.assertEquals('Updated', refreshed.superbill.Subscriber_First_Name__c, 'Review snapshots should refresh on request');
        System.assertEquals(2, refreshed.superbill.Snapshot_Version__c, 'Each refresh should advance the version');

        ClaimReadinessController.Workspace ready = ClaimReadinessController.markReady(refreshed.superbill.Id);
        data.coverage.Subscriber_First_Name__c = 'Later source edit';
        update data.coverage;
        data.patient.First_Name__c = 'Later patient edit';
        update data.patient;
        ClaimReadinessController.Workspace unchanged = ClaimReadinessController.initializeSuperbill(data.encounter.Id);
        System.assertEquals('Ready', unchanged.superbill.Status__c, 'Sync must not reopen a ready claim');
        System.assertEquals('Updated', unchanged.superbill.Subscriber_First_Name__c, 'Ready snapshot must remain frozen');
        System.assertEquals('Jamie', unchanged.superbill.Patient_First_Name__c, 'Ready patient snapshot must remain frozen');

        Superbill__c directEdit = new Superbill__c(
            Id = ready.superbill.Id,
            Subscriber_First_Name__c = 'Bypass'
        );
        Boolean directEditBlocked = false;
        try {
            update directEdit;
        } catch (DmlException e) {
            directEditBlocked = true;
        }
        System.assertEquals(true, directEditBlocked, 'Direct snapshot edits must be blocked while ready');

        ClaimReadinessController.reopen(ready.superbill.Id);
        ClaimReadinessController.Workspace afterReopen = ClaimReadinessController.refreshClaimSnapshots(ready.superbill.Id);
        System.assertEquals('Later source edit', afterReopen.superbill.Subscriber_First_Name__c, 'Reopened snapshots can refresh');
        System.assertEquals(3, afterReopen.superbill.Snapshot_Version__c, 'Post-reopen refresh should advance the version');
    }

    @IsTest
    static void readinessReportsMissingProviderSnapshotIdentifiers() {
        TestData data = createCompleteEncounter('NO-TAXONOMY');
        data.practitioner.Taxonomy_Code__c = null;
        data.organization.Taxonomy_Code__c = null;
        update data.practitioner;
        update data.organization;
        ClaimReadinessController.manageClaimsOverride = true;

        ClaimReadinessController.Workspace workspace = ClaimReadinessController.initializeSuperbill(data.encounter.Id);

        System.assert(
            workspace.issues.contains('Rendering provider snapshot requires a 10-character taxonomy code.'),
            'Rendering taxonomy should be validated from its snapshot'
        );
        System.assert(
            workspace.issues.contains('Billing provider snapshot requires a 10-character taxonomy code.'),
            'Billing taxonomy should be validated from its snapshot'
        );
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
            NPI__c = npiFor(suffix),
            Taxonomy_Code__c = '207Q00000X'
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
            Taxonomy_Code__c = '261QP2300X',
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
        data.feeSchedule = new Fee_Schedule__c(
            Name = 'Test Payer Schedule ' + suffix,
            Schedule_Type__c = 'Payer',
            Payer__c = data.payer.Id,
            Priority__c = 100,
            Active__c = true
        );
        insert data.feeSchedule;
        data.officeRate = new Fee_Schedule_Rate__c(
            Fee_Schedule__c = data.feeSchedule.Id,
            Procedure_Code_System__c = 'CPT',
            Procedure_Code__c = '99213',
            Procedure_Display__c = 'Established patient office visit',
            Rate_Amount__c = 175,
            Effective_Start__c = data.serviceDate.addYears(-1),
            Active__c = true
        );
        Fee_Schedule_Rate__c wellnessRate = new Fee_Schedule_Rate__c(
            Fee_Schedule__c = data.feeSchedule.Id,
            Procedure_Code_System__c = 'HCPCS',
            Procedure_Code__c = 'G0439',
            Procedure_Display__c = 'Annual wellness visit',
            Rate_Amount__c = 225,
            Effective_Start__c = data.serviceDate.addYears(-1),
            Active__c = true
        );
        insert new List<Fee_Schedule_Rate__c>{ data.officeRate, wellnessRate };
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
        String digits = String.valueOf(Math.abs(seed.hashCode())).leftPad(9, '0').right(9);
        return (seed.startsWith('ORG-') ? '8' : '9') + digits;
    }

    private class TestData {
        Patient__c patient;
        Practitioner__c practitioner;
        Encounter__c encounter;
        Organization__c organization;
        Payer__c payer;
        Coverage__c coverage;
        Fee_Schedule__c feeSchedule;
        Fee_Schedule_Rate__c officeRate;
        Date serviceDate;
    }
}
