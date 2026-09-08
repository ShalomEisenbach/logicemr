public with sharing class EligibilityService {
    public static Eligibility_Check__c runCheck(Id patientId, Id coverageId, String serviceType) {
        if (patientId == null) {
            throw new EligibilityProviderFactory.EligibilityException('Patient Id is required.');
        }
        List<Patient__c> patients = [
            SELECT Id
            FROM Patient__c
            WHERE Id = :patientId
            LIMIT 1
        ];
        if (patients.isEmpty()) {
            throw new EligibilityProviderFactory.EligibilityException('Patient was not found.');
        }

        EligibilityRequest req = new EligibilityRequest();
        req.patient = patientId;
        req.coverage = coverageId;
        req.serviceType = serviceType;

        EligibilityResult result = EligibilityProviderFactory.getProvider().check(req);
        if (result == null || result.eligibilityCheckId == null) {
            String message = result != null && String.isNotBlank(result.error)
                ? result.error
                : 'Eligibility check did not persist a result.';
            throw new EligibilityProviderFactory.EligibilityException(message);
        }

        List<Eligibility_Check__c> rows = [
            SELECT
                Id,
                Name,
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
                Checked_Date__c,
                Provider_Used__c,
                Request_Payload__c,
                Raw_Response__c,
                Error_Message__c
            FROM Eligibility_Check__c
            WHERE Id = :result.eligibilityCheckId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new EligibilityProviderFactory.EligibilityException('Eligibility check record was not found.');
        }
        return rows[0];
    }
}
