public with sharing class ClaimSubmissionController {
    private static final String MANAGE_CLAIMS_PERMISSION = 'LogicEMR_Manage_Claims';
    @TestVisible private static Boolean manageClaimsOverride;

    @AuraEnabled(cacheable=true)
    public static List<Claim_Submission__c> getSubmissions(Id superbillId) {
        requireManageClaims();
        if (superbillId == null) throw auraError('Superbill Id is required.');
        return [
            SELECT Id, Name, Superbill__c, Status__c, Attempt_Number__c,
                   Patient_Control_Number__c, Provider_Used__c, Http_Status_Code__c,
                   Provider_Status__c, Correlation_Id__c, Clearinghouse_Claim_Id__c,
                   Control_Number__c, Queued_At__c, Last_Attempt_At__c,
                   Submitted_At__c, Error_Message__c
            FROM Claim_Submission__c
            WHERE Superbill__c = :superbillId
            ORDER BY CreatedDate DESC
            LIMIT 25
        ];
    }

    @AuraEnabled
    public static Claim_Submission__c queueSubmission(Id superbillId) {
        requireManageClaims();
        try {
            return ClaimSubmissionService.queue(superbillId);
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    @AuraEnabled
    public static Claim_Submission__c retrySubmission(Id submissionId) {
        requireManageClaims();
        try {
            return ClaimSubmissionService.retry(submissionId);
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    private static void requireManageClaims() {
        Boolean allowed = manageClaimsOverride != null
            ? manageClaimsOverride
            : FeatureManagement.checkPermission(MANAGE_CLAIMS_PERMISSION);
        if (!allowed) throw auraError('You do not have permission to submit LogicEMR claims.');
    }

    private static AuraHandledException auraError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
