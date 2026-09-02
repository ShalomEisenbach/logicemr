@IsTest
private class MappingInvocableTest {
    @IsTest
    static void mapRecordsCreatesPatientFromDefinitionId() {
        Mapping_Definition__c definition = insertContactToPatientDefinition();
        insertStandardFieldMappings(definition.Id);
        Contact source = insertContact('Ada', 'Lovelace');

        MappingInvocable.Request request = new MappingInvocable.Request();
        request.mappingDefinitionId = definition.Id;
        request.sourceRecordId = source.Id;

        Test.startTest();
        List<MappingInvocable.Result> results = MappingInvocable.mapRecords(
            new List<MappingInvocable.Request>{ request }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Invocable should return one result per request');
        System.assertEquals(true, results[0].success, 'Invocable should succeed for a valid mapping');
        System.assertEquals(source.Id, results[0].sourceRecordId, 'Result should echo the source record');
        System.assertEquals(1, results[0].created, 'Engine should report one created Patient');

        List<Patient__c> patients = queryPatients();
        System.assertEquals(1, patients.size(), 'Invocable should persist one Patient');
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
    static void mapRecordsResolvesMappingNameAndIsBulkSafe() {
        Mapping_Definition__c definition = insertContactToPatientDefinition();
        insertStandardFieldMappings(definition.Id);
        Contact first = insertContact('Ada', 'Lovelace');
        Contact second = insertContact('Charles', 'Babbage');

        MappingInvocable.Request byName = new MappingInvocable.Request();
        byName.mappingName = definition.Name;
        byName.sourceRecordId = first.Id;

        MappingInvocable.Request byId = new MappingInvocable.Request();
        byId.mappingDefinitionId = definition.Id;
        byId.sourceRecordId = second.Id;

        Test.startTest();
        List<MappingInvocable.Result> results = MappingInvocable.mapRecords(
            new List<MappingInvocable.Request>{ byName, byId }
        );
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Invocable should return a result for each request');
        System.assertEquals(true, results[0].success, 'Name-based request should succeed');
        System.assertEquals(true, results[1].success, 'Id-based request should succeed');
        System.assertEquals(
            2,
            results[0].created,
            'Both requests share one mapping and should see the grouped create count'
        );
        System.assertEquals(
            results[0].created,
            results[1].created,
            'Grouped requests should receive the same engine totals'
        );

        List<Patient__c> patients = queryPatients();
        System.assertEquals(2, patients.size(), 'One Patient should be created per Contact');
        Set<String> lastNames = new Set<String>{ patients[0].Last_Name__c, patients[1].Last_Name__c };
        System.assert(lastNames.contains('Lovelace'), 'Ada Lovelace should be mapped');
        System.assert(lastNames.contains('Babbage'), 'Charles Babbage should be mapped');
    }

    @IsTest
    static void mapRecordsReturnsErrorsForInvalidRequests() {
        Mapping_Definition__c definition = insertContactToPatientDefinition();
        insertStandardFieldMappings(definition.Id);
        Contact source = insertContact('Ada', 'Lovelace');

        MappingInvocable.Request missingSource = new MappingInvocable.Request();
        missingSource.mappingDefinitionId = definition.Id;

        MappingInvocable.Request missingMapping = new MappingInvocable.Request();
        missingMapping.sourceRecordId = source.Id;

        MappingInvocable.Request unknownName = new MappingInvocable.Request();
        unknownName.mappingName = 'Does Not Exist';
        unknownName.sourceRecordId = source.Id;

        Test.startTest();
        List<MappingInvocable.Result> results = MappingInvocable.mapRecords(
            new List<MappingInvocable.Request>{ missingSource, missingMapping, unknownName, null }
        );
        List<MappingInvocable.Result> empty = MappingInvocable.mapRecords(new List<MappingInvocable.Request>());
        Test.stopTest();

        System.assertEquals(4, results.size(), 'Invalid requests should still return aligned results');
        System.assertEquals(false, results[0].success, 'Missing source Id should fail');
        System.assertEquals(false, results[1].success, 'Missing mapping identity should fail');
        System.assertEquals(false, results[2].success, 'Unknown mapping name should fail');
        System.assertEquals(false, results[3].success, 'Null request should fail');
        System.assertEquals(0, queryPatients().size(), 'Invalid requests should not create Patients');
        System.assertEquals(0, empty.size(), 'Empty request list should return an empty result list');
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

    private static List<Patient__c> queryPatients() {
        return [
            SELECT Id, First_Name__c, Last_Name__c, MRN__c, Status__c, Source_System_Id__c
            FROM Patient__c
            ORDER BY Last_Name__c
        ];
    }
}
