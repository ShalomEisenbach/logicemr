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
      vital('temp', 98.6),
      vital('spo2', 98),
      vital('height', 67),
      vital('weight', 154)
    };

    Test.startTest();
    List<Observation__c> created = VitalsCaptureController.saveVitals(
      encounter.Id,
      inputs
    );
    Test.stopTest();

    System.assertEquals(
      8,
      created.size(),
      'All eight vitals should persist in one call'
    );
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

    assertVital(
      byCode.get('8480-6'),
      encounter,
      'Systolic blood pressure',
      120,
      'mmHg'
    );
    assertVital(
      byCode.get('8462-4'),
      encounter,
      'Diastolic blood pressure',
      80,
      'mmHg'
    );
    assertVital(byCode.get('8867-4'), encounter, 'Heart rate', 72, '/min');
    assertVital(
      byCode.get('9279-1'),
      encounter,
      'Respiratory rate',
      16,
      '/min'
    );
    assertVital(byCode.get('8310-5'), encounter, 'Body temperature', 98.6, 'F');
    assertVital(byCode.get('59408-5'), encounter, 'Oxygen saturation', 98, '%');
    assertVital(byCode.get('8302-2'), encounter, 'Body height', 67, 'in');
    assertVital(byCode.get('29463-7'), encounter, 'Body weight', 154, 'lbs');
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
    List<Observation__c> created = VitalsCaptureController.saveVitals(
      encounter.Id,
      mixed
    );
    try {
      VitalsCaptureController.saveVitals(encounter.Id, null);
    } catch (AuraHandledException e) {
      nullListThrew = true;
    }
    try {
      VitalsCaptureController.saveVitals(
        encounter.Id,
        new List<VitalsCaptureController.VitalInput>()
      );
    } catch (AuraHandledException e) {
      emptyThrew = true;
    }
    Test.stopTest();

    System.assertEquals(1, created.size(), 'Null values should be skipped');
    System.assertEquals(
      '8867-4',
      created[0].Observation_Code__c,
      'Only heart rate should insert'
    );
    System.assertEquals(true, emptyThrew, 'Empty vitals should be rejected');
    System.assertEquals(
      true,
      nullListThrew,
      'Null vitals list should be rejected'
    );
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
        new List<VitalsCaptureController.VitalInput>{
          vital('systolic', 80),
          vital('diastolic', 90)
        }
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

    System.assertEquals(
      true,
      rangeThrew,
      'Out-of-range heart rate should be rejected'
    );
    System.assertEquals(
      true,
      bpThrew,
      'Systolic below diastolic should be rejected'
    );
    System.assertEquals(
      true,
      unknownThrew,
      'Unknown vital key should be rejected'
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Observation__c WHERE Encounter__c = :encounter.Id],
      'Rejected saves must not insert observations'
    );

    List<String> rangeErrors = VitalsCaptureController.validateVitals(
      new List<VitalsCaptureController.VitalInput>{
        vital('temp', 50),
        vital(null, 1)
      }
    );
    System.assertEquals(
      true,
      !rangeErrors.isEmpty(),
      'Validate should return range and unknown errors'
    );
  }

  @IsTest
  static void saveVitalsUpdatesExistingObservationForSameCode() {
    Encounter__c encounter = insertEncounter('MRN-VIT-UPSERT');
    VitalsCaptureController.saveVitals(
      encounter.Id,
      new List<VitalsCaptureController.VitalInput>{ vital('hr', 72) }
    );

    Test.startTest();
    List<Observation__c> updated = VitalsCaptureController.saveVitals(
      encounter.Id,
      new List<VitalsCaptureController.VitalInput>{
        vital('hr', 80),
        vital('spo2', 98)
      }
    );
    Test.stopTest();

    System.assertEquals(
      2,
      updated.size(),
      'Existing heart rate should update and SpO2 should insert'
    );
    System.assertEquals(
      2,
      [SELECT COUNT() FROM Observation__c WHERE Encounter__c = :encounter.Id],
      'Repeat save must not create a second heart rate observation'
    );
    Observation__c heartRate = [
      SELECT Value_Quantity__c
      FROM Observation__c
      WHERE Encounter__c = :encounter.Id AND Observation_Code__c = '8867-4'
    ];
    System.assertEquals(
      80,
      heartRate.Value_Quantity__c,
      'Heart rate should update in place'
    );
  }

  @IsTest
  static void getEncounterVitalsReturnsLatestNumericValues() {
    Encounter__c encounter = insertEncounter('MRN-VIT-LOAD');
    VitalsCaptureController.saveVitals(
      encounter.Id,
      new List<VitalsCaptureController.VitalInput>{
        vital('hr', 64),
        vital('temp', 98.6)
      }
    );
    insert new Observation__c(
      Patient__c = encounter.Patient__c,
      Encounter__c = encounter.Id,
      Category__c = 'Vital Signs',
      Status__c = 'Final',
      Observation_Code_System__c = 'LOINC',
      Observation_Code__c = '8867-4',
      Observation_Display__c = 'Heart rate',
      Value_Quantity__c = 88,
      Value_Unit__c = '/min',
      Effective_DateTime__c = Datetime.now().addMinutes(5)
    );

    Test.startTest();
    Map<String, Decimal> latest = VitalsCaptureController.getEncounterVitals(
      encounter.Id
    );
    Map<String, Decimal> blank = VitalsCaptureController.getEncounterVitals(
      null
    );
    Test.stopTest();

    System.assertEquals(88, latest.get('hr'), 'Latest heart rate should win');
    System.assertEquals(98.6, latest.get('temp'), 'Temperature should load');
    System.assertEquals(
      true,
      blank.isEmpty(),
      'Null encounter should return no vitals'
    );
  }

  @IsTest
  static void saveVitalsRejectsBlankOrUnknownEncounter() {
    Patient__c patient = new Patient__c(
      MRN__c = 'MRN-VIT-BAD',
      Last_Name__c = 'Vitals'
    );
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

    System.assertEquals(
      true,
      nullIdThrew,
      'Null encounter Id should be rejected'
    );
    System.assertEquals(
      true,
      unknownThrew,
      'Non-encounter Id should be rejected'
    );
  }

  @IsTest
  static void metricVitalsLoadWithUnitsAndLegacyValuesAreConverted() {
    Encounter__c encounter = insertEncounter('MRN-VIT-METRIC');
    insertMetricVitals(encounter);

    Test.startTest();
    Map<String, VitalsCaptureController.VitalValue> details = VitalsCaptureController.getEncounterVitalDetails(
      encounter.Id
    );
    Map<String, Decimal> legacy = VitalsCaptureController.getEncounterVitals(
      encounter.Id
    );
    Test.stopTest();

    System.assertEquals(
      36.8,
      details.get('temp').value,
      'Unit-aware load must retain Celsius quantity'
    );
    System.assertEquals(
      'Cel',
      details.get('temp').unit,
      'Celsius source unit must be returned'
    );
    System.assertEquals(
      '°C',
      details.get('temp').displayUnit,
      'Celsius should have its clinical label'
    );
    System.assertEquals(
      30,
      details.get('temp').minValue,
      'Temperature bounds must use Celsius'
    );
    System.assertEquals(
      45,
      details.get('temp').maxValue,
      'Temperature bounds must use Celsius'
    );
    System.assertEquals(
      'kg',
      details.get('weight').unit,
      'Weight must retain kilograms'
    );
    System.assertEquals(
      'cm',
      details.get('height').unit,
      'Height must retain centimeters'
    );
    System.assertEquals(
      98.24,
      legacy.get('temp'),
      'Legacy numeric load must convert Celsius to Fahrenheit'
    );
    System.assertEquals(
      (70 / Decimal.valueOf('0.45359237')).setScale(4),
      legacy.get('weight').setScale(4),
      'Legacy load must convert kilograms to pounds'
    );
    System.assertEquals(
      (170 / Decimal.valueOf('2.54')).setScale(4),
      legacy.get('height').setScale(4),
      'Legacy load must convert centimeters to inches'
    );
  }

  @IsTest
  static void metricEditsPreserveSourceUnitsAndLeaveOtherVitalsUntouched() {
    Encounter__c encounter = insertEncounter('MRN-VIT-PRESERVE');
    insertMetricVitals(encounter);
    Observation__c heightBefore = [
      SELECT Id, Value_Quantity__c, Value_Unit__c, Effective_DateTime__c
      FROM Observation__c
      WHERE Encounter__c = :encounter.Id AND Observation_Code__c = '8302-2'
    ];

    Test.startTest();
    VitalsCaptureController.saveVitals(
      encounter.Id,
      new List<VitalsCaptureController.VitalInput>{
        vitalWithUnit('temp', 37, 'Cel'),
        vitalWithUnit('weight', 71, 'kg')
      }
    );
    Test.stopTest();

    Map<String, VitalsCaptureController.VitalValue> details = VitalsCaptureController.getEncounterVitalDetails(
      encounter.Id
    );
    System.assertEquals(
      37,
      details.get('temp').value,
      'Edited Celsius value must persist without relabeling'
    );
    System.assertEquals(
      'Cel',
      details.get('temp').unit,
      'Celsius unit must remain'
    );
    System.assertEquals(
      71,
      details.get('weight').value,
      'Edited kilogram value must persist'
    );
    System.assertEquals(
      'kg',
      details.get('weight').unit,
      'Kilogram unit must remain'
    );
    Observation__c heightAfter = [
      SELECT Value_Quantity__c, Value_Unit__c, Effective_DateTime__c
      FROM Observation__c
      WHERE Id = :heightBefore.Id
    ];
    System.assertEquals(
      heightBefore.Value_Quantity__c,
      heightAfter.Value_Quantity__c,
      'Untouched height value must remain'
    );
    System.assertEquals(
      heightBefore.Value_Unit__c,
      heightAfter.Value_Unit__c,
      'Untouched height unit must remain'
    );
    System.assertEquals(
      heightBefore.Effective_DateTime__c,
      heightAfter.Effective_DateTime__c,
      'Untouched height timestamp must remain'
    );
  }

  @IsTest
  static void legacyEditsConvertToSupportedExistingUnitsAndNoOpDoesNotRedate() {
    Encounter__c encounter = insertEncounter('MRN-VIT-LEGACY');
    insertMetricVitals(encounter);
    Observation__c before = [
      SELECT Id, Effective_DateTime__c
      FROM Observation__c
      WHERE Encounter__c = :encounter.Id AND Observation_Code__c = '8310-5'
    ];

    Test.startTest();
    List<Observation__c> unchanged = VitalsCaptureController.saveVitals(
      encounter.Id,
      new List<VitalsCaptureController.VitalInput>{ vital('temp', 98.24) }
    );
    Observation__c afterNoOp = [
      SELECT Effective_DateTime__c
      FROM Observation__c
      WHERE Id = :before.Id
    ];
    VitalsCaptureController.saveVitals(
      encounter.Id,
      new List<VitalsCaptureController.VitalInput>{
        vital('temp', 98.6),
        vitalWithUnit('weight', 158.7328287731, '[lb_av]'),
        vitalWithUnit('height', 68, '[in_i]')
      }
    );
    Test.stopTest();

    System.assertEquals(
      0,
      unchanged.size(),
      'An equivalent value must not rewrite a measurement'
    );
    System.assertEquals(
      before.Effective_DateTime__c,
      afterNoOp.Effective_DateTime__c,
      'No-op must preserve effective time'
    );
    Map<String, VitalsCaptureController.VitalValue> details = VitalsCaptureController.getEncounterVitalDetails(
      encounter.Id
    );
    System.assertEquals(
      37,
      details.get('temp').value,
      'Legacy Fahrenheit edit must convert back to Celsius'
    );
    System.assertEquals(
      'Cel',
      details.get('temp').unit,
      'Legacy edit must preserve Celsius source unit'
    );
    System.assertEquals(
      72,
      details.get('weight').value,
      'Explicit pound edit must convert back to kilograms'
    );
    System.assertEquals(
      'kg',
      details.get('weight').unit,
      'Source kilograms must remain'
    );
    System.assertEquals(
      172.72,
      details.get('height').value,
      'Explicit inch edit must convert back to centimeters'
    );
  }

  @IsTest
  static void unknownAndMissingUnitsAreVisibleButCannotBeGuessedOrOverwritten() {
    Encounter__c encounter = insertEncounter('MRN-VIT-UNKNOWN');
    insert new List<Observation__c>{
      recordedVital(encounter, '8310-5', 310, 'K'),
      recordedVital(encounter, '29463-7', 70, null)
    };
    Map<String, VitalsCaptureController.VitalValue> details = VitalsCaptureController.getEncounterVitalDetails(
      encounter.Id
    );
    System.assertEquals(
      310,
      details.get('temp').value,
      'Unsupported quantities should remain visible'
    );
    System.assertEquals(
      'K',
      details.get('temp').unit,
      'Unsupported unit must be returned unchanged'
    );
    System.assertEquals(
      false,
      details.get('temp').supportedUnit,
      'Unknown unit must be identified'
    );
    System.assertEquals(
      false,
      details.get('weight').supportedUnit,
      'Missing unit cannot be guessed'
    );
    System.assertEquals(
      true,
      VitalsCaptureController.getEncounterVitals(encounter.Id).isEmpty(),
      'Legacy load must omit quantities it cannot safely convert'
    );

    Boolean inputUnitRejected = false;
    Boolean sourceUnitRejected = false;
    Test.startTest();
    try {
      VitalsCaptureController.saveVitals(
        encounter.Id,
        new List<VitalsCaptureController.VitalInput>{
          vitalWithUnit('temp', 310, 'K')
        }
      );
    } catch (AuraHandledException e) {
      inputUnitRejected = true;
    }
    try {
      VitalsCaptureController.saveVitals(
        encounter.Id,
        new List<VitalsCaptureController.VitalInput>{ vital('weight', 150) }
      );
    } catch (AuraHandledException e) {
      sourceUnitRejected = true;
    }
    VitalsCaptureController.saveVitals(
      encounter.Id,
      new List<VitalsCaptureController.VitalInput>{
        vitalWithUnit('hr', 72, '/min')
      }
    );
    Test.stopTest();
    System.assertEquals(
      true,
      inputUnitRejected,
      'Unsupported submitted units must fail'
    );
    System.assertEquals(
      true,
      sourceUnitRejected,
      'Unsupported source units must not be overwritten'
    );
    Observation__c weight = [
      SELECT Value_Quantity__c, Value_Unit__c
      FROM Observation__c
      WHERE Encounter__c = :encounter.Id AND Observation_Code__c = '29463-7'
    ];
    System.assertEquals(
      70,
      weight.Value_Quantity__c,
      'Unknown-unit measurement must remain untouched'
    );
    System.assertEquals(
      null,
      weight.Value_Unit__c,
      'Unknown source unit must not be relabeled'
    );
  }

  @IsTest
  static void partialBloodPressureEditValidatesRecordedCounterpart() {
    Encounter__c encounter = insertEncounter('MRN-VIT-PARTIAL-BP');
    VitalsCaptureController.saveVitals(
      encounter.Id,
      new List<VitalsCaptureController.VitalInput>{
        vital('systolic', 120),
        vital('diastolic', 90)
      }
    );
    Boolean rejected = false;
    Test.startTest();
    try {
      VitalsCaptureController.saveVitals(
        encounter.Id,
        new List<VitalsCaptureController.VitalInput>{
          vitalWithUnit('systolic', 80, 'mm[Hg]')
        }
      );
    } catch (AuraHandledException e) {
      rejected = true;
    }
    Test.stopTest();
    System.assertEquals(
      true,
      rejected,
      'Partial BP edit must validate the recorded diastolic value'
    );
    System.assertEquals(
      120,
      VitalsCaptureController.getEncounterVitals(encounter.Id).get('systolic'),
      'Rejected edit must leave systolic unchanged'
    );
  }

  private static void insertMetricVitals(Encounter__c encounter) {
    insert new List<Observation__c>{
      recordedVital(encounter, '8310-5', 36.8, 'Cel'),
      recordedVital(encounter, '29463-7', 70, 'kg'),
      recordedVital(encounter, '8302-2', 170, 'cm')
    };
  }

  private static Observation__c recordedVital(
    Encounter__c encounter,
    String code,
    Decimal value,
    String unit
  ) {
    return new Observation__c(
      Patient__c = encounter.Patient__c,
      Encounter__c = encounter.Id,
      Category__c = 'Vital Signs',
      Status__c = 'Final',
      Observation_Code_System__c = 'LOINC',
      Observation_Code__c = code,
      Value_Quantity__c = value,
      Value_Unit__c = unit,
      Effective_DateTime__c = Datetime.newInstance(2024, 3, 1, 9, 0, 0)
    );
  }

  private static VitalsCaptureController.VitalInput vitalWithUnit(
    String key,
    Decimal value,
    String unit
  ) {
    VitalsCaptureController.VitalInput input = vital(key, value);
    input.unit = unit;
    return input;
  }

  private static void assertVital(
    Observation__c row,
    Encounter__c encounter,
    String display,
    Decimal value,
    String unit
  ) {
    System.assertNotEquals(null, row, display + ' should be saved');
    System.assertEquals(
      encounter.Patient__c,
      row.Patient__c,
      display + ' should stamp Patient'
    );
    System.assertEquals(
      encounter.Id,
      row.Encounter__c,
      display + ' should stamp Encounter'
    );
    System.assertEquals(
      'Vital Signs',
      row.Category__c,
      display + ' category should be Vital Signs'
    );
    System.assertEquals(
      'Final',
      row.Status__c,
      display + ' status should be Final'
    );
    System.assertEquals(
      'LOINC',
      row.Observation_Code_System__c,
      display + ' should use LOINC'
    );
    System.assertEquals(
      display,
      row.Observation_Display__c,
      display + ' display should match'
    );
    System.assertEquals(
      value,
      row.Value_Quantity__c,
      display + ' quantity should persist'
    );
    System.assertEquals(
      unit,
      row.Value_Unit__c,
      display + ' unit should persist'
    );
    System.assertNotEquals(
      null,
      row.Effective_DateTime__c,
      display + ' should stamp effective time'
    );
  }

  private static VitalsCaptureController.VitalInput vital(
    String key,
    Decimal value
  ) {
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
