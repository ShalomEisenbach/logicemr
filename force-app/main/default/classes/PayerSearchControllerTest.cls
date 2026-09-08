@IsTest
private class PayerSearchControllerTest {
    @IsTest
    static void searchPayersReturnsStediMatches() {
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{ activeSetting() };
        Test.setMock(HttpCalloutMock.class, new PayerSearchMock(200, payerSearchJson()));

        Test.startTest();
        List<EligibilityPayerMatch> matches = PayerSearchController.searchPayers('United');
        List<EligibilityPayerMatch> blank = PayerSearchController.searchPayers('');
        Test.stopTest();

        System.assertEquals(2, matches.size(), 'Mocked payer search should return both items');
        System.assertEquals('KMQTZ', matches[0].payerId, 'First Stedi id should parse');
        System.assertEquals('UnitedHealthcare', matches[0].name, 'First display name should parse');
        System.assertEquals('GUFCO', matches[1].payerId, 'Second Stedi id should parse');
        System.assertEquals(0, blank.size(), 'Blank query should not call out');
    }

    @IsTest
    static void searchPayersSurfacesHttpErrors() {
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{ activeSetting() };
        Test.setMock(HttpCalloutMock.class, new PayerSearchMock(500, '{"message":"search failed"}'));
        Boolean thrown = false;

        Test.startTest();
        try {
            PayerSearchController.searchPayers('Aetna');
        } catch (AuraHandledException e) {
            thrown = e.getMessage().contains('search failed');
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'HTTP search errors should surface to the LWC');
    }

    @IsTest
    static void getAndSavePayerIdentifier() {
        Payer__c payer = new Payer__c(Name = 'Aetna', Type__c = 'Commercial', Active__c = true);
        insert payer;

        Test.startTest();
        Payer__c loaded = PayerSearchController.getPayer(payer.Id);
        Payer__c saved = PayerSearchController.savePayerIdentifier(payer.Id, '  KMQTZ  ');
        Test.stopTest();

        System.assertEquals(null, loaded.Payer_Identifier__c, 'New payer should have no Stedi id');
        System.assertEquals('KMQTZ', saved.Payer_Identifier__c, 'Save should trim and store the Stedi id');
        System.assertEquals(
            'KMQTZ',
            [SELECT Payer_Identifier__c FROM Payer__c WHERE Id = :payer.Id].Payer_Identifier__c,
            'Payer record should persist the Stedi id'
        );
    }

    @IsTest
    static void getAndSaveValidateInputs() {
        Boolean missingPayerGet = false;
        Boolean unknownPayerGet = false;
        Boolean missingPayerSave = false;
        Boolean missingIdSave = false;
        Boolean unknownPayerSave = false;

        Test.startTest();
        try {
            PayerSearchController.getPayer(null);
        } catch (AuraHandledException e) {
            missingPayerGet = e.getMessage().contains('Payer Id is required');
        }
        try {
            PayerSearchController.getPayer(UserInfo.getUserId());
        } catch (AuraHandledException e) {
            unknownPayerGet = e.getMessage().contains('Payer was not found');
        }
        try {
            PayerSearchController.savePayerIdentifier(null, 'KMQTZ');
        } catch (AuraHandledException e) {
            missingPayerSave = e.getMessage().contains('Payer Id is required');
        }
        try {
            PayerSearchController.savePayerIdentifier(UserInfo.getUserId(), '   ');
        } catch (AuraHandledException e) {
            missingIdSave = e.getMessage().contains('Stedi payer id is required');
        }
        try {
            PayerSearchController.savePayerIdentifier(UserInfo.getUserId(), 'KMQTZ');
        } catch (AuraHandledException e) {
            unknownPayerSave = e.getMessage().contains('Payer was not found');
        }
        Test.stopTest();

        System.assertEquals(true, missingPayerGet, 'Null payer get should throw');
        System.assertEquals(true, unknownPayerGet, 'Unknown payer get should throw');
        System.assertEquals(true, missingPayerSave, 'Null payer save should throw');
        System.assertEquals(true, missingIdSave, 'Blank Stedi id should throw');
        System.assertEquals(true, unknownPayerSave, 'Unknown payer save should throw');
    }

    private static Eligibility_Setting__mdt activeSetting() {
        return new Eligibility_Setting__mdt(
            Provider_Name__c = 'Stedi',
            Named_Credential__c = 'Stedi_Eligibility',
            Default_Service_Type__c = '30',
            Active__c = true
        );
    }

    private static String payerSearchJson() {
        return '{"items":[' +
            '{"payer":{"stediId":"KMQTZ","displayName":"UnitedHealthcare","primaryPayerId":"87726"}},' +
            '{"payer":{"stediId":"GUFCO","displayName":"Highmark of Pennsylvania"}}' +
            ']}';
    }

    private class PayerSearchMock implements HttpCalloutMock {
        Integer statusCode;
        String body;

        PayerSearchMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest request) {
            System.assert(request.getEndpoint().contains('/payers/search'), request.getEndpoint());
            System.assertEquals(null, request.getHeader('Authorization'));
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(body);
            return response;
        }
    }
}
