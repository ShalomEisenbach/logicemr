@IsTest
private class PatientBannerControllerTest {
    @IsTest
    static void getLatestVitalsReturnsNewestOfEachCodeAndPairsBloodPressure() {
        Patient__c patient = insertPatient('MRN-BAN-1');
        Patient__c other = insertPatient('MRN-BAN-2');
        Datetime older = Datetime.newInstance(2024, 3, 1, 8, 0, 0);
        Datetime newer = Datetime.newInstance(2024, 3, 2, 10, 15, 0);

        insertObservation(patient.Id, '8480-6', 118, 'mmHg', older);
        insertObservation(patient.Id, '8480-6', 128, 'mmHg', newer);
        insertObservation(patient.Id, '8462-4', 76, 'mmHg', older);
        insertObservation(patient.Id, '8867-4', 60, '/min', older);
        insertObservation(patient.Id, '8867-4', 74, '/min', newer);
        insertObservation(patient.Id, '9279-1', 16, '/min', newer);
        insertObservation(patient.Id, '8310-5', 98.60, 'F', newer);
        insertObservation(patient.Id, '59408-5', 98, '%', newer);
        insertObservation(patient.Id, '29463-7', 70.50, 'kg', newer);
        insertObservation(other.Id, '8867-4', 99, '/min', newer);
        insertLab(patient.Id, '8867-4', 40, newer);

        Test.startTest();
        PatientBannerController.LatestVitals vitals = PatientBannerController.getLatestVitals(patient.Id);
        PatientBannerController.LatestVitals blank = PatientBannerController.getLatestVitals(null);
        PatientBannerController.LatestVitals empty = PatientBannerController.getLatestVitals(other.Id);
        Test.stopTest();

        Map<String, String> byKey = valuesByKey(vitals.items);
        System.assertEquals(6, vitals.items.size(), 'Banner should include BP plus five latest vitals');
        System.assertEquals('128/76 mmHg', byKey.get('bp'), 'BP should pair latest systolic with latest diastolic');
        System.assertEquals('74 /min', byKey.get('hr'), 'Heart rate should use the newest observation');
        System.assertEquals('16 /min', byKey.get('rr'), 'Respiratory rate should be included');
        System.assertEquals('98.6 °F', byKey.get('temp'), 'Temperature should drop trailing zeros and show °F');
        System.assertEquals('98 %', byKey.get('spo2'), 'SpO2 should include the percent unit');
        System.assertEquals('70.5 kg', byKey.get('weight'), 'Weight should include the unit');
        System.assertEquals(newer, vitals.recordedAt, 'Recorded time should be the newest vital timestamp');
        System.assertEquals(0, blank.items.size(), 'Null patient should return no vitals');
        System.assertEquals(null, blank.recordedAt, 'Null patient should have no recorded time');
        System.assertEquals(1, empty.items.size(), 'Other patient should only see their own heart rate');
        System.assertEquals('99 /min', empty.items[0].value, 'Other patient heart rate should not mix records');
    }

    @IsTest
    static void getActiveCoverageReturnsPrimaryActiveForPatient() {
        Patient__c patient = insertPatient('MRN-BAN-COV-1');
        Patient__c other = insertPatient('MRN-BAN-COV-2');
        Payer__c aetna = insertPayer('Aetna');
        Payer__c medicaid = insertPayer('State Medicaid');
        insertCoverage(patient.Id, medicaid.Id, 'M-200', 'Medicaid', 'Secondary', 'Active');
        Coverage__c primary = insertCoverage(patient.Id, aetna.Id, 'M-100', 'Gold PPO', 'Primary', 'Active');
        insertCoverage(patient.Id, aetna.Id, 'M-300', 'Old Plan', 'Primary', 'Inactive');
        insertCoverage(other.Id, aetna.Id, 'M-999', 'Other Plan', 'Primary', 'Active');

        Test.startTest();
        PatientBannerController.ActiveCoverage coverage = PatientBannerController.getActiveCoverage(patient.Id);
        PatientBannerController.ActiveCoverage blank = PatientBannerController.getActiveCoverage(null);
        PatientBannerController.ActiveCoverage none = PatientBannerController.getActiveCoverage(
            insertPatient('MRN-BAN-COV-3').Id
        );
        Test.stopTest();

        System.assertNotEquals(null, coverage, 'Active primary coverage should be returned');
        System.assertEquals(primary.Id, coverage.coverageId, 'Primary active coverage should win sort order');
        System.assertEquals('Gold PPO (Banner) - Active', coverage.name, 'Coverage name should compose plan, patient, and status');
        System.assertEquals('Active', coverage.status, 'Status should load');
        System.assertEquals('Aetna', coverage.payerName, 'Payer name should load');
        System.assertEquals('Gold PPO', coverage.planName, 'Plan name should load');
        System.assertEquals('M-100', coverage.memberId, 'Member Id should load');
        System.assertEquals('Primary', coverage.priority, 'Priority should load');
        System.assertEquals(null, blank, 'Null patient should return no coverage');
        System.assertEquals(null, none, 'Patient without coverage should return null');
    }

    @IsTest
    static void getLatestVitalsHandlesPartialBloodPressureAndStringValues() {
        Patient__c systolicOnly = insertPatient('MRN-BAN-3');
        Patient__c diastolicOnly = insertPatient('MRN-BAN-4');
        Patient__c stringVital = insertPatient('MRN-BAN-5');
        Patient__c none = insertPatient('MRN-BAN-6');
        Datetime whenRecorded = Datetime.newInstance(2024, 4, 1, 9, 30, 0);

        insertObservation(systolicOnly.Id, '8480-6', 140, 'mmHg', whenRecorded);
        insertObservation(diastolicOnly.Id, '8462-4', 88, 'mmHg', whenRecorded);
        insertStringObservation(stringVital.Id, '8867-4', 'Irregular', whenRecorded);

        Test.startTest();
        PatientBannerController.LatestVitals sys = PatientBannerController.getLatestVitals(systolicOnly.Id);
        PatientBannerController.LatestVitals dia = PatientBannerController.getLatestVitals(diastolicOnly.Id);
        PatientBannerController.LatestVitals text = PatientBannerController.getLatestVitals(stringVital.Id);
        PatientBannerController.LatestVitals empty = PatientBannerController.getLatestVitals(none.Id);
        Test.stopTest();

        System.assertEquals(1, sys.items.size(), 'Systolic-only patient should return a BP item');
        System.assertEquals('bp', sys.items[0].key, 'Partial systolic should still use the BP key');
        System.assertEquals('BP', sys.items[0].label, 'Partial systolic should still use the BP label');
        System.assertEquals('140 mmHg', sys.items[0].value, 'Systolic-only BP should omit the missing diastolic');
        System.assertEquals('88 mmHg', dia.items[0].value, 'Diastolic-only BP should omit the missing systolic');
        System.assertEquals(1, text.items.size(), 'String-valued vital should still appear');
        System.assertEquals('hr', text.items[0].key, 'String heart rate should keep the HR key');
        System.assertEquals('Irregular', text.items[0].value, 'String value should be used when quantity is blank');
        System.assertEquals(0, empty.items.size(), 'Patient with no vitals should return an empty list');
        System.assertEquals(null, empty.recordedAt, 'Patient with no vitals should have no recorded time');
    }

    private static Map<String, String> valuesByKey(List<PatientBannerController.VitalItem> items) {
        Map<String, String> byKey = new Map<String, String>();
        for (PatientBannerController.VitalItem item : items) {
            byKey.put(item.key, item.value);
        }
        return byKey;
    }

    private static Patient__c insertPatient(String mrn) {
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'Banner');
        insert patient;
        return patient;
    }

    private static Payer__c insertPayer(String payerName) {
        Payer__c payer = new Payer__c(Name = payerName, Type__c = 'Commercial', Active__c = true);
        insert payer;
        return payer;
    }

    private static Coverage__c insertCoverage(
        Id patientId,
        Id payerId,
        String memberId,
        String planName,
        String priority,
        String status
    ) {
        Coverage__c coverage = new Coverage__c(
            Patient__c = patientId,
            Payer__c = payerId,
            Member_Id__c = memberId,
            Plan_Name__c = planName,
            Type__c = 'Medical',
            Priority__c = priority,
            Status__c = status
        );
        insert coverage;
        return coverage;
    }

    private static Observation__c insertObservation(
        Id patientId,
        String code,
        Decimal quantity,
        String unit,
        Datetime effective
    ) {
        Observation__c observation = new Observation__c(
            Patient__c = patientId,
            Category__c = 'Vital Signs',
            Status__c = 'Final',
            Observation_Code_System__c = 'LOINC',
            Observation_Code__c = code,
            Value_Quantity__c = quantity,
            Value_Unit__c = unit,
            Effective_DateTime__c = effective
        );
        insert observation;
        return observation;
    }

    private static Observation__c insertStringObservation(Id patientId, String code, String value, Datetime effective) {
        Observation__c observation = new Observation__c(
            Patient__c = patientId,
            Category__c = 'Vital Signs',
            Status__c = 'Final',
            Observation_Code_System__c = 'LOINC',
            Observation_Code__c = code,
            Value_String__c = value,
            Effective_DateTime__c = effective
        );
        insert observation;
        return observation;
    }

    private static Observation__c insertLab(Id patientId, String code, Decimal quantity, Datetime effective) {
        Observation__c observation = new Observation__c(
            Patient__c = patientId,
            Category__c = 'Laboratory',
            Status__c = 'Final',
            Observation_Code_System__c = 'LOINC',
            Observation_Code__c = code,
            Value_Quantity__c = quantity,
            Value_Unit__c = '/min',
            Effective_DateTime__c = effective
        );
        insert observation;
        return observation;
    }
}
