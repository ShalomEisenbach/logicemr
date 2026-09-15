@IsTest
private class ClaimSubmissionServiceTest {
    @IsTest
    static void queuesAndSubmitsProfessionalClaim() {
        TestData data = createReadyClaim('Spouse');
        configureSubmission();
        ClaimSubmissionController.manageClaimsOverride = true;
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Claim_Submission__c queued;
        Test.startTest();
        queued = ClaimSubmissionController.queueSubmission(data.superbill.Id);
        Test.stopTest();

        Claim_Submission__c stored = ClaimSubmissionService.getById(queued.Id);
        Superbill__c superbill = [SELECT Status__c FROM Superbill__c WHERE Id = :data.superbill.Id];
        System.assertEquals('Submitted', stored.Status__c);
        System.assertEquals(1, stored.Attempt_Number__c);
        System.assertEquals(200, stored.Http_Status_Code__c);
        System.assertEquals('SUCCESS', stored.Provider_Status__c);
        System.assertEquals('CORR-100', stored.Correlation_Id__c);
        System.assertEquals('RH-100', stored.Clearinghouse_Claim_Id__c);
        System.assertEquals('CN-100', stored.Control_Number__c);
        System.assertNotEquals(null, stored.Submitted_At__c);
        System.assert(stored.Request_Payload__c.contains('"claimFilingCode":"CI"'));
        System.assert(stored.Request_Payload__c.contains('"placeOfServiceCode":"11"'));
        System.assert(stored.Request_Payload__c.contains('"dependent"'));
        System.assertEquals('Exported', superbill.Status__c, 'Successful handoff must mark the claim Exported');
        System.assertEquals(1, ClaimSubmissionController.getSubmissions(data.superbill.Id).size());
    }

    @IsTest
    static void clearinghouseRejectionRemainsCorrectable() {
        TestData data = createReadyClaim('Self');
        configureSubmission();
        Test.setMock(HttpCalloutMock.class, new RejectionMock());

        Test.startTest();
        Claim_Submission__c queued = ClaimSubmissionService.queue(data.superbill.Id);
        Test.stopTest();

        Claim_Submission__c stored = ClaimSubmissionService.getById(queued.Id);
        System.assertEquals('Rejected', stored.Status__c);
        System.assert(stored.Error_Message__c.contains('Invalid claim filing code'));
        System.assertEquals(
            'Ready',
            [SELECT Status__c FROM Superbill__c WHERE Id = :data.superbill.Id].Status__c,
            'Rejected claims remain Ready so billing can reopen and correct them'
        );
    }

    @IsTest
    static void failedTransportCanBeRetriedWithSameIdempotencyKey() {
        TestData data = createReadyClaim('Self');
        configureSubmission();
        Claim_Submission__c submission = new Claim_Submission__c(
            Superbill__c = data.superbill.Id,
            Status__c = 'Failed',
            Attempt_Number__c = 1,
            Idempotency_Key__c = 'IDEMPOTENCY-RETRY-1',
            Patient_Control_Number__c = 'PCNRETRY000000001',
            Provider_Used__c = 'Stedi',
            Error_Message__c = 'Timed out'
        );
        insert submission;
        ClaimSubmissionService.skipEnqueue = true;
        ClaimSubmissionController.manageClaimsOverride = true;

        Claim_Submission__c retried = ClaimSubmissionController.retrySubmission(submission.Id);

        Claim_Submission__c stored = [
            SELECT Status__c, Idempotency_Key__c, Patient_Control_Number__c, Async_Job_Id__c
            FROM Claim_Submission__c WHERE Id = :retried.Id
        ];
        System.assertEquals('Queued', stored.Status__c);
        System.assertEquals('IDEMPOTENCY-RETRY-1', stored.Idempotency_Key__c);
        System.assertEquals('PCNRETRY000000001', stored.Patient_Control_Number__c);
        System.assertNotEquals(null, stored.Async_Job_Id__c);
    }

    @IsTest
    static void blocksDuplicatePendingSubmissionAndUnauthorizedControllerAccess() {
        TestData data = createReadyClaim('Self');
        configureSubmission();
        insert new Claim_Submission__c(
            Superbill__c = data.superbill.Id,
            Status__c = 'Queued',
            Attempt_Number__c = 0,
            Idempotency_Key__c = 'DUPLICATE-PENDING-KEY',
            Patient_Control_Number__c = 'PCNDUPLICATE00001',
            Provider_Used__c = 'Stedi'
        );
        ClaimSubmissionController.manageClaimsOverride = true;
        Boolean duplicateBlocked = false;
        try {
            ClaimSubmissionController.queueSubmission(data.superbill.Id);
        } catch (AuraHandledException e) {
            duplicateBlocked = e.getMessage().contains('already has a queued submission');
        }
        System.assertEquals(true, duplicateBlocked);

        ClaimSubmissionController.manageClaimsOverride = false;
        Boolean permissionBlocked = false;
        try {
            ClaimSubmissionController.getSubmissions(data.superbill.Id);
        } catch (AuraHandledException e) {
            permissionBlocked = e.getMessage().contains('permission');
        }
        System.assertEquals(true, permissionBlocked);
    }

    @IsTest
    static void providerFactoryValidatesSettingsAndAdapterTypes() {
        ClaimSubmissionProvider stedi = ClaimSubmissionProviderFactory.getProvider('stedi');
        System.assert(stedi instanceof StediClaimSubmissionProvider);

        Boolean unknownBlocked = false;
        try {
            ClaimSubmissionProviderFactory.getProvider('NoSuchClaimAdapter');
        } catch (ClaimSubmissionProviderFactory.ClaimSubmissionException e) {
            unknownBlocked = e.getMessage().contains('Unknown');
        }
        System.assertEquals(true, unknownBlocked);

        Boolean wrongTypeBlocked = false;
        try {
            ClaimSubmissionProviderFactory.getProvider('ClaimSubmissionResult');
        } catch (ClaimSubmissionProviderFactory.ClaimSubmissionException e) {
            wrongTypeBlocked = e.getMessage().contains('not a ClaimSubmissionProvider');
        }
        System.assertEquals(true, wrongTypeBlocked);

        ClaimSubmissionProviderFactory.settingsOverride = new List<Claim_Submission_Setting__mdt>();
        Boolean missingSettingBlocked = false;
        try {
            ClaimSubmissionProviderFactory.getActiveConfig();
        } catch (ClaimSubmissionProviderFactory.ClaimSubmissionException e) {
            missingSettingBlocked = e.getMessage().contains('No active');
        }
        System.assertEquals(true, missingSettingBlocked);

        ClaimSubmissionProviderFactory.settingsOverride = new List<Claim_Submission_Setting__mdt>{
            new Claim_Submission_Setting__mdt(
                Provider_Name__c = 'Stedi', Named_Credential__c = null,
                Usage_Indicator__c = 'T', Submitter_Name__c = 'Billing',
                Contact_Name__c = 'Office', Contact_Phone__c = '5552223333', Active__c = true
            )
        };
        Boolean invalidSettingBlocked = false;
        try {
            ClaimSubmissionProviderFactory.getActiveConfig();
        } catch (ClaimSubmissionProviderFactory.ClaimSubmissionException e) {
            invalidSettingBlocked = e.getMessage().contains('Named Credential');
        }
        System.assertEquals(true, invalidSettingBlocked);
    }

    @IsTest
    static void mapperRejectsX12ReservedCharacters() {
        TestData data = createReadyClaim('Self');
        VendorNeutralClaim claim = ClaimExportService.build(data.superbill.Id);
        claim.payer.name = 'Bad:Payer';
        ClaimSubmissionConfig config = testConfig();
        Boolean blocked = false;
        try {
            Stedi837PMapper.serialize(claim, config, 'PCN12345678901234');
        } catch (ClaimSubmissionProviderFactory.ClaimSubmissionException e) {
            blocked = e.getMessage().contains('reserved character');
        }
        System.assertEquals(true, blocked);
    }

    private static void configureSubmission() {
        ClaimSubmissionConfig config = testConfig();
        ClaimSubmissionProviderFactory.settingsOverride = new List<Claim_Submission_Setting__mdt>{
            new Claim_Submission_Setting__mdt(
                Provider_Name__c = config.providerName,
                Named_Credential__c = config.namedCredential,
                Usage_Indicator__c = config.usageIndicator,
                Submitter_Name__c = config.submitterName,
                Submitter_Identifier__c = config.submitterIdentifier,
                Contact_Name__c = config.contactName,
                Contact_Phone__c = config.contactPhone,
                Active__c = true
            )
        };
    }

    private static ClaimSubmissionConfig testConfig() {
        ClaimSubmissionConfig config = new ClaimSubmissionConfig();
        config.providerName = 'Stedi';
        config.namedCredential = 'Stedi_Claims';
        config.usageIndicator = 'T';
        config.submitterName = 'LogicEMR Billing';
        config.submitterIdentifier = 'SUBMITTER-1';
        config.contactName = 'Billing Office';
        config.contactPhone = '555-222-3333';
        return config;
    }

    private static TestData createReadyClaim(String relationship) {
        TestData data = new TestData();
        Date serviceDate = Date.newInstance(2026, 9, 15);
        Patient__c patient = new Patient__c(
            MRN__c = 'MRN-SUB-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            First_Name__c = 'Jamie', Last_Name__c = 'Patient',
            Date_of_Birth__c = Date.newInstance(1990, 1, 2), Sex_at_Birth__c = 'Female'
        );
        insert patient;
        Practitioner__c practitioner = new Practitioner__c(
            First_Name__c = 'Pat', Last_Name__c = 'Provider', NPI__c = '1999999984',
            Taxonomy_Code__c = '207Q00000X'
        );
        insert practitioner;
        Organization__c organization = new Organization__c(
            Name = 'Logic Clinic', NPI__c = '1888888875', EIN__c = '12-3456789',
            Taxonomy_Code__c = '261QP2300X', Street__c = '100 Clinic Ave', City__c = 'Boston',
            State__c = 'MA', Postal_Code__c = '02108', Country__c = 'US', Active__c = true
        );
        insert organization;
        Payer__c payer = new Payer__c(
            Name = 'Test Payer', Type__c = 'Commercial', Payer_Identifier__c = '60054', Active__c = true
        );
        insert payer;
        Coverage__c coverage = new Coverage__c(
            Patient__c = patient.Id, Payer__c = payer.Id, Member_Id__c = 'MEMBER-100',
            Relationship_to_Subscriber__c = relationship, Status__c = 'Active', Priority__c = 'Primary'
        );
        insert coverage;
        Encounter__c encounter = new Encounter__c(
            Patient__c = patient.Id, Practitioner__c = practitioner.Id, Status__c = 'Finished',
            Class__c = 'Outpatient', Start__c = Datetime.newInstance(serviceDate, Time.newInstance(9, 0, 0, 0))
        );
        insert encounter;

        data.superbill = new Superbill__c(
            Encounter__c = encounter.Id, Encounter_Key__c = String.valueOf(encounter.Id),
            Patient__c = patient.Id, Coverage__c = coverage.Id,
            Rendering_Practitioner__c = practitioner.Id, Billing_Organization__c = organization.Id,
            Date_of_Service__c = serviceDate, Place_of_Service_Code__c = '11', Status__c = 'Ready',
            Ready_Date__c = Datetime.now(), Snapshot_Refreshed_At__c = Datetime.now(), Snapshot_Version__c = 1,
            Patient_First_Name__c = 'Jamie', Patient_Last_Name__c = 'Patient',
            Patient_Date_of_Birth__c = Date.newInstance(1990, 1, 2), Patient_Sex__c = 'Female',
            Patient_Street__c = '1 Patient St', Patient_City__c = 'Boston', Patient_State__c = 'MA',
            Patient_Postal_Code__c = '02108', Patient_Country__c = 'US',
            Subscriber_First_Name__c = relationship == 'Self' ? 'Jamie' : 'Sam',
            Subscriber_Last_Name__c = relationship == 'Self' ? 'Patient' : 'Subscriber',
            Subscriber_Date_of_Birth__c = relationship == 'Self' ? Date.newInstance(1990, 1, 2) : Date.newInstance(1980, 5, 6),
            Subscriber_Sex__c = relationship == 'Self' ? 'Female' : 'Male',
            Subscriber_Relationship__c = relationship, Subscriber_Member_Id__c = 'MEMBER-100',
            Subscriber_Group_Number__c = 'GROUP-1', Subscriber_Street__c = '2 Subscriber St',
            Subscriber_City__c = 'Boston', Subscriber_State__c = 'MA',
            Subscriber_Postal_Code__c = '02109', Subscriber_Country__c = 'US',
            Payer_Name__c = 'Test Payer', Payer_Identifier__c = '60054', Claim_Filing_Code__c = 'CI',
            Rendering_Provider_Name__c = 'Pat Provider', Rendering_Provider_First_Name__c = 'Pat',
            Rendering_Provider_Last_Name__c = 'Provider', Rendering_Provider_NPI__c = '1999999984',
            Rendering_Provider_Taxonomy__c = '207Q00000X', Billing_Provider_Name__c = 'Logic Clinic',
            Billing_Provider_NPI__c = '1888888875', Billing_Provider_EIN__c = '12-3456789',
            Billing_Provider_Taxonomy__c = '261QP2300X', Billing_Provider_Street__c = '100 Clinic Ave',
            Billing_Provider_City__c = 'Boston', Billing_Provider_State__c = 'MA',
            Billing_Provider_Postal_Code__c = '02108', Billing_Provider_Country__c = 'US'
        );
        insert data.superbill;
        insert new Superbill_Diagnosis__c(
            Superbill__c = data.superbill.Id, Sequence__c = 1, Diagnosis_Type__c = 'Principal',
            Diagnosis_Code_System__c = 'ICD-10', Diagnosis_Code__c = 'J06.9', Diagnosis_Display__c = 'Acute URI'
        );
        insert new Charge_Line__c(
            Superbill__c = data.superbill.Id, Procedure_Code_System__c = 'CPT', Procedure_Code__c = '99213',
            Procedure_Display__c = 'Office visit', Service_Date__c = serviceDate, Units__c = 1,
            Applied_Unit_Rate__c = 175, Charge_Amount__c = 175, Diagnosis_Pointers__c = '1',
            Rate_Source__c = 'Frozen contract rate', Rate_Override__c = false
        );
        return data;
    }

    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            System.assertEquals('POST', request.getMethod());
            System.assertEquals(
                'callout:Stedi_Claims/2024-04-01/change/medicalnetwork/professionalclaims/v3/submission',
                request.getEndpoint()
            );
            System.assertEquals(null, request.getHeader('Authorization'));
            System.assert(String.isNotBlank(request.getHeader('Idempotency-Key')));
            System.assert(request.getBody().contains('"usageIndicator":"T"'));
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('{"status":"SUCCESS","controlNumber":"CN-100","claimReference":{"correlationId":"CORR-100","rhclaimNumber":"RH-100"}}');
            return response;
        }
    }

    private class RejectionMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(400);
            response.setBody('{"status":"ERROR","errors":[{"description":"Invalid claim filing code","location":"claimInformation.claimFilingCode"}]}');
            return response;
        }
    }

    private class TestData {
        Superbill__c superbill;
    }
}
