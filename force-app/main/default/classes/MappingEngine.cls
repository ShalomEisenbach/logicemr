public with sharing class MappingEngine {
    private static final String DEFAULT_TARGET_OBJECT = 'lfemr__Patient__c';
    private static final String SOURCE_SYSTEM_ID_FIELD = 'lfemr__Source_System_Id__c';
    private static final String TX_DIRECT = 'Direct';
    private static final String TX_DEFAULT = 'Default Value';
    private static final String TX_TRIM = 'Trim';
    private static final String TX_UPPER = 'Uppercase';
    private static final String TX_LOWER = 'Lowercase';
    private static final String TX_DATE = 'Date Format';
    private static final String TX_PICKLIST = 'Picklist Value Map';
    private static final String TX_CONCAT = 'Concatenate';

    private Map<String, Schema.SObjectType> globalDescribeCache;
    private Map<String, Map<String, Schema.SObjectField>> fieldMapCache;
    private String packageNamespace;

    public MappingResult run(Id mappingDefinitionId, Set<Id> sourceRecordIds, Boolean dryRun) {
        MappingResult result = new MappingResult();
        if (mappingDefinitionId == null || sourceRecordIds == null || sourceRecordIds.isEmpty()) {
            return result;
        }
        Boolean isDryRun = dryRun == true;

        MappingConfig config = loadConfig(mappingDefinitionId);
        if (config == null) {
            result.skipped = sourceRecordIds.size();
            result.errors.add(new RowError(null, 'Mapping definition was not found.'));
            return result;
        }
        if (config.definition.Active__c != true) {
            result.skipped = sourceRecordIds.size();
            result.errors.add(new RowError(null, 'Mapping definition is inactive.'));
            return result;
        }

        Schema.SObjectType sourceType = resolveSObjectType(config.definition.Source_Object__c);
        if (sourceType == null) {
            result.skipped = sourceRecordIds.size();
            result.errors.add(
                new RowError(null, 'Source object is not available: ' + config.definition.Source_Object__c)
            );
            return result;
        }

        String targetObjectApi = String.isBlank(config.definition.Target_Object__c)
            ? DEFAULT_TARGET_OBJECT
            : config.definition.Target_Object__c;
        Schema.SObjectType targetType = resolveSObjectType(targetObjectApi);
        if (targetType == null) {
            result.skipped = sourceRecordIds.size();
            result.errors.add(new RowError(null, 'Target object is not available: ' + targetObjectApi));
            return result;
        }

        Schema.DescribeSObjectResult sourceDescribe = sourceType.getDescribe();
        Schema.DescribeSObjectResult targetDescribe = targetType.getDescribe();
        Map<String, Schema.SObjectField> sourceFields = fieldMapFor(sourceDescribe);
        Map<String, Schema.SObjectField> targetFields = fieldMapFor(targetDescribe);

        List<SObject> sourceRecords = querySourceRecords(
            sourceDescribe,
            sourceFields,
            config.fieldMappings,
            sourceRecordIds
        );
        Set<Id> foundIds = new Set<Id>();
        for (SObject sourceRecord : sourceRecords) {
            foundIds.add(sourceRecord.Id);
        }
        for (Id sourceId : sourceRecordIds) {
            if (!foundIds.contains(sourceId)) {
                result.skipped++;
            }
        }

        String matchApi = String.isBlank(config.definition.Match_Target_Field__c)
            ? SOURCE_SYSTEM_ID_FIELD
            : config.definition.Match_Target_Field__c;
        Schema.SObjectField matchField = resolveField(targetFields, matchApi);
        if (matchField == null) {
            result.skipped += sourceRecords.size();
            result.errors.add(new RowError(null, 'Match target field is not available: ' + matchApi));
            return result;
        }
        Schema.DescribeFieldResult matchDescribe = matchField.getDescribe();
        String matchName = matchDescribe.getName();
        Schema.SObjectField sourceSystemIdField = resolveField(targetFields, SOURCE_SYSTEM_ID_FIELD);
        Boolean mappingSetsSourceSystemId = mappingTargetsField(config.fieldMappings, targetFields, SOURCE_SYSTEM_ID_FIELD);

        List<PendingRow> pendingRows = new List<PendingRow>();
        for (SObject sourceRecord : sourceRecords) {
            PendingRow row = buildTargetRow(
                sourceRecord,
                config,
                sourceFields,
                targetType,
                targetFields,
                sourceSystemIdField,
                mappingSetsSourceSystemId
            );
            pendingRows.add(row);
            if (row.hasError) {
                result.errors.addAll(row.errors);
                result.skipped++;
            }
        }

        List<PendingRow> successfulRows = new List<PendingRow>();
        for (PendingRow row : pendingRows) {
            if (!row.hasError) {
                successfulRows.add(row);
            }
        }

        Map<String, Id> existingByMatch = queryExistingTargets(
            targetDescribe.getName(),
            matchName,
            successfulRows
        );
        for (PendingRow row : successfulRows) {
            Object matchValue = row.target.get(matchName);
            if (matchValue != null) {
                Id existingId = existingByMatch.get(String.valueOf(matchValue));
                if (existingId != null) {
                    row.target.Id = existingId;
                    row.isUpdate = true;
                }
            }
        }

        if (isDryRun) {
            for (PendingRow row : pendingRows) {
                result.previewRecords.add(row.target);
            }
            for (PendingRow row : successfulRows) {
                if (row.isUpdate) {
                    result.updated++;
                } else {
                    result.created++;
                }
            }
            return result;
        }

        persist(successfulRows, matchDescribe, result);
        return result;
    }

    private MappingConfig loadConfig(Id mappingDefinitionId) {
        List<Mapping_Definition__c> definitions = [
            SELECT Id, Source_Object__c, Target_Object__c, Match_Target_Field__c, Active__c
            FROM Mapping_Definition__c
            WHERE Id = :mappingDefinitionId
            LIMIT 1
        ];
        if (definitions.isEmpty()) {
            return null;
        }

        MappingConfig config = new MappingConfig();
        config.definition = definitions[0];
        config.fieldMappings = [
            SELECT
                Id,
                Source_Field__c,
                Target_Field__c,
                Transformation_Type__c,
                Default_Value__c,
                Format_Pattern__c,
                Concat_Separator__c,
                Sort_Order__c,
                (SELECT Source_Value__c, Target_Value__c FROM ValueMaps__r)
            FROM Field_Mapping__c
            WHERE Mapping_Definition__c = :mappingDefinitionId
            ORDER BY Sort_Order__c NULLS LAST
        ];
        return config;
    }

    private List<SObject> querySourceRecords(
        Schema.DescribeSObjectResult sourceDescribe,
        Map<String, Schema.SObjectField> sourceFields,
        List<Field_Mapping__c> fieldMappings,
        Set<Id> sourceRecordIds
    ) {
        Set<String> selectNames = new Set<String>{ 'Id' };
        for (String requested : collectSourceFieldNames(fieldMappings)) {
            Schema.SObjectField token = resolveField(sourceFields, requested);
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
            ' WHERE Id IN :sourceRecordIds';
        List<SObject> queried = Database.query(soql);
        if (queried.isEmpty()) {
            return queried;
        }
        return Security.stripInaccessible(AccessType.READABLE, queried).getRecords();
    }

    private Set<String> collectSourceFieldNames(List<Field_Mapping__c> fieldMappings) {
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

    private PendingRow buildTargetRow(
        SObject sourceRecord,
        MappingConfig config,
        Map<String, Schema.SObjectField> sourceFields,
        Schema.SObjectType targetType,
        Map<String, Schema.SObjectField> targetFields,
        Schema.SObjectField sourceSystemIdField,
        Boolean mappingSetsSourceSystemId
    ) {
        PendingRow row = new PendingRow();
        row.sourceId = sourceRecord.Id;
        row.target = targetType.newSObject();
        Map<String, Object> populated = sourceRecord.getPopulatedFieldsAsMap();

        for (Field_Mapping__c mapping : config.fieldMappings) {
            if (String.isBlank(mapping.Target_Field__c)) {
                continue;
            }
            Schema.SObjectField targetToken = resolveField(targetFields, mapping.Target_Field__c);
            if (targetToken == null) {
                continue;
            }
            Schema.DescribeFieldResult targetDescribe = targetToken.getDescribe();
            try {
                Object rawValue = applyTransform(mapping, sourceRecord, sourceFields, populated);
                Object coerced = coerce(rawValue, targetDescribe);
                row.target.put(targetDescribe.getName(), coerced);
            } catch (Exception e) {
                row.hasError = true;
                row.errors.add(
                    new RowError(
                        sourceRecord.Id,
                        'Field ' + mapping.Target_Field__c + ': ' + e.getMessage()
                    )
                );
            }
        }

        if (!mappingSetsSourceSystemId && sourceSystemIdField != null) {
            String key = String.valueOf(config.definition.Source_Object__c) + ':' + String.valueOf(sourceRecord.Id);
            row.target.put(sourceSystemIdField.getDescribe().getName(), key);
        }
        return row;
    }

    private Object applyTransform(
        Field_Mapping__c mapping,
        SObject sourceRecord,
        Map<String, Schema.SObjectField> sourceFields,
        Map<String, Object> populated
    ) {
        String transform = String.isBlank(mapping.Transformation_Type__c) ? TX_DIRECT : mapping.Transformation_Type__c;
        if (transform == TX_DEFAULT) {
            return mapping.Default_Value__c;
        }
        if (transform == TX_CONCAT) {
            return applyConcatenate(mapping, sourceRecord, sourceFields, populated);
        }

        Object sourceValue = readSourceValue(sourceRecord, sourceFields, populated, mapping.Source_Field__c);
        if (transform == TX_TRIM) {
            return sourceValue == null ? null : String.valueOf(sourceValue).trim();
        }
        if (transform == TX_UPPER) {
            return sourceValue == null ? null : String.valueOf(sourceValue).toUpperCase();
        }
        if (transform == TX_LOWER) {
            return sourceValue == null ? null : String.valueOf(sourceValue).toLowerCase();
        }
        if (transform == TX_DATE) {
            return applyDateFormat(sourceValue, mapping.Format_Pattern__c);
        }
        if (transform == TX_PICKLIST) {
            return applyPicklistMap(sourceValue, mapping);
        }
        return sourceValue;
    }

    private String applyConcatenate(
        Field_Mapping__c mapping,
        SObject sourceRecord,
        Map<String, Schema.SObjectField> sourceFields,
        Map<String, Object> populated
    ) {
        List<String> parts = new List<String>();
        for (String fieldName : splitSourceFields(mapping.Source_Field__c)) {
            Object value = readSourceValue(sourceRecord, sourceFields, populated, fieldName);
            parts.add(value == null ? '' : String.valueOf(value));
        }
        String separator = mapping.Concat_Separator__c == null ? '' : mapping.Concat_Separator__c;
        return String.join(parts, separator);
    }

    private Object applyPicklistMap(Object sourceValue, Field_Mapping__c mapping) {
        if (sourceValue == null) {
            return null;
        }
        String sourceText = String.valueOf(sourceValue);
        if (mapping.ValueMaps__r != null) {
            for (Value_Map__c valueMap : mapping.ValueMaps__r) {
                if (valueMap.Source_Value__c == sourceText) {
                    return valueMap.Target_Value__c;
                }
            }
        }
        return sourceText;
    }

    private Object applyDateFormat(Object sourceValue, String pattern) {
        if (sourceValue == null) {
            return null;
        }
        if (sourceValue instanceof Date) {
            return (Date) sourceValue;
        }
        if (sourceValue instanceof Datetime) {
            return ((Datetime) sourceValue).date();
        }
        return parseDateWithPattern(String.valueOf(sourceValue), pattern);
    }

    private Date parseDateWithPattern(String input, String pattern) {
        if (String.isBlank(input)) {
            return null;
        }
        if (String.isBlank(pattern)) {
            return Date.valueOf(input);
        }
        Map<String, String> tokens = new Map<String, String>();
        Integer inputIndex = 0;
        Integer patternIndex = 0;
        List<String> tokenNames = new List<String>{ 'yyyy', 'HH', 'MM', 'mm', 'dd', 'ss' };
        while (patternIndex < pattern.length()) {
            Boolean matchedToken = false;
            String remainingPattern = pattern.substring(patternIndex);
            for (String token : tokenNames) {
                if (remainingPattern.startsWith(token)) {
                    if (inputIndex + token.length() > input.length()) {
                        throw new MappingException('Date value "' + input + '" does not match pattern ' + pattern);
                    }
                    tokens.put(token, input.substring(inputIndex, inputIndex + token.length()));
                    patternIndex += token.length();
                    inputIndex += token.length();
                    matchedToken = true;
                    break;
                }
            }
            if (!matchedToken) {
                if (inputIndex >= input.length() || pattern.substring(patternIndex, patternIndex + 1) != input.substring(inputIndex, inputIndex + 1)) {
                    throw new MappingException('Date value "' + input + '" does not match pattern ' + pattern);
                }
                patternIndex++;
                inputIndex++;
            }
        }
        if (inputIndex != input.length() || !tokens.containsKey('yyyy') || !tokens.containsKey('MM') || !tokens.containsKey('dd')) {
            throw new MappingException('Date value "' + input + '" does not match pattern ' + pattern);
        }
        return Date.newInstance(
            Integer.valueOf(tokens.get('yyyy')),
            Integer.valueOf(tokens.get('MM')),
            Integer.valueOf(tokens.get('dd'))
        );
    }

    private Object coerce(Object value, Schema.DescribeFieldResult targetField) {
        if (value == null || targetField == null) {
            return null;
        }
        Schema.DisplayType displayType = targetField.getType();
        if (displayType == Schema.DisplayType.Date) {
            if (value instanceof Date) {
                return (Date) value;
            }
            if (value instanceof Datetime) {
                return ((Datetime) value).date();
            }
            return Date.valueOf(String.valueOf(value));
        }
        if (displayType == Schema.DisplayType.DateTime) {
            if (value instanceof Datetime) {
                return (Datetime) value;
            }
            if (value instanceof Date) {
                return Datetime.newInstance((Date) value, Time.newInstance(0, 0, 0, 0));
            }
            return Datetime.valueOf(String.valueOf(value));
        }
        if (displayType == Schema.DisplayType.Double || displayType == Schema.DisplayType.Currency || displayType == Schema.DisplayType.Percent) {
            return value instanceof Decimal ? (Decimal) value : Decimal.valueOf(String.valueOf(value));
        }
        if (displayType == Schema.DisplayType.Integer) {
            return value instanceof Integer ? (Integer) value : Integer.valueOf(String.valueOf(value));
        }
        if (displayType == Schema.DisplayType.Boolean) {
            if (value instanceof Boolean) {
                return (Boolean) value;
            }
            String asText = String.valueOf(value);
            return 'true'.equalsIgnoreCase(asText) || '1'.equals(asText);
        }
        if (displayType == Schema.DisplayType.ID || displayType == Schema.DisplayType.Reference) {
            return value instanceof Id ? (Id) value : Id.valueOf(String.valueOf(value));
        }
        return String.valueOf(value);
    }

    private Object readSourceValue(
        SObject sourceRecord,
        Map<String, Schema.SObjectField> sourceFields,
        Map<String, Object> populated,
        String fieldApiName
    ) {
        if (String.isBlank(fieldApiName)) {
            return null;
        }
        Schema.SObjectField token = resolveField(sourceFields, fieldApiName.trim());
        if (token == null) {
            return null;
        }
        String resolvedName = token.getDescribe().getName();
        if (!populated.containsKey(resolvedName)) {
            return null;
        }
        return sourceRecord.get(resolvedName);
    }

    private List<String> splitSourceFields(String sourceFieldCsv) {
        List<String> names = new List<String>();
        if (String.isBlank(sourceFieldCsv)) {
            return names;
        }
        for (String part : sourceFieldCsv.split(',')) {
            String trimmed = part.trim();
            if (String.isNotBlank(trimmed)) {
                names.add(trimmed);
            }
        }
        return names;
    }

    private Boolean mappingTargetsField(
        List<Field_Mapping__c> fieldMappings,
        Map<String, Schema.SObjectField> targetFields,
        String fieldApiName
    ) {
        Schema.SObjectField expected = resolveField(targetFields, fieldApiName);
        if (expected == null) {
            return false;
        }
        String expectedName = expected.getDescribe().getName();
        for (Field_Mapping__c mapping : fieldMappings) {
            Schema.SObjectField mapped = resolveField(targetFields, mapping.Target_Field__c);
            if (mapped != null && mapped.getDescribe().getName() == expectedName) {
                return true;
            }
        }
        return false;
    }

    private Map<String, Id> queryExistingTargets(String targetObjectName, String matchName, List<PendingRow> rows) {
        Map<String, Id> existingByMatch = new Map<String, Id>();
        Set<String> matchValues = new Set<String>();
        for (PendingRow row : rows) {
            Object matchValue = row.target.get(matchName);
            if (matchValue != null) {
                matchValues.add(String.valueOf(matchValue));
            }
        }
        if (matchValues.isEmpty()) {
            return existingByMatch;
        }

        String soql =
            'SELECT Id, ' +
            matchName +
            ' FROM ' +
            targetObjectName +
            ' WHERE ' +
            matchName +
            ' IN :matchValues';
        for (SObject existing : Database.query(soql)) {
            Object matchValue = existing.get(matchName);
            if (matchValue != null && !existingByMatch.containsKey(String.valueOf(matchValue))) {
                existingByMatch.put(String.valueOf(matchValue), existing.Id);
            }
        }
        return existingByMatch;
    }

    private void persist(List<PendingRow> rows, Schema.DescribeFieldResult matchDescribe, MappingResult result) {
        if (rows.isEmpty()) {
            return;
        }

        List<SObject> toInsert = new List<SObject>();
        List<SObject> toUpdate = new List<SObject>();
        List<PendingRow> insertRows = new List<PendingRow>();
        List<PendingRow> updateRows = new List<PendingRow>();
        for (PendingRow row : rows) {
            if (row.isUpdate) {
                toUpdate.add(row.target);
                updateRows.add(row);
            } else {
                toInsert.add(row.target);
                insertRows.add(row);
            }
        }

        if (!toInsert.isEmpty()) {
            toInsert = Security.stripInaccessible(AccessType.CREATABLE, toInsert).getRecords();
        }
        if (!toUpdate.isEmpty()) {
            toUpdate = Security.stripInaccessible(AccessType.UPDATABLE, toUpdate).getRecords();
        }

        if (matchDescribe.isExternalId()) {
            List<SObject> upsertRecords = new List<SObject>();
            List<PendingRow> upsertRows = new List<PendingRow>();
            upsertRecords.addAll(toInsert);
            upsertRows.addAll(insertRows);
            upsertRecords.addAll(toUpdate);
            upsertRows.addAll(updateRows);
            applyDmlResults(Database.upsert(upsertRecords, matchDescribe.getSObjectField(), false), upsertRows, result);
            return;
        }

        if (!toInsert.isEmpty()) {
            applyDmlResults(Database.insert(toInsert, false), insertRows, result);
        }
        if (!toUpdate.isEmpty()) {
            applyDmlResults(Database.update(toUpdate, false), updateRows, result);
        }
    }

    private void applyDmlResults(List<Database.UpsertResult> dmlResults, List<PendingRow> rows, MappingResult result) {
        for (Integer i = 0; i < dmlResults.size(); i++) {
            Database.UpsertResult dmlResult = dmlResults[i];
            PendingRow row = rows[i];
            if (dmlResult.isSuccess()) {
                if (dmlResult.isCreated()) {
                    result.created++;
                } else {
                    result.updated++;
                }
            } else {
                result.skipped++;
                result.errors.add(new RowError(row.sourceId, dmlResult.getErrors()[0].getMessage()));
            }
        }
    }

    private void applyDmlResults(List<Database.SaveResult> dmlResults, List<PendingRow> rows, MappingResult result) {
        for (Integer i = 0; i < dmlResults.size(); i++) {
            Database.SaveResult dmlResult = dmlResults[i];
            PendingRow row = rows[i];
            if (dmlResult.isSuccess()) {
                if (row.isUpdate) {
                    result.updated++;
                } else {
                    result.created++;
                }
            } else {
                result.skipped++;
                result.errors.add(new RowError(row.sourceId, dmlResult.getErrors()[0].getMessage()));
            }
        }
    }

    private Map<String, Schema.SObjectType> globalDescribe() {
        if (globalDescribeCache == null) {
            globalDescribeCache = Schema.getGlobalDescribe();
        }
        return globalDescribeCache;
    }

    private Map<String, Schema.SObjectField> fieldMapFor(Schema.DescribeSObjectResult describeResult) {
        if (fieldMapCache == null) {
            fieldMapCache = new Map<String, Map<String, Schema.SObjectField>>();
        }
        String objectName = describeResult.getName();
        if (!fieldMapCache.containsKey(objectName)) {
            fieldMapCache.put(objectName, describeResult.fields.getMap());
        }
        return fieldMapCache.get(objectName);
    }

    private Schema.SObjectType resolveSObjectType(String apiName) {
        if (String.isBlank(apiName)) {
            return null;
        }
        Map<String, Schema.SObjectType> describeMap = globalDescribe();
        if (describeMap.containsKey(apiName)) {
            return describeMap.get(apiName);
        }
        String localName = stripNamespace(apiName);
        if (describeMap.containsKey(localName)) {
            return describeMap.get(localName);
        }
        String namespacedName = qualifyWithNamespace(localName);
        if (namespacedName != localName && describeMap.containsKey(namespacedName)) {
            return describeMap.get(namespacedName);
        }
        return null;
    }

    private Schema.SObjectField resolveField(Map<String, Schema.SObjectField> fieldMap, String apiName) {
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
        String namespacedName = qualifyWithNamespace(localName);
        if (namespacedName != localName && fieldMap.containsKey(namespacedName)) {
            return fieldMap.get(namespacedName);
        }
        return null;
    }

    private String stripNamespace(String apiName) {
        if (String.isBlank(apiName)) {
            return apiName;
        }
        Integer separatorCount = apiName.countMatches('__');
        if (separatorCount >= 2) {
            return apiName.substringAfter('__');
        }
        return apiName;
    }

    private String qualifyWithNamespace(String localName) {
        String ns = currentNamespace();
        if (String.isBlank(ns) || String.isBlank(localName) || localName.startsWith(ns + '__')) {
            return localName;
        }
        return ns + '__' + localName;
    }

    private String currentNamespace() {
        if (packageNamespace != null) {
            return packageNamespace;
        }
        String objectName = Mapping_Definition__c.SObjectType.getDescribe().getName();
        packageNamespace = objectName.countMatches('__') >= 2 ? objectName.substringBefore('__') : '';
        return packageNamespace;
    }

    private class MappingConfig {
        Mapping_Definition__c definition;
        List<Field_Mapping__c> fieldMappings;
    }

    private class PendingRow {
        Id sourceId;
        SObject target;
        Boolean isUpdate = false;
        Boolean hasError = false;
        List<RowError> errors = new List<RowError>();
    }

    public class MappingResult {
        public Integer created = 0;
        public Integer updated = 0;
        public Integer skipped = 0;
        public List<RowError> errors = new List<RowError>();
        public List<SObject> previewRecords = new List<SObject>();
    }

    public class RowError {
        public Id sourceRecordId;
        public String message;

        public RowError(Id sourceRecordId, String message) {
            this.sourceRecordId = sourceRecordId;
            this.message = message;
        }
    }

    public class MappingException extends Exception {
    }
}
