@IsTest
private class EncounterWorkspaceControllerTest {
    @IsTest
    static void validAdvanceSequenceIsAllowed() {
        Encounter__c encounter = insertEncounter('Planned');

        Test.startTest();
        System.assertEquals(
            true,
            EncounterWorkspaceController.isValidTransition('Planned', 'Arrived'),
            'Planned may advance to Arrived'
        );
        Encounter__c arrived = EncounterWorkspaceController.transitionStatus(
            encounter.Id,
            'Arrived'
        );
        System.assertEquals(
            true,
            EncounterWorkspaceController.isValidTransition('Arrived', 'In Progress'),
            'Arrived may advance to In Progress'
        );
        Encounter__c inProgress = EncounterWorkspaceController.transitionStatus(
            encounter.Id,
            'In Progress'
        );
        System.assertEquals(
            true,
            EncounterWorkspaceController.isValidTransition('In Progress', 'Finished'),
            'In Progress may advance to Finished'
        );
        Encounter__c finished = EncounterWorkspaceController.transitionStatus(
            encounter.Id,
            'Finished'
        );
        Test.stopTest();

        System.assertEquals('Arrived', arrived.Status__c, 'First advance should set Arrived');
        System.assertEquals('In Progress', inProgress.Status__c, 'Second advance should set In Progress');
        System.assertEquals('Finished', finished.Status__c, 'Third advance should set Finished');
        System.assertEquals(
            'Finished',
            [SELECT Status__c FROM Encounter__c WHERE Id = :encounter.Id]
            .Status__c,
            'Persisted status should be Finished'
        );
    }

    @IsTest
    static void illegalTransitionsAreRejectedAndStatusUnchanged() {
        Encounter__c planned = insertEncounter('Planned');
        Encounter__c arrived = insertEncounter('Arrived');
        Encounter__c finished = insertEncounter('Finished');
        Encounter__c cancelled = insertEncounter('Cancelled');

        Test.startTest();
        assertTransitionRejected(planned.Id, 'In Progress', 'Planned');
        assertTransitionRejected(planned.Id, 'Finished', 'Planned');
        assertTransitionRejected(arrived.Id, 'Planned', 'Arrived');
        assertTransitionRejected(arrived.Id, 'Finished', 'Arrived');
        assertTransitionRejected(finished.Id, 'In Progress', 'Finished');
        assertTransitionRejected(finished.Id, 'Arrived', 'Finished');
        assertTransitionRejected(cancelled.Id, 'Arrived', 'Cancelled');
        assertTransitionRejected(cancelled.Id, 'Planned', 'Cancelled');
        Test.stopTest();

        System.assertEquals(
            false,
            EncounterWorkspaceController.isValidTransition('Planned', 'Finished'),
            'Skipping to Finished is illegal'
        );
        System.assertEquals(
            false,
            EncounterWorkspaceController.isValidTransition('Finished', 'Planned'),
            'Backward from Finished is illegal'
        );
        System.assertEquals(
            false,
            EncounterWorkspaceController.isValidTransition('Cancelled', 'Arrived'),
            'Cancelled cannot advance'
        );
        System.assertEquals(
            false,
            EncounterWorkspaceController.isValidTransition(null, 'Arrived'),
            'Blank current status is illegal'
        );
        System.assertEquals(
            false,
            EncounterWorkspaceController.isValidTransition('Planned', null),
            'Blank new status is illegal'
        );
        System.assertEquals(
            false,
            EncounterWorkspaceController.isValidTransition('Planned', 'Planned'),
            'Same-status transition is illegal'
        );
    }

    @IsTest
    static void getDiagnosesReturnsEncounterConditionRows() {
        Encounter__c encounter = insertEncounter('In Progress');
        Encounter__c other = insertEncounter('In Progress');
        Condition__c diabetes = insertCondition(encounter, 'ICD-10', 'E11.9', 'Type 2 diabetes');
        EncounterDiagnosis__c principal = insertEncounterDiagnosis(
            encounter.Id,
            diabetes.Id,
            'Principal',
            1
        );
        insertEncounterDiagnosis(
            other.Id,
            insertCondition(other, 'SNOMED', '38341003', 'Hypertension').Id,
            'Secondary',
            1
        );

        Test.startTest();
        List<EncounterWorkspaceController.DiagnosisRow> rows = EncounterWorkspaceController.getDiagnoses(
            encounter.Id
        );
        List<EncounterWorkspaceController.DiagnosisRow> blank = EncounterWorkspaceController.getDiagnoses(
            null
        );
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'Only this encounter\'s diagnoses should return');
        System.assertEquals(principal.Id, rows[0].id, 'Junction Id should match');
        System.assertEquals(diabetes.Id, rows[0].conditionId, 'Condition Id should match');
        System.assertEquals('Type 2 diabetes', rows[0].display, 'Display should come from Condition');
        System.assertEquals('E11.9', rows[0].code, 'Code should come from Condition');
        System.assertEquals('ICD-10', rows[0].codeSystem, 'Code system should come from Condition');
        System.assertEquals('Principal', rows[0].diagnosisType, 'Type should persist');
        System.assertEquals(1, rows[0].rank, 'Rank should persist');
        System.assertEquals('Active', rows[0].status, 'Status should come from Condition');
        System.assertEquals(0, blank.size(), 'Null encounter should return no diagnoses');
    }

    @IsTest
    static void addDiagnosisCreatesConditionAndJunction() {
        Encounter__c encounter = insertEncounter('In Progress');
        Code_Reference__c codeRef = insertCode('SNOMED', '44054006', 'Diabetes mellitus type 2');

        Test.startTest();
        EncounterDiagnosis__c created = EncounterWorkspaceController.addDiagnosis(
            encounter.Id,
            codeRef.Code_System__c,
            codeRef.Code__c,
            codeRef.Display__c,
            codeRef.Id,
            'Secondary',
            2
        );
        Test.stopTest();

        EncounterDiagnosis__c stored = [
            SELECT
                Encounter__c,
                Condition__c,
                Type__c,
                Rank__c,
                Condition__r.Patient__c,
                Condition__r.Encounter__c,
                Condition__r.Category__c,
                Condition__r.Clinical_Status__c,
                Condition__r.Diagnosis_Ref__c,
                Condition__r.Diagnosis_Code_System__c,
                Condition__r.Diagnosis_Code__c,
                Condition__r.Diagnosis_Display__c
            FROM EncounterDiagnosis__c
            WHERE Id = :created.Id
        ];
        System.assertEquals(encounter.Id, stored.Encounter__c, 'Junction should stamp Encounter');
        System.assertEquals(
            encounter.Patient__c,
            stored.Condition__r.Patient__c,
            'Condition should stamp Patient'
        );
        System.assertEquals(
            encounter.Id,
            stored.Condition__r.Encounter__c,
            'Condition should stamp Encounter'
        );
        System.assertEquals(
            'Encounter Diagnosis',
            stored.Condition__r.Category__c,
            'Category should be Encounter Diagnosis'
        );
        System.assertEquals('Active', stored.Condition__r.Clinical_Status__c, 'New dx should be Active');
        System.assertEquals(
            codeRef.Id,
            stored.Condition__r.Diagnosis_Ref__c,
            'Lookup should point at the Code Reference'
        );
        System.assertEquals(
            codeRef.Code_System__c,
            stored.Condition__r.Diagnosis_Code_System__c,
            'Code system'
        );
        System.assertEquals(codeRef.Code__c, stored.Condition__r.Diagnosis_Code__c, 'Code');
        System.assertEquals(
            codeRef.Display__c,
            stored.Condition__r.Diagnosis_Display__c,
            'Display'
        );
        System.assertEquals('Secondary', stored.Type__c, 'Type should persist');
        System.assertEquals(2, stored.Rank__c, 'Rank should persist');
        System.assertEquals(
            1,
            EncounterWorkspaceController.getDiagnoses(encounter.Id).size(),
            'Added diagnosis should be queryable'
        );
    }

    @IsTest
    static void addDiagnosisRejectsBlankEncounterDisplayOrWrongSystem() {
        Encounter__c encounter = insertEncounter('In Progress');
        Boolean missingEncounter = false;
        Boolean unknownEncounter = false;
        Boolean missingDisplay = false;
        Boolean wrongSystem = false;

        Test.startTest();
        try {
            EncounterWorkspaceController.addDiagnosis(
                null,
                'ICD-10',
                'E11.9',
                'Diabetes',
                null,
                'Principal',
                1
            );
        } catch (AuraHandledException e) {
            missingEncounter = true;
        }
        try {
            EncounterWorkspaceController.addDiagnosis(
                encounter.Patient__c,
                'ICD-10',
                'E11.9',
                'Diabetes',
                null,
                'Principal',
                1
            );
        } catch (AuraHandledException e) {
            unknownEncounter = true;
        }
        try {
            EncounterWorkspaceController.addDiagnosis(
                encounter.Id,
                'ICD-10',
                'E11.9',
                '',
                null,
                'Principal',
                1
            );
        } catch (AuraHandledException e) {
            missingDisplay = true;
        }
        try {
            EncounterWorkspaceController.addDiagnosis(
                encounter.Id,
                'CPT',
                '99213',
                'Office visit',
                null,
                'Principal',
                1
            );
        } catch (AuraHandledException e) {
            wrongSystem = true;
        }
        Test.stopTest();

        System.assertEquals(true, missingEncounter, 'Blank encounter Id should be rejected');
        System.assertEquals(true, unknownEncounter, 'Non-encounter Id should be rejected');
        System.assertEquals(true, missingDisplay, 'Blank display should be rejected');
        System.assertEquals(true, wrongSystem, 'Non ICD-10/SNOMED system should be rejected');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM EncounterDiagnosis__c WHERE Encounter__c = :encounter.Id],
            'Rejected adds must not insert junctions'
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Condition__c WHERE Patient__c = :encounter.Patient__c],
            'Rejected adds must not insert conditions'
        );
    }

    @IsTest
    static void deleteDiagnosesRemovesJunctionAndEncounterCondition() {
        Encounter__c encounter = insertEncounter('In Progress');
        Condition__c condition = insertCondition(encounter, 'ICD-10', 'J06.9', 'URI');
        EncounterDiagnosis__c link = insertEncounterDiagnosis(encounter.Id, condition.Id, 'Principal', 1);

        Test.startTest();
        EncounterWorkspaceController.deleteDiagnoses(null);
        EncounterWorkspaceController.deleteDiagnoses(new List<Id>());
        EncounterWorkspaceController.deleteDiagnoses(new List<Id>{ link.Id });
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM EncounterDiagnosis__c WHERE Id = :link.Id],
            'Encounter diagnosis junction should be deleted'
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Condition__c WHERE Id = :condition.Id],
            'Encounter diagnosis condition should be deleted'
        );
    }

    @IsTest
    static void blankIdOrUnknownEncounterIsRejected() {
        Patient__c patient = insertPatient('MRN-WS-BAD');
        Boolean nullIdThrew = false;
        Boolean blankStatusThrew = false;
        Boolean unknownThrew = false;

        Test.startTest();
        try {
            EncounterWorkspaceController.transitionStatus(null, 'Arrived');
        } catch (AuraHandledException e) {
            nullIdThrew = true;
        }
        Encounter__c encounter = insertEncounter('Planned');
        try {
            EncounterWorkspaceController.transitionStatus(encounter.Id, '');
        } catch (AuraHandledException e) {
            blankStatusThrew = true;
        }
        try {
            EncounterWorkspaceController.transitionStatus(patient.Id, 'Arrived');
        } catch (AuraHandledException e) {
            unknownThrew = true;
        }
        Test.stopTest();

        System.assertEquals(true, nullIdThrew, 'Null encounter Id should be rejected');
        System.assertEquals(true, blankStatusThrew, 'Blank new status should be rejected');
        System.assertEquals(true, unknownThrew, 'Non-encounter Id should be rejected');
    }

    private static void assertTransitionRejected(
        Id encounterId,
        String newStatus,
        String expectedStatus
    ) {
        Boolean threw = false;
        try {
            EncounterWorkspaceController.transitionStatus(encounterId, newStatus);
        } catch (AuraHandledException e) {
            threw = true;
            System.assertNotEquals(null, e.getMessage(), 'Rejection should include a message');
        }
        System.assertEquals(
            true,
            threw,
            'Illegal transition to ' + newStatus + ' should throw'
        );
        System.assertEquals(
            expectedStatus,
            [SELECT Status__c FROM Encounter__c WHERE Id = :encounterId]
            .Status__c,
            'Illegal transition must not persist a new status'
        );
    }

    private static Patient__c insertPatient(String mrn) {
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'Workspace');
        insert patient;
        return patient;
    }

    private static Encounter__c insertEncounter(String status) {
        Encounter__c encounter = new Encounter__c(
            Patient__c = insertPatient('MRN-WS-' + String.valueOf(Math.abs(Crypto.getRandomInteger()))).Id,
            Status__c = status,
            Class__c = 'Outpatient',
            Start__c = Datetime.newInstance(2024, 3, 1, 9, 0, 0)
        );
        insert encounter;
        return encounter;
    }

    private static Condition__c insertCondition(
        Encounter__c encounter,
        String codeSystem,
        String code,
        String display
    ) {
        Condition__c condition = new Condition__c(
            Patient__c = encounter.Patient__c,
            Encounter__c = encounter.Id,
            Category__c = 'Encounter Diagnosis',
            Clinical_Status__c = 'Active',
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

    private static EncounterDiagnosis__c insertEncounterDiagnosis(
        Id encounterId,
        Id conditionId,
        String diagnosisType,
        Decimal rank
    ) {
        EncounterDiagnosis__c link = new EncounterDiagnosis__c(
            Encounter__c = encounterId,
            Condition__c = conditionId,
            Type__c = diagnosisType,
            Rank__c = rank
        );
        insert link;
        return link;
    }
}
