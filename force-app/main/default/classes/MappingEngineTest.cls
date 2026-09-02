@IsTest
private class MappingEngineTest {
    @IsTest
    static void runCreatesPatientWithMappedValuesAndSourceSystemId() {
        Mapping_Definition__c definition = insertContactToPatientDefinition();
        insertStandardFieldMappings(definition.Id);
        Contact source = insertContact('Ada', 'Lovelace');

        Test.startTest();
        MappingEngine.MappingResult result = new MappingEngine()
            .run(definition.Id, new Set<Id>{ source.Id }, false);
        Test.stopTest();

        System.assertEquals(1, result.created, 'First run should create one Patient');
        System.assertEquals(0, result.updated, 'First run should not update a Patient');
        System.assertEquals(0, result.skipped, 'First run should not skip the Contact');
        System.assertEquals(0, result.errors.size(), 'First run should have no row errors');

        List<Patient__c> patients = queryPatients();
        System.assertEquals(1, patients.size(), 'Exactly one Patient should exist');
        System.assertEquals('Ada', patients[0].First_Name__c, 'FirstName should map to First_Name__c');
        System.assertEquals('Lovelace', patients[0].Last_Name__c, 'LastName should map to Last_Name__c');
        System.assertEquals('Ada-Lovelace', patients[0].MRN__c, 'Concatenate should build MRN__c');
        System.assertEquals('Active', patients[0].Status__c, 'Default Value should set Status__c');
        System.assertEquals(
            'Contact:' + source.Id,
            patients[0].Source_System_Id__c,
            'Source_System_Id__c should be the composed idempotency key'
        );
    }

    @IsTest
    static void rerunUpdatesTheSamePatient() {
        Mapping_Definition__c definition = insertContactToPatientDefinition();
        insertStandardFieldMappings(definition.Id);
        Contact source = insertContact('Ada', 'Lovelace');

        MappingEngine engine = new MappingEngine();
        engine.run(definition.Id, new Set<Id>{ source.Id }, false);

        source.LastName = 'Byron';
        update source;

        Test.startTest();
        MappingEngine.MappingResult result = engine.run(definition.Id, new Set<Id>{ source.Id }, false);
        Test.stopTest();

        System.assertEquals(0, result.created, 'Re-run should not create a second Patient');
        System.assertEquals(1, result.updated, 'Re-run should update the existing Patient');
        System.assertEquals(0, result.errors.size(), 'Re-run should have no row errors');

        List<Patient__c> patients = queryPatients();
        System.assertEquals(1, patients.size(), 'Re-run must stay idempotent and not duplicate');
        System.assertEquals('Byron', patients[0].Last_Name__c, 'Updated LastName should flow to the same Patient');
        System.assertEquals('Ada-Byron', patients[0].MRN__c, 'Concatenate on re-run should refresh MRN__c');
        System.assertEquals(
            'Contact:' + source.Id,
            patients[0].Source_System_Id__c,
            'Idempotency key should remain the composed Source_System_Id__c'
        );
    }

    @IsTest
    static void dryRunReturnsPreviewAndCreatesNothing() {
        Mapping_Definition__c definition = insertContactToPatientDefinition();
        insertStandardFieldMappings(definition.Id);
        Contact source = insertContact('Ada', 'Lovelace');

        Test.startTest();
        MappingEngine.MappingResult result = new MappingEngine()
            .run(definition.Id, new Set<Id>{ source.Id }, true);
        Test.stopTest();

        System.assertEquals(1, result.created, 'Dry run should report a would-be create');
        System.assertEquals(0, result.updated, 'Dry run should not report an update');
        System.assertEquals(1, result.previewRecords.size(), 'Dry run should return one preview record');
        System.assertEquals(
            'Ada',
            (String) result.previewRecords[0].get(Patient__c.First_Name__c),
            'Preview should include the mapped First_Name__c'
        );
        System.assertEquals(
            'Lovelace',
            (String) result.previewRecords[0].get(Patient__c.Last_Name__c),
            'Preview should include the mapped Last_Name__c'
        );
        System.assertEquals(
            'Ada-Lovelace',
            (String) result.previewRecords[0].get(Patient__c.MRN__c),
            'Preview should include the concatenated MRN__c'
        );
        System.assertEquals(
            'Active',
            (String) result.previewRecords[0].get(Patient__c.Status__c),
            'Preview should include the default Status__c'
        );
        System.assertEquals(
            'Contact:' + source.Id,
            (String) result.previewRecords[0].get(Patient__c.Source_System_Id__c),
            'Preview should include the composed Source_System_Id__c'
        );
        System.assertEquals(0, queryPatients().size(), 'Dry run must not insert a Patient');
    }

    @IsTest
    static void badDateIsRowErrorWithoutAbortingBatch() {
        Mapping_Definition__c definition = insertContactToPatientDefinition();
        insertStandardFieldMappings(definition.Id);
        insertFieldMapping(
            definition.Id,
            'Title',
            'Date_of_Birth__c',
            'Date Format',
            null,
            'yyyy-MM-dd',
            null,
            50
        );

        Contact good = insertContact('Ada', 'Lovelace');
        good.Title = '1815-12-10';
        Contact bad = insertContact('Bad', 'Dateperson');
        bad.Title = 'not-a-date';
        update new List<Contact>{ good, bad };

        Test.startTest();
        MappingEngine.MappingResult result = new MappingEngine()
            .run(definition.Id, new Set<Id>{ good.Id, bad.Id }, false);
        Test.stopTest();

        System.assertEquals(1, result.created, 'The valid Contact should still create a Patient');
        System.assertEquals(1, result.skipped, 'The bad date row should be skipped');
        System.assertEquals(1, result.errors.size(), 'The bad date should be captured as a single row error');
        System.assertEquals(bad.Id, result.errors[0].sourceRecordId, 'The row error should point at the bad Contact');
        System.assert(
            result.errors[0].message.contains('not-a-date'),
            'The row error should describe the bad date value'
        );

        List<Patient__c> patients = queryPatients();
        System.assertEquals(1, patients.size(), 'Only the valid Contact should persist a Patient');
        System.assertEquals('Ada', patients[0].First_Name__c, 'The surviving Patient should be Ada');
        System.assertEquals(Date.newInstance(1815, 12, 10), patients[0].Date_of_Birth__c, 'Valid date should map');
    }

    @IsTest
    static void trimUppercaseLowercaseAndPicklistValueMap() {
        Mapping_Definition__c definition = insertContactToPatientDefinition();
        insertFieldMapping(definition.Id, 'FirstName', 'First_Name__c', 'Trim', null, null, null, 10);
        insertFieldMapping(definition.Id, 'LastName', 'Last_Name__c', 'Uppercase', null, null, null, 20);
        insertFieldMapping(definition.Id, 'Department', 'FHIR_Id__c', 'Lowercase', null, null, null, 30);
        insertFieldMapping(definition.Id, null, 'Status__c', 'Default Value', 'Active', null, null, 40);
        insertFieldMapping(definition.Id, 'FirstName,LastName', 'MRN__c', 'Concatenate', null, null, '-', 50);
        Field_Mapping__c sexMapping = insertFieldMapping(
            definition.Id,
            'Salutation',
            'Sex_at_Birth__c',
            'Picklist Value Map',
            null,
            null,
            null,
            60
        );
        insertValueMap(sexMapping.Id, 'Ms.', 'Female');

        Contact source = new Contact(
            FirstName = '  Ada  ',
            LastName = 'Lovelace',
            Department = 'MATH',
            Salutation = 'Ms.'
        );
        insert source;

        Test.startTest();
        MappingEngine.MappingResult result = new MappingEngine()
            .run(definition.Id, new Set<Id>{ source.Id }, false);
        Test.stopTest();

        System.assertEquals(1, result.created, 'Transform example should create one Patient');
        Patient__c patient = queryPatients()[0];
        System.assertEquals('Ada', patient.First_Name__c, 'Trim should strip surrounding spaces');
        System.assertEquals('LOVELACE', patient.Last_Name__c, 'Uppercase should convert LastName');
        System.assertEquals('math', patient.FHIR_Id__c, 'Lowercase should convert Department');
        System.assertEquals('Female', patient.Sex_at_Birth__c, 'Picklist Value Map should translate Salutation');
    }

    @IsTest
    static void picklistPassesThroughWhenNoMatch() {
        Mapping_Definition__c definition = insertContactToPatientDefinition();
        insertStandardFieldMappings(definition.Id);
        Field_Mapping__c fhirMapping = insertFieldMapping(
            definition.Id,
            'Salutation',
            'FHIR_Id__c',
            'Picklist Value Map',
            null,
            null,
            null,
            60
        );
        insertValueMap(fhirMapping.Id, 'Ms.', 'Female');

        Contact source = insertContact('Ada', 'Lovelace');
        source.Salutation = 'Mr.';
        update source;

        Test.startTest();
        new MappingEngine().run(definition.Id, new Set<Id>{ source.Id }, false);
        Test.stopTest();

        System.assertEquals(
            'Mr.',
            queryPatients()[0].FHIR_Id__c,
            'Unmapped picklist values should pass through unchanged'
        );
    }

    @IsTest
    static void emptyInputReturnsZeroCounts() {
        Mapping_Definition__c definition = insertContactToPatientDefinition();

        Test.startTest();
        MappingEngine.MappingResult noIds = new MappingEngine().run(definition.Id, new Set<Id>(), false);
        MappingEngine.MappingResult nullDef = new MappingEngine().run(null, new Set<Id>{ UserInfo.getUserId() }, false);
        Test.stopTest();

        System.assertEquals(0, noIds.created, 'Empty source set should create nothing');
        System.assertEquals(0, noIds.updated, 'Empty source set should update nothing');
        System.assertEquals(0, noIds.skipped, 'Empty source set should skip nothing');
        System.assertEquals(0, nullDef.created, 'Null definition should create nothing');
    }

    @IsTest
    static void inactiveDefinitionSkipsAll() {
        Mapping_Definition__c definition = insertContactToPatientDefinition();
        definition.Active__c = false;
        update definition;
        insertStandardFieldMappings(definition.Id);
        Contact source = insertContact('Ada', 'Lovelace');

        Test.startTest();
        MappingEngine.MappingResult result = new MappingEngine()
            .run(definition.Id, new Set<Id>{ source.Id }, false);
        Test.stopTest();

        System.assertEquals(1, result.skipped, 'Inactive mapping should skip the source row');
        System.assertEquals(0, result.created, 'Inactive mapping should not create a Patient');
        System.assertEquals(0, queryPatients().size(), 'Inactive mapping should persist nothing');
    }

    @IsTest
    static void nonExternalIdMatchInsertsThenUpdates() {
        Mapping_Definition__c definition = insertContactToPatientDefinition();
        definition.Match_Target_Field__c = 'Last_Name__c';
        update definition;
        insertStandardFieldMappings(definition.Id);
        Contact source = insertContact('Ada', 'Lovelace');

        MappingEngine engine = new MappingEngine();
        MappingEngine.MappingResult first = engine.run(definition.Id, new Set<Id>{ source.Id }, false);
        System.assertEquals(1, first.created, 'Non-external-id match should insert on the first run');

        source.FirstName = 'Augusta';
        update source;

        Test.startTest();
        MappingEngine.MappingResult second = engine.run(definition.Id, new Set<Id>{ source.Id }, false);
        Test.stopTest();

        System.assertEquals(1, second.updated, 'Non-external-id match should update the existing Last_Name__c row');
        System.assertEquals(1, queryPatients().size(), 'Non-external-id match must not duplicate');
        System.assertEquals('Augusta', queryPatients()[0].First_Name__c, 'Update path should refresh mapped fields');
    }

    private static Mapping_Definition__c insertContactToPatientDefinition() {
        Mapping_Definition__c definition = new Mapping_Definition__c(
            Name = 'Contact to Patient',
            Source_Object__c = 'Contact',
            Target_Object__c = 'lfemr__Patient__c',
            Match_Target_Field__c = 'lfemr__Source_System_Id__c',
            Active__c = true
        );
        insert definition;
        return definition;
    }

    private static void insertStandardFieldMappings(Id definitionId) {
        insertFieldMapping(definitionId, 'FirstName', 'First_Name__c', 'Direct', null, null, null, 10);
        insertFieldMapping(definitionId, 'LastName', 'Last_Name__c', 'Direct', null, null, null, 20);
        insertFieldMapping(definitionId, null, 'Status__c', 'Default Value', 'Active', null, null, 30);
        insertFieldMapping(definitionId, 'FirstName,LastName', 'MRN__c', 'Concatenate', null, null, '-', 40);
    }

    private static Field_Mapping__c insertFieldMapping(
        Id definitionId,
        String sourceField,
        String targetField,
        String transformationType,
        String defaultValue,
        String formatPattern,
        String concatSeparator,
        Integer sortOrder
    ) {
        Field_Mapping__c mapping = new Field_Mapping__c(
            Mapping_Definition__c = definitionId,
            Source_Field__c = sourceField,
            Target_Field__c = targetField,
            Transformation_Type__c = transformationType,
            Default_Value__c = defaultValue,
            Format_Pattern__c = formatPattern,
            Concat_Separator__c = concatSeparator,
            Sort_Order__c = sortOrder
        );
        insert mapping;
        return mapping;
    }

    private static void insertValueMap(Id fieldMappingId, String sourceValue, String targetValue) {
        insert new Value_Map__c(
            Field_Mapping__c = fieldMappingId,
            Source_Value__c = sourceValue,
            Target_Value__c = targetValue
        );
    }

    private static Contact insertContact(String firstName, String lastName) {
        Contact source = new Contact(FirstName = firstName, LastName = lastName);
        insert source;
        return source;
    }

    private static List<Patient__c> queryPatients() {
        return [
            SELECT
                Id,
                First_Name__c,
                Last_Name__c,
                MRN__c,
                Status__c,
                Source_System_Id__c,
                Date_of_Birth__c,
                Sex_at_Birth__c,
                FHIR_Id__c
            FROM Patient__c
            ORDER BY CreatedDate
        ];
    }
}
