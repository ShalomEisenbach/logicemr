@IsTest
private class MappingBatchTest {
    @IsTest
    static void batchBackfillsMultipleSourceRecords() {
        Mapping_Definition__c definition = insertContactToPatientDefinition();
        insertStandardFieldMappings(definition.Id);
        Contact first = insertContact('Ada', 'Lovelace');
        Contact second = insertContact('Charles', 'Babbage');

        Test.startTest();
        Database.executeBatch(new MappingBatch(definition.Id), 1);
        Test.stopTest();

        List<Patient__c> patients = [
            SELECT Id, First_Name__c, Last_Name__c, MRN__c, Status__c, Source_System_Id__c
            FROM Patient__c
            ORDER BY Last_Name__c
        ];
        System.assertEquals(2, patients.size(), 'Batch should create one Patient per Contact');
        System.assertEquals('Charles', patients[0].First_Name__c, 'Babbage should be mapped');
        System.assertEquals('Babbage', patients[0].Last_Name__c, 'Babbage last name should map');
        System.assertEquals('Charles-Babbage', patients[0].MRN__c, 'Babbage MRN should be concatenated');
        System.assertEquals('Ada', patients[1].First_Name__c, 'Lovelace should be mapped');
        System.assertEquals('Lovelace', patients[1].Last_Name__c, 'Lovelace last name should map');
        System.assertEquals('Ada-Lovelace', patients[1].MRN__c, 'Lovelace MRN should be concatenated');
        System.assertEquals('Active', patients[0].Status__c, 'Default Status should be applied');
        System.assertEquals(
            'Contact:' + second.Id,
            patients[0].Source_System_Id__c,
            'Babbage should have a composed Source_System_Id__c'
        );
        System.assertEquals(
            'Contact:' + first.Id,
            patients[1].Source_System_Id__c,
            'Lovelace should have a composed Source_System_Id__c'
        );
        System.assertNotEquals(null, MappingBatch.lastSummary, 'finish should record a summary');
        System.assert(
            MappingBatch.lastSummary.contains('created=2'),
            'Stateful tally should report two creates: ' + MappingBatch.lastSummary
        );
    }

    @IsTest
    static void startRejectsMissingDefinition() {
        Boolean threw = false;

        try {
            Test.startTest();
            Database.executeBatch(new MappingBatch(UserInfo.getUserId()), 1);
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
            System.assert(
                e.getMessage().contains('not found') || e.getMessage().contains('required'),
                'Missing definition should fail start: ' + e.getMessage()
            );
        }

        System.assertEquals(true, threw, 'Batch start should reject a non-mapping Id');
        System.assertEquals(0, [SELECT COUNT() FROM Patient__c], 'Failed start should create no Patients');
    }

    @IsTest
    static void startRejectsUnknownSourceObject() {
        Mapping_Definition__c definition = insertContactToPatientDefinition();
        definition.Source_Object__c = 'NotARealObject__c';
        update definition;
        insertStandardFieldMappings(definition.Id);
        Boolean threw = false;

        try {
            Test.startTest();
            Database.executeBatch(new MappingBatch(definition.Id), 1);
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
            System.assert(
                e.getMessage().contains('Source object'),
                'Unknown source object should fail start: ' + e.getMessage()
            );
        }

        System.assertEquals(true, threw, 'Batch start should reject an unresolved source object');
    }

    private static Mapping_Definition__c insertContactToPatientDefinition() {
        Mapping_Definition__c definition = new Mapping_Definition__c(
            Name = 'Contact to Patient Backfill',
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
}
