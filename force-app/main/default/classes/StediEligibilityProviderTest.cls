@IsTest
private class StediEligibilityProviderTest {
    @IsTest
    static void checkCreatesActiveRecordWithParsedBenefits() {
        Fixture data = insertFixture();
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting('Stedi_Eligibility', '30')
        };
        Test.setMock(HttpCalloutMock.class, new EligibilityMock(200, activeCoverageJson()));

        EligibilityRequest req = newRequest(data);
        req.serviceType = '30';

        Test.startTest();
        EligibilityResult result = new StediEligibilityProvider().check(req);
        Test.stopTest();

        System.assertEquals('Active', result.status, 'Active 271 should map to Active');
        System.assertEquals('CHOICE PLUS (Jane Doe)', result.plan, 'Plan name should include the patient when it fits');
        System.assertEquals(25, result.copay, 'Copay should parse from benefitAmount');
        System.assertEquals(20, result.coinsurance, 'Coinsurance should parse from benefitPercent');
        System.assertEquals(1500, result.deductible, 'Deductible should use calendar-year amount');
        System.assertEquals(400, result.deductibleRemaining, 'Remaining deductible should use timeQualifier 29');
        System.assertEquals(6000, result.oop, 'OOP max should parse from code G');
        System.assertNotEquals(null, result.eligibilityCheckId, 'Successful check should persist a record');
        System.assertEquals(null, result.error, 'Successful check should have no error');

        Eligibility_Check__c stored = queryCheck(result.eligibilityCheckId);
        System.assertEquals(data.patient.Id, stored.Patient__c, 'Check should link to the patient');
        System.assertEquals(data.coverage.Id, stored.Coverage__c, 'Check should link to the coverage');
        System.assertEquals('Active', stored.Status__c, 'Persisted status should be Active');
        System.assertEquals('CHOICE PLUS (Jane Doe)', stored.Plan_Name__c, 'Persisted plan should include the patient');
        System.assertEquals(25, stored.Copay__c, 'Persisted copay should match parse');
        System.assertEquals(20, stored.Coinsurance_Percent__c, 'Persisted coinsurance should match parse');
        System.assertEquals(1500, stored.Deductible__c, 'Persisted deductible should match parse');
        System.assertEquals(400, stored.Deductible_Remaining__c, 'Persisted remaining deductible should match parse');
        System.assertEquals(6000, stored.Out_of_Pocket_Max__c, 'Persisted OOP should match parse');
        System.assertEquals('30', stored.Service_Type__c, 'Service type should be stored');
        System.assertEquals('Stedi', stored.Provider_Used__c, 'Provider used should be Stedi');
        System.assert(stored.Request_Payload__c.contains('tradingPartnerServiceId'), 'Request payload should be stored');
        System.assert(stored.Request_Payload__c.contains('KMQTZ'), 'Request should send the Stedi payer id');
        System.assert(stored.Request_Payload__c.contains('19850312'), 'Subscriber DOB should use Stedi CCYYMMDD');
        System.assert(stored.Raw_Response__c.contains('CHOICE PLUS'), 'Raw 271 JSON should be stored');
        System.assertEquals(null, stored.Error_Message__c, 'Active check should not store an error');
    }

    @IsTest
    static void checkPersistsInactiveCoverage() {
        Fixture data = insertFixture();
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting('Stedi_Eligibility', '30')
        };
        Test.setMock(HttpCalloutMock.class, new EligibilityMock(200, inactiveCoverageJson()));

        Test.startTest();
        EligibilityResult result = new StediEligibilityProvider().check(newRequest(data));
        Test.stopTest();

        System.assertEquals('Inactive', result.status, 'Inactive 271 should map to Inactive');
        Eligibility_Check__c stored = queryCheck(result.eligibilityCheckId);
        System.assertEquals('Inactive', stored.Status__c, 'Persisted status should be Inactive');
        System.assertEquals(null, stored.Error_Message__c, 'Inactive is not an error');
    }

    @IsTest
    static void checkPersistsHttpError() {
        Fixture data = insertFixture();
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting('Stedi_Eligibility', '30')
        };
        Test.setMock(HttpCalloutMock.class, new EligibilityMock(502, 'upstream unavailable'));

        Test.startTest();
        EligibilityResult result = new StediEligibilityProvider().check(newRequest(data));
        Test.stopTest();

        System.assertEquals('Error', result.status, 'Non-2xx should mark Error');
        System.assert(result.error.contains('HTTP 502'), 'HTTP status should be in the error: ' + result.error);
        Eligibility_Check__c stored = queryCheck(result.eligibilityCheckId);
        System.assertEquals('Error', stored.Status__c, 'Persisted status should be Error');
        System.assert(stored.Error_Message__c.contains('HTTP 502'), 'Error message should be stored');
        System.assertEquals('upstream unavailable', stored.Raw_Response__c, 'Error body should be stored');
    }

    @IsTest
    static void checkPersistsCalloutException() {
        Fixture data = insertFixture();
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting('Stedi_Eligibility', '30')
        };
        Test.setMock(HttpCalloutMock.class, new ThrowMock());

        Test.startTest();
        EligibilityResult result = new StediEligibilityProvider().check(newRequest(data));
        Test.stopTest();

        System.assertEquals('Error', result.status, 'Callout exception should error');
        System.assertEquals('simulated callout failure', result.error, 'Exception message should be stored');
        Eligibility_Check__c stored = queryCheck(result.eligibilityCheckId);
        System.assertEquals('Error', stored.Status__c, 'Exception should persist Status=Error');
        System.assertEquals('simulated callout failure', stored.Error_Message__c, 'Exception should persist Error_Message');
    }

    @IsTest
    static void checkMapsNonCompliantValuesWithoutThrowing() {
        Fixture data = insertFixture();
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting('Stedi_Eligibility', '30')
        };
        Test.setMock(HttpCalloutMock.class, new EligibilityMock(200, nonCompliantJson()));

        Test.startTest();
        EligibilityResult result = new StediEligibilityProvider().check(newRequest(data));
        Test.stopTest();

        System.assertEquals('Active', result.status, 'Numeric active code should still map to Active');
        System.assertEquals('Weird Plan (Jane Doe)', result.plan, 'Plan should parse from non-string-friendly payload');
        System.assertEquals(35, result.copay, 'Numeric benefitAmount should parse');
        System.assertEquals(20, result.coinsurance, 'Fractional benefitPercent should become 20');
        System.assertEquals(null, result.error, 'Unknown codes must not throw or error');
        System.assertNotEquals(null, result.eligibilityCheckId, 'Non-compliant 271 should still persist');
    }

    @IsTest
    static void checkUsesDefaultServiceTypeAndPayerFromCoverage() {
        Fixture data = insertFixture();
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting('Stedi_Eligibility', '30')
        };
        Test.setMock(HttpCalloutMock.class, new EligibilityMock(200, activeCoverageJson(), true));

        EligibilityRequest req = new EligibilityRequest();
        req.patient = data.patient.Id;
        req.coverage = data.coverage.Id;
        req.providerOrganizationName = 'Logic Clinic';
        req.providerNpi = '1999999984';

        Test.startTest();
        EligibilityResult result = new StediEligibilityProvider().check(req);
        Test.stopTest();

        System.assertEquals('Active', result.status, 'Defaulted service type should still succeed');
        Eligibility_Check__c stored = queryCheck(result.eligibilityCheckId);
        System.assertEquals('30', stored.Service_Type__c, 'Blank request service type should use the setting default');
        System.assert(stored.Request_Payload__c.contains('"30"'), 'Encounter should include default STC 30');
    }

    @IsTest
    static void checkRejectsNullRequestAndMissingNamedCredential() {
        Fixture data = insertFixture();
        StediEligibilityProvider provider = new StediEligibilityProvider();

        Test.startTest();
        EligibilityResult missingReq = provider.check(null);

        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting(null, '30')
        };
        EligibilityResult missingCredential = provider.check(newRequest(data));

        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>();
        EligibilityResult missingSetting = provider.check(newRequest(data));
        Test.stopTest();

        System.assertEquals('Error', missingReq.status, 'Null request should error');
        System.assertEquals(null, missingReq.eligibilityCheckId, 'Null request cannot persist');
        System.assert(
            missingReq.error.contains('Eligibility request is required'),
            'Null request error should be explicit: ' + missingReq.error
        );
        System.assertEquals('Error', missingCredential.status, 'Blank Named Credential should error');
        System.assertNotEquals(null, missingCredential.eligibilityCheckId, 'Missing credential should still persist');
        System.assert(
            missingCredential.error.contains('Named Credential is not configured'),
            'Missing credential error should be explicit: ' + missingCredential.error
        );
        System.assertEquals('Error', missingSetting.status, 'Missing setting should error');
        System.assert(
            missingSetting.error.contains('No active Eligibility Setting'),
            'Missing setting error should be explicit: ' + missingSetting.error
        );
        System.assertEquals(
            2,
            [SELECT COUNT() FROM Eligibility_Check__c WHERE Patient__c = :data.patient.Id],
            'Credential and setting failures with a patient should persist Error rows'
        );
    }

    @IsTest
    static void checkSurfacesMissingPayerAndProvider() {
        Fixture data = insertFixture();
        data.payer.Payer_Identifier__c = null;
        update data.payer;
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting('Stedi_Eligibility', '30')
        };

        EligibilityRequest noPayer = newRequest(data);
        noPayer.payerId = null;

        EligibilityRequest noNpi = newRequest(data);
        noNpi.payerId = 'KMQTZ';
        noNpi.providerNpi = null;
        delete data.practitioner;

        Test.startTest();
        EligibilityResult missingPayer = new StediEligibilityProvider().check(noPayer);
        EligibilityResult missingNpi = new StediEligibilityProvider().check(noNpi);
        Test.stopTest();

        System.assertEquals('Error', missingPayer.status, 'Missing payer id should error');
        System.assert(missingPayer.error.contains('Payer identifier is required'), missingPayer.error);
        System.assertEquals('Error', missingNpi.status, 'Missing NPI should error');
        System.assert(missingNpi.error.contains('Provider NPI is required'), missingNpi.error);
        System.assertEquals(
            2,
            [SELECT COUNT() FROM Eligibility_Check__c WHERE Status__c = 'Error'],
            'Validation errors should persist Error rows'
        );
    }

    @IsTest
    static void checkErrorsOnEmptyResponse() {
        Fixture data = insertFixture();
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting('Stedi_Eligibility', '30')
        };
        Test.setMock(HttpCalloutMock.class, new EligibilityMock(200, ''));

        Test.startTest();
        EligibilityResult result = new StediEligibilityProvider().check(newRequest(data));
        Test.stopTest();

        System.assertEquals('Error', result.status, 'Empty 271 should error');
        System.assertEquals('Error', queryCheck(result.eligibilityCheckId).Status__c, 'Empty body should persist Error');
    }

    @IsTest
    static void checkErrorsOnUnparseableResponse() {
        Fixture data = insertFixture();
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting('Stedi_Eligibility', '30')
        };
        Test.setMock(HttpCalloutMock.class, new EligibilityMock(200, 'not-json'));

        Test.startTest();
        EligibilityResult result = new StediEligibilityProvider().check(newRequest(data));
        Test.stopTest();

        System.assertEquals('Error', result.status, 'Non-JSON 271 should error');
        System.assert(result.error.contains('Unable to parse'), result.error);
    }

    @IsTest
    static void checkErrorsOnStediErrorsArray() {
        Fixture data = insertFixture();
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting('Stedi_Eligibility', '30')
        };
        Test.setMock(
            HttpCalloutMock.class,
            new EligibilityMock(200, '{"errors":[{"description":"Subscriber not found"}]}')
        );

        Test.startTest();
        EligibilityResult result = new StediEligibilityProvider().check(newRequest(data));
        Test.stopTest();

        System.assertEquals('Error', result.status, 'errors[] with no benefits should error');
        System.assert(result.error.contains('Subscriber not found'), result.error);
    }

    @IsTest
    static void checkMapsDeprecatedPlanStatus() {
        Fixture data = insertFixture();
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting('Stedi_Eligibility', '30')
        };
        Test.setMock(
            HttpCalloutMock.class,
            new EligibilityMock(
                200,
                '{"planStatus":[{"statusCode":"1","status":"Active Coverage","planDetails":"Basic PPO"}]}'
            )
        );

        Test.startTest();
        EligibilityResult result = new StediEligibilityProvider().check(newRequest(data));
        Test.stopTest();

        System.assertEquals('Active', result.status, 'Deprecated planStatus should still map coverage');
        System.assertEquals('Basic PPO (Jane Doe)', result.plan, 'planDetails should be used when planCoverage is absent');
    }

    @IsTest
    static void checkRejectsCoverageForAnotherPatient() {
        Fixture data = insertFixture();
        Patient__c other = new Patient__c(Last_Name__c = 'Other', MRN__c = 'MRN-ELIG-OTHER', Status__c = 'Active');
        insert other;
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting('Stedi_Eligibility', '30')
        };

        EligibilityRequest mismatch = newRequest(data);
        mismatch.patient = other.Id;

        Test.startTest();
        EligibilityResult result = new StediEligibilityProvider().check(mismatch);
        Test.stopTest();

        System.assertEquals('Error', result.status, 'Coverage for another patient should error');
        System.assert(result.error.contains('does not belong'), result.error);
    }

    @IsTest
    static void checkRejectsUnknownCoverage() {
        Fixture data = insertFixture();
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting('Stedi_Eligibility', '30')
        };

        EligibilityRequest missingCoverage = newRequest(data);
        missingCoverage.coverage =
            Coverage__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001';

        Test.startTest();
        EligibilityResult result = new StediEligibilityProvider().check(missingCoverage);
        Test.stopTest();

        System.assertEquals('Error', result.status, 'Unknown coverage Id should error');
        System.assert(result.error.contains('Coverage was not found'), result.error);
    }

    @IsTest
    static void checkSendsCommaSeparatedServiceTypes() {
        Fixture data = insertFixture();
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting('Stedi_Eligibility', '30')
        };
        Test.setMock(HttpCalloutMock.class, new EligibilityMock(200, activeCoverageJson()));

        EligibilityRequest commaTypes = newRequest(data);
        commaTypes.serviceType = '30, 98';

        Test.startTest();
        EligibilityResult result = new StediEligibilityProvider().check(commaTypes);
        Test.stopTest();

        System.assertEquals('Active', result.status, 'Comma-separated service types should still check');
        Eligibility_Check__c stored = queryCheck(result.eligibilityCheckId);
        System.assert(stored.Request_Payload__c.contains('98'), 'Both service type codes should be sent');
    }

    @IsTest
    static void checkOmitsPatientFromPlanWhenNameWouldExceedLimit() {
        Fixture data = insertFixture();
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting('Stedi_Eligibility', '30')
        };
        String longPlan = 'P'.repeat(115);
        Test.setMock(
            HttpCalloutMock.class,
            new EligibilityMock(
                200,
                '{"benefitsInformation":[{"code":"1","name":"Active Coverage","planCoverage":"' +
                    longPlan +
                    '","serviceTypeCodes":["30"]}]}'
            )
        );

        Test.startTest();
        EligibilityResult result = new StediEligibilityProvider().check(newRequest(data));
        Test.stopTest();

        System.assertEquals(longPlan, result.plan, 'Patient suffix must be omitted when it would exceed 120 characters');
        System.assertEquals(longPlan, queryCheck(result.eligibilityCheckId).Plan_Name__c, 'Stored plan should stay within 120');
    }

    @IsTest
    static void checkLoadsPatientWhenCoverageIsOmitted() {
        Fixture data = insertFixture();
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting('Stedi_Eligibility', '30')
        };
        Test.setMock(HttpCalloutMock.class, new EligibilityMock(200, activeCoverageJson()));

        EligibilityRequest req = newRequest(data);
        req.coverage = null;

        Test.startTest();
        EligibilityResult result = new StediEligibilityProvider().check(req);
        Test.stopTest();

        System.assertEquals('Active', result.status, 'Patient-only request should still check');
        Eligibility_Check__c stored = queryCheck(result.eligibilityCheckId);
        System.assertEquals(null, stored.Coverage__c, 'Omitted coverage should not be stamped');
        System.assert(stored.Request_Payload__c.contains('Jane'), 'Subscriber first name should come from Patient');
    }

    @IsTest
    static void searchPayersReturnsStediIdsFromNamedCredential() {
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting('Stedi_Eligibility', '30')
        };
        Test.setMock(HttpCalloutMock.class, new PayerSearchMock(200, payerSearchJson()));

        Test.startTest();
        List<EligibilityPayerMatch> matches = new StediEligibilityProvider().searchPayers('United');
        List<EligibilityPayerMatch> blank = new StediEligibilityProvider().searchPayers('');
        Test.stopTest();

        System.assertEquals(2, matches.size(), 'Mocked payer search should return both items');
        System.assertEquals('KMQTZ', matches[0].payerId, 'payerId should be the Stedi id');
        System.assertEquals('UnitedHealthcare', matches[0].name, 'name should be displayName');
        System.assertEquals('GUFCO', matches[1].payerId, 'Second Stedi id should parse');
        System.assertEquals(0, blank.size(), 'Blank query should not call out');
    }

    @IsTest
    static void searchPayersSurfacesHttpErrors() {
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting('Stedi_Eligibility', '30')
        };
        Test.setMock(HttpCalloutMock.class, new PayerSearchMock(500, '{"message":"search failed"}'));

        Boolean thrown = false;
        Test.startTest();
        try {
            new StediEligibilityProvider().searchPayers('Aetna');
        } catch (EligibilityProviderFactory.EligibilityException e) {
            thrown = e.getMessage().contains('search failed');
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'Payer search HTTP errors should throw');
    }

    @IsTest
    static void searchPayersUsesPrimaryPayerIdWhenStediIdMissing() {
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting('Stedi_Eligibility', '30')
        };
        Test.setMock(
            HttpCalloutMock.class,
            new PayerSearchMock(200, '{"items":[{"payer":{"primaryPayerId":"87726","displayName":"UHC"}}]}')
        );

        Test.startTest();
        List<EligibilityPayerMatch> matches = new StediEligibilityProvider().searchPayers('UHC');
        Test.stopTest();

        System.assertEquals(1, matches.size(), 'One payer should parse');
        System.assertEquals('87726', matches[0].payerId, 'primaryPayerId is the fallback Stedi routing id');
        System.assertEquals('UHC', matches[0].name, 'displayName should parse');
    }

    @IsTest
    static void searchPayersRequiresNamedCredential() {
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting(null, '30')
        };
        Boolean thrown = false;

        Test.startTest();
        try {
            new StediEligibilityProvider().searchPayers('Aetna');
        } catch (EligibilityProviderFactory.EligibilityException e) {
            thrown = e.getMessage().contains('Named Credential is not configured');
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'Payer search should require a Named Credential');
    }

    private static EligibilityRequest newRequest(Fixture data) {
        EligibilityRequest req = new EligibilityRequest();
        req.patient = data.patient.Id;
        req.coverage = data.coverage.Id;
        req.payerId = data.payer.Payer_Identifier__c;
        req.serviceType = '30';
        req.providerOrganizationName = 'Logic Clinic';
        req.providerNpi = '1999999984';
        return req;
    }

    private static Eligibility_Setting__mdt setting(String namedCredential, String serviceType) {
        return new Eligibility_Setting__mdt(
            Provider_Name__c = 'Stedi',
            Named_Credential__c = namedCredential,
            Default_Service_Type__c = serviceType,
            Active__c = true
        );
    }

    private static Eligibility_Check__c queryCheck(Id checkId) {
        return [
            SELECT
                Patient__c,
                Coverage__c,
                Status__c,
                Plan_Name__c,
                Copay__c,
                Coinsurance_Percent__c,
                Deductible__c,
                Deductible_Remaining__c,
                Out_of_Pocket_Max__c,
                Service_Type__c,
                Provider_Used__c,
                Request_Payload__c,
                Raw_Response__c,
                Error_Message__c
            FROM Eligibility_Check__c
            WHERE Id = :checkId
        ];
    }

    private static Fixture insertFixture() {
        Fixture data = new Fixture();
        data.patient = new Patient__c(
            First_Name__c = 'Jane',
            Last_Name__c = 'Doe',
            Date_of_Birth__c = Date.newInstance(1985, 3, 12),
            MRN__c = 'MRN-ELIG-' + String.valueOf(Crypto.getRandomInteger()),
            Status__c = 'Active'
        );
        insert data.patient;
        data.payer = new Payer__c(
            Name = 'UnitedHealthcare',
            Type__c = 'Commercial',
            Active__c = true,
            Payer_Identifier__c = 'KMQTZ'
        );
        insert data.payer;
        data.coverage = new Coverage__c(
            Patient__c = data.patient.Id,
            Payer__c = data.payer.Id,
            Member_Id__c = 'UHC202649',
            Plan_Name__c = 'Gold PPO',
            Type__c = 'Medical',
            Relationship_to_Subscriber__c = 'Self',
            Status__c = 'Active',
            Priority__c = 'Primary'
        );
        insert data.coverage;
        data.practitioner = new Practitioner__c(
            First_Name__c = 'Pat',
            Last_Name__c = 'Provider',
            NPI__c = '1' + String.valueOf(Math.abs(Math.mod(Crypto.getRandomInteger(), 1000000000))).left(9),
            Active__c = true
        );
        insert data.practitioner;
        return data;
    }

    private static String activeCoverageJson() {
        return '{"controlNumber":"123456789","benefitsInformation":[' +
            '{"code":"1","name":"Active Coverage","planCoverage":"CHOICE PLUS","serviceTypeCodes":["30"]},' +
            '{"code":"B","name":"Co-Payment","benefitAmount":"25","coverageLevelCode":"IND","inPlanNetworkIndicatorCode":"Y","serviceTypeCodes":["30"]},' +
            '{"code":"A","name":"Co-Insurance","benefitPercent":"20","coverageLevelCode":"IND","inPlanNetworkIndicatorCode":"Y","serviceTypeCodes":["30"]},' +
            '{"code":"C","name":"Deductible","benefitAmount":"1500","timeQualifierCode":"23","coverageLevelCode":"IND","inPlanNetworkIndicatorCode":"Y","serviceTypeCodes":["30"]},' +
            '{"code":"C","name":"Deductible","benefitAmount":"400","timeQualifierCode":"29","coverageLevelCode":"IND","inPlanNetworkIndicatorCode":"Y","serviceTypeCodes":["30"]},' +
            '{"code":"G","name":"Out of Pocket (Stop Loss)","benefitAmount":"6000","timeQualifierCode":"23","coverageLevelCode":"IND","inPlanNetworkIndicatorCode":"Y","serviceTypeCodes":["30"]}' +
            ']}';
    }

    private static String inactiveCoverageJson() {
        return '{"benefitsInformation":[{"code":"6","name":"Inactive","serviceTypeCodes":["30"]}]}';
    }

    private static String nonCompliantJson() {
        return '{"benefitsInformation":[' +
            '{"code":1,"name":"Active Coverage","planCoverage":"Weird Plan","serviceTypeCodes":[30]},' +
            '{"code":"ZZ","name":"NonCompliant","benefitAmount":"not-a-number"},' +
            '{"code":"B","benefitAmount":35,"inPlanNetworkIndicatorCode":"Y","coverageLevelCode":"IND","serviceTypeCodes":["30"]},' +
            '{"code":"A","benefitPercent":"0.2","inPlanNetworkIndicatorCode":"Y","coverageLevelCode":"IND","serviceTypeCodes":["30"]}' +
            ']}';
    }

    private static String payerSearchJson() {
        return '{"items":[' +
            '{"payer":{"stediId":"KMQTZ","displayName":"UnitedHealthcare","primaryPayerId":"87726"}},' +
            '{"payer":{"stediId":"GUFCO","displayName":"Highmark of Pennsylvania"}}' +
            ']}';
    }

    private class Fixture {
        Patient__c patient;
        Payer__c payer;
        Coverage__c coverage;
        Practitioner__c practitioner;
    }

    private class EligibilityMock implements HttpCalloutMock {
        Integer statusCode;
        String body;
        Boolean requireDefaultServiceType;

        EligibilityMock(Integer statusCode, String body) {
            this(statusCode, body, false);
        }

        EligibilityMock(Integer statusCode, String body, Boolean requireDefaultServiceType) {
            this.statusCode = statusCode;
            this.body = body;
            this.requireDefaultServiceType = requireDefaultServiceType;
        }

        public HttpResponse respond(HttpRequest request) {
            System.assert(
                request.getEndpoint().startsWith('callout:'),
                'Endpoint must use a Named Credential, not a hardcoded URL: ' + request.getEndpoint()
            );
            System.assert(
                !request.getEndpoint().containsIgnoreCase('stedi.com'),
                'Apex must not hardcode the Stedi host: ' + request.getEndpoint()
            );
            System.assertEquals(null, request.getHeader('Authorization'), 'Apex must not set Authorization');
            System.assertEquals('POST', request.getMethod(), 'Eligibility check should POST');
            System.assert(
                request.getEndpoint().contains('/change/medicalnetwork/eligibility/v3'),
                'Eligibility path should be /change/medicalnetwork/eligibility/v3: ' + request.getEndpoint()
            );
            System.assertEquals('application/json', request.getHeader('Content-Type'), 'JSON content type is required');
            if (requireDefaultServiceType) {
                System.assert(
                    request.getBody().contains('"30"'),
                    'Blank request service type should fall back to the setting default'
                );
            }
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(body);
            return response;
        }
    }

    private class PayerSearchMock implements HttpCalloutMock {
        Integer statusCode;
        String body;

        PayerSearchMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest request) {
            System.assert(
                request.getEndpoint().startsWith('callout:'),
                'Endpoint must use a Named Credential, not a hardcoded URL: ' + request.getEndpoint()
            );
            System.assert(
                !request.getEndpoint().containsIgnoreCase('stedi.com'),
                'Apex must not hardcode the Stedi host'
            );
            System.assertEquals(null, request.getHeader('Authorization'), 'Apex must not set Authorization');
            System.assertEquals('GET', request.getMethod(), 'Payer search should GET');
            System.assert(
                request.getEndpoint().contains('/2024-04-01/payers/search'),
                'Payer search path is required: ' + request.getEndpoint()
            );
            System.assert(request.getEndpoint().contains('query='), 'Payer search must include query');
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(body);
            return response;
        }
    }

    private class ThrowMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            throw new CalloutException('simulated callout failure');
        }
    }
}
