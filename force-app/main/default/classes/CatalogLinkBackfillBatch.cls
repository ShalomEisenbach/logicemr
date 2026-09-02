global without sharing class CatalogLinkBackfillBatch implements Database.Batchable<SObject>, Database.Stateful {
    @TestVisible
    static String lastSummary;

    private String objectApiName;
    private String codeSystemField;
    private String codeField;
    private String lookupField;

    @TestVisible
    Integer updatedCount = 0;
    @TestVisible
    Integer unmatchedCount = 0;
    @TestVisible
    Set<String> unmatchedKeys = new Set<String>();

    global CatalogLinkBackfillBatch(
        String objectApiName,
        String codeSystemField,
        String codeField,
        String lookupField
    ) {
        this.objectApiName = objectApiName;
        this.codeSystemField = codeSystemField;
        this.codeField = codeField;
        this.lookupField = lookupField;
    }

    global Database.QueryLocator start(Database.BatchableContext context) {
        Schema.SObjectType sObjectType = resolveSObjectType(objectApiName);
        if (sObjectType == null) {
            throw new BatchException('Object is not available: ' + objectApiName);
        }

        Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
        Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();
        String systemApi = resolveFieldName(fieldMap, codeSystemField);
        String codeApi = resolveFieldName(fieldMap, codeField);
        String lookupApi = resolveFieldName(fieldMap, lookupField);
        if (systemApi == null || codeApi == null || lookupApi == null) {
            throw new BatchException(
                'One or more fields are not available on ' +
                objectApiName +
                ': ' +
                codeSystemField +
                ', ' +
                codeField +
                ', ' +
                lookupField
            );
        }

        this.codeSystemField = systemApi;
        this.codeField = codeApi;
        this.lookupField = lookupApi;

        return Database.getQueryLocator(
            'SELECT Id, ' +
            systemApi +
            ', ' +
            codeApi +
            ', ' +
            lookupApi +
            ' FROM ' +
            describeResult.getName() +
            ' WHERE ' +
            lookupApi +
            ' = null AND ' +
            codeApi +
            ' != null'
        );
    }

    global void execute(Database.BatchableContext context, List<SObject> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }

        Set<String> codes = new Set<String>();
        Set<String> systems = new Set<String>();
        for (SObject record : scope) {
            String code = stringify(record.get(codeField));
            String codeSystem = stringify(record.get(codeSystemField));
            if (String.isBlank(code) || String.isBlank(codeSystem)) {
                registerUnmatched(codeSystem, code);
                continue;
            }
            codes.add(code);
            systems.add(codeSystem);
        }

        Map<String, Id> catalogByKey = queryCatalog(codes, systems);
        List<SObject> toUpdate = new List<SObject>();
        for (SObject record : scope) {
            String code = stringify(record.get(codeField));
            String codeSystem = stringify(record.get(codeSystemField));
            if (String.isBlank(code) || String.isBlank(codeSystem)) {
                continue;
            }
            String key = catalogKey(codeSystem, code);
            Id catalogId = catalogByKey.get(key);
            if (catalogId == null) {
                registerUnmatched(codeSystem, code);
                System.debug(
                    LoggingLevel.WARN,
                    'CatalogLinkBackfill unmatched ' +
                    objectApiName +
                    ' ' +
                    key +
                    ' Id=' +
                    record.Id
                );
                continue;
            }
            record.put(lookupField, catalogId);
            toUpdate.add(record);
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
            updatedCount += toUpdate.size();
        }
    }

    global void finish(Database.BatchableContext context) {
        lastSummary =
            'LogicEMR catalog-link backfill complete for ' +
            objectApiName +
            '. updated=' +
            String.valueOf(updatedCount) +
            ', unmatched=' +
            String.valueOf(unmatchedCount);
        if (!unmatchedKeys.isEmpty()) {
            lastSummary += '. unmatchedKeys=' + String.join(new List<String>(unmatchedKeys), ', ');
        }
        System.debug(LoggingLevel.INFO, lastSummary);
    }

    private Map<String, Id> queryCatalog(Set<String> codes, Set<String> systems) {
        Map<String, Id> catalogByKey = new Map<String, Id>();
        if (codes.isEmpty() || systems.isEmpty()) {
            return catalogByKey;
        }
        for (Code_Reference__c row : [
            SELECT Id, Code_System__c, Code__c
            FROM Code_Reference__c
            WHERE Code__c IN :codes AND Code_System__c IN :systems
        ]) {
            String key = catalogKey(row.Code_System__c, row.Code__c);
            if (!catalogByKey.containsKey(key)) {
                catalogByKey.put(key, row.Id);
            }
        }
        return catalogByKey;
    }

    private void registerUnmatched(String codeSystem, String code) {
        unmatchedCount++;
        unmatchedKeys.add(catalogKey(codeSystem, code));
    }

    private static String catalogKey(String codeSystem, String code) {
        return String.valueOf(codeSystem) + '::' + String.valueOf(code);
    }

    private static String stringify(Object value) {
        return value == null ? '' : String.valueOf(value).trim();
    }

    private Schema.SObjectType resolveSObjectType(String apiName) {
        if (String.isBlank(apiName)) {
            return null;
        }
        Map<String, Schema.SObjectType> describeMap = Schema.getGlobalDescribe();
        if (describeMap.containsKey(apiName)) {
            return describeMap.get(apiName);
        }
        String localName = stripNamespace(apiName);
        if (describeMap.containsKey(localName)) {
            return describeMap.get(localName);
        }
        String packagedName = Code_Reference__c.SObjectType.getDescribe().getName();
        String packageNamespace = packagedName.countMatches('__') >= 2
            ? packagedName.substringBefore('__')
            : '';
        if (String.isNotBlank(packageNamespace)) {
            String namespacedName = packageNamespace + '__' + localName;
            if (describeMap.containsKey(namespacedName)) {
                return describeMap.get(namespacedName);
            }
        }
        return null;
    }

    private String resolveFieldName(Map<String, Schema.SObjectField> fieldMap, String apiName) {
        if (String.isBlank(apiName) || fieldMap == null) {
            return null;
        }
        if (fieldMap.containsKey(apiName)) {
            return fieldMap.get(apiName).getDescribe().getName();
        }
        String localName = stripNamespace(apiName);
        if (fieldMap.containsKey(localName)) {
            return fieldMap.get(localName).getDescribe().getName();
        }
        for (Schema.SObjectField field : fieldMap.values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            if (
                fieldDescribe.getLocalName().equalsIgnoreCase(apiName) ||
                fieldDescribe.getName().equalsIgnoreCase(apiName) ||
                fieldDescribe.getLocalName().equalsIgnoreCase(localName)
            ) {
                return fieldDescribe.getName();
            }
        }
        return null;
    }

    private String stripNamespace(String apiName) {
        if (String.isBlank(apiName) || apiName.countMatches('__') < 2) {
            return apiName;
        }
        return apiName.substringAfter('__');
    }

    public class BatchException extends Exception {
    }
}
