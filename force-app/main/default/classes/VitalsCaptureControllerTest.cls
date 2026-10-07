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

  @IsTest
  static void readOnlyUserCannotInsertOrUpdateVitals() {
    User reader = vitalsAccessUser('vitread', false, false, null);
    Encounter__c encounter;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      encounter = insertEncounter('MRN-VIT-READ-ONLY');
      insertMetricVitals(encounter);
    }
    Observation__c before = [
      SELECT Id, Value_Quantity__c, Effective_DateTime__c
      FROM Observation__c
      WHERE Encounter__c = :encounter.Id AND Observation_Code__c = '8310-5'
    ];
    System.runAs(reader) {
      System.assert(Observation__c.SObjectType.getDescribe().isAccessible());
      System.assert(!Observation__c.SObjectType.getDescribe().isCreateable());
      System.assert(!Observation__c.SObjectType.getDescribe().isUpdateable());
      System.assertEquals(
        0,
        VitalsCaptureController.saveVitals(
            encounter.Id,
            new List<VitalsCaptureController.VitalInput>{ vital('temp', 98.24) }
          )
          .size(),
        'An equivalent value remains a read-only no-op'
      );
      assertVitalSaveDenied(encounter.Id, vital('hr', 72));
      assertVitalSaveDenied(encounter.Id, vitalWithUnit('temp', 37, 'Cel'));
    }
    assertMeasurementUnchanged(before);
    System.assertEquals(
      3,
      [SELECT COUNT() FROM Observation__c WHERE Encounter__c = :encounter.Id],
      'Denied creation must not add a measurement'
    );
  }

  @IsTest
  static void objectWriteAccessCannotBypassVitalFieldPermissions() {
    User writer = vitalsAccessUser(
      'vitfls',
      true,
      true,
      Observation__c.Value_Quantity__c
    );
    Encounter__c encounter;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      encounter = insertEncounter('MRN-VIT-FIELD-PERMISSION');
      insertMetricVitals(encounter);
    }
    Observation__c before = [
      SELECT Id, Value_Quantity__c, Effective_DateTime__c
      FROM Observation__c
      WHERE Encounter__c = :encounter.Id AND Observation_Code__c = '8310-5'
    ];
    System.runAs(writer) {
      System.assert(Observation__c.SObjectType.getDescribe().isCreateable());
      System.assert(Observation__c.SObjectType.getDescribe().isUpdateable());
      System.assert(
        Observation__c.Value_Quantity__c.getDescribe().isAccessible()
      );
      System.assert(
        !Observation__c.Value_Quantity__c.getDescribe().isCreateable()
      );
      System.assert(
        !Observation__c.Value_Quantity__c.getDescribe().isUpdateable()
      );
      assertVitalSaveDenied(encounter.Id, vital('hr', 72));
      assertVitalSaveDenied(encounter.Id, vitalWithUnit('temp', 37, 'Cel'));
    }
    assertMeasurementUnchanged(before);
    System.assertEquals(
      3,
      [SELECT COUNT() FROM Observation__c WHERE Encounter__c = :encounter.Id]
    );
  }

  @IsTest
  static void mixedSaveChecksInsertFieldsBeforeUpdatingExistingVitals() {
    User writer = vitalsAccessUser(
      'vitmix',
      true,
      true,
      Observation__c.Observation_Display__c
    );
    Encounter__c encounter;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      encounter = insertEncounter('MRN-VIT-MIXED-PERMISSIONS');
      insertMetricVitals(encounter);
    }
    Observation__c before = [
      SELECT Id, Value_Quantity__c, Effective_DateTime__c
      FROM Observation__c
      WHERE Encounter__c = :encounter.Id AND Observation_Code__c = '8310-5'
    ];
    System.runAs(writer) {
      System.assert(
        Observation__c.Value_Quantity__c.getDescribe().isUpdateable()
      );
      System.assert(
        !Observation__c.Observation_Display__c.getDescribe().isCreateable()
      );
      Boolean denied = false;
      try {
        VitalsCaptureController.saveVitals(
          encounter.Id,
          new List<VitalsCaptureController.VitalInput>{
            vitalWithUnit('temp', 37, 'Cel'),
            vital('hr', 72)
          }
        );
      } catch (AuraHandledException error) {
        denied = error.getMessage().contains('permission');
      }
      System.assert(denied, 'Every insertion field must be authorized');
    }
    assertMeasurementUnchanged(before);
    System.assertEquals(
      3,
      [SELECT COUNT() FROM Observation__c WHERE Encounter__c = :encounter.Id],
      'A denied mixed save must leave both operation groups untouched'
    );
    System.runAs(writer) {
      List<Observation__c> saved = VitalsCaptureController.saveVitals(
        encounter.Id,
        new List<VitalsCaptureController.VitalInput>{
          vitalWithUnit('temp', 37, 'Cel')
        }
      );
      System.assertEquals(1, saved.size());
      System.assertEquals(37, saved[0].Value_Quantity__c);
      System.assertEquals('Cel', saved[0].Value_Unit__c);
      System.assertEquals('8310-5', saved[0].Observation_Code__c);
    }
    System.assertEquals(
      37,
      [SELECT Value_Quantity__c FROM Observation__c WHERE Id = :before.Id]
      .Value_Quantity__c,
      'Editing an existing value does not require writing its source metadata'
    );
  }

  @IsTest
  static void createOnlyUserCannotChangeRecordedVitals() {
    User creator = vitalsAccessUser('vitnew', true, false, null);
    Encounter__c encounter;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      encounter = insertEncounter('MRN-VIT-CREATE-ONLY');
    }
    Observation__c before;
    System.runAs(creator) {
      System.assert(Observation__c.SObjectType.getDescribe().isCreateable());
      System.assert(!Observation__c.SObjectType.getDescribe().isUpdateable());
      before = VitalsCaptureController.saveVitals(
        encounter.Id,
        new List<VitalsCaptureController.VitalInput>{ vital('hr', 72) }
      )[0];
      System.assertNotEquals(null, before.Id);
      assertVitalSaveDenied(encounter.Id, vital('hr', 74));
    }
    assertMeasurementUnchanged(before);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Observation__c WHERE Encounter__c = :encounter.Id]
    );
  }

  @IsTest
  static void packagedBillingRoleCannotMutateVitals() {
    User billing = accessUser('vitbill');
    insert billing;
    insert new PermissionSetAssignment(
      AssigneeId = billing.Id,
      PermissionSetId = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'LogicEMR_Billing'
        LIMIT 1
      ]
      .Id
    );
    Encounter__c encounter;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      encounter = insertEncounter('MRN-VIT-BILLING');
    }
    System.runAs(billing) {
      System.assert(!Observation__c.SObjectType.getDescribe().isCreateable());
      System.assert(!Observation__c.SObjectType.getDescribe().isUpdateable());
      assertVitalSaveDenied(encounter.Id, vital('hr', 72));
    }
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Observation__c WHERE Encounter__c = :encounter.Id]
    );
  }

  @IsTest
  static void captureDefaultsPopulateEveryBlankVitalWithIndependentPreferences() {
    Encounter__c encounter = insertEncounter('MRN-VIT-CAPTURE-BLANK');
    setCapturePreferences('F', 'Metric');
    Map<String, VitalsCaptureController.VitalValue> fahrenheitMetric = VitalsCaptureController.getEncounterVitalsForCapture(
      encounter.Id
    );
    assertCaptureKeys(fahrenheitMetric);
    assertCaptureDetail(fahrenheitMetric.get('temp'), null, 'F', 86, 113);
    assertCaptureDetail(
      fahrenheitMetric.get('height'),
      null,
      'cm',
      30.48,
      274.32
    );
    assertCaptureDetail(
      fahrenheitMetric.get('weight'),
      null,
      'kg',
      0.4536,
      498.9516
    );
    for (
      VitalsCaptureController.VitalValue detail : fahrenheitMetric.values()
    ) {
      System.assertEquals(
        null,
        detail.value,
        'New measurements must stay blank'
      );
      System.assertEquals(null, detail.sourceValue);
      System.assertEquals(null, detail.sourceUnit);
      System.assertEquals(false, detail.converted);
      System.assertEquals(true, detail.supportedUnit);
    }
    setCapturePreferences('Cel', 'Imperial');
    Map<String, VitalsCaptureController.VitalValue> celsiusImperial = VitalsCaptureController.getEncounterVitalsForCapture(
      encounter.Id
    );
    assertCaptureDetail(celsiusImperial.get('temp'), null, 'Cel', 30, 45);
    assertCaptureDetail(celsiusImperial.get('height'), null, 'in', 12, 108);
    assertCaptureDetail(celsiusImperial.get('weight'), null, 'lbs', 1, 1100);
    System.assertEquals('°C', celsiusImperial.get('temp').displayUnit);
    System.assertEquals('/min', celsiusImperial.get('hr').unit);
    System.assertEquals('mmHg', celsiusImperial.get('systolic').unit);
    System.assertEquals('%', celsiusImperial.get('spo2').unit);
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Observation__c WHERE Encounter__c = :encounter.Id]
    );
    System.assertEquals(
      true,
      VitalsCaptureController.getEncounterVitalDetails(encounter.Id).isEmpty(),
      'The raw API must retain its sparse empty-map contract'
    );
    assertCaptureKeys(
      VitalsCaptureController.getEncounterVitalsForCapture(null)
    );
  }

  @IsTest
  static void captureConvertsMetricSourcesWithoutChangingRawOrLegacyReads() {
    Encounter__c encounter = insertEncounter('MRN-VIT-CAPTURE-IMPERIAL');
    insertMetricVitals(encounter);
    List<Observation__c> before = captureObservations(encounter.Id);
    setCapturePreferences('F', 'Imperial');
    Integer dmlBefore = Limits.getDmlStatements();
    Map<String, VitalsCaptureController.VitalValue> capture = VitalsCaptureController.getEncounterVitalsForCapture(
      encounter.Id
    );
    System.assertEquals(
      dmlBefore,
      Limits.getDmlStatements(),
      'Capture reads must not write observations'
    );
    assertCaptureDetail(capture.get('temp'), 98.24, 'F', 86, 113);
    assertCaptureDetail(
      capture.get('height'),
      (170 / Decimal.valueOf('2.54')).setScale(4),
      'in',
      12,
      108
    );
    assertCaptureDetail(
      capture.get('weight'),
      (70 / Decimal.valueOf('0.45359237')).setScale(4),
      'lbs',
      1,
      1100
    );
    System.assertEquals('°F', capture.get('temp').displayUnit);
    System.assertEquals(36.8, capture.get('temp').sourceValue);
    System.assertEquals('Cel', capture.get('temp').sourceUnit);
    System.assertEquals(true, capture.get('temp').converted);
    Map<String, VitalsCaptureController.VitalValue> raw = VitalsCaptureController.getEncounterVitalDetails(
      encounter.Id
    );
    System.assertEquals(36.8, raw.get('temp').value);
    System.assertEquals('Cel', raw.get('temp').unit);
    System.assertEquals(170, raw.get('height').value);
    System.assertEquals('cm', raw.get('height').unit);
    System.assertEquals(70, raw.get('weight').value);
    System.assertEquals('kg', raw.get('weight').unit);
    System.assertEquals(
      98.24,
      VitalsCaptureController.getEncounterVitals(encounter.Id).get('temp')
    );
    assertCaptureObservationsUnchanged(before);
  }

  @IsTest
  static void captureConvertsImperialSourcesToCelsiusAndMetric() {
    Encounter__c encounter = insertEncounter('MRN-VIT-CAPTURE-METRIC');
    insert new List<Observation__c>{
      recordedVital(encounter, '8310-5', 98.6, '[degF]'),
      recordedVital(encounter, '8302-2', 67, '[in_i]'),
      recordedVital(encounter, '29463-7', 154, '[lb_av]')
    };
    List<Observation__c> before = captureObservations(encounter.Id);
    setCapturePreferences('Cel', 'Metric');
    Map<String, VitalsCaptureController.VitalValue> capture = VitalsCaptureController.getEncounterVitalsForCapture(
      encounter.Id
    );
    assertCaptureDetail(capture.get('temp'), 37, 'Cel', 30, 45);
    assertCaptureDetail(capture.get('height'), 170.18, 'cm', 30.48, 274.32);
    assertCaptureDetail(
      capture.get('weight'),
      (154 * Decimal.valueOf('0.45359237')).setScale(4),
      'kg',
      0.4536,
      498.9516
    );
    System.assertEquals('[degF]', capture.get('temp').sourceUnit);
    System.assertEquals('[in_i]', capture.get('height').sourceUnit);
    System.assertEquals('[lb_av]', capture.get('weight').sourceUnit);
    System.assertEquals(true, capture.get('height').converted);
    assertCaptureObservationsUnchanged(before);
  }

  @IsTest
  static void convertedCaptureRoundTripsDoNotRedateButRealEditsPreserveSourceAliases() {
    Encounter__c encounter = insertEncounter('MRN-VIT-CAPTURE-ROUNDTRIP');
    insert new List<Observation__c>{
      recordedVital(encounter, '8310-5', 36.8123, 'degC'),
      recordedVital(encounter, '8302-2', 1.7001, 'm'),
      recordedVital(encounter, '29463-7', 70000.1234, 'g')
    };
    List<Observation__c> before = captureObservations(encounter.Id);
    for (String measurementSystem : new List<String>{ 'Imperial', 'Metric' }) {
      setCapturePreferences(
        measurementSystem == 'Imperial' ? 'F' : 'Cel',
        measurementSystem
      );
      Map<String, VitalsCaptureController.VitalValue> capture = VitalsCaptureController.getEncounterVitalsForCapture(
        encounter.Id
      );
      List<VitalsCaptureController.VitalInput> unchangedInputs = new List<VitalsCaptureController.VitalInput>();
      for (String key : new List<String>{ 'temp', 'height', 'weight' }) {
        unchangedInputs.add(
          vitalWithUnit(key, capture.get(key).value, capture.get(key).unit)
        );
      }
      Integer dmlBefore = Limits.getDmlStatements();
      System.assertEquals(
        0,
        VitalsCaptureController.saveVitals(encounter.Id, unchangedInputs)
          .size(),
        'A rounded preferred presentation is still the same source measurement'
      );
      System.assertEquals(
        dmlBefore,
        Limits.getDmlStatements(),
        'Preference changes must not cause DML'
      );
      assertCaptureObservationsUnchanged(before);
    }
    setCapturePreferences('F', 'Imperial');
    VitalsCaptureController.saveVitals(
      encounter.Id,
      new List<VitalsCaptureController.VitalInput>{
        vitalWithUnit('temp', 99.5, 'F'),
        vitalWithUnit('height', 68, 'in'),
        vitalWithUnit('weight', 160, 'lbs')
      }
    );
    Map<String, VitalsCaptureController.VitalValue> raw = VitalsCaptureController.getEncounterVitalDetails(
      encounter.Id
    );
    System.assertEquals(37.5, raw.get('temp').value);
    System.assertEquals('degC', raw.get('temp').unit);
    System.assertEquals(1.7272, raw.get('height').value);
    System.assertEquals('m', raw.get('height').unit);
    System.assertEquals(72574.7792, raw.get('weight').value);
    System.assertEquals('g', raw.get('weight').unit);
    for (Observation__c after : captureObservations(encounter.Id)) {
      System.assertNotEquals(
        before[0].Effective_DateTime__c,
        after.Effective_DateTime__c,
        'A genuine edit records a new effective timestamp'
      );
    }
  }

  @IsTest
  static void blankCaptureCreatesMeasurementsInSelectedUnitsThenReloadsWithoutWrites() {
    Encounter__c encounter = insertEncounter('MRN-VIT-CAPTURE-NEW');
    setCapturePreferences('Cel', 'Metric');
    Map<String, VitalsCaptureController.VitalValue> empty = VitalsCaptureController.getEncounterVitalsForCapture(
      encounter.Id
    );
    VitalsCaptureController.saveVitals(
      encounter.Id,
      new List<VitalsCaptureController.VitalInput>{
        vitalWithUnit('temp', 36.8, empty.get('temp').unit),
        vitalWithUnit('height', 170, empty.get('height').unit),
        vitalWithUnit('weight', 70, empty.get('weight').unit)
      }
    );
    Map<String, VitalsCaptureController.VitalValue> raw = VitalsCaptureController.getEncounterVitalDetails(
      encounter.Id
    );
    System.assertEquals(36.8, raw.get('temp').value);
    System.assertEquals('Cel', raw.get('temp').unit);
    System.assertEquals(170, raw.get('height').value);
    System.assertEquals('cm', raw.get('height').unit);
    System.assertEquals(70, raw.get('weight').value);
    System.assertEquals('kg', raw.get('weight').unit);
    List<Observation__c> before = captureObservations(encounter.Id);
    setCapturePreferences('F', 'Imperial');
    Map<String, VitalsCaptureController.VitalValue> reload = VitalsCaptureController.getEncounterVitalsForCapture(
      encounter.Id
    );
    System.assertEquals(
      0,
      VitalsCaptureController.saveVitals(
          encounter.Id,
          new List<VitalsCaptureController.VitalInput>{
            vitalWithUnit(
              'temp',
              reload.get('temp').value,
              reload.get('temp').unit
            ),
            vitalWithUnit(
              'height',
              reload.get('height').value,
              reload.get('height').unit
            ),
            vitalWithUnit(
              'weight',
              reload.get('weight').value,
              reload.get('weight').unit
            )
          }
        )
        .size()
    );
    assertCaptureObservationsUnchanged(before);
  }

  @IsTest
  static void preferredCaptureRetainsUnsupportedAndMissingSourceUnits() {
    Encounter__c encounter = insertEncounter('MRN-VIT-CAPTURE-UNKNOWN');
    insert new List<Observation__c>{
      recordedVital(encounter, '8310-5', 310, 'K'),
      recordedVital(encounter, '8302-2', 1, 'furlong'),
      recordedVital(encounter, '29463-7', 70, null)
    };
    List<Observation__c> before = captureObservations(encounter.Id);
    setCapturePreferences('Cel', 'Metric');
    Map<String, VitalsCaptureController.VitalValue> capture = VitalsCaptureController.getEncounterVitalsForCapture(
      encounter.Id
    );
    assertCaptureKeys(capture);
    for (String key : new List<String>{ 'temp', 'height', 'weight' }) {
      VitalsCaptureController.VitalValue detail = capture.get(key);
      System.assertEquals(false, detail.supportedUnit);
      System.assertEquals(false, detail.converted);
      System.assertEquals(detail.sourceValue, detail.value);
      System.assertEquals(detail.sourceUnit, detail.unit);
      System.assertEquals(null, detail.minValue);
      System.assertEquals(null, detail.maxValue);
    }
    System.assertEquals(310, capture.get('temp').value);
    System.assertEquals('K', capture.get('temp').displayUnit);
    System.assertEquals(null, capture.get('weight').unit);
    Boolean rejected = false;
    try {
      VitalsCaptureController.saveVitals(
        encounter.Id,
        new List<VitalsCaptureController.VitalInput>{
          vitalWithUnit('weight', 71, 'kg')
        }
      );
    } catch (AuraHandledException error) {
      rejected = true;
    }
    System.assert(
      rejected,
      'A preference cannot label an unknown recorded unit'
    );
    assertCaptureObservationsUnchanged(before);
  }

  @IsTest
  static void sharedPreferredVitalHelperPreservesProvenanceAndIgnoresOtherCodes() {
    setCapturePreferences('Cel', 'Metric');
    VitalsCaptureController.VitalValue converted = VitalsCaptureController.preferredVitalValue(
      '8310-5',
      98.6,
      '[degF]'
    );
    System.assertEquals(37, converted.value);
    System.assertEquals('Cel', converted.unit);
    System.assertEquals(98.6, converted.sourceValue);
    System.assertEquals('[degF]', converted.sourceUnit);
    System.assertEquals(true, converted.converted);
    VitalsCaptureController.VitalValue sameUnit = VitalsCaptureController.preferredVitalValue(
      '8310-5',
      37.1234,
      'degC'
    );
    System.assertEquals(37.1234, sameUnit.value);
    System.assertEquals('Cel', sameUnit.unit);
    System.assertEquals('degC', sameUnit.sourceUnit);
    System.assertEquals(
      false,
      sameUnit.converted,
      'Same-canonical unit aliases allow displays to preserve their original text'
    );
    System.assertEquals(
      170,
      VitalsCaptureController.preferredVitalValue('8302-2', 1.7, 'm').value
    );
    System.assertEquals(
      70,
      VitalsCaptureController.preferredVitalValue('29463-7', 70000, 'g').value
    );
    System.assertEquals(
      null,
      VitalsCaptureController.preferredVitalValue('2339-0', 90, 'mg/dL'),
      'An unrelated lab result must not be classified as a vital'
    );
    System.assertEquals(
      null,
      VitalsCaptureController.preferredVitalValue(null, 90, 'mg/dL')
    );
  }

  @IsTest
  static void captureRequiresObservationReadAccess() {
    User reader = accessUser('vitnread');
    insert reader;
    Encounter__c encounter;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      encounter = insertEncounter('MRN-VIT-CAPTURE-NO-READ');
      insertMetricVitals(encounter);
    }
    System.runAs(reader) {
      System.assertEquals(
        false,
        Observation__c.SObjectType.getDescribe().isAccessible()
      );
      Boolean denied = false;
      try {
        VitalsCaptureController.getEncounterVitalsForCapture(encounter.Id);
      } catch (AuraHandledException error) {
        denied = error.getMessage().contains('permission');
      }
      System.assert(
        denied,
        'A direct capture API call must enforce read access'
      );
    }
  }

  @IsTest
  static void captureAllowsAuthorizedReaderAndRequiresUnitFieldAccess() {
    User reader = vitalsAccessUser('vitcaprd', false, false, null);
    User restricted = vitalsAccessUser('vitcapfl', false, false, null);
    String unitFieldName =
      qualifiedObjectName(Observation__c.SObjectType) +
      '.' +
      Observation__c.Value_Unit__c.getDescribe().getName();
    delete [
      SELECT Id
      FROM FieldPermissions
      WHERE Parent.Name = 'Vitals_vitcapfl_Test' AND Field = :unitFieldName
    ];
    Encounter__c encounter;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      encounter = insertEncounter('MRN-VIT-CAPTURE-READ-FLS');
      insertMetricVitals(encounter);
    }
    setCapturePreferences('Cel', 'Metric');
    System.runAs(reader) {
      System.assertEquals(
        36.8,
        VitalsCaptureController.getEncounterVitalsForCapture(encounter.Id)
          .get('temp')
          .value,
        'A reader can view preferred values without clinical edit grants'
      );
    }
    System.runAs(restricted) {
      System.assertEquals(
        false,
        Observation__c.Value_Unit__c.getDescribe().isAccessible()
      );
      Boolean denied = false;
      try {
        VitalsCaptureController.getEncounterVitalsForCapture(encounter.Id);
      } catch (AuraHandledException error) {
        denied = error.getMessage().contains('permission');
      }
      System.assert(
        denied,
        'Unit conversion must not read a restricted source field'
      );
    }
  }

  private static void setCapturePreferences(
    String temperatureUnit,
    String measurementSystem
  ) {
    ClinicalUnitSettings.Preferences preferences = new ClinicalUnitSettings.Preferences();
    preferences.temperatureUnit = temperatureUnit;
    preferences.measurementSystem = measurementSystem;
    ClinicalUnitSettings.preferenceOverride = preferences;
  }

  private static void assertCaptureKeys(
    Map<String, VitalsCaptureController.VitalValue> capture
  ) {
    System.assertEquals(
      new Set<String>{
        'systolic',
        'diastolic',
        'hr',
        'rr',
        'temp',
        'spo2',
        'height',
        'weight'
      },
      capture.keySet()
    );
  }

  private static void assertCaptureDetail(
    VitalsCaptureController.VitalValue detail,
    Decimal value,
    String unit,
    Decimal minimum,
    Decimal maximum
  ) {
    System.assertEquals(value, detail.value);
    System.assertEquals(unit, detail.unit);
    System.assertEquals(minimum, detail.minValue);
    System.assertEquals(maximum, detail.maxValue);
    System.assertEquals(true, detail.supportedUnit);
  }

  private static List<Observation__c> captureObservations(Id encounterId) {
    return [
      SELECT
        Id,
        Observation_Code__c,
        Value_Quantity__c,
        Value_Unit__c,
        Effective_DateTime__c
      FROM Observation__c
      WHERE Encounter__c = :encounterId
      ORDER BY Id
    ];
  }

  private static void assertCaptureObservationsUnchanged(
    List<Observation__c> before
  ) {
    Set<Id> observationIds = new Map<Id, Observation__c>(before).keySet();
    Map<Id, Observation__c> after = new Map<Id, Observation__c>(
      [
        SELECT Id, Value_Quantity__c, Value_Unit__c, Effective_DateTime__c
        FROM Observation__c
        WHERE Id IN :observationIds
      ]
    );
    for (Observation__c row : before) {
      System.assertEquals(
        row.Value_Quantity__c,
        after.get(row.Id).Value_Quantity__c
      );
      System.assertEquals(row.Value_Unit__c, after.get(row.Id).Value_Unit__c);
      System.assertEquals(
        row.Effective_DateTime__c,
        after.get(row.Id).Effective_DateTime__c,
        'A preferred presentation must not redate a recorded observation'
      );
    }
  }

  private static void assertMeasurementUnchanged(Observation__c before) {
    Observation__c after = [
      SELECT Value_Quantity__c, Effective_DateTime__c
      FROM Observation__c
      WHERE Id = :before.Id
    ];
    System.assertEquals(before.Value_Quantity__c, after.Value_Quantity__c);
    System.assertEquals(
      before.Effective_DateTime__c,
      after.Effective_DateTime__c,
      'Denied or unchanged saves must preserve the measurement time'
    );
  }

  private static void assertVitalSaveDenied(
    Id encounterId,
    VitalsCaptureController.VitalInput input
  ) {
    Boolean denied = false;
    try {
      VitalsCaptureController.saveVitals(
        encounterId,
        new List<VitalsCaptureController.VitalInput>{ input }
      );
    } catch (AuraHandledException error) {
      denied = error.getMessage().contains('permission');
    }
    System.assert(
      denied,
      'Vitals mutation must enforce the caller permissions'
    );
  }

  private static User accessUser(String alias) {
    Profile profile = [
      SELECT Id
      FROM Profile
      WHERE Name IN ('Minimum Access - Salesforce', 'Standard User')
      ORDER BY Name
      LIMIT 1
    ];
    return new User(
      Alias = alias,
      LastName = alias,
      Email = alias + '@logicemr.test',
      Username = alias +
        '.' +
        String.valueOf(Crypto.getRandomInteger()) +
        '@logicemr.test',
      ProfileId = profile.Id,
      TimeZoneSidKey = 'America/New_York',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
  }

  private static User vitalsAccessUser(
    String alias,
    Boolean creating,
    Boolean editing,
    Schema.SObjectField readOnlyField
  ) {
    User user = accessUser(alias);
    insert user;
    PermissionSet access = new PermissionSet(
      Name = 'Vitals_' + alias + '_Test',
      Label = 'Vitals ' + alias + ' Test'
    );
    insert access;
    String patientObject = qualifiedObjectName(Patient__c.SObjectType);
    String encounterObject = qualifiedObjectName(Encounter__c.SObjectType);
    String observationObject = qualifiedObjectName(Observation__c.SObjectType);
    insert new List<ObjectPermissions>{
      new ObjectPermissions(
        ParentId = access.Id,
        SobjectType = patientObject,
        PermissionsRead = true,
        PermissionsCreate = true,
        PermissionsEdit = true,
        PermissionsDelete = true,
        PermissionsViewAllRecords = true,
        PermissionsModifyAllRecords = true
      ),
      new ObjectPermissions(
        ParentId = access.Id,
        SobjectType = encounterObject,
        PermissionsRead = true
      ),
      new ObjectPermissions(
        ParentId = access.Id,
        SobjectType = observationObject,
        PermissionsRead = true,
        PermissionsCreate = creating,
        PermissionsEdit = editing
      )
    };
    Map<String, List<Schema.SObjectField>> fieldsByObject = new Map<String, List<Schema.SObjectField>>{
      encounterObject => new List<Schema.SObjectField>{
        Encounter__c.Patient__c
      },
      observationObject => new List<Schema.SObjectField>{
        Observation__c.Patient__c,
        Observation__c.Encounter__c,
        Observation__c.Category__c,
        Observation__c.Status__c,
        Observation__c.Observation_Code_System__c,
        Observation__c.Observation_Code__c,
        Observation__c.Observation_Display__c,
        Observation__c.Value_Quantity__c,
        Observation__c.Value_Unit__c,
        Observation__c.Effective_DateTime__c
      }
    };
    List<FieldPermissions> fieldAccess = new List<FieldPermissions>();
    for (String objectApiName : fieldsByObject.keySet()) {
      for (Schema.SObjectField field : fieldsByObject.get(objectApiName)) {
        Schema.DescribeFieldResult description = field.getDescribe();
        if (description.isPermissionable()) {
          fieldAccess.add(
            new FieldPermissions(
              ParentId = access.Id,
              SobjectType = objectApiName,
              Field = objectApiName + '.' + description.getName(),
              PermissionsRead = true,
              PermissionsEdit = objectApiName == observationObject &&
                (creating || editing) &&
                field != readOnlyField
            )
          );
        }
      }
    }
    insert fieldAccess;
    insert new PermissionSetAssignment(
      AssigneeId = user.Id,
      PermissionSetId = access.Id
    );
    return user;
  }

  private static String qualifiedObjectName(Schema.SObjectType objectType) {
    String keyPrefix = objectType.getDescribe().getKeyPrefix();
    return [
      SELECT QualifiedApiName
      FROM EntityDefinition
      WHERE KeyPrefix = :keyPrefix
      LIMIT 1
    ]
    .QualifiedApiName;
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
