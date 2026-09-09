@IsTest
private class ImmunizationPanelControllerTest {
    @IsTest
    static void getImmunizationsReturnsPatientRowsNewestFirst() {
        Patient__c patient = insertPatient('MRN-IMM-1');
        Patient__c other = insertPatient('MRN-IMM-2');
        Immunization__c newest = insertImmunization(
            patient.Id,
            'Completed',
            'CVX',
            '141',
            'Influenza, seasonal, injectable',
            Date.newInstance(2026, 9, 1),
            'LOT-A',
            null
        );
        insertImmunization(
            patient.Id,
            'Not Done',
            'CVX',
            '03',
            'MMR',
            Date.newInstance(2026, 5, 1),
            null,
            null
        );
        insertImmunization(
            other.Id,
            'Completed',
            'CVX',
            '08',
            'Hep B, adolescent or pediatric',
            Date.newInstance(2026, 9, 8),
            'LOT-B',
            null
        );

        Test.startTest();
        List<Immunization__c> rows = ImmunizationPanelController.getImmunizations(patient.Id);
        List<Immunization__c> blank = ImmunizationPanelController.getImmunizations(null);
        Test.stopTest();

        System.assertEquals(2, rows.size(), 'Should return both immunizations for this patient');
        System.assertEquals(newest.Id, rows[0].Id, 'Newest occurrence date should be first');
        System.assertEquals('141', rows[0].Vaccine_Code__c, 'Code should be queried');
        System.assertEquals('LOT-A', rows[0].Lot_Number__c, 'Lot number should be queried');
        System.assertEquals(0, blank.size(), 'Null patient should return no immunizations');
    }

    @IsTest
    static void addImmunizationPersistsCodingDateLotStatusAndPerformer() {
        Patient__c patient = insertPatient('MRN-IMM-3');
        Code_Reference__c codeRef = insertCode('CVX', '141', 'Influenza, seasonal, injectable');
        Practitioner__c performer = new Practitioner__c(First_Name__c = 'Pat', Last_Name__c = 'Provider');
        insert performer;
        Date occurrence = Date.newInstance(2026, 9, 9);

        Test.startTest();
        Immunization__c created = ImmunizationPanelController.addImmunization(
            patient.Id,
            codeRef.Code_System__c,
            codeRef.Code__c,
            codeRef.Display__c,
            codeRef.Id,
            occurrence,
            'LOT-FLU-26',
            'Completed',
            performer.Id
        );
        Test.stopTest();

        Immunization__c stored = [
            SELECT
                Patient__c,
                Encounter__c,
                Vaccine_Ref__c,
                Vaccine_Code_System__c,
                Vaccine_Code__c,
                Vaccine_Display__c,
                Occurrence_Date__c,
                Lot_Number__c,
                Status__c,
                Performer__c
            FROM Immunization__c
            WHERE Id = :created.Id
        ];
        System.assertEquals(patient.Id, stored.Patient__c, 'Immunization should belong to the patient');
        System.assertEquals(null, stored.Encounter__c, 'Patient chart add should not stamp an encounter');
        System.assertEquals(codeRef.Id, stored.Vaccine_Ref__c, 'Lookup should point at the Code Reference');
        System.assertEquals(codeRef.Code_System__c, stored.Vaccine_Code_System__c, 'Code system should persist');
        System.assertEquals(codeRef.Code__c, stored.Vaccine_Code__c, 'Snapshot code should match the Code Reference');
        System.assertEquals(
            codeRef.Display__c,
            stored.Vaccine_Display__c,
            'Snapshot display should match the Code Reference'
        );
        System.assertEquals(occurrence, stored.Occurrence_Date__c, 'Occurrence date should persist');
        System.assertEquals('LOT-FLU-26', stored.Lot_Number__c, 'Lot number should persist');
        System.assertEquals('Completed', stored.Status__c, 'Status should persist');
        System.assertEquals(performer.Id, stored.Performer__c, 'Performer should persist');
    }

    @IsTest
    static void addImmunizationDefaultsBlankStatusAndRejectsInvalidInput() {
        Patient__c patient = insertPatient('MRN-IMM-4');
        Boolean missingPatient = false;
        Boolean missingDisplay = false;
        Boolean badSystem = false;
        Boolean badStatus = false;

        Test.startTest();
        Immunization__c created = ImmunizationPanelController.addImmunization(
            patient.Id,
            'CVX',
            '141',
            'Influenza, seasonal, injectable',
            null,
            Date.newInstance(2026, 9, 9),
            null,
            '',
            null
        );
        try {
            ImmunizationPanelController.addImmunization(
                null,
                'CVX',
                '141',
                'Influenza, seasonal, injectable',
                null,
                Date.newInstance(2026, 9, 9),
                null,
                'Completed',
                null
            );
        } catch (AuraHandledException e) {
            missingPatient = true;
        }
        try {
            ImmunizationPanelController.addImmunization(
                patient.Id,
                'CVX',
                '141',
                '',
                null,
                Date.newInstance(2026, 9, 9),
                null,
                'Completed',
                null
            );
        } catch (AuraHandledException e) {
            missingDisplay = true;
        }
        try {
            ImmunizationPanelController.addImmunization(
                patient.Id,
                'RxNorm',
                '141',
                'Influenza, seasonal, injectable',
                null,
                Date.newInstance(2026, 9, 9),
                null,
                'Completed',
                null
            );
        } catch (AuraHandledException e) {
            badSystem = true;
        }
        try {
            ImmunizationPanelController.addImmunization(
                patient.Id,
                'CVX',
                '141',
                'Influenza, seasonal, injectable',
                null,
                Date.newInstance(2026, 9, 9),
                null,
                'Active',
                null
            );
        } catch (AuraHandledException e) {
            badStatus = true;
        }
        Test.stopTest();

        Immunization__c stored = [SELECT Status__c FROM Immunization__c WHERE Id = :created.Id];
        System.assertEquals('Completed', stored.Status__c, 'Blank status should default to Completed');
        System.assertEquals(true, missingPatient, 'Blank patient Id should be rejected');
        System.assertEquals(true, missingDisplay, 'Blank display should be rejected');
        System.assertEquals(true, badSystem, 'Non CVX/SNOMED code system should be rejected');
        System.assertEquals(true, badStatus, 'Invalid status should be rejected');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Immunization__c WHERE Patient__c = :patient.Id],
            'Rejected adds must not insert extra rows'
        );
    }

    @IsTest
    static void markEnteredInErrorUpdatesOpenRowsInOneCall() {
        Patient__c patient = insertPatient('MRN-IMM-5');
        Immunization__c first = insertImmunization(
            patient.Id,
            'Completed',
            'CVX',
            '141',
            'Influenza, seasonal, injectable',
            Date.newInstance(2026, 9, 1),
            null,
            null
        );
        Immunization__c second = insertImmunization(
            patient.Id,
            'Not Done',
            'CVX',
            '03',
            'MMR',
            Date.newInstance(2026, 8, 1),
            null,
            null
        );
        Immunization__c alreadyError = insertImmunization(
            patient.Id,
            'Entered in Error',
            'CVX',
            '08',
            'Hep B, adolescent or pediatric',
            Date.newInstance(2026, 7, 1),
            null,
            null
        );

        Test.startTest();
        ImmunizationPanelController.markEnteredInError(null);
        ImmunizationPanelController.markEnteredInError(new List<Id>());
        ImmunizationPanelController.markEnteredInError(new List<Id>{ first.Id, second.Id, alreadyError.Id });
        Test.stopTest();

        Map<Id, Immunization__c> stored = new Map<Id, Immunization__c>(
            [
                SELECT Status__c
                FROM Immunization__c
                WHERE Id IN :new List<Id>{ first.Id, second.Id, alreadyError.Id }
            ]
        );
        System.assertEquals('Entered in Error', stored.get(first.Id).Status__c, 'First row should be entered in error');
        System.assertEquals('Entered in Error', stored.get(second.Id).Status__c, 'Second row should be entered in error');
        System.assertEquals(
            'Entered in Error',
            stored.get(alreadyError.Id).Status__c,
            'Already entered-in-error row should stay Entered in Error'
        );
    }

    @IsTest
    static void deleteImmunizationsRemovesRowsAndIgnoresBlankIds() {
        Patient__c patient = insertPatient('MRN-IMM-6');
        Immunization__c first = insertImmunization(
            patient.Id,
            'Completed',
            'CVX',
            '141',
            'Influenza, seasonal, injectable',
            Date.newInstance(2026, 9, 1),
            null,
            null
        );
        Immunization__c second = insertImmunization(
            patient.Id,
            'Not Done',
            'CVX',
            '03',
            'MMR',
            Date.newInstance(2026, 8, 1),
            null,
            null
        );

        Test.startTest();
        ImmunizationPanelController.deleteImmunizations(null);
        ImmunizationPanelController.deleteImmunizations(new List<Id>());
        ImmunizationPanelController.deleteImmunizations(new List<Id>{ first.Id, second.Id });
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Immunization__c WHERE Id IN :new List<Id>{ first.Id, second.Id }],
            'Both immunizations should be deleted'
        );
    }

    @IsTest
    static void encounterContextScopesRowsAndStampsEncounter() {
        Patient__c patient = insertPatient('MRN-IMM-7');
        Encounter__c visit = insertEncounter(patient.Id);
        Encounter__c otherVisit = insertEncounter(patient.Id);
        insertImmunization(
            patient.Id,
            'Completed',
            'CVX',
            '141',
            'Influenza, seasonal, injectable',
            Date.newInstance(2026, 9, 1),
            'LOT-A',
            null,
            visit.Id
        );
        insertImmunization(
            patient.Id,
            'Not Done',
            'CVX',
            '03',
            'MMR',
            Date.newInstance(2026, 8, 1),
            null,
            null,
            otherVisit.Id
        );
        insertImmunization(
            patient.Id,
            'Completed',
            'CVX',
            '08',
            'Hep B, adolescent or pediatric',
            Date.newInstance(2026, 7, 1),
            null,
            null,
            null
        );

        Test.startTest();
        List<Immunization__c> visitRows = ImmunizationPanelController.getImmunizations(visit.Id);
        Immunization__c created = ImmunizationPanelController.addImmunization(
            visit.Id,
            'CVX',
            '115',
            'Tdap',
            null,
            Date.newInstance(2026, 9, 9),
            'LOT-TDAP',
            'Completed',
            null
        );
        Test.stopTest();

        System.assertEquals(1, visitRows.size(), 'Encounter list should only include this visit');
        Immunization__c stored = [
            SELECT Patient__c, Encounter__c, Vaccine_Display__c
            FROM Immunization__c
            WHERE Id = :created.Id
        ];
        System.assertEquals(patient.Id, stored.Patient__c, 'Encounter add should use the visit patient');
        System.assertEquals(visit.Id, stored.Encounter__c, 'Encounter add should stamp the visit');
        System.assertEquals('Tdap', stored.Vaccine_Display__c, 'Vaccine display should persist');
    }

    private static Patient__c insertPatient(String mrn) {
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'Immunizations');
        insert patient;
        return patient;
    }

    private static Encounter__c insertEncounter(Id patientId) {
        Encounter__c encounter = new Encounter__c(
            Patient__c = patientId,
            Status__c = 'In Progress',
            Class__c = 'Outpatient',
            Start__c = Datetime.newInstance(2026, 9, 9, 9, 0, 0)
        );
        insert encounter;
        return encounter;
    }

    private static Immunization__c insertImmunization(
        Id patientId,
        String status,
        String codeSystem,
        String code,
        String display,
        Date occurrence,
        String lotNumber,
        Id performerId
    ) {
        return insertImmunization(
            patientId,
            status,
            codeSystem,
            code,
            display,
            occurrence,
            lotNumber,
            performerId,
            null
        );
    }

    private static Immunization__c insertImmunization(
        Id patientId,
        String status,
        String codeSystem,
        String code,
        String display,
        Date occurrence,
        String lotNumber,
        Id performerId,
        Id encounterId
    ) {
        Immunization__c immunization = new Immunization__c(
            Patient__c = patientId,
            Encounter__c = encounterId,
            Status__c = status,
            Vaccine_Code_System__c = codeSystem,
            Vaccine_Code__c = code,
            Vaccine_Display__c = display,
            Occurrence_Date__c = occurrence,
            Lot_Number__c = lotNumber,
            Performer__c = performerId
        );
        insert immunization;
        return immunization;
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
