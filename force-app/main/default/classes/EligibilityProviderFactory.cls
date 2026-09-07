public with sharing class EligibilityProviderFactory {
    public class EligibilityException extends Exception {
    }

    @TestVisible
    static List<Eligibility_Setting__mdt> settingsOverride;

    public static EligibilityProvider getProvider() {
        return forName(getActiveSetting().Provider_Name__c);
    }

    public static Eligibility_Setting__mdt getActiveSetting() {
        List<Eligibility_Setting__mdt> rows = settingsOverride != null
            ? settingsOverride
            : [
                  SELECT Provider_Name__c, Named_Credential__c, Default_Service_Type__c, Active__c
                  FROM Eligibility_Setting__mdt
                  WHERE Active__c = TRUE
                  ORDER BY Provider_Name__c
                  LIMIT 1
              ];
        if (rows.isEmpty()) {
            throw new EligibilityException('No active Eligibility Setting found.');
        }
        return rows[0];
    }

    public static EligibilityProvider forName(String providerName) {
        if (String.isBlank(providerName) || providerName.equalsIgnoreCase('Stedi')) {
            return new StediEligibilityProvider();
        }
        Type providerType = Type.forName(providerName);
        if (providerType == null) {
            throw new EligibilityException('Unknown eligibility provider: ' + providerName);
        }
        Object instance = providerType.newInstance();
        if (!(instance instanceof EligibilityProvider)) {
            throw new EligibilityException('Class is not an EligibilityProvider: ' + providerName);
        }
        return (EligibilityProvider) instance;
    }
}
