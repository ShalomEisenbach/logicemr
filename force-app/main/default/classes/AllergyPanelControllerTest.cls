@IsTest
private class AllergyPanelControllerTest {
    @IsTest
    static void getAllergiesReturnsPatientRowsWithCriticalityAndReaction() {
        Patient__c patient = insertPatient('MRN-ALG-1');
        Patient__c other = insertPatient('MRN-ALG-2');
        AllergyIntolerance__c penicillin = insertAllergy(
            patient.Id,
            'Active',
            'RxNorm',
            '7980',
            'Penicillin',
            'High',
            'Anaphylaxis'
        );
        insertAllergy(patient.Id, 'Inactive', 'SNOMED', '227493005', 'Cashew', 'Low', 'Rash');
        insertAllergy(other.Id, 'Active', 'RxNorm', '2670', 'Codeine', 'High', 'Hives');

        Test.startTest();
        List<AllergyIntolerance__c> allRows = AllergyPanelController.getAllergies(patient.Id);
        List<AllergyIntolerance__c> active = AllergyPanelController.getActiveAllergies(patient.Id);
        List<AllergyIntolerance__c> blank = AllergyPanelController.getAllergies(null);
        List<AllergyIntolerance__c> blankActive = AllergyPanelController.getActiveAllergies(null);
        Test.stopTest();

        System.assertEquals(2, allRows.size(), 'Should return both allergies for this patient');
        System.assertEquals(1, active.size(), 'Active list should exclude inactivated allergies');
        System.assertEquals(penicillin.Id, active[0].Id, 'Active allergy should be penicillin');
        System.assertEquals('High', active[0].Criticality__c, 'Criticality should be queried');
        System.assertEquals('Anaphylaxis', active[0].Reaction__c, 'Reaction should be queried');
        System.assertEquals(0, blank.size(), 'Null patient should return no allergies');
        System.assertEquals(0, blankActive.size(), 'Null patient should return no active allergies');
    }

    @IsTest
    static void addAllergyPersistsCodingCriticalityAndReaction() {
        Patient__c patient = insertPatient('MRN-ALG-3');
        Code_Reference__c codeRef = insertCode('SNOMED', '91936005', 'Allergy to penicillin');

        Test.startTest();
        AllergyIntolerance__c created = AllergyPanelController.addAllergy(
            patient.Id,
            codeRef.Code_System__c,
            codeRef.Code__c,
            codeRef.Display__c,
            codeRef.Id,
            'Allergy',
            'Medication',
            'High',
            'Anaphylaxis'
        );
        Test.stopTest();

        AllergyIntolerance__c stored = [
            SELECT
                Patient__c,
                Clinical_Status__c,
                Allergen_Ref__c,
                Allergen_Code_System__c,
                Allergen_Code__c,
                Allergen_Display__c,
                Type__c,
                Category__c,
                Criticality__c,
                Reaction__c
            FROM AllergyIntolerance__c
            WHERE Id = :created.Id
        ];
        System.assertEquals(patient.Id, stored.Patient__c, 'Allergy should belong to the patient');
        System.assertEquals('Active', stored.Clinical_Status__c, 'New allergy should be Active');
        System.assertEquals(codeRef.Id, stored.Allergen_Ref__c, 'Lookup should point at the Code Reference');
        System.assertEquals(codeRef.Code_System__c, stored.Allergen_Code_System__c, 'Code system should persist');
        System.assertEquals(codeRef.Code__c, stored.Allergen_Code__c, 'Snapshot code should match the Code Reference');
        System.assertEquals(
            codeRef.Display__c,
            stored.Allergen_Display__c,
            'Snapshot display should match the Code Reference'
        );
        System.assertEquals('Allergy', stored.Type__c, 'Type should persist');
        System.assertEquals('Medication', stored.Category__c, 'Category should persist');
        System.assertEquals('High', stored.Criticality__c, 'Criticality should persist');
        System.assertEquals('Anaphylaxis', stored.Reaction__c, 'Reaction should persist');
    }

    @IsTest
    static void addAllergyRejectsBlankPatientOrDisplay() {
        Patient__c patient = insertPatient('MRN-ALG-4');
        Boolean missingPatient = false;
        Boolean missingDisplay = false;

        Test.startTest();
        try {
            AllergyPanelController.addAllergy(
                null,
                'RxNorm',
                '7980',
                'Penicillin',
                null,
                'Allergy',
                'Medication',
                'High',
                'Rash'
            );
        } catch (AuraHandledException e) {
            missingPatient = true;
        }
        try {
            AllergyPanelController.addAllergy(
                patient.Id,
                'RxNorm',
                '7980',
                '',
                null,
                'Allergy',
                'Medication',
                'High',
                'Rash'
            );
        } catch (AuraHandledException e) {
            missingDisplay = true;
        }
        Test.stopTest();

        System.assertEquals(true, missingPatient, 'Blank patient Id should be rejected');
        System.assertEquals(true, missingDisplay, 'Blank display should be rejected');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM AllergyIntolerance__c WHERE Patient__c = :patient.Id],
            'Rejected adds must not insert rows'
        );
    }

    @IsTest
    static void inactivateAllergiesUpdatesBothActiveRowsInOneCall() {
        Patient__c patient = insertPatient('MRN-ALG-5');
        AllergyIntolerance__c first = insertAllergy(
            patient.Id,
            'Active',
            'RxNorm',
            '7980',
            'Penicillin',
            'High',
            'Anaphylaxis'
        );
        AllergyIntolerance__c second = insertAllergy(
            patient.Id,
            'Active',
            'SNOMED',
            '227493005',
            'Cashew',
            'Low',
            'Rash'
        );
        AllergyIntolerance__c alreadyInactive = insertAllergy(
            patient.Id,
            'Inactive',
            'RxNorm',
            '2670',
            'Codeine',
            'Low',
            'Itch'
        );

        Test.startTest();
        AllergyPanelController.inactivateAllergies(null);
        AllergyPanelController.inactivateAllergies(new List<Id>());
        AllergyPanelController.inactivateAllergies(new List<Id>{ first.Id, second.Id, alreadyInactive.Id });
        Test.stopTest();

        Map<Id, AllergyIntolerance__c> stored = new Map<Id, AllergyIntolerance__c>(
            [
                SELECT Clinical_Status__c
                FROM AllergyIntolerance__c
                WHERE Id IN :new List<Id>{ first.Id, second.Id, alreadyInactive.Id }
            ]
        );
        System.assertEquals('Inactive', stored.get(first.Id).Clinical_Status__c, 'First row should inactivate');
        System.assertEquals('Inactive', stored.get(second.Id).Clinical_Status__c, 'Second row should inactivate');
        System.assertEquals(
            'Inactive',
            stored.get(alreadyInactive.Id).Clinical_Status__c,
            'Already inactive row should stay Inactive'
        );
        System.assertEquals(
            0,
            AllergyPanelController.getActiveAllergies(patient.Id).size(),
            'No active allergies should remain'
        );
    }

    private static Patient__c insertPatient(String mrn) {
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'Allergies');
        insert patient;
        return patient;
    }

    private static AllergyIntolerance__c insertAllergy(
        Id patientId,
        String status,
        String codeSystem,
        String code,
        String display,
        String criticality,
        String reaction
    ) {
        AllergyIntolerance__c allergy = new AllergyIntolerance__c(
            Patient__c = patientId,
            Clinical_Status__c = status,
            Allergen_Code_System__c = codeSystem,
            Allergen_Code__c = code,
            Allergen_Display__c = display,
            Type__c = 'Allergy',
            Category__c = 'Medication',
            Criticality__c = criticality,
            Reaction__c = reaction
        );
        insert allergy;
        return allergy;
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
