@IsTest
private class CodeSearchControllerTest {
    @IsTest
    static void searchByCodeAndDisplayReturnsExpectedShape() {
        Code_Reference__c diabetes = insertCode(
            'ICD-10',
            'E11.9',
            'Type 2 diabetes mellitus',
            true
        );
        insertCode('SNOMED', '44054006', 'Diabetes mellitus type 2', true);

        Test.startTest();
        List<CodeSearchController.CodeHit> byCode = CodeSearchController.search(
            'E11.9',
            new List<String>{ 'ICD-10', 'SNOMED' }
        );
        List<CodeSearchController.CodeHit> byDisplay = CodeSearchController.search(
            'diabetes mellitus',
            new List<String>{ 'ICD-10' }
        );
        Test.stopTest();

        System.assertEquals(1, byCode.size(), 'Code search should return the ICD-10 match');
        assertHit(byCode[0], diabetes.Id, 'ICD-10', 'E11.9', 'Type 2 diabetes mellitus');
        System.assertEquals(diabetes.Code__c, byCode[0].code, 'Returned code should match the inserted reference');
        System.assertEquals(1, byDisplay.size(), 'Display search filtered to ICD-10 should return one match');
        assertHit(byDisplay[0], diabetes.Id, 'ICD-10', 'E11.9', 'Type 2 diabetes mellitus');
    }

    @IsTest
    static void searchFiltersSystemsAndExcludesInactive() {
        Code_Reference__c icd = insertCode('ICD-10', 'E11.9', 'Type 2 diabetes mellitus', true);
        Code_Reference__c snomed = insertCode('SNOMED', '44054006', 'Diabetes mellitus type 2', true);
        Code_Reference__c lisinopril = insertCode('RxNorm', '197361', 'Lisinopril 10 MG Oral Tablet', true);
        insertCode('ICD-10', 'E10.9', 'Type 1 diabetes mellitus', false);

        Test.startTest();
        List<CodeSearchController.CodeHit> filtered = CodeSearchController.search(
            'diabetes',
            new List<String>{ 'ICD-10', 'SNOMED' }
        );
        List<CodeSearchController.CodeHit> rxnormOnly = CodeSearchController.search(
            'Lisinopril',
            new List<String>{ 'RxNorm' }
        );
        Test.stopTest();

        System.assertEquals(2, filtered.size(), 'Should return active ICD-10 and SNOMED diabetes codes');
        Set<String> systems = new Set<String>();
        Set<String> codes = new Set<String>();
        Set<Id> ids = new Set<Id>();
        for (CodeSearchController.CodeHit hit : filtered) {
            systems.add(hit.codeSystem);
            codes.add(hit.code);
            ids.add(hit.recordId);
            System.assertNotEquals(null, hit.display, 'Display should be populated');
            System.assertNotEquals(null, hit.recordId, 'Each hit should include the Code Reference Id');
        }
        System.assertEquals(true, ids.contains(icd.Id), 'Filtered hits should include the ICD-10 Code Reference Id');
        System.assertEquals(true, ids.contains(snomed.Id), 'Filtered hits should include the SNOMED Code Reference Id');
        System.assertEquals(true, systems.contains('ICD-10'), 'ICD-10 should be included');
        System.assertEquals(true, systems.contains('SNOMED'), 'SNOMED should be included');
        System.assertEquals(false, systems.contains('RxNorm'), 'RxNorm should be excluded by the system filter');
        System.assertEquals(false, codes.contains('E10.9'), 'Inactive codes should be excluded');
        System.assertEquals(1, rxnormOnly.size(), 'RxNorm filter should return the medication');
        assertHit(rxnormOnly[0], lisinopril.Id, 'RxNorm', '197361', 'Lisinopril 10 MG Oral Tablet');
    }

    @IsTest
    static void searchReturnsMultipleMatchesInOneCall() {
        insertCode('CPT', '71046', 'Chest X-ray 2 views', true);
        insertCode('LOINC', '36643-5', 'Chest X-ray views', true);
        insertCode('LOINC', '24323-8', 'Comprehensive metabolic panel', true);
        insertCode('CPT', '99213', 'Office visit established patient', true);

        Test.startTest();
        List<CodeSearchController.CodeHit> results = CodeSearchController.search(
            'Chest',
            new List<String>{ 'CPT', 'LOINC' }
        );
        List<CodeSearchController.CodeHit> allSystems = CodeSearchController.search('panel', new List<String>());
        Test.stopTest();

        System.assertEquals(2, results.size(), 'A single search should return both CPT and LOINC chest codes');
        System.assertEquals(1, allSystems.size(), 'Empty systems list should search all active codes');
        System.assertEquals('LOINC', allSystems[0].codeSystem, 'Unfiltered search should still return the matching system');
        System.assertEquals('24323-8', allSystems[0].code, 'Unfiltered search should return the matching code');
    }

    @IsTest
    static void blankOrUnmatchedSearchReturnsEmpty() {
        insertCode('ICD-10', 'I10', 'Essential hypertension', true);

        Test.startTest();
        List<CodeSearchController.CodeHit> blank = CodeSearchController.search('   ', new List<String>{ 'ICD-10' });
        List<CodeSearchController.CodeHit> nullTerm = CodeSearchController.search(null, new List<String>{ 'ICD-10' });
        List<CodeSearchController.CodeHit> unmatched = CodeSearchController.search(
            'NoSuchCode',
            new List<String>{ 'ICD-10' }
        );
        Test.stopTest();

        System.assertEquals(0, blank.size(), 'Whitespace-only search should return no rows');
        System.assertEquals(0, nullTerm.size(), 'Null search should return no rows');
        System.assertEquals(0, unmatched.size(), 'Unmatched search should return no rows');
    }

    private static Code_Reference__c insertCode(
        String codeSystem,
        String code,
        String display,
        Boolean active
    ) {
        Code_Reference__c row = new Code_Reference__c(
            Name = display.left(120),
            Code_System__c = codeSystem,
            Code__c = code,
            Display__c = display,
            Active__c = active
        );
        insert row;
        return row;
    }

    private static void assertHit(
        CodeSearchController.CodeHit hit,
        Id recordId,
        String codeSystem,
        String code,
        String display
    ) {
        System.assertEquals(recordId, hit.recordId, 'recordId should be the Code Reference Id');
        System.assertEquals(codeSystem, hit.codeSystem, 'codeSystem should be populated');
        System.assertEquals(code, hit.code, 'code should be populated');
        System.assertEquals(display, hit.display, 'display should be populated');
    }
}
