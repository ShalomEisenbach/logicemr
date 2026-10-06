trigger ClaimSubmissionTrigger on Claim_Submission__c(before update) {
  for (Claim_Submission__c row : Trigger.new) {
    Claim_Submission__c previous = Trigger.oldMap.get(row.Id);
    if (
      row.Canonical_Payload__c != previous.Canonical_Payload__c ||
      row.Submission_Config__c != previous.Submission_Config__c ||
      row.Idempotency_Key__c != previous.Idempotency_Key__c ||
      row.Patient_Control_Number__c != previous.Patient_Control_Number__c ||
      row.Superbill__c != previous.Superbill__c ||
      row.Provider_Used__c != previous.Provider_Used__c
    ) {
      row.addError(
        'Submission payload, configuration, and claim identifiers are immutable. Create a new submission for a corrected claim.'
      );
    }
  }
}
