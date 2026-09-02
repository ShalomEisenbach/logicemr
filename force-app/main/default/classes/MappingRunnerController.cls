public with sharing class MappingRunnerController {
    private static final String TX_DEFAULT = 'Default Value';
    private static final String TX_CONCAT = 'Concatenate';
    private static final String SOURCE_SYSTEM_ID_FIELD = 'lfemr__Source_System_Id__c';

    public class MappingOption {
        @AuraEnabled
        public Id id { get; set; }
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public String sourceObject { get; set; }
    }

    public class PreviewRow {
        @AuraEnabled
        public String sourceField { get; set; }
        @AuraEnabled
        public String sourceValue { get; set; }
        @AuraEnabled
        public String targetField { get; set; }
        @AuraEnabled
        public String targetValue { get; set; }
        @AuraEnabled
        public String transformationType { get; set; }
    }

    public class RowError {
        @AuraEnabled
        public Id sourceRecordId { get; set; }
        @AuraEnabled
        public String message { get; set; }
    }

    public class RunSummary {
        @AuraEnabled
        public Integer created { get; set; }
        @AuraEnabled
        public Integer updated { get; set; }
        @AuraEnabled
        public Integer skipped { get; set; }
        @AuraEnabled
        public List<RowError> errors { get; set; }
    }

    public class PreviewResult {
        @AuraEnabled
        public RunSummary summary { get; set; }
        @AuraEnabled
        public List<PreviewRow> rows { get; set; }
        @AuraEnabled
        public Id sourceRecordId { get; set; }
        @AuraEnabled
        public String sourceObject { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static List<MappingOption> getActiveMappings() {
        try {
            List<MappingOption> options = new List<MappingOption>();
            for (Mapping_Definition__c definition : [
                SELECT Id, Name, Source_Object__c
                FROM Mapping_Definition__c
                WHERE Active__c = TRUE
                ORDER BY Name
            ]) {
                MappingOption option = new MappingOption();
                option.id = definition.Id;
                option.name = definition.Name;
                option.sourceObject = definition.Source_Object__c;
                options.add(option);
            }
            return options;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static PreviewResult previewMapping(Id mappingDefinitionId, Id sourceRecordId) {
        try {
            if (mappingDefinitionId == null) {
                throw new AuraHandledException('Mapping Definition Id is required.');
            }
            if (sourceRecordId == null) {
                throw new AuraHandledException('Source record Id is required.');
            }

            Mapping_Definition__c definition = requireDefinition(mappingDefinitionId);
            List<Field_Mapping__c> fieldMappings = queryFieldMappings(mappingDefinitionId);
            SObject sourceRecord = querySourceRecord(definition, fieldMappings, sourceRecordId);

            MappingEngine.MappingResult engineResult = new MappingEngine()
                .run(mappingDefinitionId, new Set<Id>{ sourceRecordId }, true);

            PreviewResult preview = new PreviewResult();
            preview.summary = toSummary(engineResult);
            preview.sourceRecordId = sourceRecordId;
            preview.sourceObject = definition.Source_Object__c;
            preview.rows = buildPreviewRows(
                fieldMappings,
                sourceRecord,
                engineResult.previewRecords.isEmpty() ? null : engineResult.previewRecords[0]
            );
            return preview;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static RunSummary runMapping(Id mappingDefinitionId, List<Id> sourceRecordIds) {
        try {
            if (mappingDefinitionId == null) {
                throw new AuraHandledException('Mapping Definition Id is required.');
            }
            Set<Id> sourceIds = new Set<Id>();
            if (sourceRecordIds != null) {
                for (Id sourceId : sourceRecordIds) {
                    if (sourceId != null) {
                        sourceIds.add(sourceId);
                    }
                }
            }
            if (sourceIds.isEmpty()) {
                throw new AuraHandledException('At least one source record Id is required.');
            }
            requireDefinition(mappingDefinitionId);
            return toSummary(new MappingEngine().run(mappingDefinitionId, sourceIds, false));
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Id startBackfill(Id mappingDefinitionId) {
        try {
            if (mappingDefinitionId == null) {
                throw new AuraHandledException('Mapping Definition Id is required.');
            }
            Mapping_Definition__c definition = requireDefinition(mappingDefinitionId);
            if (definition.Active__c != true) {
                throw new AuraHandledException('Mapping definition is inactive.');
            }
            return Database.executeBatch(new MappingBatch(mappingDefinitionId));
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static Mapping_Definition__c requireDefinition(Id mappingDefinitionId) {
        List<Mapping_Definition__c> definitions = [
            SELECT Id, Name, Source_Object__c, Target_Object__c, Active__c
            FROM Mapping_Definition__c
            WHERE Id = :mappingDefinitionId
            LIMIT 1
        ];
        if (definitions.isEmpty()) {
            throw new AuraHandledException('Mapping definition was not found.');
        }
        return definitions[0];
    }

    private static List<Field_Mapping__c> queryFieldMappings(Id mappingDefinitionId) {
        return [
            SELECT
                Source_Field__c,
                Target_Field__c,
                Transformation_Type__c,
                Default_Value__c,
                Concat_Separator__c,
                Sort_Order__c
            FROM Field_Mapping__c
            WHERE Mapping_Definition__c = :mappingDefinitionId
            ORDER BY Sort_Order__c NULLS LAST
        ];
    }

    private static SObject querySourceRecord(
        Mapping_Definition__c definition,
        List<Field_Mapping__c> fieldMappings,
        Id sourceRecordId
    ) {
        Schema.SObjectType sourceType = resolveSObjectType(definition.Source_Object__c);
        if (sourceType == null) {
            throw new AuraHandledException('Source object is not available: ' + definition.Source_Object__c);
        }
        if (sourceRecordId.getSobjectType() != sourceType) {
            throw new AuraHandledException(
                'Source record is not a ' + sourceType.getDescribe().getName() + ' record.'
            );
        }

        Schema.DescribeSObjectResult sourceDescribe = sourceType.getDescribe();
        if (!sourceDescribe.isAccessible() || !sourceDescribe.isQueryable()) {
            throw new AuraHandledException('Source object is not accessible: ' + definition.Source_Object__c);
        }

        Map<String, Schema.SObjectField> fieldMap = sourceDescribe.fields.getMap();
        Set<String> selectNames = new Set<String>{ 'Id' };
        for (String requested : collectSourceFieldNames(fieldMappings)) {
            Schema.SObjectField token = resolveField(fieldMap, requested);
            if (token == null) {
                continue;
            }
            Schema.DescribeFieldResult fieldDescribe = token.getDescribe();
            if (fieldDescribe.isAccessible()) {
                selectNames.add(fieldDescribe.getName());
            }
        }

        String soql =
            'SELECT ' +
            String.join(new List<String>(selectNames), ',') +
            ' FROM ' +
            sourceDescribe.getName() +
            ' WHERE Id = :sourceRecordId LIMIT 1';
        List<SObject> queried = Database.query(soql);
        if (queried.isEmpty()) {
            throw new AuraHandledException('Source record was not found.');
        }
        return Security.stripInaccessible(AccessType.READABLE, queried).getRecords()[0];
    }

    private static List<PreviewRow> buildPreviewRows(
        List<Field_Mapping__c> fieldMappings,
        SObject sourceRecord,
        SObject previewTarget
    ) {
        List<PreviewRow> rows = new List<PreviewRow>();
        Set<String> mappedTargetLocals = new Set<String>();
        Map<String, Object> sourcePopulated = sourceRecord == null
            ? new Map<String, Object>()
            : sourceRecord.getPopulatedFieldsAsMap();
        Map<String, Object> targetPopulated = previewTarget == null
            ? new Map<String, Object>()
            : previewTarget.getPopulatedFieldsAsMap();

        for (Field_Mapping__c mapping : fieldMappings) {
            PreviewRow row = new PreviewRow();
            row.sourceField = mapping.Source_Field__c;
            row.targetField = mapping.Target_Field__c;
            row.transformationType = mapping.Transformation_Type__c;
            row.sourceValue = readSourceDisplay(mapping, sourcePopulated);
            row.targetValue = readPopulatedValue(targetPopulated, mapping.Target_Field__c);
            rows.add(row);
            if (String.isNotBlank(mapping.Target_Field__c)) {
                mappedTargetLocals.add(stripNamespace(mapping.Target_Field__c).toLowerCase());
            }
        }

        String composedKey = readPopulatedValue(targetPopulated, SOURCE_SYSTEM_ID_FIELD);
        if (
            String.isNotBlank(composedKey) &&
            !mappedTargetLocals.contains(stripNamespace(SOURCE_SYSTEM_ID_FIELD).toLowerCase())
        ) {
            PreviewRow systemRow = new PreviewRow();
            systemRow.sourceField = 'Id';
            systemRow.sourceValue = sourceRecord == null ? '' : String.valueOf(sourceRecord.Id);
            systemRow.targetField = SOURCE_SYSTEM_ID_FIELD;
            systemRow.targetValue = composedKey;
            systemRow.transformationType = 'System';
            rows.add(systemRow);
        }
        return rows;
    }

    private static String readSourceDisplay(Field_Mapping__c mapping, Map<String, Object> populated) {
        if (mapping.Transformation_Type__c == TX_DEFAULT) {
            return '';
        }
        if (mapping.Transformation_Type__c == TX_CONCAT) {
            List<String> parts = new List<String>();
            for (String fieldName : splitSourceFields(mapping.Source_Field__c)) {
                parts.add(readPopulatedValue(populated, fieldName));
            }
            return String.join(parts, ', ');
        }
        return readPopulatedValue(populated, mapping.Source_Field__c);
    }

    private static String readPopulatedValue(Map<String, Object> populated, String fieldApi) {
        if (populated == null || String.isBlank(fieldApi)) {
            return '';
        }
        if (populated.containsKey(fieldApi)) {
            return stringify(populated.get(fieldApi));
        }
        String localName = stripNamespace(fieldApi);
        if (populated.containsKey(localName)) {
            return stringify(populated.get(localName));
        }
        for (String key : populated.keySet()) {
            if (key != null && stripNamespace(key).equalsIgnoreCase(localName)) {
                return stringify(populated.get(key));
            }
        }
        return '';
    }

    private static String stringify(Object value) {
        return value == null ? '' : String.valueOf(value);
    }

    private static Set<String> collectSourceFieldNames(List<Field_Mapping__c> fieldMappings) {
        Set<String> names = new Set<String>();
        for (Field_Mapping__c mapping : fieldMappings) {
            if (mapping.Transformation_Type__c == TX_DEFAULT) {
                continue;
            }
            if (mapping.Transformation_Type__c == TX_CONCAT) {
                names.addAll(splitSourceFields(mapping.Source_Field__c));
            } else if (String.isNotBlank(mapping.Source_Field__c)) {
                names.add(mapping.Source_Field__c.trim());
            }
        }
        return names;
    }

    private static List<String> splitSourceFields(String sourceField) {
        List<String> names = new List<String>();
        if (String.isBlank(sourceField)) {
            return names;
        }
        for (String part : sourceField.split(',')) {
            String trimmed = part == null ? '' : part.trim();
            if (String.isNotBlank(trimmed)) {
                names.add(trimmed);
            }
        }
        return names;
    }

    private static RunSummary toSummary(MappingEngine.MappingResult engineResult) {
        RunSummary summary = new RunSummary();
        summary.created = engineResult.created;
        summary.updated = engineResult.updated;
        summary.skipped = engineResult.skipped;
        summary.errors = new List<RowError>();
        if (engineResult.errors != null) {
            for (MappingEngine.RowError engineError : engineResult.errors) {
                RowError row = new RowError();
                row.sourceRecordId = engineError.sourceRecordId;
                row.message = engineError.message;
                summary.errors.add(row);
            }
        }
        return summary;
    }

    private static Schema.SObjectType resolveSObjectType(String apiName) {
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
        String ns = currentNamespace();
        if (String.isNotBlank(ns)) {
            String qualified = ns + '__' + localName;
            if (describeMap.containsKey(qualified)) {
                return describeMap.get(qualified);
            }
        }
        return null;
    }

    private static Schema.SObjectField resolveField(Map<String, Schema.SObjectField> fieldMap, String apiName) {
        if (String.isBlank(apiName) || fieldMap == null) {
            return null;
        }
        if (fieldMap.containsKey(apiName)) {
            return fieldMap.get(apiName);
        }
        String localName = stripNamespace(apiName);
        if (fieldMap.containsKey(localName)) {
            return fieldMap.get(localName);
        }
        String ns = currentNamespace();
        if (String.isNotBlank(ns)) {
            String qualified = ns + '__' + localName;
            if (fieldMap.containsKey(qualified)) {
                return fieldMap.get(qualified);
            }
        }
        return null;
    }

    private static String stripNamespace(String apiName) {
        if (String.isBlank(apiName)) {
            return apiName;
        }
        Integer separatorCount = apiName.countMatches('__');
        if (separatorCount >= 2) {
            return apiName.substringAfter('__');
        }
        return apiName;
    }

    private static String currentNamespace() {
        String objectName = Mapping_Definition__c.SObjectType.getDescribe().getName();
        return objectName.countMatches('__') >= 2 ? objectName.substringBefore('__') : '';
    }
}
