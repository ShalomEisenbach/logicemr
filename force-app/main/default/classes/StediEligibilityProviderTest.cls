@IsTest
private class StediEligibilityProviderTest {
    @IsTest
    static void checkPostsThroughNamedCredentialAndReturnsActive() {
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting('Stedi_Eligibility', '30')
        };
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        EligibilityRequest req = new EligibilityRequest();
        req.patient = UserInfo.getUserId();
        req.coverage = UserInfo.getUserId();
        req.payerId = 'STEDI-PAYER';
        req.serviceType = '30';

        Test.startTest();
        EligibilityResult result = new StediEligibilityProvider().check(req);
        Test.stopTest();

        System.assertEquals('Active', result.status, 'HTTP 200 should mark the check Active');
        System.assertEquals('{"eligible":true}', result.rawResponse, 'Raw response should be stored');
        System.assertEquals(null, result.error, 'Successful callout should have no error');
    }

    @IsTest
    static void checkUsesDefaultServiceTypeAndSurfacesHttpErrors() {
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting('Stedi_Eligibility', '30')
        };
        Test.setMock(HttpCalloutMock.class, new FailureMock());

        EligibilityRequest req = new EligibilityRequest();
        req.payerId = 'STEDI-PAYER';

        Test.startTest();
        EligibilityResult result = new StediEligibilityProvider().check(req);
        Test.stopTest();

        System.assertEquals('Error', result.status, 'Non-2xx should mark the check Error');
        System.assertEquals('HTTP 502', result.error, 'HTTP status should be in the error');
        System.assertEquals('upstream unavailable', result.rawResponse, 'Error body should be stored');
    }

    @IsTest
    static void checkRejectsNullRequestAndMissingNamedCredential() {
        StediEligibilityProvider provider = new StediEligibilityProvider();

        Test.startTest();
        EligibilityResult missingReq = provider.check(null);

        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting(null, '30')
        };
        EligibilityResult missingCredential = provider.check(new EligibilityRequest());

        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>();
        EligibilityResult missingSetting = provider.check(new EligibilityRequest());
        Test.stopTest();

        System.assertEquals('Error', missingReq.status, 'Null request should error');
        System.assert(
            missingReq.error.contains('Eligibility request is required'),
            'Null request error should be explicit: ' + missingReq.error
        );
        System.assertEquals('Error', missingCredential.status, 'Blank Named Credential should error');
        System.assert(
            missingCredential.error.contains('Named Credential is not configured'),
            'Missing credential error should be explicit: ' + missingCredential.error
        );
        System.assertEquals('Error', missingSetting.status, 'Missing setting should error');
        System.assert(
            missingSetting.error.contains('No active Eligibility Setting'),
            'Missing setting error should be explicit: ' + missingSetting.error
        );
    }

    @IsTest
    static void checkSurfacesCalloutExceptions() {
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
            setting('Stedi_Eligibility', '30')
        };
        Test.setMock(HttpCalloutMock.class, new ThrowMock());

        Test.startTest();
        EligibilityResult result = new StediEligibilityProvider().check(new EligibilityRequest());
        Test.stopTest();

        System.assertEquals('Error', result.status, 'Callout exception should error');
        System.assertEquals('simulated callout failure', result.error, 'Exception message should be stored');
    }

    private static Eligibility_Setting__mdt setting(String namedCredential, String serviceType) {
        return new Eligibility_Setting__mdt(
            Provider_Name__c = 'Stedi',
            Named_Credential__c = namedCredential,
            Default_Service_Type__c = serviceType,
            Active__c = true
        );
    }

    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            System.assert(
                request.getEndpoint().startsWith('callout:'),
                'Endpoint must use a Named Credential, not a hardcoded URL: ' + request.getEndpoint()
            );
            System.assertEquals(null, request.getHeader('Authorization'), 'Apex must not set Authorization');
            System.assertEquals('POST', request.getMethod(), 'Eligibility check should POST');
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('{"eligible":true}');
            return response;
        }
    }

    private class FailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            System.assert(
                request.getBody().contains('"serviceType":"30"'),
                'Blank request service type should fall back to the setting default'
            );
            HttpResponse response = new HttpResponse();
            response.setStatusCode(502);
            response.setBody('upstream unavailable');
            return response;
        }
    }

    private class ThrowMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            throw new CalloutException('simulated callout failure');
        }
    }
}
