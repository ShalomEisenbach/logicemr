@IsTest
private class VitalsCaptureControllerTest {
    @IsTest
    static void saveVitalsInsertsBulkObservationsWithLoincAndEncounter() {
        Encounter__c encounter = insertEncounter('MRN-VIT-1');
        List<VitalsCaptureController.VitalInput> inputs = new List<VitalsCaptureController.VitalInput>{
            vital('systolic', 120),
            vital('diastolic', 80),
            vital('hr', 72),
            vital('rr', 16),
            vital('temp', 36.8),
            vital('spo2', 98),
            vital('height', 170),
            vital('weight', 70)
        };

        Test.startTest();
        List<Observation__c> created = VitalsCaptureController.saveVitals(encounter.Id, inputs);
        Test.stopTest();

        System.assertEquals(8, created.size(), 'All eight vitals should persist in one call');
        Map<String, Observation__c> byCode = new Map<String, Observation__c>();
        for (Observation__c row : [
            SELECT
                Patient__c,
                Encounter__c,
                Category__c,
                Status__c,
                Observation_Code_System__c,
                Observation_Code__c,
                Observation_Display__c,
                Value_Quantity__c,
                Value_Unit__c,
                Effective_DateTime__c
            FROM Observation__c
            WHERE Encounter__c = :encounter.Id
        ]) {
            byCode.put(row.Observation_Code__c, row);
        }

        assertVital(byCode.get('8480-6'), encounter, 'Systolic blood pressure', 120, 'mmHg');
        assertVital(byCode.get('8462-4'), encounter, 'Diastolic blood pressure', 80, 'mmHg');
        assertVital(byCode.get('8867-4'), encounter, 'Heart rate', 72, '/min');
        assertVital(byCode.get('9279-1'), encounter, 'Respiratory rate', 16, '/min');
        assertVital(byCode.get('8310-5'), encounter, 'Body temperature', 36.8, 'Cel');
        assertVital(byCode.get('59408-5'), encounter, 'Oxygen saturation', 98, '%');
        assertVital(byCode.get('8302-2'), encounter, 'Body height', 170, 'cm');
        assertVital(byCode.get('29463-7'), encounter, 'Body weight', 70, 'kg');
    }

    @IsTest
    static void saveVitalsSkipsBlankValuesAndRejectsEmptySet() {
        Encounter__c encounter = insertEncounter('MRN-VIT-2');
        List<VitalsCaptureController.VitalInput> mixed = new List<VitalsCaptureController.VitalInput>{
            vital('hr', 64),
            vital('rr', null),
            null
        };
        Boolean emptyThrew = false;
        Boolean nullListThrew = false;

        Test.startTest();
        List<Observation__c> created = VitalsCaptureController.saveVitals(encounter.Id, mixed);
        try {
            VitalsCaptureController.saveVitals(encounter.Id, null);
        } catch (AuraHandledException e) {
            nullListThrew = true;
        }
        try {
            VitalsCaptureController.saveVitals(encounter.Id, new List<VitalsCaptureController.VitalInput>());
        } catch (AuraHandledException e) {
            emptyThrew = true;
        }
        Test.stopTest();

        System.assertEquals(1, created.size(), 'Null values should be skipped');
        System.assertEquals('8867-4', created[0].Observation_Code__c, 'Only heart rate should insert');
        System.assertEquals(true, emptyThrew, 'Empty vitals should be rejected');
        System.assertEquals(true, nullListThrew, 'Null vitals list should be rejected');
    }

    @IsTest
    static void saveVitalsRejectsRangeBpAndUnknownKeys() {
        Encounter__c encounter = insertEncounter('MRN-VIT-3');
        Boolean rangeThrew = false;
        Boolean bpThrew = false;
        Boolean unknownThrew = false;

        Test.startTest();
        try {
            VitalsCaptureController.saveVitals(
                encounter.Id,
                new List<VitalsCaptureController.VitalInput>{ vital('hr', 10) }
            );
        } catch (AuraHandledException e) {
            rangeThrew = true;
        }
        try {
            VitalsCaptureController.saveVitals(
                encounter.Id,
                new List<VitalsCaptureController.VitalInput>{ vital('systolic', 80), vital('diastolic', 90) }
            );
        } catch (AuraHandledException e) {
            bpThrew = true;
        }
        try {
            VitalsCaptureController.saveVitals(
                encounter.Id,
                new List<VitalsCaptureController.VitalInput>{ vital('not-a-vital', 12) }
            );
        } catch (AuraHandledException e) {
            unknownThrew = true;
        }
        Test.stopTest();

        System.assertEquals(true, rangeThrew, 'Out-of-range heart rate should be rejected');
        System.assertEquals(true, bpThrew, 'Systolic below diastolic should be rejected');
        System.assertEquals(true, unknownThrew, 'Unknown vital key should be rejected');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Observation__c WHERE Encounter__c = :encounter.Id],
            'Rejected saves must not insert observations'
        );

        List<String> rangeErrors = VitalsCaptureController.validateVitals(
            new List<VitalsCaptureController.VitalInput>{ vital('temp', 50), vital(null, 1) }
        );
        System.assertEquals(true, !rangeErrors.isEmpty(), 'Validate should return range and unknown errors');
    }

    @IsTest
    static void saveVitalsRejectsBlankOrUnknownEncounter() {
        Patient__c patient = new Patient__c(MRN__c = 'MRN-VIT-BAD', Last_Name__c = 'Vitals');
        insert patient;
        Boolean nullIdThrew = false;
        Boolean unknownThrew = false;

        Test.startTest();
        try {
            VitalsCaptureController.saveVitals(
                null,
                new List<VitalsCaptureController.VitalInput>{ vital('hr', 70) }
            );
        } catch (AuraHandledException e) {
            nullIdThrew = true;
        }
        try {
            VitalsCaptureController.saveVitals(
                patient.Id,
                new List<VitalsCaptureController.VitalInput>{ vital('hr', 70) }
            );
        } catch (AuraHandledException e) {
            unknownThrew = true;
        }
        Test.stopTest();

        System.assertEquals(true, nullIdThrew, 'Null encounter Id should be rejected');
        System.assertEquals(true, unknownThrew, 'Non-encounter Id should be rejected');
    }

    private static void assertVital(
        Observation__c row,
        Encounter__c encounter,
        String display,
        Decimal value,
        String unit
    ) {
        System.assertNotEquals(null, row, display + ' should be saved');
        System.assertEquals(encounter.Patient__c, row.Patient__c, display + ' should stamp Patient');
        System.assertEquals(encounter.Id, row.Encounter__c, display + ' should stamp Encounter');
        System.assertEquals('Vital Signs', row.Category__c, display + ' category should be Vital Signs');
        System.assertEquals('Final', row.Status__c, display + ' status should be Final');
        System.assertEquals('LOINC', row.Observation_Code_System__c, display + ' should use LOINC');
        System.assertEquals(display, row.Observation_Display__c, display + ' display should match');
        System.assertEquals(value, row.Value_Quantity__c, display + ' quantity should persist');
        System.assertEquals(unit, row.Value_Unit__c, display + ' unit should persist');
        System.assertNotEquals(null, row.Effective_DateTime__c, display + ' should stamp effective time');
    }

    private static VitalsCaptureController.VitalInput vital(String key, Decimal value) {
        VitalsCaptureController.VitalInput row = new VitalsCaptureController.VitalInput();
        row.key = key;
        row.value = value;
        return row;
    }

    private static Encounter__c insertEncounter(String mrn) {
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'Vitals');
        insert patient;
        Encounter__c encounter = new Encounter__c(
            Patient__c = patient.Id,
            Status__c = 'In Progress',
            Class__c = 'Outpatient',
            Start__c = Datetime.newInstance(2024, 3, 1, 9, 0, 0)
        );
        insert encounter;
        return encounter;
    }
}
