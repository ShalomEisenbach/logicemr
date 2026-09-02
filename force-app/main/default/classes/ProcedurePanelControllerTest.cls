@IsTest
private class ProcedurePanelControllerTest {
    @IsTest
    static void getProceduresReturnsPatientRowsNewestFirst() {
        Patient__c patient = insertPatient('MRN-PROC-1');
        Patient__c other = insertPatient('MRN-PROC-2');
        Procedure__c newest = insertProcedure(
            patient.Id,
            'Completed',
            'Diagnostic',
            'CPT',
            '93000',
            'Electrocardiogram, complete',
            Datetime.newInstance(2026, 6, 3, 23, 5, 0)
        );
        insertProcedure(
            patient.Id,
            'In Progress',
            'Surgical',
            'CPT',
            '47562',
            'Laparoscopic cholecystectomy',
            Datetime.newInstance(2026, 5, 1, 8, 0, 0)
        );
        insertProcedure(
            other.Id,
            'Completed',
            'Diagnostic',
            'CPT',
            '73502',
            'X-ray hip, 2 or 3 views',
            Datetime.newInstance(2026, 8, 2, 19, 35, 0)
        );

        Test.startTest();
        List<Procedure__c> rows = ProcedurePanelController.getProcedures(patient.Id);
        List<Procedure__c> blank = ProcedurePanelController.getProcedures(null);
        Test.stopTest();

        System.assertEquals(2, rows.size(), 'Should return both procedures for this patient');
        System.assertEquals(newest.Id, rows[0].Id, 'Newest performed datetime should be first');
        System.assertEquals('93000', rows[0].Procedure_Code__c, 'Code should be queried');
        System.assertEquals('Diagnostic', rows[0].Category__c, 'Category should be queried');
        System.assertEquals(0, blank.size(), 'Null patient should return no procedures');
    }

    @IsTest
    static void addProcedurePersistsCodingCategoryStatusAndNotes() {
        Patient__c patient = insertPatient('MRN-PROC-3');
        Code_Reference__c codeRef = insertCode('CPT', '93000', 'Electrocardiogram, complete');
        Datetime performed = Datetime.newInstance(2026, 9, 2, 10, 15, 0);

        Test.startTest();
        Procedure__c created = ProcedurePanelController.addProcedure(
            patient.Id,
            codeRef.Code_System__c,
            codeRef.Code__c,
            codeRef.Display__c,
            codeRef.Id,
            'Diagnostic',
            'In Progress',
            performed,
            'No acute ST changes.'
        );
        Test.stopTest();

        Procedure__c stored = [
            SELECT
                Patient__c,
                Procedure_Ref__c,
                Procedure_Code_System__c,
                Procedure_Code__c,
                Procedure_Display__c,
                Category__c,
                Status__c,
                Performed_DateTime__c,
                Notes__c
            FROM Procedure__c
            WHERE Id = :created.Id
        ];
        System.assertEquals(patient.Id, stored.Patient__c, 'Procedure should belong to the patient');
        System.assertEquals(codeRef.Id, stored.Procedure_Ref__c, 'Lookup should point at the Code Reference');
        System.assertEquals(codeRef.Code_System__c, stored.Procedure_Code_System__c, 'Code system should persist');
        System.assertEquals(codeRef.Code__c, stored.Procedure_Code__c, 'Snapshot code should match the Code Reference');
        System.assertEquals(
            codeRef.Display__c,
            stored.Procedure_Display__c,
            'Snapshot display should match the Code Reference'
        );
        System.assertEquals('Diagnostic', stored.Category__c, 'Category should persist');
        System.assertEquals('In Progress', stored.Status__c, 'Status should persist');
        System.assertEquals(performed, stored.Performed_DateTime__c, 'Performed datetime should persist');
        System.assertEquals('No acute ST changes.', stored.Notes__c, 'Notes should persist');
    }

    @IsTest
    static void addProcedureDefaultsBlankStatusAndRejectsInvalidInput() {
        Patient__c patient = insertPatient('MRN-PROC-4');
        Boolean missingPatient = false;
        Boolean missingDisplay = false;
        Boolean badSystem = false;

        Test.startTest();
        Procedure__c created = ProcedurePanelController.addProcedure(
            patient.Id,
            'CPT',
            '93000',
            'Electrocardiogram, complete',
            null,
            'Diagnostic',
            '',
            null,
            null
        );
        try {
            ProcedurePanelController.addProcedure(
                null,
                'CPT',
                '93000',
                'Electrocardiogram, complete',
                null,
                'Diagnostic',
                'Completed',
                null,
                null
            );
        } catch (AuraHandledException e) {
            missingPatient = true;
        }
        try {
            ProcedurePanelController.addProcedure(
                patient.Id,
                'CPT',
                '93000',
                '',
                null,
                'Diagnostic',
                'Completed',
                null,
                null
            );
        } catch (AuraHandledException e) {
            missingDisplay = true;
        }
        try {
            ProcedurePanelController.addProcedure(
                patient.Id,
                'ICD-10',
                '93000',
                'Electrocardiogram, complete',
                null,
                'Diagnostic',
                'Completed',
                null,
                null
            );
        } catch (AuraHandledException e) {
            badSystem = true;
        }
        Test.stopTest();

        Procedure__c stored = [SELECT Status__c FROM Procedure__c WHERE Id = :created.Id];
        System.assertEquals('Completed', stored.Status__c, 'Blank status should default to Completed');
        System.assertEquals(true, missingPatient, 'Blank patient Id should be rejected');
        System.assertEquals(true, missingDisplay, 'Blank display should be rejected');
        System.assertEquals(true, badSystem, 'Non CPT/SNOMED code system should be rejected');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Procedure__c WHERE Patient__c = :patient.Id],
            'Rejected adds must not insert extra rows'
        );
    }

    @IsTest
    static void completeProceduresUpdatesOpenRowsInOneCall() {
        Patient__c patient = insertPatient('MRN-PROC-5');
        Procedure__c first = insertProcedure(
            patient.Id,
            'In Progress',
            'Surgical',
            'CPT',
            '47562',
            'Laparoscopic cholecystectomy',
            Datetime.newInstance(2026, 9, 20, 7, 30, 0)
        );
        Procedure__c second = insertProcedure(
            patient.Id,
            'Preparation',
            'Diagnostic',
            'CPT',
            '93306',
            'Echocardiogram, complete',
            Datetime.newInstance(2026, 9, 1, 9, 0, 0)
        );
        Procedure__c alreadyDone = insertProcedure(
            patient.Id,
            'Completed',
            'Diagnostic',
            'CPT',
            '93000',
            'Electrocardiogram, complete',
            Datetime.newInstance(2026, 6, 3, 23, 5, 0)
        );

        Test.startTest();
        ProcedurePanelController.completeProcedures(null);
        ProcedurePanelController.completeProcedures(new List<Id>());
        ProcedurePanelController.completeProcedures(new List<Id>{ first.Id, second.Id, alreadyDone.Id });
        Test.stopTest();

        Map<Id, Procedure__c> stored = new Map<Id, Procedure__c>(
            [
                SELECT Status__c
                FROM Procedure__c
                WHERE Id IN :new List<Id>{ first.Id, second.Id, alreadyDone.Id }
            ]
        );
        System.assertEquals('Completed', stored.get(first.Id).Status__c, 'First row should complete');
        System.assertEquals('Completed', stored.get(second.Id).Status__c, 'Second row should complete');
        System.assertEquals(
            'Completed',
            stored.get(alreadyDone.Id).Status__c,
            'Already completed row should stay Completed'
        );
    }

    @IsTest
    static void deleteProceduresRemovesRowsAndIgnoresBlankIds() {
        Patient__c patient = insertPatient('MRN-PROC-6');
        Procedure__c first = insertProcedure(
            patient.Id,
            'Completed',
            'Diagnostic',
            'CPT',
            '93000',
            'Electrocardiogram, complete',
            Datetime.newInstance(2026, 6, 3, 23, 5, 0)
        );
        Procedure__c second = insertProcedure(
            patient.Id,
            'In Progress',
            'Surgical',
            'CPT',
            '27236',
            'Open treatment of femoral neck fracture',
            Datetime.newInstance(2026, 8, 3, 14, 0, 0)
        );

        Test.startTest();
        ProcedurePanelController.deleteProcedures(null);
        ProcedurePanelController.deleteProcedures(new List<Id>());
        ProcedurePanelController.deleteProcedures(new List<Id>{ first.Id, second.Id });
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Procedure__c WHERE Id IN :new List<Id>{ first.Id, second.Id }],
            'Both procedures should be deleted'
        );
    }

    private static Patient__c insertPatient(String mrn) {
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'Procedures');
        insert patient;
        return patient;
    }

    private static Procedure__c insertProcedure(
        Id patientId,
        String status,
        String category,
        String codeSystem,
        String code,
        String display,
        Datetime performed
    ) {
        Procedure__c procedure = new Procedure__c(
            Patient__c = patientId,
            Status__c = status,
            Category__c = category,
            Procedure_Code_System__c = codeSystem,
            Procedure_Code__c = code,
            Procedure_Display__c = display,
            Performed_DateTime__c = performed
        );
        insert procedure;
        return procedure;
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
