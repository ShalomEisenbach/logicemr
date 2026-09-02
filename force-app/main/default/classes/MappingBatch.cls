global with sharing class MappingBatch implements Database.Batchable<SObject>, Database.Stateful {
    @TestVisible
    static String lastSummary;

    private Id mappingDefinitionId;
    @TestVisible
    Integer created = 0;
    @TestVisible
    Integer updated = 0;
    @TestVisible
    Integer skipped = 0;
    @TestVisible
    Integer errorCount = 0;
    @TestVisible
    String summary;

    global MappingBatch(Id mappingDefinitionId) {
        this.mappingDefinitionId = mappingDefinitionId;
    }

    global Database.QueryLocator start(Database.BatchableContext context) {
        if (mappingDefinitionId == null) {
            throw new MappingEngine.MappingException('Mapping Definition Id is required.');
        }

        List<Mapping_Definition__c> definitions = [
            SELECT Id, Source_Object__c
            FROM Mapping_Definition__c
            WHERE Id = :mappingDefinitionId
            LIMIT 1
        ];
        if (definitions.isEmpty()) {
            throw new MappingEngine.MappingException('Mapping definition was not found.');
        }

        Schema.SObjectType sourceType = resolveSObjectType(definitions[0].Source_Object__c);
        if (sourceType == null) {
            throw new MappingEngine.MappingException(
                'Source object is not available: ' + definitions[0].Source_Object__c
            );
        }

        String sourceObjectName = sourceType.getDescribe().getName();
        return Database.getQueryLocator('SELECT Id FROM ' + sourceObjectName);
    }

    global void execute(Database.BatchableContext context, List<SObject> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }

        Set<Id> sourceRecordIds = new Map<Id, SObject>(scope).keySet();
        MappingEngine.MappingResult result = new MappingEngine().run(mappingDefinitionId, sourceRecordIds, false);
        created += result.created;
        updated += result.updated;
        skipped += result.skipped;
        errorCount += result.errors.size();
    }

    global void finish(Database.BatchableContext context) {
        summary =
            'LogicEMR mapping backfill complete for ' +
            String.valueOf(mappingDefinitionId) +
            '. created=' +
            String.valueOf(created) +
            ', updated=' +
            String.valueOf(updated) +
            ', skipped=' +
            String.valueOf(skipped) +
            ', errors=' +
            String.valueOf(errorCount);
        lastSummary = summary;
        System.debug(LoggingLevel.INFO, summary);
        // TODO: persist this summary to an Integration_Log__c if that object is added.
        sendSummaryEmail(summary);
    }

    private void sendSummaryEmail(String body) {
        String toAddress = UserInfo.getUserEmail();
        if (String.isBlank(toAddress)) {
            return;
        }
        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ toAddress });
            mail.setSubject('LogicEMR mapping backfill complete');
            mail.setPlainTextBody(body);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'MappingBatch summary email was not sent: ' + e.getMessage());
        }
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
        String objectName = Mapping_Definition__c.SObjectType.getDescribe().getName();
        String packageNamespace = objectName.countMatches('__') >= 2 ? objectName.substringBefore('__') : '';
        if (String.isNotBlank(packageNamespace)) {
            String namespacedName = packageNamespace + '__' + localName;
            if (describeMap.containsKey(namespacedName)) {
                return describeMap.get(namespacedName);
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
}
