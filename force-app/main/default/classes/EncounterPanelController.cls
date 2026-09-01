public with sharing class EncounterPanelController {
    private static final Integer MAX_RESULTS = 50;

    @AuraEnabled(cacheable=true)
    public static List<Encounter__c> getEncounters(Id patientId) {
        if (patientId == null) {
            return new List<Encounter__c>();
        }
        return [
            SELECT
                Id,
                Status__c,
                Class__c,
                Start__c,
                Practitioner__c,
                Practitioner__r.First_Name__c,
                Practitioner__r.Last_Name__c
            FROM Encounter__c
            WHERE Patient__c = :patientId
            ORDER BY Start__c DESC NULLS LAST
            LIMIT :MAX_RESULTS
        ];
    }
}
