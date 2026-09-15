public with sharing class ClaimSubmissionProviderFactory {
    public class ClaimSubmissionException extends Exception {
    }

    @TestVisible
    static List<Claim_Submission_Setting__mdt> settingsOverride;

    public static ClaimSubmissionConfig getActiveConfig() {
        List<Claim_Submission_Setting__mdt> rows = settingsOverride != null
            ? settingsOverride
            : [
                  SELECT Provider_Name__c, Named_Credential__c, Usage_Indicator__c,
                         Submitter_Name__c, Submitter_Identifier__c, Contact_Name__c,
                         Contact_Phone__c, Active__c
                  FROM Claim_Submission_Setting__mdt
                  WHERE Active__c = TRUE
                  ORDER BY Provider_Name__c
                  LIMIT 1
              ];
        if (rows.isEmpty()) {
            throw new ClaimSubmissionException('No active Claim Submission Setting found.');
        }
        Claim_Submission_Setting__mdt row = rows[0];
        ClaimSubmissionConfig config = new ClaimSubmissionConfig();
        config.providerName = row.Provider_Name__c;
        config.namedCredential = row.Named_Credential__c;
        config.usageIndicator = row.Usage_Indicator__c;
        config.submitterName = row.Submitter_Name__c;
        config.submitterIdentifier = row.Submitter_Identifier__c;
        config.contactName = row.Contact_Name__c;
        config.contactPhone = row.Contact_Phone__c;
        config.validate();
        return config;
    }

    public static ClaimSubmissionProvider getProvider(String providerName) {
        if (String.isBlank(providerName) || providerName.equalsIgnoreCase('Stedi')) {
            return new StediClaimSubmissionProvider();
        }
        Type providerType = Type.forName(providerName);
        if (providerType == null) {
            throw new ClaimSubmissionException('Unknown claim submission provider: ' + providerName);
        }
        Object instance = providerType.newInstance();
        if (!(instance instanceof ClaimSubmissionProvider)) {
            throw new ClaimSubmissionException('Class is not a ClaimSubmissionProvider: ' + providerName);
        }
        return (ClaimSubmissionProvider) instance;
    }
}
