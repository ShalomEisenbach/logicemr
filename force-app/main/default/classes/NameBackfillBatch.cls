global without sharing class NameBackfillBatch implements Database.Batchable<SObject>, Database.Stateful {
    @TestVisible
    static String lastSummary;

    private String objectApiName;
    @TestVisible
    Integer updatedCount = 0;

    global NameBackfillBatch(String objectApiName) {
        this.objectApiName = objectApiName;
    }

    global Database.QueryLocator start(Database.BatchableContext context) {
        Schema.SObjectType sObjectType = resolveSObjectType(objectApiName);
        if (sObjectType == null) {
            throw new BatchException('Object is not available: ' + objectApiName);
        }

        Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
        if (!describeResult.isQueryable() || !describeResult.isUpdateable()) {
            throw new BatchException('Object is not queryable and updateable: ' + objectApiName);
        }

        Set<String> selectFields = new Set<String>{ 'Id', 'Name' };
        for (Schema.SObjectField field : describeResult.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            if (
                fieldDescribe.isAccessible() &&
                fieldDescribe.isCustom() &&
                !isLongOrBinary(fieldDescribe)
            ) {
                selectFields.add(fieldDescribe.getName());
            }
        }

        return Database.getQueryLocator(
            'SELECT ' +
            String.join(new List<String>(selectFields), ', ') +
            ' FROM ' +
            describeResult.getName()
        );
    }

    global void execute(Database.BatchableContext context, List<SObject> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }
        NameFormatterHandler.format(scope);
        update scope;
        updatedCount += scope.size();
    }

    global void finish(Database.BatchableContext context) {
        lastSummary =
            'LogicEMR name backfill complete for ' +
            objectApiName +
            '. updated=' +
            String.valueOf(updatedCount);
        System.debug(LoggingLevel.INFO, lastSummary);
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
        String packagedName = Name_Format__mdt.SObjectType.getDescribe().getName();
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

    private static Boolean isLongOrBinary(Schema.DescribeFieldResult fieldDescribe) {
        Schema.DisplayType fieldType = fieldDescribe.getType();
        if (
            fieldType == Schema.DisplayType.BASE64 ||
            fieldType == Schema.DisplayType.ENCRYPTEDSTRING
        ) {
            return true;
        }
        return fieldType == Schema.DisplayType.TEXTAREA && fieldDescribe.getLength() > 255;
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
