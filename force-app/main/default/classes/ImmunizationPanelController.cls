public with sharing class ImmunizationPanelController {
    private static final Integer MAX_RESULTS = 200;
    private static final String STATUS_COMPLETED = 'Completed';
    private static final String STATUS_ENTERED_IN_ERROR = 'Entered in Error';
    private static final Set<String> ALLOWED_CODE_SYSTEMS = new Set<String>{ 'CVX', 'SNOMED' };
    private static final Set<String> ALLOWED_STATUSES = new Set<String>{
        'Completed',
        'Entered in Error',
        'Not Done'
    };

    @AuraEnabled(cacheable=true)
    public static List<Immunization__c> getImmunizations(Id recordId) {
        Context context = resolveContext(recordId, false);
        if (context == null || context.patientId == null) {
            return new List<Immunization__c>();
        }

        if (context.encounterId != null) {
            return [
                SELECT
                    Id,
                    Vaccine_Display__c,
                    Vaccine_Code__c,
                    Vaccine_Code_System__c,
                    Status__c,
                    Occurrence_Date__c,
                    Lot_Number__c,
                    Performer__c,
                    Performer__r.Name,
                    Encounter__c
                FROM Immunization__c
                WHERE Encounter__c = :context.encounterId
                ORDER BY Occurrence_Date__c DESC NULLS LAST, Vaccine_Display__c ASC NULLS LAST
                LIMIT :MAX_RESULTS
            ];
        }

        return [
            SELECT
                Id,
                Vaccine_Display__c,
                Vaccine_Code__c,
                Vaccine_Code_System__c,
                Status__c,
                Occurrence_Date__c,
                Lot_Number__c,
                Performer__c,
                Performer__r.Name,
                Encounter__c
            FROM Immunization__c
            WHERE Patient__c = :context.patientId
            ORDER BY Occurrence_Date__c DESC NULLS LAST, Vaccine_Display__c ASC NULLS LAST
            LIMIT :MAX_RESULTS
        ];
    }

    @AuraEnabled
    public static Immunization__c addImmunization(
        Id recordId,
        String codeSystem,
        String code,
        String display,
        Id codeReferenceId,
        Date occurrenceDate,
        String lotNumber,
        String status,
        Id performerId
    ) {
        Context context = resolveContext(recordId, true);
        if (String.isBlank(display)) {
            throw new AuraHandledException('Vaccine display is required.');
        }
        if (String.isBlank(codeSystem) || !ALLOWED_CODE_SYSTEMS.contains(codeSystem)) {
            throw new AuraHandledException('Code system must be CVX or SNOMED.');
        }

        String resolvedStatus = String.isBlank(status) ? STATUS_COMPLETED : status;
        if (!ALLOWED_STATUSES.contains(resolvedStatus)) {
            throw new AuraHandledException('Status must be Completed, Not Done, or Entered in Error.');
        }

        Immunization__c immunization = new Immunization__c(
            Patient__c = context.patientId,
            Encounter__c = context.encounterId,
            Vaccine_Ref__c = codeReferenceId,
            Vaccine_Code_System__c = codeSystem,
            Vaccine_Code__c = code,
            Vaccine_Display__c = display,
            Occurrence_Date__c = occurrenceDate,
            Lot_Number__c = lotNumber,
            Status__c = resolvedStatus,
            Performer__c = performerId
        );
        insert immunization;
        return immunization;
    }

    @AuraEnabled
    public static void markEnteredInError(List<Id> immunizationIds) {
        if (immunizationIds == null || immunizationIds.isEmpty()) {
            return;
        }

        List<Immunization__c> immunizations = [
            SELECT Id, Status__c
            FROM Immunization__c
            WHERE Id IN :immunizationIds AND Status__c != :STATUS_ENTERED_IN_ERROR
        ];
        for (Immunization__c immunization : immunizations) {
            immunization.Status__c = STATUS_ENTERED_IN_ERROR;
        }
        if (!immunizations.isEmpty()) {
            update immunizations;
        }
    }

    @AuraEnabled
    public static void deleteImmunizations(List<Id> immunizationIds) {
        if (immunizationIds == null || immunizationIds.isEmpty()) {
            return;
        }
        delete [SELECT Id FROM Immunization__c WHERE Id IN :immunizationIds];
    }

    private class Context {
        public Id patientId;
        public Id encounterId;
    }

    private static Context resolveContext(Id recordId, Boolean requireRecord) {
        if (recordId == null) {
            if (requireRecord) {
                throw new AuraHandledException('Record Id is required.');
            }
            return null;
        }

        Schema.SObjectType recordType = recordId.getSObjectType();
        Context context = new Context();
        if (recordType == Patient__c.SObjectType) {
            context.patientId = recordId;
            return context;
        }
        if (recordType == Encounter__c.SObjectType) {
            List<Encounter__c> encounters = [
                SELECT Id, Patient__c
                FROM Encounter__c
                WHERE Id = :recordId
                LIMIT 1
            ];
            if (encounters.isEmpty() || encounters[0].Patient__c == null) {
                if (requireRecord) {
                    throw new AuraHandledException('Encounter was not found.');
                }
                return null;
            }
            context.patientId = encounters[0].Patient__c;
            context.encounterId = encounters[0].Id;
            return context;
        }
        if (requireRecord) {
            throw new AuraHandledException('Patient or Encounter Id is required.');
        }
        return null;
    }
}
