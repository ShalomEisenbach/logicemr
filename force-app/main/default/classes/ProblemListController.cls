public with sharing class ProblemListController {
    private static final Integer MAX_RESULTS = 200;
    private static final String CATEGORY_PROBLEM = 'Problem List Item';
    private static final String STATUS_ACTIVE = 'Active';
    private static final String STATUS_RESOLVED = 'Resolved';
    private static final Set<String> ALLOWED_CODE_SYSTEMS = new Set<String>{ 'ICD-10', 'SNOMED' };

    public class ProblemListView {
        @AuraEnabled
        public List<Condition__c> activeProblems;
        @AuraEnabled
        public List<Condition__c> resolvedProblems;
    }

    @AuraEnabled(cacheable=true)
    public static ProblemListView getProblems(Id patientId) {
        ProblemListView view = new ProblemListView();
        view.activeProblems = new List<Condition__c>();
        view.resolvedProblems = new List<Condition__c>();
        if (patientId == null) {
            return view;
        }

        for (Condition__c condition : queryProblems(new Set<Id>{ patientId })) {
            if (condition.Clinical_Status__c == STATUS_RESOLVED) {
                view.resolvedProblems.add(condition);
            } else {
                view.activeProblems.add(condition);
            }
        }
        return view;
    }

    @AuraEnabled
    public static Condition__c addProblem(
        Id patientId,
        String codeSystem,
        String code,
        String display,
        Id codeReferenceId,
        Date onsetDate
    ) {
        if (patientId == null) {
            throw new AuraHandledException('Patient Id is required.');
        }
        if (String.isBlank(display)) {
            throw new AuraHandledException('Diagnosis display is required.');
        }
        if (String.isBlank(codeSystem) || !ALLOWED_CODE_SYSTEMS.contains(codeSystem)) {
            throw new AuraHandledException('Code system must be ICD-10 or SNOMED.');
        }

        Condition__c condition = new Condition__c(
            Patient__c = patientId,
            Category__c = CATEGORY_PROBLEM,
            Clinical_Status__c = STATUS_ACTIVE,
            Diagnosis_Ref__c = codeReferenceId,
            Diagnosis_Code_System__c = codeSystem,
            Diagnosis_Code__c = code,
            Diagnosis_Display__c = display,
            Onset_Date__c = onsetDate
        );
        insert condition;
        return condition;
    }

    @AuraEnabled
    public static void updateOnsetDate(Id conditionId, Date onsetDate) {
        if (conditionId == null) {
            throw new AuraHandledException('Condition Id is required.');
        }

        Condition__c condition = [
            SELECT Id, Onset_Date__c
            FROM Condition__c
            WHERE Id = :conditionId
            LIMIT 1
        ];
        condition.Onset_Date__c = onsetDate;
        update condition;
    }

    @AuraEnabled
    public static void resolveProblems(List<Id> conditionIds) {
        if (conditionIds == null || conditionIds.isEmpty()) {
            return;
        }

        List<Condition__c> conditions = [
            SELECT Id, Clinical_Status__c, Abatement_Date__c
            FROM Condition__c
            WHERE Id IN :conditionIds AND Clinical_Status__c != :STATUS_RESOLVED
        ];
        for (Condition__c condition : conditions) {
            condition.Clinical_Status__c = STATUS_RESOLVED;
            condition.Abatement_Date__c = Date.today();
        }
        if (!conditions.isEmpty()) {
            update conditions;
        }
    }

    @AuraEnabled
    public static void reopenProblems(List<Id> conditionIds) {
        if (conditionIds == null || conditionIds.isEmpty()) {
            return;
        }

        List<Condition__c> conditions = [
            SELECT Id, Clinical_Status__c, Abatement_Date__c
            FROM Condition__c
            WHERE Id IN :conditionIds AND Clinical_Status__c = :STATUS_RESOLVED
        ];
        for (Condition__c condition : conditions) {
            condition.Clinical_Status__c = STATUS_ACTIVE;
            condition.Abatement_Date__c = null;
        }
        if (!conditions.isEmpty()) {
            update conditions;
        }
    }

    @AuraEnabled
    public static void deleteProblems(List<Id> conditionIds) {
        if (conditionIds == null || conditionIds.isEmpty()) {
            return;
        }
        delete [SELECT Id FROM Condition__c WHERE Id IN :conditionIds];
    }

    private static List<Condition__c> queryProblems(Set<Id> patientIds) {
        return [
            SELECT
                Id,
                Diagnosis_Code_System__c,
                Diagnosis_Code__c,
                Diagnosis_Display__c,
                Clinical_Status__c,
                Onset_Date__c,
                Abatement_Date__c
            FROM Condition__c
            WHERE Patient__c IN :patientIds AND Category__c = :CATEGORY_PROBLEM
            ORDER BY Diagnosis_Display__c ASC NULLS LAST
            LIMIT :MAX_RESULTS
        ];
    }
}
