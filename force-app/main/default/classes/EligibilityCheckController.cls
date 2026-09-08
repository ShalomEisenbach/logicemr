public with sharing class EligibilityCheckController {
    private static final Integer MAX_CHECKS = 50;
    private static final String RUN_ELIGIBILITY_PERMISSION = 'LogicEMR_Run_Eligibility';

    @TestVisible
    static Boolean runEligibilityOverride;

    @AuraEnabled(cacheable=true)
    public static List<Eligibility_Check__c> getChecks(Id coverageId) {
        if (coverageId == null) {
            return new List<Eligibility_Check__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Status__c,
                Plan_Name__c,
                Copay__c,
                Deductible__c,
                Deductible_Remaining__c,
                Coinsurance_Percent__c,
                Out_of_Pocket_Max__c,
                Service_Type__c,
                Checked_Date__c,
                Provider_Used__c,
                Error_Message__c,
                Patient__c,
                Coverage__c
            FROM Eligibility_Check__c
            WHERE Coverage__c = :coverageId
            ORDER BY Checked_Date__c DESC NULLS LAST, CreatedDate DESC
            LIMIT :MAX_CHECKS
        ];
    }

    @AuraEnabled
    public static Eligibility_Check__c runCheck(Id coverageId) {
        requireRunEligibility();
        if (coverageId == null) {
            throw auraError('Coverage Id is required.');
        }
        List<Coverage__c> coverages = [
            SELECT Id, Patient__c
            FROM Coverage__c
            WHERE Id = :coverageId
            LIMIT 1
        ];
        if (coverages.isEmpty()) {
            throw auraError('Coverage was not found.');
        }
        try {
            return EligibilityService.runCheck(coverages[0].Patient__c, coverages[0].Id, null);
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    private static void requireRunEligibility() {
        Boolean allowed = runEligibilityOverride != null
            ? runEligibilityOverride
            : FeatureManagement.checkPermission(RUN_ELIGIBILITY_PERMISSION);
        if (!allowed) {
            throw auraError('You do not have permission to run eligibility checks.');
        }
    }

    private static AuraHandledException auraError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
