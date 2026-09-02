public with sharing class MappingBuilderController {
    @TestVisible
    private static final String DEFAULT_TARGET_OBJECT = 'lfemr__Patient__c';
    @TestVisible
    private static final String DEFAULT_MATCH_FIELD = 'lfemr__Source_System_Id__c';
    @TestVisible
    private static final String TX_DIRECT = 'Direct';
    @TestVisible
    private static final String TX_DEFAULT = 'Default Value';
    @TestVisible
    private static final String TX_DATE = 'Date Format';
    @TestVisible
    private static final String TX_PICKLIST = 'Picklist Value Map';
    @TestVisible
    private static final String TX_CONCAT = 'Concatenate';

    private static final Set<String> TRANSFORMS = new Set<String>{
        TX_DIRECT,
        TX_DEFAULT,
        'Trim',
        'Uppercase',
        'Lowercase',
        TX_DATE,
        TX_PICKLIST,
        TX_CONCAT
    };

    private static final List<String> EXCLUDED_STANDARD_PREFIXES = new List<String>{
        'Apex',
        'AsyncApex',
        'AuthConfig',
        'AuthProvider',
        'AuthSession',
        'BackgroundOperation',
        'BrandTemplate',
        'CollaborationGroup',
        'CorsWhitelist',
        'CronJob',
        'CronTrigger',
        'CspTrustedSite',
        'CustomPermission',
        'Dashboard',
        'DuplicateRecord',
        'EntityDefinition',
        'EntityParticle',
        'EventBusSubscriber',
        'FieldDefinition',
        'FieldPermissions',
        'FlowDefinition',
        'FlowInterview',
        'FlowOrchestration',
        'Folder',
        'GrantedByLicense',
        'LightningExperienceTheme',
        'ListView',
        'LoginHistory',
        'LoginIp',
        'Macro',
        'NamedCredential',
        'Network',
        'OauthToken',
        'ObjectPermissions',
        'OrgWideEmailAddress',
        'PackageLicense',
        'PermissionSet',
        'PlatformEvent',
        'ProcessDefinition',
        'ProcessInstance',
        'ProcessNode',
        'Profile',
        'Publisher',
        'RecentlyViewed',
        'RecordType',
        'Report',
        'SamlSsoConfig',
        'SetupEntityAccess',
        'Site',
        'StaticResource',
        'StreamingChannel',
        'TenantUsageEntitlement',
        'ThirdPartyAccountLink',
        'Topic',
        'TwoFactor',
        'UserAppInfo',
        'UserAppMenu',
        'UserLicense',
        'UserLogin',
        'UserPackageLicense',
        'UserPermissionAccess',
        'UserPreference',
        'UserProvisioning',
        'UserRecordAccess',
        'UserRole',
        'VerificationHistory',
        'VisualforceAccessMetrics',
        'Wave',
        'WebLink',
        'WorkAccess',
        'WorkBadge',
        'WorkThanks'
    };

    public class ObjectOption implements Comparable {
        @AuraEnabled
        public String label { get; set; }
        @AuraEnabled
        public String apiName { get; set; }

        public Integer compareTo(Object other) {
            ObjectOption that = (ObjectOption) other;
            String thisLabel = this.label == null ? '' : this.label.toLowerCase();
            String thatLabel = that.label == null ? '' : that.label.toLowerCase();
            Integer byLabel = thisLabel.compareTo(thatLabel);
            if (byLabel != 0) {
                return byLabel;
            }
            String thisApi = this.apiName == null ? '' : this.apiName;
            String thatApi = that.apiName == null ? '' : that.apiName;
            return thisApi.compareTo(thatApi);
        }
    }

    public class FieldOption implements Comparable {
        @AuraEnabled
        public String apiName { get; set; }
        @AuraEnabled
        public String label { get; set; }
        @AuraEnabled
        public String type { get; set; }

        public Integer compareTo(Object other) {
            FieldOption that = (FieldOption) other;
            String thisLabel = this.label == null ? '' : this.label.toLowerCase();
            String thatLabel = that.label == null ? '' : that.label.toLowerCase();
            Integer byLabel = thisLabel.compareTo(thatLabel);
            if (byLabel != 0) {
                return byLabel;
            }
            String thisApi = this.apiName == null ? '' : this.apiName;
            String thatApi = that.apiName == null ? '' : that.apiName;
            return thisApi.compareTo(thatApi);
        }
    }

    public class MappingDefinitionDto {
        @AuraEnabled
        public Id id { get; set; }
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public String description { get; set; }
        @AuraEnabled
        public String sourceObject { get; set; }
        @AuraEnabled
        public String targetObject { get; set; }
        @AuraEnabled
        public String matchTargetField { get; set; }
        @AuraEnabled
        public Boolean active { get; set; }
    }

    public class ValueMapDto {
        @AuraEnabled
        public Id id { get; set; }
        @AuraEnabled
        public String sourceValue { get; set; }
        @AuraEnabled
        public String targetValue { get; set; }
    }

    public class FieldMappingRowDto {
        @AuraEnabled
        public Id id { get; set; }
        @AuraEnabled
        public String sourceField { get; set; }
        @AuraEnabled
        public String targetField { get; set; }
        @AuraEnabled
        public String transformationType { get; set; }
        @AuraEnabled
        public String defaultValue { get; set; }
        @AuraEnabled
        public String formatPattern { get; set; }
        @AuraEnabled
        public String concatSeparator { get; set; }
        @AuraEnabled
        public Decimal sortOrder { get; set; }
        @AuraEnabled
        public List<ValueMapDto> valueMaps { get; set; }
    }

    public class MappingPayload {
        @AuraEnabled
        public MappingDefinitionDto definition { get; set; }
        @AuraEnabled
        public List<FieldMappingRowDto> rows { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static List<ObjectOption> getSourceObjectOptions() {
        try {
            List<ObjectOption> options = new List<ObjectOption>();
            for (Schema.SObjectType token : Schema.getGlobalDescribe().values()) {
                Schema.DescribeSObjectResult describeResult = token.getDescribe();
                if (!isUsableSourceObject(describeResult)) {
                    continue;
                }
                ObjectOption option = new ObjectOption();
                option.label = describeResult.getLabel();
                option.apiName = describeResult.getName();
                options.add(option);
            }
            options.sort();
            return options;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getFields(String objectApiName) {
        try {
            if (String.isBlank(objectApiName)) {
                throw new AuraHandledException('Object API name is required.');
            }
            Schema.SObjectType token = resolveSObjectType(objectApiName);
            if (token == null) {
                throw new AuraHandledException('Object is not available: ' + objectApiName);
            }
            Schema.DescribeSObjectResult describeResult = token.getDescribe();
            if (!describeResult.isAccessible()) {
                throw new AuraHandledException('Object is not accessible: ' + objectApiName);
            }

            List<FieldOption> options = new List<FieldOption>();
            for (Schema.SObjectField fieldToken : describeResult.fields.getMap().values()) {
                Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
                if (!fieldDescribe.isAccessible() || fieldDescribe.isDeprecatedAndHidden()) {
                    continue;
                }
                FieldOption option = new FieldOption();
                option.apiName = fieldDescribe.getName();
                option.label = fieldDescribe.getLabel();
                option.type = String.valueOf(fieldDescribe.getType());
                options.add(option);
            }
            options.sort();
            return options;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static MappingPayload getMapping(Id mappingId) {
        try {
            if (mappingId == null) {
                throw new AuraHandledException('Mapping Id is required.');
            }
            List<Mapping_Definition__c> definitions = [
                SELECT
                    Id,
                    Name,
                    Description__c,
                    Source_Object__c,
                    Target_Object__c,
                    Match_Target_Field__c,
                    Active__c
                FROM Mapping_Definition__c
                WHERE Id = :mappingId
                LIMIT 1
            ];
            if (definitions.isEmpty()) {
                throw new AuraHandledException('Mapping definition was not found.');
            }

            MappingPayload payload = new MappingPayload();
            payload.definition = toDefinitionDto(definitions[0]);
            payload.rows = new List<FieldMappingRowDto>();

            for (Field_Mapping__c mapping : [
                SELECT
                    Id,
                    Source_Field__c,
                    Target_Field__c,
                    Transformation_Type__c,
                    Default_Value__c,
                    Format_Pattern__c,
                    Concat_Separator__c,
                    Sort_Order__c,
                    (SELECT Id, Source_Value__c, Target_Value__c FROM ValueMaps__r)
                FROM Field_Mapping__c
                WHERE Mapping_Definition__c = :mappingId
                ORDER BY Sort_Order__c NULLS LAST
            ]) {
                payload.rows.add(toRowDto(mapping));
            }
            return payload;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Id saveMapping(MappingDefinitionDto definition, List<FieldMappingRowDto> rows) {
        try {
            return persistMapping(definition, rows);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static Id persistMapping(MappingDefinitionDto definition, List<FieldMappingRowDto> rows) {
        if (definition == null) {
            throw new AuraHandledException('Mapping definition is required.');
        }
        if (String.isBlank(definition.name)) {
            throw new AuraHandledException('Mapping name is required.');
        }
        if (String.isBlank(definition.sourceObject)) {
            throw new AuraHandledException('Source object is required.');
        }
        if (rows == null || rows.isEmpty()) {
            throw new AuraHandledException('At least one field mapping is required.');
        }
        for (Integer i = 0; i < rows.size(); i++) {
            if (rows[i] == null) {
                throw new AuraHandledException('Field mapping row is required.');
            }
            validateRow(rows[i], i);
        }

        Mapping_Definition__c record = new Mapping_Definition__c();
        if (definition.id != null) {
            record.Id = definition.id;
        }
        record.Name = definition.name;
        record.Description__c = definition.description;
        record.Source_Object__c = definition.sourceObject;
        record.Target_Object__c = DEFAULT_TARGET_OBJECT;
        record.Match_Target_Field__c = String.isBlank(definition.matchTargetField)
            ? DEFAULT_MATCH_FIELD
            : definition.matchTargetField;
        record.Active__c = definition.active == true;
        upsert record;

        List<Field_Mapping__c> existing = [
            SELECT Id
            FROM Field_Mapping__c
            WHERE Mapping_Definition__c = :record.Id
        ];
        Set<Id> incomingIds = new Set<Id>();
        for (FieldMappingRowDto row : rows) {
            if (row != null && row.id != null) {
                incomingIds.add(row.id);
            }
        }
        List<Field_Mapping__c> fieldMappingsToDelete = new List<Field_Mapping__c>();
        for (Field_Mapping__c existingRow : existing) {
            if (!incomingIds.contains(existingRow.Id)) {
                fieldMappingsToDelete.add(existingRow);
            }
        }
        if (!fieldMappingsToDelete.isEmpty()) {
            delete fieldMappingsToDelete;
        }

        if (!incomingIds.isEmpty()) {
            List<Value_Map__c> staleValueMaps = [
                SELECT Id
                FROM Value_Map__c
                WHERE Field_Mapping__c IN :incomingIds
            ];
            if (!staleValueMaps.isEmpty()) {
                delete staleValueMaps;
            }
        }

        List<Field_Mapping__c> fieldRecords = new List<Field_Mapping__c>();
        for (Integer i = 0; i < rows.size(); i++) {
            FieldMappingRowDto row = rows[i];
            Field_Mapping__c fieldRecord = new Field_Mapping__c();
            if (row.id != null) {
                fieldRecord.Id = row.id;
            }
            fieldRecord.Mapping_Definition__c = record.Id;
            fieldRecord.Source_Field__c = row.sourceField;
            fieldRecord.Target_Field__c = row.targetField;
            fieldRecord.Transformation_Type__c = normalizeTransform(row.transformationType);
            fieldRecord.Default_Value__c = row.defaultValue;
            fieldRecord.Format_Pattern__c = row.formatPattern;
            fieldRecord.Concat_Separator__c = row.concatSeparator;
            fieldRecord.Sort_Order__c = row.sortOrder == null ? i * 10 : row.sortOrder;
            fieldRecords.add(fieldRecord);
        }
        upsert fieldRecords;

        List<Value_Map__c> valueMapsToInsert = new List<Value_Map__c>();
        for (Integer i = 0; i < rows.size(); i++) {
            List<ValueMapDto> valueMaps = rows[i].valueMaps;
            if (valueMaps == null || valueMaps.isEmpty()) {
                continue;
            }
            for (ValueMapDto valueMap : valueMaps) {
                if (valueMap == null) {
                    continue;
                }
                if (String.isBlank(valueMap.sourceValue) && String.isBlank(valueMap.targetValue)) {
                    continue;
                }
                valueMapsToInsert.add(
                    new Value_Map__c(
                        Field_Mapping__c = fieldRecords[i].Id,
                        Source_Value__c = valueMap.sourceValue,
                        Target_Value__c = valueMap.targetValue
                    )
                );
            }
        }
        if (!valueMapsToInsert.isEmpty()) {
            insert valueMapsToInsert;
        }
        return record.Id;
    }

    private static void validateRow(FieldMappingRowDto row, Integer index) {
        Integer displayIndex = index + 1;
        if (String.isBlank(row.targetField)) {
            throw new AuraHandledException('Target field is required on row ' + displayIndex + '.');
        }
        String transform = normalizeTransform(row.transformationType);
        if (transform == TX_DEFAULT) {
            if (String.isBlank(row.defaultValue)) {
                throw new AuraHandledException('Default value is required on row ' + displayIndex + '.');
            }
            return;
        }
        if (transform == TX_CONCAT) {
            if (splitSourceFields(row.sourceField).isEmpty()) {
                throw new AuraHandledException(
                    'At least one source field is required for Concatenate on row ' + displayIndex + '.'
                );
            }
            return;
        }
        if (String.isBlank(row.sourceField)) {
            throw new AuraHandledException('Source field is required on row ' + displayIndex + '.');
        }
        if (transform == TX_DATE && String.isBlank(row.formatPattern)) {
            throw new AuraHandledException('Format pattern is required on row ' + displayIndex + '.');
        }
        if (transform == TX_PICKLIST && !hasPopulatedValueMap(row.valueMaps)) {
            throw new AuraHandledException(
                'At least one value map is required on row ' + displayIndex + '.'
            );
        }
    }

    private static Boolean hasPopulatedValueMap(List<ValueMapDto> valueMaps) {
        if (valueMaps == null) {
            return false;
        }
        for (ValueMapDto valueMap : valueMaps) {
            if (
                valueMap != null &&
                String.isNotBlank(valueMap.sourceValue) &&
                String.isNotBlank(valueMap.targetValue)
            ) {
                return true;
            }
        }
        return false;
    }

    private static String normalizeTransform(String transformationType) {
        if (String.isBlank(transformationType)) {
            return TX_DIRECT;
        }
        if (!TRANSFORMS.contains(transformationType)) {
            throw new AuraHandledException('Unknown transformation type: ' + transformationType);
        }
        return transformationType;
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

    private static MappingDefinitionDto toDefinitionDto(Mapping_Definition__c record) {
        MappingDefinitionDto dto = new MappingDefinitionDto();
        dto.id = record.Id;
        dto.name = record.Name;
        dto.description = record.Description__c;
        dto.sourceObject = record.Source_Object__c;
        dto.targetObject = record.Target_Object__c;
        dto.matchTargetField = record.Match_Target_Field__c;
        dto.active = record.Active__c;
        return dto;
    }

    private static FieldMappingRowDto toRowDto(Field_Mapping__c mapping) {
        FieldMappingRowDto row = new FieldMappingRowDto();
        row.id = mapping.Id;
        row.sourceField = mapping.Source_Field__c;
        row.targetField = mapping.Target_Field__c;
        row.transformationType = mapping.Transformation_Type__c;
        row.defaultValue = mapping.Default_Value__c;
        row.formatPattern = mapping.Format_Pattern__c;
        row.concatSeparator = mapping.Concat_Separator__c;
        row.sortOrder = mapping.Sort_Order__c;
        row.valueMaps = new List<ValueMapDto>();
        if (mapping.ValueMaps__r != null) {
            for (Value_Map__c valueMap : mapping.ValueMaps__r) {
                ValueMapDto dto = new ValueMapDto();
                dto.id = valueMap.Id;
                dto.sourceValue = valueMap.Source_Value__c;
                dto.targetValue = valueMap.Target_Value__c;
                row.valueMaps.add(dto);
            }
        }
        return row;
    }

    private static Boolean isUsableSourceObject(Schema.DescribeSObjectResult describeResult) {
        if (describeResult == null || !describeResult.isQueryable() || !describeResult.isAccessible()) {
            return false;
        }
        if (describeResult.isCustomSetting() || describeResult.isDeprecatedAndHidden()) {
            return false;
        }
        String apiName = describeResult.getName();
        if (isPlatformStyleName(apiName)) {
            return false;
        }
        if (String.isNotBlank(describeResult.getAssociateEntityType())) {
            return false;
        }
        if (!describeResult.isCustom() && isExcludedStandardObject(apiName)) {
            return false;
        }
        return true;
    }

    private static Boolean isPlatformStyleName(String apiName) {
        return apiName.endsWith('History') ||
            apiName.endsWith('Share') ||
            apiName.endsWith('Feed') ||
            apiName.endsWith('ChangeEvent') ||
            apiName.endsWith('Tag') ||
            apiName.endsWith('__mdt') ||
            apiName.endsWith('__e') ||
            apiName.endsWith('__b') ||
            apiName.endsWith('__x') ||
            apiName.endsWith('__hd') ||
            apiName.endsWith('__dll');
    }

    private static Boolean isExcludedStandardObject(String apiName) {
        for (String prefix : EXCLUDED_STANDARD_PREFIXES) {
            if (apiName == prefix || apiName.startsWith(prefix)) {
                return true;
            }
        }
        return false;
    }

    private static Schema.SObjectType resolveSObjectType(String apiName) {
        if (String.isBlank(apiName)) {
            return null;
        }
        if (apiName == DEFAULT_TARGET_OBJECT || apiName == 'Patient__c') {
            return Patient__c.SObjectType;
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
