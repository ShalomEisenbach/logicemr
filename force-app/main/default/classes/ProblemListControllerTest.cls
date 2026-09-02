@IsTest
private class ProblemListControllerTest {
    @IsTest
    static void getProblemsGroupsActiveAndResolvedForOnePatient() {
        Patient__c patient = insertPatient('MRN-PROB-1');
        Patient__c other = insertPatient('MRN-PROB-2');

        Condition__c active = insertCondition(
            patient.Id,
            'Problem List Item',
            'Active',
            'ICD-10',
            'E11.9',
            'Type 2 diabetes'
        );
        Condition__c resolved = insertCondition(
            patient.Id,
            'Problem List Item',
            'Resolved',
            'SNOMED',
            '38341003',
            'Hypertension'
        );
        insertCondition(
            patient.Id,
            'Encounter Diagnosis',
            'Active',
            'ICD-10',
            'J06.9',
            'URI'
        );
        insertCondition(
            other.Id,
            'Problem List Item',
            'Active',
            'ICD-10',
            'J45.20',
            'Asthma'
        );

        Test.startTest();
        ProblemListController.ProblemListView view = ProblemListController.getProblems(patient.Id);
        ProblemListController.ProblemListView blank = ProblemListController.getProblems(null);
        Test.stopTest();

        System.assertEquals(1, view.activeProblems.size(), 'Only this patient\'s active problems');
        System.assertEquals(active.Id, view.activeProblems[0].Id, 'Active problem should be grouped as active');
        System.assertEquals('E11.9', view.activeProblems[0].Diagnosis_Code__c, 'Coding code should be queried');
        System.assertEquals('ICD-10', view.activeProblems[0].Diagnosis_Code_System__c, 'Coding system should be queried');
        System.assertEquals(1, view.resolvedProblems.size(), 'Resolved problem should be grouped separately');
        System.assertEquals(resolved.Id, view.resolvedProblems[0].Id, 'Resolved problem Id should match');
        System.assertEquals(0, blank.activeProblems.size(), 'Null patient should return no active problems');
        System.assertEquals(0, blank.resolvedProblems.size(), 'Null patient should return no resolved problems');
    }

    @IsTest
    static void addProblemPersistsCodingAndProblemListCategory() {
        Patient__c patient = insertPatient('MRN-PROB-3');
        Code_Reference__c codeRef = insertCode(
            'SNOMED',
            '44054006',
            'Diabetes mellitus type 2'
        );

        Test.startTest();
        Date onset = Date.today().addDays(-14);
        Condition__c created = ProblemListController.addProblem(
            patient.Id,
            codeRef.Code_System__c,
            codeRef.Code__c,
            codeRef.Display__c,
            codeRef.Id,
            onset
        );
        Test.stopTest();

        Condition__c stored = [
            SELECT
                Patient__c,
                Category__c,
                Clinical_Status__c,
                Diagnosis_Ref__c,
                Diagnosis_Code_System__c,
                Diagnosis_Code__c,
                Diagnosis_Display__c,
                Onset_Date__c
            FROM Condition__c
            WHERE Id = :created.Id
        ];
        System.assertEquals(patient.Id, stored.Patient__c, 'Problem should belong to the patient');
        System.assertEquals('Problem List Item', stored.Category__c, 'Add should set problem-list category');
        System.assertEquals('Active', stored.Clinical_Status__c, 'New problem should be Active');
        System.assertEquals(codeRef.Id, stored.Diagnosis_Ref__c, 'Lookup should point at the Code Reference');
        System.assertEquals(codeRef.Code_System__c, stored.Diagnosis_Code_System__c, 'Code system should persist');
        System.assertEquals(codeRef.Code__c, stored.Diagnosis_Code__c, 'Snapshot code should match the Code Reference');
        System.assertEquals(
            codeRef.Display__c,
            stored.Diagnosis_Display__c,
            'Snapshot display should match the Code Reference'
        );
        System.assertEquals(onset, stored.Onset_Date__c, 'Add should persist the onset date');
    }

    @IsTest
    static void addProblemRejectsBlankPatientDisplayOrWrongSystem() {
        Patient__c patient = insertPatient('MRN-PROB-4');
        Boolean missingPatient = false;
        Boolean missingDisplay = false;
        Boolean wrongSystem = false;

        Test.startTest();
        try {
            ProblemListController.addProblem(null, 'ICD-10', 'E11.9', 'Diabetes', null, null);
        } catch (AuraHandledException e) {
            missingPatient = true;
        }
        try {
            ProblemListController.addProblem(patient.Id, 'ICD-10', 'E11.9', '', null, null);
        } catch (AuraHandledException e) {
            missingDisplay = true;
        }
        try {
            ProblemListController.addProblem(patient.Id, 'CPT', '99213', 'Office visit', null, null);
        } catch (AuraHandledException e) {
            wrongSystem = true;
        }
        Test.stopTest();

        System.assertEquals(true, missingPatient, 'Blank patient Id should be rejected');
        System.assertEquals(true, missingDisplay, 'Blank display should be rejected');
        System.assertEquals(true, wrongSystem, 'Non ICD-10/SNOMED system should be rejected');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Condition__c WHERE Patient__c = :patient.Id],
            'Rejected adds must not insert rows'
        );
    }

    @IsTest
    static void resolveProblemsUpdatesBothRowsInOneCall() {
        Patient__c patient = insertPatient('MRN-PROB-5');
        Condition__c first = insertCondition(
            patient.Id,
            'Problem List Item',
            'Active',
            'ICD-10',
            'E11.9',
            'Diabetes'
        );
        Condition__c second = insertCondition(
            patient.Id,
            'Problem List Item',
            'Recurrence',
            'SNOMED',
            '38341003',
            'Hypertension'
        );

        Test.startTest();
        ProblemListController.resolveProblems(null);
        ProblemListController.resolveProblems(new List<Id>());
        ProblemListController.resolveProblems(new List<Id>{ first.Id, second.Id });
        Test.stopTest();

        Map<Id, Condition__c> stored = new Map<Id, Condition__c>(
            [
                SELECT Clinical_Status__c, Abatement_Date__c
                FROM Condition__c
                WHERE Id IN :new List<Id>{ first.Id, second.Id }
            ]
        );
        System.assertEquals('Resolved', stored.get(first.Id).Clinical_Status__c, 'First row should resolve');
        System.assertEquals('Resolved', stored.get(second.Id).Clinical_Status__c, 'Second row should resolve');
        System.assertEquals(Date.today(), stored.get(first.Id).Abatement_Date__c, 'Resolve should set abatement date');
        System.assertEquals(Date.today(), stored.get(second.Id).Abatement_Date__c, 'Bulk resolve should set both dates');
    }

    @IsTest
    static void reopenProblemsRestoresActiveAndClearsAbatement() {
        Patient__c patient = insertPatient('MRN-PROB-6');
        Condition__c resolved = insertCondition(
            patient.Id,
            'Problem List Item',
            'Resolved',
            'ICD-10',
            'H66.90',
            'Otitis media'
        );
        resolved.Abatement_Date__c = Date.today().addDays(-10);
        update resolved;
        Condition__c alreadyActive = insertCondition(
            patient.Id,
            'Problem List Item',
            'Active',
            'ICD-10',
            'J45.20',
            'Asthma'
        );

        Test.startTest();
        ProblemListController.reopenProblems(null);
        ProblemListController.reopenProblems(new List<Id>());
        ProblemListController.reopenProblems(new List<Id>{ resolved.Id, alreadyActive.Id });
        Test.stopTest();

        Map<Id, Condition__c> stored = new Map<Id, Condition__c>(
            [
                SELECT Clinical_Status__c, Abatement_Date__c
                FROM Condition__c
                WHERE Id IN :new List<Id>{ resolved.Id, alreadyActive.Id }
            ]
        );
        System.assertEquals('Active', stored.get(resolved.Id).Clinical_Status__c, 'Resolved row should reopen as Active');
        System.assertEquals(null, stored.get(resolved.Id).Abatement_Date__c, 'Reopen should clear abatement date');
        System.assertEquals('Active', stored.get(alreadyActive.Id).Clinical_Status__c, 'Already-active row should stay Active');
        System.assertEquals(
            null,
            stored.get(alreadyActive.Id).Abatement_Date__c,
            'Already-active row should not get an abatement date'
        );
    }

    @IsTest
    static void updateOnsetDateSetsAndClearsOnset() {
        Patient__c patient = insertPatient('MRN-PROB-7');
        Condition__c condition = insertCondition(
            patient.Id,
            'Problem List Item',
            'Active',
            'ICD-10',
            'J45.20',
            'Asthma'
        );
        Date onset = Date.newInstance(2023, 4, 11);
        Boolean missingId = false;

        Test.startTest();
        try {
            ProblemListController.updateOnsetDate(null, onset);
        } catch (AuraHandledException e) {
            missingId = true;
        }
        ProblemListController.updateOnsetDate(condition.Id, onset);
        Date storedOnset = [
            SELECT Onset_Date__c
            FROM Condition__c
            WHERE Id = :condition.Id
        ]
        .Onset_Date__c;
        ProblemListController.updateOnsetDate(condition.Id, null);
        Test.stopTest();

        System.assertEquals(true, missingId, 'Blank condition Id should be rejected');
        System.assertEquals(onset, storedOnset, 'Onset date should persist on the problem');
        System.assertEquals(
            null,
            [SELECT Onset_Date__c FROM Condition__c WHERE Id = :condition.Id].Onset_Date__c,
            'Onset date should be clearable'
        );
    }

    @IsTest
    static void deleteProblemsRemovesRowsAndIgnoresBlankIds() {
        Patient__c patient = insertPatient('MRN-PROB-8');
        Condition__c first = insertCondition(
            patient.Id,
            'Problem List Item',
            'Active',
            'ICD-10',
            'J45.20',
            'Asthma'
        );
        Condition__c second = insertCondition(
            patient.Id,
            'Problem List Item',
            'Resolved',
            'ICD-10',
            'H66.90',
            'Otitis media'
        );

        Test.startTest();
        ProblemListController.deleteProblems(null);
        ProblemListController.deleteProblems(new List<Id>());
        ProblemListController.deleteProblems(new List<Id>{ first.Id, second.Id });
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Condition__c WHERE Id IN :new List<Id>{ first.Id, second.Id }],
            'Both problems should be deleted'
        );
    }

    private static Patient__c insertPatient(String mrn) {
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'Problems');
        insert patient;
        return patient;
    }

    private static Condition__c insertCondition(
        Id patientId,
        String category,
        String status,
        String codeSystem,
        String code,
        String display
    ) {
        Condition__c condition = new Condition__c(
            Patient__c = patientId,
            Category__c = category,
            Clinical_Status__c = status,
            Diagnosis_Code_System__c = codeSystem,
            Diagnosis_Code__c = code,
            Diagnosis_Display__c = display
        );
        insert condition;
        return condition;
    }

    private static Code_Reference__c insertCode(String codeSystem, String code, String display) {
        Code_Reference__c row = new Code_Reference__c(
            Name = display.left(80),
            Code_System__c = codeSystem,
            Code__c = code,
            Display__c = display,
            Active__c = true
        );
        insert row;
        return row;
    }
}
