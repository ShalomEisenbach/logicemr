public with sharing class AlertBarController {
    private static final Integer MAX_RESULTS = 200;
    private static final String STATUS_ACTIVE = 'Active';

    @AuraEnabled(cacheable=true)
    public static Id resolvePatientId(Id recordId) {
        if (recordId == null) {
            return null;
        }

        Schema.SObjectType recordType = recordId.getSObjectType();
        if (recordType == Patient__c.SObjectType) {
            return recordId;
        }
        if (recordType == Encounter__c.SObjectType) {
            List<Encounter__c> encounters = [
                SELECT Patient__c
                FROM Encounter__c
                WHERE Id = :recordId
                LIMIT 1
            ];
            return encounters.isEmpty() ? null : encounters[0].Patient__c;
        }
        return null;
    }

    @AuraEnabled(cacheable=true)
    public static List<AllergyIntolerance__c> getActiveAllergies(Id recordId) {
        Id patientId = resolvePatientId(recordId);
        if (patientId == null) {
            return new List<AllergyIntolerance__c>();
        }
        return [
            SELECT Id, Allergen_Display__c, Allergen_Code__c, Criticality__c, Clinical_Status__c
            FROM AllergyIntolerance__c
            WHERE Patient__c = :patientId AND Clinical_Status__c = :STATUS_ACTIVE
            ORDER BY Criticality__c ASC NULLS LAST, Allergen_Display__c ASC NULLS LAST
            LIMIT :MAX_RESULTS
        ];
    }
}
