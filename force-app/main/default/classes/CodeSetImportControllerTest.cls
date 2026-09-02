@IsTest
private class CodeSetImportControllerTest {
    @IsTest
    static void importCodesCreatesRows() {
        List<CodeSetImportController.CodeRow> rows = new List<CodeSetImportController.CodeRow>{
            newRow(2, 'ICD-10', 'E11.9', 'Type 2 diabetes mellitus without complications'),
            newRow(3, 'LOINC', '8867-4', 'Heart rate'),
            newRow(4, 'RxNorm', '197361', 'Amlodipine 5 MG Oral Tablet')
        };

        Test.startTest();
        CodeSetImportController.ImportResult result = CodeSetImportController.importCodes(rows);
        Test.stopTest();

        System.assertEquals(3, result.created, 'All three rows should be inserted');
        System.assertEquals(0, result.updated, 'No existing rows should be updated on first import');
        System.assertEquals(0, result.failed, 'No row should fail: ' + result.errors);
        System.assertEquals(0, result.errors.size(), 'Error list should be empty on a clean import');

        List<Code_Reference__c> stored = [
            SELECT Name, Code_System__c, Code__c, Display__c, Active__c
            FROM Code_Reference__c
            ORDER BY Code__c
        ];
        System.assertEquals(3, stored.size(), 'Exactly three Code Reference records should exist');
        System.assertEquals('RxNorm', stored[0].Code_System__c, 'Amlodipine should store RxNorm');
        System.assertEquals('197361', stored[0].Code__c, 'Amlodipine code should be stored');
        System.assertEquals(
            'Amlodipine 5 MG Oral Tablet',
            stored[0].Display__c,
            'Amlodipine display should be stored'
        );
        System.assertEquals(true, stored[0].Active__c, 'Imported codes should default to active');
        System.assertEquals('LOINC', stored[1].Code_System__c, 'Heart rate should store LOINC');
        System.assertEquals('Heart rate', stored[1].Display__c, 'LOINC display should be stored');
        System.assertEquals(
            'Type 2 diabetes mellitus without complications',
            stored[2].Display__c,
            'ICD-10 display should be stored'
        );
        System.assertEquals(
            'Type 2 diabetes mellitus without complications',
            stored[2].Name,
            'Name should use the display text as the code label'
        );
    }

    @IsTest
    static void reimportUpdatesExistingRowsInsteadOfDuplicating() {
        CodeSetImportController.importCodes(
            new List<CodeSetImportController.CodeRow>{
                newRow(2, 'ICD-10', 'E11.9', 'Type 2 diabetes'),
                newRow(3, 'CPT', '99213', 'Office visit')
            }
        );
        Id originalDiabetesId = [
            SELECT Id
            FROM Code_Reference__c
            WHERE Code_System__c = 'ICD-10' AND Code__c = 'E11.9'
            LIMIT 1
        ]
        .Id;

        List<CodeSetImportController.CodeRow> secondPass = new List<CodeSetImportController.CodeRow>{
            newRow(2, 'icd-10', 'E11.9', 'Type 2 diabetes mellitus without complications'),
            newRow(3, 'SNOMED', '44054006', 'Diabetes mellitus type 2')
        };

        Test.startTest();
        CodeSetImportController.ImportResult result = CodeSetImportController.importCodes(secondPass);
        Test.stopTest();

        System.assertEquals(1, result.created, 'Only the new SNOMED row should be inserted');
        System.assertEquals(1, result.updated, 'The matching ICD-10 row should be updated');
        System.assertEquals(0, result.failed, 'Re-import should not fail: ' + result.errors);

        List<Code_Reference__c> stored = [
            SELECT Id, Code_System__c, Code__c, Display__c
            FROM Code_Reference__c
            ORDER BY Code_System__c, Code__c
        ];
        System.assertEquals(3, stored.size(), 'Re-import must not create a duplicate ICD-10 E11.9 row');

        Code_Reference__c diabetes = null;
        for (Code_Reference__c record : stored) {
            if (record.Code_System__c == 'ICD-10' && record.Code__c == 'E11.9') {
                diabetes = record;
            }
        }
        System.assertNotEquals(null, diabetes, 'Updated ICD-10 row should still exist');
        System.assertEquals(
            originalDiabetesId,
            diabetes.Id,
            'Re-import should update the original record Id'
        );
        System.assertEquals(
            'Type 2 diabetes mellitus without complications',
            diabetes.Display__c,
            'Re-import should replace the previous display text'
        );
    }

    @IsTest
    static void importCodesReportsValidationErrorsAndSkipsInvalidRows() {
        String longCode = 'X'.repeat(CodeSetImportController.CODE_MAX_LENGTH + 1);
        List<CodeSetImportController.CodeRow> rows = new List<CodeSetImportController.CodeRow>{
            newRow(2, 'ICD-10', 'E11.9', 'Valid diabetes'),
            newRow(3, '', 'A00', 'Missing system'),
            newRow(4, 'ICD-9', '250.00', 'Unknown system'),
            newRow(5, 'CPT', '', 'Missing code'),
            newRow(6, 'LOINC', longCode, 'Code too long'),
            null
        };

        Test.startTest();
        CodeSetImportController.ImportResult result = CodeSetImportController.importCodes(rows);
        Test.stopTest();

        System.assertEquals(1, result.created, 'Only the valid ICD-10 row should be created');
        System.assertEquals(0, result.updated, 'No updates expected');
        System.assertEquals(5, result.failed, 'Five invalid rows should be reported');
        System.assertEquals(5, result.errors.size(), 'Each failed row should produce an error message');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Code_Reference__c],
            'Invalid rows must not be written'
        );
        System.assert(
            containsMessage(result.errors, 'Code System is required'),
            'Blank code system should be reported: ' + result.errors
        );
        System.assert(
            containsMessage(result.errors, 'Unknown Code System'),
            'ICD-9 should be rejected: ' + result.errors
        );
        System.assert(
            containsMessage(result.errors, 'Code is required'),
            'Blank code should be reported: ' + result.errors
        );
        System.assert(
            containsMessage(result.errors, '50 characters or fewer'),
            'Over-long code should be reported: ' + result.errors
        );
        System.assert(
            containsMessage(result.errors, 'Row is required'),
            'Null row should be reported: ' + result.errors
        );
    }

    @IsTest
    static void importCodesDeduplicatesSameKeyInOneBatch() {
        List<CodeSetImportController.CodeRow> rows = new List<CodeSetImportController.CodeRow>{
            newRow(2, 'CVX', '03', 'MMR first'),
            newRow(3, 'CVX', '03', 'MMR vaccine')
        };

        Test.startTest();
        CodeSetImportController.ImportResult result = CodeSetImportController.importCodes(rows);
        Test.stopTest();

        System.assertEquals(1, result.created, 'Duplicate keys in one file should collapse to one insert');
        System.assertEquals(0, result.updated, 'No prior row exists to update');
        System.assertEquals(0, result.failed, 'Collapsed duplicates are not failures');
        System.assertEquals(1, [SELECT COUNT() FROM Code_Reference__c WHERE Code__c = '03'], 'One CVX 03 row');
        System.assertEquals(
            'MMR vaccine',
            [SELECT Display__c FROM Code_Reference__c WHERE Code__c = '03' LIMIT 1].Display__c,
            'Last row for the same key should win'
        );
    }

    @IsTest
    static void importCodesUsesCodeAsLabelWhenDisplayIsBlank() {
        Test.startTest();
        CodeSetImportController.ImportResult result = CodeSetImportController.importCodes(
            new List<CodeSetImportController.CodeRow>{ newRow(2, 'SNOMED', '44054006', '  ') }
        );
        Test.stopTest();

        System.assertEquals(1, result.created, 'Blank display is allowed');
        Code_Reference__c stored = [
            SELECT Name, Display__c
            FROM Code_Reference__c
            WHERE Code__c = '44054006'
            LIMIT 1
        ];
        System.assertEquals('44054006', stored.Name, 'Name should fall back to the code');
        System.assertEquals('', stored.Display__c, 'Blank display should be stored as empty');
    }

    @IsTest
    static void importCodesReturnsOnlyErrorsWhenEveryRowIsInvalid() {
        CodeSetImportController.CodeRow missingNumber = new CodeSetImportController.CodeRow();
        missingNumber.codeSystem = 'NotASystem';
        missingNumber.code = 'X';
        missingNumber.display = null;

        Test.startTest();
        CodeSetImportController.ImportResult result = CodeSetImportController.importCodes(
            new List<CodeSetImportController.CodeRow>{ missingNumber }
        );
        Test.stopTest();

        System.assertEquals(0, result.created, 'Invalid-only import should create nothing');
        System.assertEquals(0, result.updated, 'Invalid-only import should update nothing');
        System.assertEquals(1, result.failed, 'The invalid row should be counted');
        System.assertEquals(0, [SELECT COUNT() FROM Code_Reference__c], 'No Code Reference should be written');
        System.assert(
            containsMessage(result.errors, 'Unknown Code System'),
            'Unknown system should be reported: ' + result.errors
        );
    }

    @IsTest
    static void importCodesRejectsEmptyList() {
        Boolean emptyThrew = false;
        Boolean nullThrew = false;

        Test.startTest();
        try {
            CodeSetImportController.importCodes(new List<CodeSetImportController.CodeRow>());
        } catch (AuraHandledException e) {
            emptyThrew = true;
        }
        try {
            CodeSetImportController.importCodes(null);
        } catch (AuraHandledException e) {
            nullThrew = true;
        }
        Test.stopTest();

        System.assertEquals(true, emptyThrew, 'Empty list should be rejected');
        System.assertEquals(true, nullThrew, 'Null list should be rejected');
    }

    @IsTest
    static void getCsvContentReturnsUploadedFileText() {
        String csv = 'Code System,Code,Display\nICD-10,E11.9,Type 2 diabetes';
        ContentVersion version = new ContentVersion(
            Title = 'codes',
            PathOnClient = 'codes.csv',
            VersionData = Blob.valueOf(csv),
            IsMajorVersion = true
        );
        insert version;
        Id documentId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ]
        .ContentDocumentId;

        Test.startTest();
        String downloaded = CodeSetImportController.getCsvContent(documentId);
        Test.stopTest();

        System.assertEquals(csv, downloaded, 'Uploaded CSV text should be returned for client-side parse');
    }

    @IsTest
    static void getCsvContentRejectsMissingFile() {
        Boolean blankThrew = false;
        Boolean missingThrew = false;

        Test.startTest();
        try {
            CodeSetImportController.getCsvContent(null);
        } catch (AuraHandledException e) {
            blankThrew = true;
        }
        try {
            CodeSetImportController.getCsvContent(UserInfo.getUserId());
        } catch (AuraHandledException e) {
            missingThrew = true;
        }
        Test.stopTest();

        System.assertEquals(true, blankThrew, 'Null ContentDocument Id should be rejected');
        System.assertEquals(true, missingThrew, 'Unknown ContentDocument Id should be rejected');
    }

    @IsTest
    static void importCodesTruncatesLongDisplayAndLabel() {
        String longDisplay = 'D'.repeat(CodeSetImportController.DISPLAY_MAX_LENGTH + 40);

        Test.startTest();
        CodeSetImportController.ImportResult result = CodeSetImportController.importCodes(
            new List<CodeSetImportController.CodeRow>{ newRow(2, 'CPT', '99213', longDisplay) }
        );
        Test.stopTest();

        System.assertEquals(1, result.created, 'Long display should be accepted after truncate');
        Code_Reference__c stored = [
            SELECT Name, Display__c
            FROM Code_Reference__c
            WHERE Code__c = '99213'
            LIMIT 1
        ];
        System.assertEquals(
            CodeSetImportController.DISPLAY_MAX_LENGTH,
            stored.Display__c.length(),
            'Display should be truncated to 255'
        );
        System.assertEquals(
            CodeSetImportController.NAME_MAX_LENGTH,
            stored.Name.length(),
            'Code Label (Name) should be truncated to the Salesforce Name limit'
        );
    }

    private static CodeSetImportController.CodeRow newRow(
        Integer rowNumber,
        String codeSystem,
        String code,
        String display
    ) {
        CodeSetImportController.CodeRow row = new CodeSetImportController.CodeRow();
        row.rowNumber = rowNumber;
        row.codeSystem = codeSystem;
        row.code = code;
        row.display = display;
        return row;
    }

    private static Boolean containsMessage(List<String> errors, String fragment) {
        for (String error : errors) {
            if (error != null && error.contains(fragment)) {
                return true;
            }
        }
        return false;
    }
}
