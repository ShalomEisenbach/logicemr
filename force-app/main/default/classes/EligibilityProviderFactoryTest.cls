@IsTest
private class EligibilityProviderFactoryTest {
    @IsTest
    static void getProviderReturnsActiveStediProvider() {
        Test.startTest();
        EligibilityProvider provider = EligibilityProviderFactory.getProvider();
        Eligibility_Setting__mdt setting = EligibilityProviderFactory.getActiveSetting();
        Test.stopTest();

        System.assert(provider instanceof StediEligibilityProvider, 'Active packaged setting should resolve to Stedi');
        System.assertEquals('Stedi', setting.Provider_Name__c, 'Packaged setting provider name should be Stedi');
        System.assertEquals(
            'Stedi_Eligibility',
            setting.Named_Credential__c,
            'Packaged setting should reference the Stedi Named Credential'
        );
        System.assertEquals('30', setting.Default_Service_Type__c, 'Packaged default service type should be 30');
        System.assertEquals(true, setting.Active__c, 'Packaged Stedi setting should be active');
    }

    @IsTest
    static void forNameResolvesStediAliasBlankAndClassName() {
        Test.startTest();
        EligibilityProvider byAlias = EligibilityProviderFactory.forName('Stedi');
        EligibilityProvider byCase = EligibilityProviderFactory.forName('stedi');
        EligibilityProvider byBlank = EligibilityProviderFactory.forName(null);
        EligibilityProvider byClass = EligibilityProviderFactory.forName('StediEligibilityProvider');
        Test.stopTest();

        System.assert(byAlias instanceof StediEligibilityProvider, 'Stedi alias should return Stedi provider');
        System.assert(byCase instanceof StediEligibilityProvider, 'Provider name should be case-insensitive');
        System.assert(byBlank instanceof StediEligibilityProvider, 'Blank name should default to Stedi');
        System.assert(byClass instanceof StediEligibilityProvider, 'Class name should instantiate via Type.forName');
    }

    @IsTest
    static void forNameRejectsUnknownAndNonProviderTypes() {
        Boolean unknownThrown = false;
        Boolean nonProviderThrown = false;

        Test.startTest();
        try {
            EligibilityProviderFactory.forName('NotARealEligibilityProvider');
        } catch (EligibilityProviderFactory.EligibilityException e) {
            unknownThrown = e.getMessage().contains('Unknown eligibility provider');
        }
        try {
            EligibilityProviderFactory.forName('EligibilityRequest');
        } catch (EligibilityProviderFactory.EligibilityException e) {
            nonProviderThrown = e.getMessage().contains('is not an EligibilityProvider');
        }
        Test.stopTest();

        System.assertEquals(true, unknownThrown, 'Unknown class name should throw');
        System.assertEquals(true, nonProviderThrown, 'Non-provider class should throw');
    }

    @IsTest
    static void getActiveSettingThrowsWhenNoneAreActive() {
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>();
        Boolean thrown = false;

        Test.startTest();
        try {
            EligibilityProviderFactory.getActiveSetting();
        } catch (EligibilityProviderFactory.EligibilityException e) {
            thrown = e.getMessage().contains('No active Eligibility Setting');
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'Empty settings should throw');
    }

    @IsTest
    static void wrappersHoldRequestAndResultValues() {
        EligibilityRequest req = new EligibilityRequest();
        req.patient = UserInfo.getUserId();
        req.coverage = UserInfo.getUserId();
        req.payerId = 'PAYER-1';
        req.serviceType = '30';
        req.providerOrganizationName = 'Logic Clinic';
        req.providerNpi = '1999999984';

        EligibilityResult result = new EligibilityResult();
        result.status = 'Active';
        result.plan = 'Gold PPO';
        result.copay = 25;
        result.coinsurance = 20;
        result.deductible = 1500;
        result.deductibleRemaining = 400;
        result.oop = 6000;
        result.rawResponse = '{"ok":true}';
        result.error = null;

        System.assertEquals(UserInfo.getUserId(), req.patient, 'Patient id should persist');
        System.assertEquals('PAYER-1', req.payerId, 'Payer id should persist');
        System.assertEquals('Gold PPO', result.plan, 'Plan should persist');
        System.assertEquals(25, result.copay, 'Copay should persist');
        System.assertEquals(400, result.deductibleRemaining, 'Remaining deductible should persist');
        System.assertEquals('Logic Clinic', req.providerOrganizationName, 'Provider org name should persist');
        System.assertEquals(null, result.error, 'Error should be empty on success');
    }
}
