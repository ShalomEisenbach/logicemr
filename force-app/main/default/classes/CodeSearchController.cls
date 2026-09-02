public with sharing class CodeSearchController {
    private static final Integer MAX_RESULTS = 50;

    public class CodeHit {
        @AuraEnabled
        public Id recordId;
        @AuraEnabled
        public String codeSystem;
        @AuraEnabled
        public String code;
        @AuraEnabled
        public String display;
    }

    @AuraEnabled(cacheable=true)
    public static List<CodeHit> search(String term, List<String> systems) {
        if (String.isBlank(term)) {
            return new List<CodeHit>();
        }

        String likePattern = '%' + term.trim() + '%';
        Set<String> systemFilter = new Set<String>();
        if (systems != null) {
            for (String codeSystem : systems) {
                if (!String.isBlank(codeSystem)) {
                    systemFilter.add(codeSystem);
                }
            }
        }

        List<Code_Reference__c> rows = systemFilter.isEmpty()
            ? queryAllSystems(likePattern)
            : queryBySystems(likePattern, systemFilter);

        List<CodeHit> results = new List<CodeHit>();
        for (Code_Reference__c row : rows) {
            CodeHit hit = new CodeHit();
            hit.recordId = row.Id;
            hit.codeSystem = row.Code_System__c;
            hit.code = row.Code__c;
            hit.display = row.Display__c;
            results.add(hit);
        }
        return results;
    }

    private static List<Code_Reference__c> queryAllSystems(String likePattern) {
        return [
            SELECT Id, Code_System__c, Code__c, Display__c
            FROM Code_Reference__c
            WHERE
                Active__c = TRUE
                AND (Code__c LIKE :likePattern OR Display__c LIKE :likePattern)
            ORDER BY Code__c, Display__c
            LIMIT :MAX_RESULTS
        ];
    }

    private static List<Code_Reference__c> queryBySystems(String likePattern, Set<String> systemFilter) {
        return [
            SELECT Id, Code_System__c, Code__c, Display__c
            FROM Code_Reference__c
            WHERE
                Active__c = TRUE
                AND Code_System__c IN :systemFilter
                AND (Code__c LIKE :likePattern OR Display__c LIKE :likePattern)
            ORDER BY Code__c, Display__c
            LIMIT :MAX_RESULTS
        ];
    }
}
