public with sharing class AllergyPanelController {
    private static final Integer MAX_RESULTS = 200;
    private static final String STATUS_ACTIVE = 'Active';
    private static final String STATUS_INACTIVE = 'Inactive';

    @AuraEnabled(cacheable=true)
    public static List<AllergyIntolerance__c> getAllergies(Id patientId) {
        if (patientId == null) {
            return new List<AllergyIntolerance__c>();
        }
        return queryAllergies(new Set<Id>{ patientId }, false);
    }

    @AuraEnabled(cacheable=true)
    public static List<AllergyIntolerance__c> getActiveAllergies(Id patientId) {
        if (patientId == null) {
            return new List<AllergyIntolerance__c>();
        }
        return queryAllergies(new Set<Id>{ patientId }, true);
    }

    @AuraEnabled
    public static AllergyIntolerance__c addAllergy(
        Id patientId,
        String codeSystem,
        String code,
        String display,
        Id codeReferenceId,
        String allergyType,
        String category,
        String criticality,
        String reaction
    ) {
        if (patientId == null) {
            throw new AuraHandledException('Patient Id is required.');
        }
        if (String.isBlank(display)) {
            throw new AuraHandledException('Allergen display is required.');
        }

        AllergyIntolerance__c allergy = new AllergyIntolerance__c(
            Patient__c = patientId,
            Clinical_Status__c = STATUS_ACTIVE,
            Allergen_Ref__c = codeReferenceId,
            Allergen_Code_System__c = codeSystem,
            Allergen_Code__c = code,
            Allergen_Display__c = display,
            Type__c = allergyType,
            Category__c = category,
            Criticality__c = criticality,
            Reaction__c = reaction
        );
        insert allergy;
        return allergy;
    }

    @AuraEnabled
    public static void inactivateAllergies(List<Id> allergyIds) {
        if (allergyIds == null || allergyIds.isEmpty()) {
            return;
        }

        List<AllergyIntolerance__c> allergies = [
            SELECT Id, Clinical_Status__c
            FROM AllergyIntolerance__c
            WHERE Id IN :allergyIds AND Clinical_Status__c = :STATUS_ACTIVE
        ];
        for (AllergyIntolerance__c allergy : allergies) {
            allergy.Clinical_Status__c = STATUS_INACTIVE;
        }
        if (!allergies.isEmpty()) {
            update allergies;
        }
    }

    @AuraEnabled
    public static void deleteAllergies(List<Id> allergyIds) {
        if (allergyIds == null || allergyIds.isEmpty()) {
            return;
        }
        delete [SELECT Id FROM AllergyIntolerance__c WHERE Id IN :allergyIds];
    }

    private static List<AllergyIntolerance__c> queryAllergies(Set<Id> patientIds, Boolean activeOnly) {
        if (activeOnly) {
            return [
                SELECT
                    Id,
                    Allergen_Code_System__c,
                    Allergen_Code__c,
                    Allergen_Display__c,
                    Type__c,
                    Category__c,
                    Criticality__c,
                    Clinical_Status__c,
                    Reaction__c,
                    Onset_Date__c
                FROM AllergyIntolerance__c
                WHERE Patient__c IN :patientIds AND Clinical_Status__c = :STATUS_ACTIVE
                ORDER BY Allergen_Display__c ASC NULLS LAST
                LIMIT :MAX_RESULTS
            ];
        }
        return [
            SELECT
                Id,
                Allergen_Code_System__c,
                Allergen_Code__c,
                Allergen_Display__c,
                Type__c,
                Category__c,
                Criticality__c,
                Clinical_Status__c,
                Reaction__c,
                Onset_Date__c
            FROM AllergyIntolerance__c
            WHERE Patient__c IN :patientIds
            ORDER BY Clinical_Status__c ASC, Allergen_Display__c ASC NULLS LAST
            LIMIT :MAX_RESULTS
        ];
    }
}
