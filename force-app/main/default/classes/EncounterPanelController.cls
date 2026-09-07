public with sharing class EncounterPanelController {
    private static final Integer MAX_RESULTS = 50;
    private static final String STATUS_PLANNED = 'Planned';
    private static final Set<String> ALLOWED_STATUSES = new Set<String>{
        'Planned',
        'Arrived',
        'In Progress',
        'Finished',
        'Cancelled'
    };
    private static final Set<String> ALLOWED_CLASSES = new Set<String>{
        'Inpatient',
        'Outpatient',
        'Emergency',
        'Virtual'
    };

    @AuraEnabled(cacheable=true)
    public static List<Encounter__c> getEncounters(Id patientId) {
        if (patientId == null) {
            return new List<Encounter__c>();
        }
        return [
            SELECT
                Id,
                Name,
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

    @AuraEnabled
    public static Encounter__c createEncounter(
        Id patientId,
        String encounterClass,
        String status,
        Datetime startTime,
        Datetime endTime,
        Id practitionerId,
        String locationName,
        String reason
    ) {
        if (patientId == null) {
            throw new AuraHandledException('Patient Id is required.');
        }
        if (String.isBlank(encounterClass) || !ALLOWED_CLASSES.contains(encounterClass)) {
            throw new AuraHandledException('Class must be Inpatient, Outpatient, Emergency, or Virtual.');
        }

        String resolvedStatus = String.isBlank(status) ? STATUS_PLANNED : status;
        if (!ALLOWED_STATUSES.contains(resolvedStatus)) {
            throw new AuraHandledException('Status is not a valid encounter status.');
        }

        Datetime resolvedStart = startTime == null ? Datetime.now() : startTime;
        if (endTime != null && endTime < resolvedStart) {
            throw new AuraHandledException('End must be on or after Start.');
        }

        Encounter__c encounter = new Encounter__c(
            Patient__c = patientId,
            Class__c = encounterClass,
            Status__c = resolvedStatus,
            Start__c = resolvedStart,
            End__c = endTime,
            Practitioner__c = practitionerId,
            Location_Name__c = locationName,
            Reason__c = reason
        );
        insert encounter;
        return encounter;
    }

    @AuraEnabled
    public static void deleteEncounters(List<Id> encounterIds) {
        if (encounterIds == null || encounterIds.isEmpty()) {
            return;
        }
        delete [SELECT Id FROM Encounter__c WHERE Id IN :encounterIds];
    }
}
