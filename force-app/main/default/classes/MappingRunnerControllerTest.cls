@IsTest
private class MappingRunnerControllerTest {
    @IsTest
    static void getActiveMappingsReturnsOnlyActiveDefinitions() {
        Mapping_Definition__c active = insertContactToPatientDefinition('Active Contact Map', true);
        insertContactToPatientDefinition('Inactive Contact Map', false);

        Test.startTest();
        List<MappingRunnerController.MappingOption> options = MappingRunnerController.getActiveMappings();
        Test.stopTest();

        System.assertEquals(1, options.size(), 'Only the active mapping should be returned');
        System.assertEquals(active.Id, options[0].id, 'Active mapping Id should match');
        System.assertEquals('Active Contact Map', options[0].name, 'Active mapping name should match');
        System.assertEquals('Contact', options[0].sourceObject, 'Source object should come from the definition');
    }

    @IsTest
    static void previewMappingReturnsValuesAndDoesNotInsertPatients() {
        Mapping_Definition__c definition = insertContactToPatientDefinition('Contact to Patient', true);
        insertStandardFieldMappings(definition.Id);
        Contact source = insertContact('Ada', 'Lovelace');

        Test.startTest();
        MappingRunnerController.PreviewResult preview = MappingRunnerController.previewMapping(
            definition.Id,
            source.Id
        );
        Test.stopTest();

        System.assertEquals(source.Id, preview.sourceRecordId, 'Preview should echo the source Id');
        System.assertEquals('Contact', preview.sourceObject, 'Preview should echo the source object');
        System.assertEquals(1, preview.summary.created, 'Dry run should report a would-be create');
        System.assertEquals(0, preview.summary.updated, 'Dry run should not report an update');
        System.assertEquals(0, preview.summary.errors.size(), 'Dry run should have no row errors');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Patient__c],
            'Preview must not insert a Patient'
        );

        System.assertEquals(
            'Ada',
            findPreviewRow(preview.rows, 'First_Name__c').sourceValue,
            'FirstName source value should appear'
        );
        System.assertEquals(
            'Ada',
            findPreviewRow(preview.rows, 'First_Name__c').targetValue,
            'FirstName should map to First_Name__c'
        );
        System.assertEquals(
            'Lovelace',
            findPreviewRow(preview.rows, 'Last_Name__c').targetValue,
            'LastName should map to Last_Name__c'
        );
        System.assertEquals(
            'Active',
            findPreviewRow(preview.rows, 'Status__c').targetValue,
            'Default Value should preview Status__c'
        );
        System.assertEquals(
            'Ada, Lovelace',
            findPreviewRow(preview.rows, 'MRN__c').sourceValue,
            'Concatenate should show joined source values'
        );
        System.assertEquals(
            'Ada-Lovelace',
            findPreviewRow(preview.rows, 'MRN__c').targetValue,
            'Concatenate should preview MRN__c'
        );
        System.assertEquals(
            'Contact:' + source.Id,
            findPreviewRow(preview.rows, 'Source_System_Id__c').targetValue,
            'Preview should include the composed Source_System_Id__c'
        );
    }

    @IsTest
    static void runMappingCommitsPatients() {
        Mapping_Definition__c definition = insertContactToPatientDefinition('Contact to Patient', true);
        insertStandardFieldMappings(definition.Id);
        Contact first = insertContact('Ada', 'Lovelace');
        Contact second = insertContact('Charles', 'Babbage');

        Test.startTest();
        MappingRunnerController.RunSummary summary = MappingRunnerController.runMapping(
            definition.Id,
            new List<Id>{ first.Id, second.Id }
        );
        Test.stopTest();

        System.assertEquals(2, summary.created, 'Run should create one Patient per Contact');
        System.assertEquals(0, summary.updated, 'First run should not update');
        System.assertEquals(0, summary.skipped, 'Both Contacts should map');
        System.assertEquals(0, summary.errors.size(), 'Run should have no row errors');

        List<Patient__c> patients = [
            SELECT First_Name__c, Last_Name__c, MRN__c, Status__c, Source_System_Id__c
            FROM Patient__c
            ORDER BY Last_Name__c
        ];
        System.assertEquals(2, patients.size(), 'Run must persist Patients');
        System.assertEquals('Charles', patients[0].First_Name__c, 'Babbage first name should persist');
        System.assertEquals('Charles-Babbage', patients[0].MRN__c, 'Babbage MRN should persist');
        System.assertEquals('Ada', patients[1].First_Name__c, 'Lovelace first name should persist');
        System.assertEquals('Active', patients[1].Status__c, 'Default Status should persist');
        System.assertEquals(
            'Contact:' + first.Id,
            patients[1].Source_System_Id__c,
            'Composed Source_System_Id__c should persist'
        );
    }

    @IsTest
    static void previewThenRunDoesNotDoubleCreateOnPreview() {
        Mapping_Definition__c definition = insertContactToPatientDefinition('Contact to Patient', true);
        insertStandardFieldMappings(definition.Id);
        Contact source = insertContact('Ada', 'Lovelace');

        Test.startTest();
        MappingRunnerController.PreviewResult preview = MappingRunnerController.previewMapping(
            definition.Id,
            source.Id
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Patient__c],
            'Preview in the same transaction must not commit'
        );
        MappingRunnerController.RunSummary summary = MappingRunnerController.runMapping(
            definition.Id,
            new List<Id>{ source.Id }
        );
        Test.stopTest();

        System.assertEquals(1, preview.summary.created, 'Preview should report a would-be create');
        System.assertEquals(1, summary.created, 'Run should commit the Patient');
        System.assertEquals(1, [SELECT COUNT() FROM Patient__c], 'Exactly one Patient should exist after run');
        System.assertEquals(
            'Ada',
            [SELECT First_Name__c FROM Patient__c LIMIT 1].First_Name__c,
            'Committed Patient should have the mapped first name'
        );
    }

    @IsTest
    static void startBackfillReturnsJobIdAndProcessesSourceRecords() {
        Mapping_Definition__c definition = insertContactToPatientDefinition('Contact to Patient', true);
        insertStandardFieldMappings(definition.Id);
        insertContact('Ada', 'Lovelace');

        Test.startTest();
        Id jobId = MappingRunnerController.startBackfill(definition.Id);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Backfill should return an AsyncApex job Id');
        System.assertEquals(1, [SELECT COUNT() FROM Patient__c], 'Enqueued batch should map the Contact');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM AsyncApexJob WHERE Id = :jobId],
            'Returned Id should be an AsyncApex job'
        );
    }

    @IsTest
    static void runnerMethodsRejectInvalidInput() {
        Mapping_Definition__c definition = insertContactToPatientDefinition('Contact to Patient', true);
        insertStandardFieldMappings(definition.Id);
        Mapping_Definition__c inactive = insertContactToPatientDefinition('Inactive', false);
        Mapping_Definition__c unknownSource = insertContactToPatientDefinition('Unknown Source', true);
        unknownSource.Source_Object__c = 'NotARealObject__c';
        update unknownSource;
        Contact source = insertContact('Ada', 'Lovelace');
        Boolean missingPreviewDefinition = false;
        Boolean missingPreviewSource = false;
        Boolean unknownDefinition = false;
        Boolean wrongSourceType = false;
        Boolean unknownSourceObject = false;
        Boolean missingRunDefinition = false;
        Boolean missingRunSources = false;
        Boolean missingBackfillDefinition = false;
        Boolean inactiveBackfill = false;
        Boolean unknownBackfill = false;

        Test.startTest();
        try {
            MappingRunnerController.previewMapping(null, source.Id);
        } catch (AuraHandledException e) {
            missingPreviewDefinition = true;
        }
        try {
            MappingRunnerController.previewMapping(definition.Id, null);
        } catch (AuraHandledException e) {
            missingPreviewSource = true;
        }
        try {
            MappingRunnerController.previewMapping(UserInfo.getUserId(), source.Id);
        } catch (AuraHandledException e) {
            unknownDefinition = true;
        }
        try {
            MappingRunnerController.previewMapping(definition.Id, UserInfo.getUserId());
        } catch (AuraHandledException e) {
            wrongSourceType = true;
        }
        try {
            MappingRunnerController.previewMapping(unknownSource.Id, source.Id);
        } catch (AuraHandledException e) {
            unknownSourceObject = true;
        }
        try {
            MappingRunnerController.runMapping(null, new List<Id>{ source.Id });
        } catch (AuraHandledException e) {
            missingRunDefinition = true;
        }
        try {
            MappingRunnerController.runMapping(definition.Id, null);
        } catch (AuraHandledException e) {
            missingRunSources = true;
        }
        try {
            MappingRunnerController.runMapping(definition.Id, new List<Id>());
        } catch (AuraHandledException e) {
            missingRunSources = true;
        }
        try {
            MappingRunnerController.startBackfill(null);
        } catch (AuraHandledException e) {
            missingBackfillDefinition = true;
        }
        try {
            MappingRunnerController.startBackfill(inactive.Id);
        } catch (AuraHandledException e) {
            inactiveBackfill = true;
        }
        try {
            MappingRunnerController.startBackfill(UserInfo.getUserId());
        } catch (AuraHandledException e) {
            unknownBackfill = true;
        }
        Test.stopTest();

        System.assertEquals(true, missingPreviewDefinition, 'Preview without a mapping Id should be rejected');
        System.assertEquals(true, missingPreviewSource, 'Preview without a source Id should be rejected');
        System.assertEquals(true, unknownDefinition, 'Unknown mapping Id should be rejected');
        System.assertEquals(true, wrongSourceType, 'A non-Contact Id should be rejected for a Contact mapping');
        System.assertEquals(true, unknownSourceObject, 'An unresolved source object should be rejected');
        System.assertEquals(true, missingRunDefinition, 'Run without a mapping Id should be rejected');
        System.assertEquals(true, missingRunSources, 'Run without source Ids should be rejected');
        System.assertEquals(true, missingBackfillDefinition, 'Backfill without a mapping Id should be rejected');
        System.assertEquals(true, inactiveBackfill, 'Inactive mapping should not enqueue a backfill');
        System.assertEquals(true, unknownBackfill, 'Unknown mapping Id should not enqueue a backfill');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Patient__c],
            'Rejected runner calls must not insert Patients'
        );
    }

    private static Mapping_Definition__c insertContactToPatientDefinition(String name, Boolean active) {
        Mapping_Definition__c definition = new Mapping_Definition__c(
            Name = name,
            Source_Object__c = 'Contact',
            Target_Object__c = 'lfemr__Patient__c',
            Match_Target_Field__c = 'lfemr__Source_System_Id__c',
            Active__c = active
        );
        insert definition;
        return definition;
    }

    private static void insertStandardFieldMappings(Id definitionId) {
        insert new List<Field_Mapping__c>{
            new Field_Mapping__c(
                Mapping_Definition__c = definitionId,
                Source_Field__c = 'FirstName',
                Target_Field__c = 'First_Name__c',
                Transformation_Type__c = 'Direct',
                Sort_Order__c = 10
            ),
            new Field_Mapping__c(
                Mapping_Definition__c = definitionId,
                Source_Field__c = 'LastName',
                Target_Field__c = 'Last_Name__c',
                Transformation_Type__c = 'Direct',
                Sort_Order__c = 20
            ),
            new Field_Mapping__c(
                Mapping_Definition__c = definitionId,
                Target_Field__c = 'Status__c',
                Transformation_Type__c = 'Default Value',
                Default_Value__c = 'Active',
                Sort_Order__c = 30
            ),
            new Field_Mapping__c(
                Mapping_Definition__c = definitionId,
                Source_Field__c = 'FirstName,LastName',
                Target_Field__c = 'MRN__c',
                Transformation_Type__c = 'Concatenate',
                Concat_Separator__c = '-',
                Sort_Order__c = 40
            )
        };
    }

    private static Contact insertContact(String firstName, String lastName) {
        Contact source = new Contact(FirstName = firstName, LastName = lastName);
        insert source;
        return source;
    }

    private static MappingRunnerController.PreviewRow findPreviewRow(
        List<MappingRunnerController.PreviewRow> rows,
        String targetField
    ) {
        for (MappingRunnerController.PreviewRow row : rows) {
            if (row.targetField == targetField || (row.targetField != null && row.targetField.endsWith(targetField))) {
                return row;
            }
        }
        System.assert(false, 'Expected a preview row for ' + targetField);
        return null;
    }
}
