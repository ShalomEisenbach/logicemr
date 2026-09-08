@IsTest
private class EligibilityServiceTest {
    @IsTest
    static void runCheckReturnsPersistedActiveRecord() {
        Patient__c patient = insertPatient();
        Payer__c payer = new Payer__c(
            Name = 'Aetna',
            Type__c = 'Commercial',
            Active__c = true,
            Payer_Identifier__c = '60054'
        );
        insert payer;
        Coverage__c coverage = new Coverage__c(
            Patient__c = patient.Id,
            Payer__c = payer.Id,
            Member_Id__c = 'MEM-100',
            Type__c = 'Medical',
            Status__c = 'Active',
            Priority__c = 'Primary'
        );
        insert coverage;
        insert new Practitioner__c(
            First_Name__c = 'Ada',
            Last_Name__c = 'Lovelace',
            NPI__c = '1234567893',
            Active__c = true
        );
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            new Eligibility_Setting__mdt(
                Provider_Name__c = 'Stedi',
                Named_Credential__c = 'Stedi_Eligibility',
                Default_Service_Type__c = '30',
                Active__c = true
            )
        };
        Test.setMock(HttpCalloutMock.class, new ActiveMock());

        Test.startTest();
        Eligibility_Check__c stored = EligibilityService.runCheck(patient.Id, coverage.Id, null);
        Test.stopTest();

        System.assertNotEquals(null, stored.Id, 'runCheck should return the created check');
        System.assertEquals(patient.Id, stored.Patient__c, 'Check should belong to the patient');
        System.assertEquals(coverage.Id, stored.Coverage__c, 'Check should belong to the coverage');
        System.assertEquals('Active', stored.Status__c, 'Service should return the parsed Active row');
        System.assertEquals('Gold Plan HMO (John Doe)', stored.Plan_Name__c, 'Parsed plan should include the patient');
        System.assertEquals(15, stored.Copay__c, 'Parsed copay should be queried back');
        System.assertEquals('30', stored.Service_Type__c, 'Null service type should use the setting default');
        System.assertEquals('Stedi', stored.Provider_Used__c, 'Factory should resolve the Stedi provider');
    }

    @IsTest
    static void runCheckPersistsErrorAndReturnsIt() {
        Patient__c patient = insertPatient();
        Payer__c payer = new Payer__c(
            Name = 'Cigna',
            Type__c = 'Commercial',
            Active__c = true,
            Payer_Identifier__c = '62308'
        );
        insert payer;
        Coverage__c coverage = new Coverage__c(
            Patient__c = patient.Id,
            Payer__c = payer.Id,
            Member_Id__c = 'MEM-200',
            Type__c = 'Medical',
            Status__c = 'Active'
        );
        insert coverage;
        insert new Practitioner__c(First_Name__c = 'Pat', Last_Name__c = 'Provider', NPI__c = '1999999984');
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            new Eligibility_Setting__mdt(
                Provider_Name__c = 'Stedi',
                Named_Credential__c = 'Stedi_Eligibility',
                Default_Service_Type__c = '30',
                Active__c = true
            )
        };
        Test.setMock(HttpCalloutMock.class, new ErrorMock());

        Test.startTest();
        Eligibility_Check__c stored = EligibilityService.runCheck(patient.Id, coverage.Id, '98');
        Test.stopTest();

        System.assertEquals('Error', stored.Status__c, 'HTTP failure should persist Error');
        System.assert(String.isNotBlank(stored.Error_Message__c), 'Error message should be returned');
        System.assertEquals('98', stored.Service_Type__c, 'Requested service type should be stored');
    }

    @IsTest
    static void runCheckRequiresAnExistingPatient() {
        Boolean missingThrown = false;
        Boolean unknownThrown = false;

        Test.startTest();
        try {
            EligibilityService.runCheck(null, null, '30');
        } catch (EligibilityProviderFactory.EligibilityException e) {
            missingThrown = e.getMessage().contains('Patient Id is required');
        }
        try {
            EligibilityService.runCheck(UserInfo.getUserId(), null, '30');
        } catch (EligibilityProviderFactory.EligibilityException e) {
            unknownThrown = e.getMessage().contains('Patient was not found');
        }
        Test.stopTest();

        System.assertEquals(true, missingThrown, 'Null patient should throw');
        System.assertEquals(true, unknownThrown, 'Unknown patient Id should throw');
    }

    private static Patient__c insertPatient() {
        Patient__c patient = new Patient__c(
            First_Name__c = 'John',
            Last_Name__c = 'Doe',
            Date_of_Birth__c = Date.newInstance(1970, 1, 1),
            MRN__c = 'MRN-SVC-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            Status__c = 'Active'
        );
        insert patient;
        return patient;
    }

    private class ActiveMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            System.assert(request.getEndpoint().startsWith('callout:'), request.getEndpoint());
            System.assertEquals(null, request.getHeader('Authorization'));
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody(
                '{"benefitsInformation":[' +
                    '{"code":"1","name":"Active Coverage","planCoverage":"Gold Plan HMO","serviceTypeCodes":["30"]},' +
                    '{"code":"B","benefitAmount":"15","inPlanNetworkIndicatorCode":"Y","serviceTypeCodes":["30"]}' +
                    ']}'
            );
            return response;
        }
    }

    private class ErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(400);
            response.setBody('{"errors":[{"description":"Invalid subscriber"}]}');
            return response;
        }
    }
}
