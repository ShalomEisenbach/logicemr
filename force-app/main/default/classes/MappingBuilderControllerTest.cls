@IsTest
private class MappingBuilderControllerTest {
    @IsTest
    static void getSourceObjectOptionsReturnsQueryableAccessibleObjects() {
        Test.startTest();
        List<MappingBuilderController.ObjectOption> options = MappingBuilderController.getSourceObjectOptions();
        Test.stopTest();

        System.assert(options.size() > 0, 'Queryable objects should be returned');
        System.assertEquals(
            true,
            containsObject(options, 'Contact'),
            'Contact should be available as a source object'
        );
        System.assertEquals(
            true,
            containsObject(options, Patient__c.SObjectType.getDescribe().getName()),
            'Patient should be available as a source object'
        );
        System.assertEquals(
            false,
            containsObject(options, 'ApexClass'),
            'ApexClass is a system object and should be filtered out'
        );
        System.assertEquals(
            false,
            containsObject(options, 'ContactHistory'),
            'History objects should be filtered out'
        );
        System.assertEquals(
            false,
            containsObject(options, 'ContactShare'),
            'Share objects should be filtered out'
        );

        String previousLabel = '';
        for (MappingBuilderController.ObjectOption option : options) {
            System.assertNotEquals(null, option.label, 'Every option needs a label');
            System.assertNotEquals(null, option.apiName, 'Every option needs an API name');
            System.assertEquals(
                false,
                option.apiName.endsWith('History') || option.apiName.endsWith('Share'),
                'History and Share objects must not appear: ' + option.apiName
            );
            System.assert(
                previousLabel.compareTo(option.label.toLowerCase()) <= 0 ||
                    previousLabel == '',
                'Options should be sorted by label'
            );
            previousLabel = option.label.toLowerCase();
        }
    }

    @IsTest
    static void getFieldsReturnsAccessibleFieldsForSourceAndPatient() {
        Test.startTest();
        List<MappingBuilderController.FieldOption> contactFields = MappingBuilderController.getFields(
            'Contact'
        );
        List<MappingBuilderController.FieldOption> patientFields = MappingBuilderController.getFields(
            MappingBuilderController.DEFAULT_TARGET_OBJECT
        );
        List<MappingBuilderController.FieldOption> localPatientFields = MappingBuilderController.getFields(
            'Patient__c'
        );
        Test.stopTest();

        MappingBuilderController.FieldOption firstName = findField(contactFields, 'FirstName');
        System.assertNotEquals(null, firstName, 'Contact.FirstName should be discoverable');
        System.assertNotEquals(null, firstName.label, 'FirstName should have a describe label');
        System.assertEquals('STRING', firstName.type, 'FirstName should be a STRING field');

        MappingBuilderController.FieldOption lastName = findField(contactFields, 'LastName');
        System.assertNotEquals(null, lastName, 'Contact.LastName should be discoverable');
        System.assertEquals('STRING', lastName.type, 'LastName should be a STRING field');

        System.assertNotEquals(
            null,
            findField(patientFields, 'First_Name__c'),
            'Patient First_Name__c should be discoverable via lfemr__Patient__c'
        );
        System.assertNotEquals(
            null,
            findField(patientFields, 'Source_System_Id__c'),
            'Patient Source_System_Id__c should be discoverable'
        );
        System.assertEquals(
            patientFields.size(),
            localPatientFields.size(),
            'Namespaced and local Patient API names should resolve to the same fields'
        );
        System.assert(
            contactFields.size() > 1,
            'Contact should expose more than one accessible field'
        );

        List<MappingBuilderController.FieldOption> definitionFields = MappingBuilderController.getFields(
            'lfemr__Mapping_Definition__c'
        );
        System.assertNotEquals(
            null,
            findField(definitionFields, 'Source_Object__c'),
            'Namespaced Mapping Definition should resolve and return Source_Object__c'
        );
    }

    @IsTest
    static void getFieldsRejectsBlankOrUnknownObject() {
        Boolean blankThrew = false;
        Boolean unknownThrew = false;

        Test.startTest();
        try {
            MappingBuilderController.getFields('');
        } catch (AuraHandledException e) {
            blankThrew = true;
        }
        try {
            MappingBuilderController.getFields('Not_A_Real_Object__c');
        } catch (AuraHandledException e) {
            unknownThrew = true;
        }
        Test.stopTest();

        System.assertEquals(true, blankThrew, 'Blank object API name should be rejected');
        System.assertEquals(true, unknownThrew, 'Unknown object API name should be rejected');
    }

    @IsTest
    static void saveMappingInsertsDefinitionRowsAndValueMaps() {
        MappingBuilderController.MappingDefinitionDto definition = newDefinition(
            'Contact to Patient',
            'Contact'
        );
        definition.description = 'Maps Contact into Patient';
        definition.active = true;

        List<MappingBuilderController.FieldMappingRowDto> rows = new List<MappingBuilderController.FieldMappingRowDto>{
            newRow(null, 'FirstName', 'First_Name__c', null, null, null, null, null, null),
            newRow(null, null, 'Status__c', 'Default Value', 'Active', null, null, 20, null),
            newRow(null, 'Birthdate', 'Date_of_Birth__c', 'Date Format', null, 'yyyy-MM-dd', null, 30, null),
            newRow(null, 'FirstName,LastName', 'MRN__c', 'Concatenate', null, null, '-', 40, null),
            newRow(
                null,
                'Salutation',
                'Sex_at_Birth__c',
                'Picklist Value Map',
                null,
                null,
                null,
                50,
                new List<MappingBuilderController.ValueMapDto>{
                    null,
                    newValueMap('', ''),
                    newValueMap('Mr.', 'Male'),
                    newValueMap('Ms.', 'Female')
                }
            )
        };

        Test.startTest();
        Id mappingId = MappingBuilderController.saveMapping(definition, rows);
        Test.stopTest();

        System.assertNotEquals(null, mappingId, 'Save should return the Mapping Definition Id');

        Mapping_Definition__c stored = [
            SELECT
                Name,
                Description__c,
                Source_Object__c,
                Target_Object__c,
                Match_Target_Field__c,
                Active__c
            FROM Mapping_Definition__c
            WHERE Id = :mappingId
        ];
        System.assertEquals('Contact to Patient', stored.Name, 'Name should persist');
        System.assertEquals(
            'Maps Contact into Patient',
            stored.Description__c,
            'Description should persist'
        );
        System.assertEquals('Contact', stored.Source_Object__c, 'Source object should persist');
        System.assertEquals(
            MappingBuilderController.DEFAULT_TARGET_OBJECT,
            stored.Target_Object__c,
            'Target should always be Patient'
        );
        System.assertEquals(
            MappingBuilderController.DEFAULT_MATCH_FIELD,
            stored.Match_Target_Field__c,
            'Match field should default to Source_System_Id__c'
        );
        System.assertEquals(true, stored.Active__c, 'Active should persist');

        List<Field_Mapping__c> fieldRows = [
            SELECT
                Source_Field__c,
                Target_Field__c,
                Transformation_Type__c,
                Default_Value__c,
                Format_Pattern__c,
                Concat_Separator__c,
                Sort_Order__c
            FROM Field_Mapping__c
            WHERE Mapping_Definition__c = :mappingId
            ORDER BY Sort_Order__c
        ];
        System.assertEquals(5, fieldRows.size(), 'All five field mapping rows should be inserted');
        System.assertEquals('FirstName', fieldRows[0].Source_Field__c, 'Direct source field');
        System.assertEquals('First_Name__c', fieldRows[0].Target_Field__c, 'Direct target field');
        System.assertEquals('Direct', fieldRows[0].Transformation_Type__c, 'Direct transform');
        System.assertEquals('Default Value', fieldRows[1].Transformation_Type__c, 'Default transform');
        System.assertEquals('Active', fieldRows[1].Default_Value__c, 'Default value should persist');
        System.assertEquals('yyyy-MM-dd', fieldRows[2].Format_Pattern__c, 'Date pattern should persist');
        System.assertEquals('FirstName,LastName', fieldRows[3].Source_Field__c, 'Concat fields');
        System.assertEquals('-', fieldRows[3].Concat_Separator__c, 'Concat separator should persist');
        System.assertEquals(
            'Picklist Value Map',
            fieldRows[4].Transformation_Type__c,
            'Picklist transform should persist'
        );

        List<Value_Map__c> valueMaps = [
            SELECT Source_Value__c, Target_Value__c
            FROM Value_Map__c
            WHERE Field_Mapping__c = :fieldRows[4].Id
            ORDER BY Source_Value__c
        ];
        System.assertEquals(2, valueMaps.size(), 'Both picklist value maps should be inserted');
        System.assertEquals('Mr.', valueMaps[0].Source_Value__c, 'First source value');
        System.assertEquals('Male', valueMaps[0].Target_Value__c, 'First target value');
        System.assertEquals('Ms.', valueMaps[1].Source_Value__c, 'Second source value');
        System.assertEquals('Female', valueMaps[1].Target_Value__c, 'Second target value');
    }

    @IsTest
    static void getMappingLoadsDefinitionRowsAndValueMaps() {
        Id mappingId = insertSavedMapping();

        Test.startTest();
        MappingBuilderController.MappingPayload payload = MappingBuilderController.getMapping(
            mappingId
        );
        Test.stopTest();

        System.assertEquals(mappingId, payload.definition.id, 'Loaded Id should match');
        System.assertEquals('Contact to Patient', payload.definition.name, 'Name should load');
        System.assertEquals('Contact', payload.definition.sourceObject, 'Source object should load');
        System.assertEquals(
            MappingBuilderController.DEFAULT_TARGET_OBJECT,
            payload.definition.targetObject,
            'Target object should load'
        );
        System.assertEquals(true, payload.definition.active, 'Active should load');
        System.assertEquals(3, payload.rows.size(), 'All saved rows should load');
        System.assertEquals('FirstName', payload.rows[0].sourceField, 'First row source should load');
        System.assertEquals(
            'Picklist Value Map',
            payload.rows[2].transformationType,
            'Picklist row should load'
        );
        System.assertEquals(1, payload.rows[2].valueMaps.size(), 'Value maps should load with the row');
        System.assertEquals('M', payload.rows[2].valueMaps[0].sourceValue, 'Source value should load');
        System.assertEquals('Male', payload.rows[2].valueMaps[0].targetValue, 'Target value should load');
    }

    @IsTest
    static void saveMappingUpdatesExistingAndReplacesRemovedRows() {
        Id mappingId = insertSavedMapping();
        MappingBuilderController.MappingPayload original = MappingBuilderController.getMapping(
            mappingId
        );

        MappingBuilderController.MappingDefinitionDto definition = original.definition;
        definition.name = 'Contact to Patient Updated';
        definition.active = false;
        definition.matchTargetField = 'Last_Name__c';

        MappingBuilderController.FieldMappingRowDto kept = original.rows[0];
        kept.targetField = 'Last_Name__c';
        MappingBuilderController.FieldMappingRowDto keptPicklist = original.rows[2];
        keptPicklist.valueMaps = new List<MappingBuilderController.ValueMapDto>{
            newValueMap('F', 'Female')
        };
        MappingBuilderController.FieldMappingRowDto added = newRow(
            null,
            'LastName',
            'Last_Name__c',
            'Trim',
            null,
            null,
            null,
            60,
            null
        );

        Test.startTest();
        Id updatedId = MappingBuilderController.saveMapping(
            definition,
            new List<MappingBuilderController.FieldMappingRowDto>{ kept, keptPicklist, added }
        );
        Test.stopTest();

        System.assertEquals(mappingId, updatedId, 'Upsert should keep the same Mapping Definition');

        Mapping_Definition__c stored = [
            SELECT Name, Active__c, Match_Target_Field__c
            FROM Mapping_Definition__c
            WHERE Id = :mappingId
        ];
        System.assertEquals('Contact to Patient Updated', stored.Name, 'Name should update');
        System.assertEquals(false, stored.Active__c, 'Active should update');
        System.assertEquals(
            'Last_Name__c',
            stored.Match_Target_Field__c,
            'Match target field should update'
        );

        List<Field_Mapping__c> fieldRows = [
            SELECT Id, Source_Field__c, Target_Field__c, Transformation_Type__c
            FROM Field_Mapping__c
            WHERE Mapping_Definition__c = :mappingId
            ORDER BY Sort_Order__c
        ];
        System.assertEquals(3, fieldRows.size(), 'Removed rows should be deleted on save');
        System.assertEquals(kept.id, fieldRows[0].Id, 'Kept row should be upserted in place');
        System.assertEquals(
            'Last_Name__c',
            fieldRows[0].Target_Field__c,
            'Updated target field should persist'
        );
        System.assertEquals(keptPicklist.id, fieldRows[1].Id, 'Picklist row should be kept');
        System.assertEquals('LastName', fieldRows[2].Source_Field__c, 'New row should be inserted');
        System.assertEquals('Trim', fieldRows[2].Transformation_Type__c, 'New transform should persist');
        List<Value_Map__c> replacedMaps = [
            SELECT Source_Value__c, Target_Value__c
            FROM Value_Map__c
            WHERE Field_Mapping__c = :keptPicklist.id
        ];
        System.assertEquals(1, replacedMaps.size(), 'Kept picklist row should replace its value maps');
        System.assertEquals('F', replacedMaps[0].Source_Value__c, 'Replaced source value should persist');
        System.assertEquals(
            'Female',
            replacedMaps[0].Target_Value__c,
            'Replaced target value should persist'
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Field_Mapping__c WHERE Id = :original.rows[1].id],
            'Default Value row that was omitted should be deleted'
        );
    }

    @IsTest
    static void saveMappingAndGetMappingRejectInvalidInput() {
        Boolean missingDefinition = false;
        Boolean missingName = false;
        Boolean missingSource = false;
        Boolean missingRows = false;
        Boolean missingTarget = false;
        Boolean missingDefault = false;
        Boolean missingFormat = false;
        Boolean missingPicklist = false;
        Boolean missingConcat = false;
        Boolean nullRow = false;
        Boolean unknownTransform = false;
        Boolean missingMappingId = false;
        Boolean unknownMapping = false;

        MappingBuilderController.MappingDefinitionDto unnamed = newDefinition(null, 'Contact');
        MappingBuilderController.MappingDefinitionDto noSource = newDefinition('Named', null);
        MappingBuilderController.FieldMappingRowDto validRow = newRow(
            null,
            'FirstName',
            'First_Name__c',
            'Direct',
            null,
            null,
            null,
            10,
            null
        );

        Test.startTest();
        try {
            MappingBuilderController.saveMapping(null, new List<MappingBuilderController.FieldMappingRowDto>{ validRow });
        } catch (AuraHandledException e) {
            missingDefinition = true;
        }
        try {
            MappingBuilderController.saveMapping(
                unnamed,
                new List<MappingBuilderController.FieldMappingRowDto>{ validRow }
            );
        } catch (AuraHandledException e) {
            missingName = true;
        }
        try {
            MappingBuilderController.saveMapping(
                noSource,
                new List<MappingBuilderController.FieldMappingRowDto>{ validRow }
            );
        } catch (AuraHandledException e) {
            missingSource = true;
        }
        try {
            MappingBuilderController.saveMapping(newDefinition('Named', 'Contact'), null);
        } catch (AuraHandledException e) {
            missingRows = true;
        }
        try {
            MappingBuilderController.saveMapping(
                newDefinition('Named', 'Contact'),
                new List<MappingBuilderController.FieldMappingRowDto>{
                    newRow(null, 'FirstName', null, 'Direct', null, null, null, 10, null)
                }
            );
        } catch (AuraHandledException e) {
            missingTarget = true;
        }
        try {
            MappingBuilderController.saveMapping(
                newDefinition('Named', 'Contact'),
                new List<MappingBuilderController.FieldMappingRowDto>{
                    newRow(null, null, 'Status__c', 'Default Value', null, null, null, 10, null)
                }
            );
        } catch (AuraHandledException e) {
            missingDefault = true;
        }
        try {
            MappingBuilderController.saveMapping(
                newDefinition('Named', 'Contact'),
                new List<MappingBuilderController.FieldMappingRowDto>{
                    newRow(null, 'Birthdate', 'Date_of_Birth__c', 'Date Format', null, null, null, 10, null)
                }
            );
        } catch (AuraHandledException e) {
            missingFormat = true;
        }
        try {
            MappingBuilderController.saveMapping(
                newDefinition('Named', 'Contact'),
                new List<MappingBuilderController.FieldMappingRowDto>{
                    newRow(null, 'Salutation', 'Sex_at_Birth__c', 'Picklist Value Map', null, null, null, 10, null)
                }
            );
        } catch (AuraHandledException e) {
            missingPicklist = true;
        }
        try {
            MappingBuilderController.saveMapping(
                newDefinition('Named', 'Contact'),
                new List<MappingBuilderController.FieldMappingRowDto>{
                    newRow(null, null, 'MRN__c', 'Concatenate', null, null, '-', 10, null)
                }
            );
        } catch (AuraHandledException e) {
            missingConcat = true;
        }
        try {
            MappingBuilderController.saveMapping(
                newDefinition('Named', 'Contact'),
                new List<MappingBuilderController.FieldMappingRowDto>{ null }
            );
        } catch (AuraHandledException e) {
            nullRow = true;
        }
        try {
            MappingBuilderController.saveMapping(
                newDefinition('Named', 'Contact'),
                new List<MappingBuilderController.FieldMappingRowDto>{
                    newRow(null, 'FirstName', 'First_Name__c', 'Not A Transform', null, null, null, 10, null)
                }
            );
        } catch (AuraHandledException e) {
            unknownTransform = true;
        }
        try {
            MappingBuilderController.getMapping(null);
        } catch (AuraHandledException e) {
            missingMappingId = true;
        }
        try {
            MappingBuilderController.getMapping(UserInfo.getUserId());
        } catch (AuraHandledException e) {
            unknownMapping = true;
        }
        Test.stopTest();

        System.assertEquals(true, missingDefinition, 'Null definition should be rejected');
        System.assertEquals(true, missingName, 'Blank name should be rejected');
        System.assertEquals(true, missingSource, 'Blank source object should be rejected');
        System.assertEquals(true, missingRows, 'Empty rows should be rejected');
        System.assertEquals(true, missingTarget, 'Blank target field should be rejected');
        System.assertEquals(true, missingDefault, 'Default Value without a value should be rejected');
        System.assertEquals(true, missingFormat, 'Date Format without a pattern should be rejected');
        System.assertEquals(true, missingPicklist, 'Picklist map without value maps should be rejected');
        System.assertEquals(true, missingConcat, 'Concatenate without source fields should be rejected');
        System.assertEquals(true, nullRow, 'A null field mapping row should be rejected');
        System.assertEquals(true, unknownTransform, 'Unknown transformation should be rejected');
        System.assertEquals(true, missingMappingId, 'Blank mapping Id should be rejected');
        System.assertEquals(true, unknownMapping, 'Unknown mapping Id should be rejected');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Mapping_Definition__c],
            'Rejected saves must not insert a definition'
        );
    }

    private static Id insertSavedMapping() {
        MappingBuilderController.MappingDefinitionDto definition = newDefinition(
            'Contact to Patient',
            'Contact'
        );
        return MappingBuilderController.saveMapping(
            definition,
            new List<MappingBuilderController.FieldMappingRowDto>{
                newRow(null, 'FirstName', 'First_Name__c', 'Direct', null, null, null, 10, null),
                newRow(null, null, 'Status__c', 'Default Value', 'Active', null, null, 20, null),
                newRow(
                    null,
                    'Salutation',
                    'Sex_at_Birth__c',
                    'Picklist Value Map',
                    null,
                    null,
                    null,
                    30,
                    new List<MappingBuilderController.ValueMapDto>{ newValueMap('M', 'Male') }
                )
            }
        );
    }

    private static MappingBuilderController.MappingDefinitionDto newDefinition(
        String name,
        String sourceObject
    ) {
        MappingBuilderController.MappingDefinitionDto definition = new MappingBuilderController.MappingDefinitionDto();
        definition.name = name;
        definition.sourceObject = sourceObject;
        definition.active = true;
        return definition;
    }

    private static MappingBuilderController.FieldMappingRowDto newRow(
        Id rowId,
        String sourceField,
        String targetField,
        String transformationType,
        String defaultValue,
        String formatPattern,
        String concatSeparator,
        Decimal sortOrder,
        List<MappingBuilderController.ValueMapDto> valueMaps
    ) {
        MappingBuilderController.FieldMappingRowDto row = new MappingBuilderController.FieldMappingRowDto();
        row.id = rowId;
        row.sourceField = sourceField;
        row.targetField = targetField;
        row.transformationType = transformationType;
        row.defaultValue = defaultValue;
        row.formatPattern = formatPattern;
        row.concatSeparator = concatSeparator;
        row.sortOrder = sortOrder;
        row.valueMaps = valueMaps;
        return row;
    }

    private static MappingBuilderController.ValueMapDto newValueMap(
        String sourceValue,
        String targetValue
    ) {
        MappingBuilderController.ValueMapDto valueMap = new MappingBuilderController.ValueMapDto();
        valueMap.sourceValue = sourceValue;
        valueMap.targetValue = targetValue;
        return valueMap;
    }

    private static Boolean containsObject(
        List<MappingBuilderController.ObjectOption> options,
        String apiName
    ) {
        if (String.isBlank(apiName)) {
            return false;
        }
        String localName = apiName.contains('__') && apiName.countMatches('__') >= 2
            ? apiName.substringAfter('__')
            : apiName;
        for (MappingBuilderController.ObjectOption option : options) {
            if (option.apiName == apiName || option.apiName == localName) {
                return true;
            }
            if (option.apiName != null && option.apiName.endsWith('__' + localName)) {
                return true;
            }
        }
        return false;
    }

    private static MappingBuilderController.FieldOption findField(
        List<MappingBuilderController.FieldOption> fields,
        String apiName
    ) {
        for (MappingBuilderController.FieldOption field : fields) {
            if (field.apiName == apiName || (field.apiName != null && field.apiName.endsWith(apiName))) {
                return field;
            }
        }
        return null;
    }
}
