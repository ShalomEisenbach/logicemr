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
    List<Procedure__c> rows = ProcedurePanelController.getProcedures(
      patient.Id
    );
    List<Procedure__c> blank = ProcedurePanelController.getProcedures(null);
    Test.stopTest();

    System.assertEquals(
      2,
      rows.size(),
      'Should return both procedures for this patient'
    );
    System.assertEquals(
      newest.Id,
      rows[0].Id,
      'Newest performed datetime should be first'
    );
    System.assertEquals(
      '93000',
      rows[0].Procedure_Code__c,
      'Code should be queried'
    );
    System.assertEquals(
      'Diagnostic',
      rows[0].Category__c,
      'Category should be queried'
    );
    System.assertEquals(
      0,
      blank.size(),
      'Null patient should return no procedures'
    );
  }

  @IsTest
  static void addProcedurePersistsCodingCategoryStatusAndNotes() {
    Patient__c patient = insertPatient('MRN-PROC-3');
    Code_Reference__c codeRef = insertCode(
      'CPT',
      '93000',
      'Electrocardiogram, complete'
    );
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
    System.assertEquals(
      patient.Id,
      stored.Patient__c,
      'Procedure should belong to the patient'
    );
    System.assertEquals(
      codeRef.Id,
      stored.Procedure_Ref__c,
      'Lookup should point at the Code Reference'
    );
    System.assertEquals(
      codeRef.Code_System__c,
      stored.Procedure_Code_System__c,
      'Code system should persist'
    );
    System.assertEquals(
      codeRef.Code__c,
      stored.Procedure_Code__c,
      'Snapshot code should match the Code Reference'
    );
    System.assertEquals(
      codeRef.Display__c,
      stored.Procedure_Display__c,
      'Snapshot display should match the Code Reference'
    );
    System.assertEquals(
      'Diagnostic',
      stored.Category__c,
      'Category should persist'
    );
    System.assertEquals(
      'In Progress',
      stored.Status__c,
      'Status should persist'
    );
    System.assertEquals(
      performed,
      stored.Performed_DateTime__c,
      'Performed datetime should persist'
    );
    System.assertEquals(
      'No acute ST changes.',
      stored.Notes__c,
      'Notes should persist'
    );
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

    Procedure__c stored = [
      SELECT Status__c
      FROM Procedure__c
      WHERE Id = :created.Id
    ];
    System.assertEquals(
      'Completed',
      stored.Status__c,
      'Blank status should default to Completed'
    );
    System.assertEquals(
      true,
      missingPatient,
      'Blank patient Id should be rejected'
    );
    System.assertEquals(
      true,
      missingDisplay,
      'Blank display should be rejected'
    );
    System.assertEquals(
      true,
      badSystem,
      'Non CPT/SNOMED code system should be rejected'
    );
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
    ProcedurePanelController.completeProcedures(
      new List<Id>{ first.Id, second.Id, alreadyDone.Id }
    );
    Test.stopTest();

    Map<Id, Procedure__c> stored = new Map<Id, Procedure__c>(
      [
        SELECT Status__c
        FROM Procedure__c
        WHERE Id IN :new List<Id>{ first.Id, second.Id, alreadyDone.Id }
      ]
    );
    System.assertEquals(
      'Completed',
      stored.get(first.Id).Status__c,
      'First row should complete'
    );
    System.assertEquals(
      'Completed',
      stored.get(second.Id).Status__c,
      'Second row should complete'
    );
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
    ProcedurePanelController.deleteProcedures(
      new List<Id>{ first.Id, second.Id }
    );
    Test.stopTest();

    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Procedure__c
        WHERE Id IN :new List<Id>{ first.Id, second.Id }
      ],
      'Both procedures should be deleted'
    );
  }

  @IsTest
  static void linkedCreationRetainsEncounterAndLegacyCreationRemainsUnlinked() {
    Patient__c patient = insertPatient('MRN-PROC-LINK');
    Encounter__c encounter = insertEncounter(patient.Id);
    Code_Reference__c codeRef = insertCode('CPT', '99213', 'Office visit');
    Datetime performed = Datetime.newInstance(2026, 10, 6, 9, 15, 0);

    Test.startTest();
    Procedure__c linked = ProcedurePanelController.addLinkedProcedure(
      patient.Id,
      encounter.Id,
      codeRef.Code_System__c,
      codeRef.Code__c,
      codeRef.Display__c,
      codeRef.Id,
      'Diagnostic',
      'In Progress',
      performed,
      'Encounter-specific procedure'
    );
    Procedure__c legacy = ProcedurePanelController.addProcedure(
      patient.Id,
      'CPT',
      '93000',
      'Electrocardiogram, complete',
      null,
      'Diagnostic',
      'Completed',
      performed,
      'Patient-level historical procedure'
    );
    Test.stopTest();

    Map<Id, Procedure__c> stored = new Map<Id, Procedure__c>(
      [
        SELECT
          Patient__c,
          Encounter__c,
          Procedure_Ref__c,
          Procedure_Code__c,
          Performed_DateTime__c,
          Notes__c
        FROM Procedure__c
        WHERE Id IN :new List<Id>{ linked.Id, legacy.Id }
      ]
    );
    System.assertEquals(encounter.Id, linked.Encounter__c);
    System.assertEquals(patient.Id, stored.get(linked.Id).Patient__c);
    System.assertEquals(encounter.Id, stored.get(linked.Id).Encounter__c);
    System.assertEquals(codeRef.Id, stored.get(linked.Id).Procedure_Ref__c);
    System.assertEquals('99213', stored.get(linked.Id).Procedure_Code__c);
    System.assertEquals(performed, stored.get(linked.Id).Performed_DateTime__c);
    System.assertEquals(
      'Encounter-specific procedure',
      stored.get(linked.Id).Notes__c
    );
    System.assertEquals(
      null,
      stored.get(legacy.Id).Encounter__c,
      'The original nine-argument API remains a patient-level procedure'
    );
    System.assertEquals(patient.Id, stored.get(legacy.Id).Patient__c);
  }

  @IsTest
  static void linkedCreationRejectsAnotherPatientsEncounterBeforeInsert() {
    Patient__c patient = insertPatient('MRN-PROC-LINK-MAIN');
    Patient__c other = insertPatient('MRN-PROC-LINK-OTHER');
    Encounter__c otherEncounter = insertEncounter(other.Id);
    Boolean denied = false;

    Test.startTest();
    try {
      ProcedurePanelController.addLinkedProcedure(
        patient.Id,
        otherEncounter.Id,
        'CPT',
        '99213',
        'Office visit',
        null,
        'Diagnostic',
        'Completed',
        Datetime.now(),
        'Mismatched patient'
      );
    } catch (AuraHandledException error) {
      denied = true;
    }
    Test.stopTest();

    System.assert(denied, 'The encounter must belong to the selected patient');
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Procedure__c],
      'A rejected link cannot leave a patient-level or encounter procedure behind'
    );
  }

  @IsTest
  static void clinicianRoleCanCreateAndCompleteButCannotDeleteProcedures() {
    User clinician;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      clinician = insertRoleUser('proccln', 'LogicEMR_Clinician');
    }
    Patient__c patient = new Patient__c(
      MRN__c = 'MRN-PROC-CLINICIAN',
      Last_Name__c = 'Procedures',
      OwnerId = clinician.Id
    );
    insert patient;
    Encounter__c encounter = insertEncounter(patient.Id);
    Code_Reference__c codeRef = insertCode('CPT', '99213', 'Office visit');

    Test.startTest();
    System.runAs(clinician) {
      System.assert(Procedure__c.SObjectType.getDescribe().isCreateable());
      System.assert(Procedure__c.SObjectType.getDescribe().isUpdateable());
      System.assertEquals(
        false,
        Procedure__c.SObjectType.getDescribe().isDeletable(),
        'The real Clinician permission set retains clinical records'
      );
      Procedure__c linked = ProcedurePanelController.addLinkedProcedure(
        patient.Id,
        encounter.Id,
        codeRef.Code_System__c,
        codeRef.Code__c,
        codeRef.Display__c,
        codeRef.Id,
        'Diagnostic',
        'In Progress',
        Datetime.now(),
        'Clinician encounter procedure'
      );
      Procedure__c legacy = ProcedurePanelController.addProcedure(
        patient.Id,
        'CPT',
        '93000',
        'Electrocardiogram, complete',
        null,
        'Diagnostic',
        'Preparation',
        Datetime.now(),
        null
      );
      ProcedurePanelController.completeProcedures(
        new List<Id>{ linked.Id, legacy.Id }
      );
      for (Procedure__c stored : [
        SELECT Status__c
        FROM Procedure__c
        WHERE Id IN :new List<Id>{ linked.Id, legacy.Id }
      ]) {
        System.assertEquals('Completed', stored.Status__c);
      }
      System.assertEquals(
        encounter.Id,
        [SELECT Encounter__c FROM Procedure__c WHERE Id = :linked.Id]
        .Encounter__c
      );
      Boolean deleteDenied = false;
      try {
        ProcedurePanelController.deleteProcedures(
          new List<Id>{ linked.Id, legacy.Id }
        );
      } catch (AuraHandledException error) {
        deleteDenied = true;
      }
      System.assert(
        deleteDenied,
        'Clinical completion does not grant deletion permission'
      );
      System.assertEquals(
        2,
        [
          SELECT COUNT()
          FROM Procedure__c
          WHERE Patient__c = :patient.Id
        ]
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void billingRoleCannotCreateCompleteOrDeleteProcedures() {
    User billing;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      billing = insertRoleUser('procbill', 'LogicEMR_Billing');
    }
    Patient__c patient = new Patient__c(
      MRN__c = 'MRN-PROC-BILLING',
      Last_Name__c = 'Procedures',
      OwnerId = billing.Id
    );
    insert patient;
    Encounter__c encounter = insertEncounter(patient.Id);
    Procedure__c existing = insertProcedure(
      patient.Id,
      'In Progress',
      'Diagnostic',
      'CPT',
      '99213',
      'Office visit',
      Datetime.now()
    );

    Test.startTest();
    System.runAs(billing) {
      System.assert(
        FeatureManagement.checkPermission('LogicEMR_Manage_Claims'),
        'Use the actual Billing role without clinical grants'
      );
      System.assertEquals(
        false,
        Procedure__c.SObjectType.getDescribe().isCreateable()
      );
      System.assertEquals(
        false,
        Procedure__c.SObjectType.getDescribe().isUpdateable()
      );
      System.assertEquals(
        false,
        Procedure__c.SObjectType.getDescribe().isDeletable()
      );
      for (Integer operation = 0; operation < 4; operation++) {
        Boolean denied = false;
        try {
          if (operation == 0) {
            ProcedurePanelController.addProcedure(
              patient.Id,
              'CPT',
              '93000',
              'ECG',
              null,
              'Diagnostic',
              'Completed',
              Datetime.now(),
              null
            );
          } else if (operation == 1) {
            ProcedurePanelController.addLinkedProcedure(
              patient.Id,
              encounter.Id,
              'CPT',
              '93000',
              'ECG',
              null,
              'Diagnostic',
              'Completed',
              Datetime.now(),
              null
            );
          } else if (operation == 2) {
            ProcedurePanelController.completeProcedures(
              new List<Id>{ existing.Id }
            );
          } else {
            ProcedurePanelController.deleteProcedures(
              new List<Id>{ existing.Id }
            );
          }
        } catch (AuraHandledException error) {
          denied = true;
        }
        System.assert(
          denied,
          'Billing procedure mutation ' + operation + ' must be denied'
        );
      }
    }
    Test.stopTest();

    System.assertEquals(
      1,
      [SELECT COUNT() FROM Procedure__c WHERE Patient__c = :patient.Id]
    );
    System.assertEquals(
      'In Progress',
      [SELECT Status__c FROM Procedure__c WHERE Id = :existing.Id].Status__c,
      'A denied completion leaves the original procedure unchanged'
    );
  }

  private static User insertRoleUser(String alias, String permissionSetName) {
    Profile profile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Minimum Access - Salesforce'
      LIMIT 1
    ];
    User user = new User(
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
    insert user;
    PermissionSet permissions = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = :permissionSetName
      LIMIT 1
    ];
    insert new PermissionSetAssignment(
      AssigneeId = user.Id,
      PermissionSetId = permissions.Id
    );
    return user;
  }

  private static Encounter__c insertEncounter(Id patientId) {
    Encounter__c encounter = new Encounter__c(
      Patient__c = patientId,
      Class__c = 'Outpatient',
      Status__c = 'In Progress',
      Start__c = Datetime.now().addHours(-1)
    );
    insert encounter;
    return encounter;
  }

  private static Patient__c insertPatient(String mrn) {
    Patient__c patient = new Patient__c(
      MRN__c = mrn,
      Last_Name__c = 'Procedures'
    );
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

  private static Code_Reference__c insertCode(
    String codeSystem,
    String code,
    String display
  ) {
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
