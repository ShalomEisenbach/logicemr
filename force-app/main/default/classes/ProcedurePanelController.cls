public with sharing class ProcedurePanelController {
    private static final Integer MAX_RESULTS = 200;
    private static final String STATUS_COMPLETED = 'Completed';
    private static final Set<String> ALLOWED_CODE_SYSTEMS = new Set<String>{ 'CPT', 'SNOMED' };

    @AuraEnabled(cacheable=true)
    public static List<Procedure__c> getProcedures(Id patientId) {
        if (patientId == null) {
            return new List<Procedure__c>();
        }
        return [
            SELECT
                Id,
                Procedure_Display__c,
                Procedure_Code__c,
                Procedure_Code_System__c,
                Category__c,
                Status__c,
                Performed_DateTime__c,
                Notes__c
            FROM Procedure__c
            WHERE Patient__c = :patientId
            ORDER BY Performed_DateTime__c DESC NULLS LAST, Procedure_Display__c ASC NULLS LAST
            LIMIT :MAX_RESULTS
        ];
    }

    @AuraEnabled
    public static Procedure__c addProcedure(
        Id patientId,
        String codeSystem,
        String code,
        String display,
        Id codeReferenceId,
        String category,
        String status,
        Datetime performedDateTime,
        String notes
    ) {
        if (patientId == null) {
            throw new AuraHandledException('Patient Id is required.');
        }
        if (String.isBlank(display)) {
            throw new AuraHandledException('Procedure display is required.');
        }
        if (String.isBlank(codeSystem) || !ALLOWED_CODE_SYSTEMS.contains(codeSystem)) {
            throw new AuraHandledException('Code system must be CPT or SNOMED.');
        }

        Procedure__c procedure = new Procedure__c(
            Patient__c = patientId,
            Procedure_Ref__c = codeReferenceId,
            Procedure_Code_System__c = codeSystem,
            Procedure_Code__c = code,
            Procedure_Display__c = display,
            Category__c = category,
            Status__c = String.isBlank(status) ? STATUS_COMPLETED : status,
            Performed_DateTime__c = performedDateTime,
            Notes__c = notes
        );
        insert procedure;
        return procedure;
    }

    @AuraEnabled
    public static void completeProcedures(List<Id> procedureIds) {
        if (procedureIds == null || procedureIds.isEmpty()) {
            return;
        }

        List<Procedure__c> procedures = [
            SELECT Id, Status__c
            FROM Procedure__c
            WHERE Id IN :procedureIds AND Status__c != :STATUS_COMPLETED
        ];
        for (Procedure__c procedure : procedures) {
            procedure.Status__c = STATUS_COMPLETED;
        }
        if (!procedures.isEmpty()) {
            update procedures;
        }
    }

    @AuraEnabled
    public static void deleteProcedures(List<Id> procedureIds) {
        if (procedureIds == null || procedureIds.isEmpty()) {
            return;
        }
        delete [SELECT Id FROM Procedure__c WHERE Id IN :procedureIds];
    }
}
