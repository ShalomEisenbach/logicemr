public with sharing class EncounterWorkspaceController {
    @TestVisible
    private static final String STATUS_PLANNED = 'Planned';
    @TestVisible
    private static final String STATUS_ARRIVED = 'Arrived';
    @TestVisible
    private static final String STATUS_IN_PROGRESS = 'In Progress';
    @TestVisible
    private static final String STATUS_FINISHED = 'Finished';
    private static final Integer MAX_DIAGNOSES = 200;
    private static final String CATEGORY_ENCOUNTER_DX = 'Encounter Diagnosis';
    private static final String STATUS_ACTIVE = 'Active';
    private static final Set<String> ALLOWED_CODE_SYSTEMS = new Set<String>{ 'ICD-10', 'SNOMED' };

    private static final Map<String, String> NEXT_STATUS = new Map<String, String>{
        STATUS_PLANNED => STATUS_ARRIVED,
        STATUS_ARRIVED => STATUS_IN_PROGRESS,
        STATUS_IN_PROGRESS => STATUS_FINISHED
    };

    public class DiagnosisRow {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public Id conditionId;
        @AuraEnabled
        public String display;
        @AuraEnabled
        public String code;
        @AuraEnabled
        public String codeSystem;
        @AuraEnabled
        public String diagnosisType;
        @AuraEnabled
        public Decimal rank;
        @AuraEnabled
        public String status;
    }

    @AuraEnabled
    public static Encounter__c transitionStatus(Id encounterId, String newStatus) {
        if (encounterId == null) {
            throw new AuraHandledException('Encounter Id is required.');
        }
        if (String.isBlank(newStatus)) {
            throw new AuraHandledException('New status is required.');
        }

        List<Encounter__c> rows = [
            SELECT Id, Status__c
            FROM Encounter__c
            WHERE Id = :encounterId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('Encounter was not found.');
        }

        Encounter__c encounter = rows[0];
        if (!isValidTransition(encounter.Status__c, newStatus)) {
            throw new AuraHandledException(
                'Cannot change status from ' +
                    String.valueOf(encounter.Status__c) +
                    ' to ' +
                    newStatus +
                    '.'
            );
        }

        encounter.Status__c = newStatus;
        update encounter;
        return encounter;
    }

    @AuraEnabled(cacheable=true)
    public static Boolean isValidTransition(String currentStatus, String newStatus) {
        if (String.isBlank(currentStatus) || String.isBlank(newStatus)) {
            return false;
        }
        return NEXT_STATUS.get(currentStatus) == newStatus;
    }

    @AuraEnabled(cacheable=true)
    public static List<DiagnosisRow> getDiagnoses(Id encounterId) {
        List<DiagnosisRow> rows = new List<DiagnosisRow>();
        if (encounterId == null) {
            return rows;
        }

        for (EncounterDiagnosis__c link : [
            SELECT
                Id,
                Type__c,
                Rank__c,
                Condition__c,
                Condition__r.Diagnosis_Display__c,
                Condition__r.Diagnosis_Code__c,
                Condition__r.Diagnosis_Code_System__c,
                Condition__r.Clinical_Status__c
            FROM EncounterDiagnosis__c
            WHERE Encounter__c = :encounterId
            ORDER BY Rank__c ASC NULLS LAST, Type__c ASC NULLS LAST
            LIMIT :MAX_DIAGNOSES
        ]) {
            DiagnosisRow row = new DiagnosisRow();
            row.id = link.Id;
            row.conditionId = link.Condition__c;
            row.display = link.Condition__r.Diagnosis_Display__c;
            row.code = link.Condition__r.Diagnosis_Code__c;
            row.codeSystem = link.Condition__r.Diagnosis_Code_System__c;
            row.diagnosisType = link.Type__c;
            row.rank = link.Rank__c;
            row.status = link.Condition__r.Clinical_Status__c;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static EncounterDiagnosis__c addDiagnosis(
        Id encounterId,
        String codeSystem,
        String code,
        String display,
        String diagnosisType,
        Decimal rank
    ) {
        if (encounterId == null) {
            throw new AuraHandledException('Encounter Id is required.');
        }
        if (String.isBlank(display)) {
            throw new AuraHandledException('Diagnosis display is required.');
        }
        if (String.isBlank(codeSystem) || !ALLOWED_CODE_SYSTEMS.contains(codeSystem)) {
            throw new AuraHandledException('Code system must be ICD-10 or SNOMED.');
        }

        List<Encounter__c> encounters = [
            SELECT Id, Patient__c
            FROM Encounter__c
            WHERE Id = :encounterId
            LIMIT 1
        ];
        if (encounters.isEmpty()) {
            throw new AuraHandledException('Encounter was not found.');
        }

        Condition__c condition = new Condition__c(
            Patient__c = encounters[0].Patient__c,
            Encounter__c = encounterId,
            Category__c = CATEGORY_ENCOUNTER_DX,
            Clinical_Status__c = STATUS_ACTIVE,
            Diagnosis_Code_System__c = codeSystem,
            Diagnosis_Code__c = code,
            Diagnosis_Display__c = display
        );
        insert condition;

        EncounterDiagnosis__c link = new EncounterDiagnosis__c(
            Encounter__c = encounterId,
            Condition__c = condition.Id,
            Type__c = diagnosisType,
            Rank__c = rank
        );
        insert link;
        return link;
    }
}
