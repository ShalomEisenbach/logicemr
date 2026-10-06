@IsTest
private class MedicationPanelControllerTest {
  @IsTest
  static void prescriptionsCaptureDispensingDetailsAndDraftsRemainVisible() {
    Patient__c patient = insertPatient('MED-RX-DRAFT');
    Practitioner__c prescriber = new Practitioner__c(
      First_Name__c = 'Pat',
      Last_Name__c = 'Prescriber',
      Active__c = true
    );
    insert prescriber;
    MedicationPanelController.PrescriptionInput input = new MedicationPanelController.PrescriptionInput();
    input.patientId = patient.Id;
    input.codeSystem = 'RxNorm';
    input.display = 'Lisinopril 10 mg';
    input.status = 'Draft';
    input.intent = 'Order';
    input.dosageText = 'Take one tablet daily';
    input.dispenseQuantity = 30;
    input.refills = 2;
    input.pharmacy = 'Local pharmacy';
    input.requesterId = prescriber.Id;
    input.startDate = Date.today();
    input.endDate = Date.today().addDays(30);
    Test.startTest();
    MedicationRequest__c draft = MedicationPanelController.addPrescription(
      input
    );
    System.assertEquals(
      draft.Id,
      MedicationPanelController.getMedications(patient.Id).activeOrders[0].Id
    );
    System.assertEquals(
      0,
      ClinicalDocumentService.getPrescriptionPad(
          patient.Id,
          new List<Id>{ draft.Id }
        )
        .prescriptions.size()
    );
    MedicationPanelController.activatePrescription(draft.Id);
    Test.stopTest();
    MedicationRequest__c stored = [
      SELECT Status__c, Dispense_Quantity__c, Refills__c, Pharmacy__c
      FROM MedicationRequest__c
      WHERE Id = :draft.Id
    ];
    System.assertEquals('Active', stored.Status__c);
    System.assertEquals(30, stored.Dispense_Quantity__c);
    System.assertEquals(2, stored.Refills__c);
    System.assertEquals('Local pharmacy', stored.Pharmacy__c);
    ClinicalDocumentService.PrescriptionRow printed = ClinicalDocumentService.getPrescriptionPad(
        patient.Id,
        new List<Id>{ draft.Id }
      )
      .prescriptions[0];
    System.assertEquals(30, printed.dispenseQuantity);
    System.assertEquals('Local pharmacy', printed.pharmacy);
  }

  @IsTest
  static void activePrescriptionsRequireDispensingAndPrescriberDetails() {
    Patient__c patient = insertPatient('MED-RX-INCOMPLETE');
    MedicationPanelController.PrescriptionInput input = new MedicationPanelController.PrescriptionInput();
    input.patientId = patient.Id;
    input.codeSystem = 'RxNorm';
    input.display = 'Medication';
    input.status = 'Active';
    try {
      MedicationPanelController.addPrescription(input);
      System.assert(false, 'Incomplete active prescription must fail.');
    } catch (AuraHandledException expected) {
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM MedicationRequest__c
          WHERE Patient__c = :patient.Id
        ]
      );
    }
    MedicationRequest__c draft = new MedicationRequest__c(
      Patient__c = patient.Id,
      Medication_Display__c = 'Incomplete draft',
      Status__c = 'Draft',
      Intent__c = 'Order'
    );
    insert draft;
    draft.Status__c = 'Active';
    Database.SaveResult activation = Database.update(draft, false);
    System.assertEquals(
      false,
      activation.isSuccess(),
      'Standard record edits must enforce draft activation requirements too.'
    );
  }
  @IsTest
  static void getMedicationsReturnsActiveOrdersAndReportedStatements() {
    Patient__c patient = insertPatient('MRN-MED-1');
    Patient__c other = insertPatient('MRN-MED-2');

    MedicationRequest__c activeOrder = insertRequest(
      patient.Id,
      'Active',
      'RxNorm',
      '197361',
      'Lisinopril 10 MG Oral Tablet'
    );
    insertRequest(
      patient.Id,
      'Stopped',
      'RxNorm',
      '314076',
      'Lisinopril 20 MG Oral Tablet'
    );
    insertRequest(
      other.Id,
      'Active',
      'RxNorm',
      '617318',
      'Atorvastatin 40 MG Oral Tablet'
    );

    MedicationStatement__c reported = insertStatement(
      patient.Id,
      'Active',
      'Patient Reported',
      'RxNorm',
      '198440',
      'Acetaminophen 325 MG Oral Tablet'
    );
    insertStatement(
      patient.Id,
      'Stopped',
      'Patient Reported',
      'RxNorm',
      '310965',
      'Ibuprofen 200 MG Oral Tablet'
    );
    insertStatement(
      other.Id,
      'Active',
      'Patient Reported',
      'RxNorm',
      '308971',
      'Aspirin 81 MG Oral Tablet'
    );

    Test.startTest();
    MedicationPanelController.MedicationPanelView view = MedicationPanelController.getMedications(
      patient.Id
    );
    MedicationPanelController.MedicationPanelView blank = MedicationPanelController.getMedications(
      null
    );
    Test.stopTest();

    System.assertEquals(
      1,
      view.activeOrders.size(),
      'Only this patient\'s active orders'
    );
    System.assertEquals(
      activeOrder.Id,
      view.activeOrders[0].Id,
      'Active order Id should match'
    );
    System.assertEquals(
      '197361',
      view.activeOrders[0].Medication_Code__c,
      'Order coding code should be queried'
    );
    System.assertEquals(
      'RxNorm',
      view.activeOrders[0].Medication_Code_System__c,
      'Order coding system should be queried'
    );
    System.assertEquals(
      1,
      view.reportedMedications.size(),
      'Only this patient\'s reported meds'
    );
    System.assertEquals(
      reported.Id,
      view.reportedMedications[0].Id,
      'Reported statement Id should match'
    );
    System.assertEquals(
      'Patient Reported',
      view.reportedMedications[0].Source__c,
      'Statement source should be queried'
    );
    System.assertEquals(
      0,
      blank.activeOrders.size(),
      'Null patient should return no orders'
    );
    System.assertEquals(
      0,
      blank.reportedMedications.size(),
      'Null patient should return no reported meds'
    );
  }

  @IsTest
  static void addMedicationPersistsRxNormCodingAsActiveOrder() {
    Patient__c patient = insertPatient('MRN-MED-3');
    Code_Reference__c codeRef = insertCode(
      'RxNorm',
      '617318',
      'Atorvastatin 40 MG Oral Tablet'
    );

    Test.startTest();
    MedicationRequest__c created = MedicationPanelController.addMedication(
      patient.Id,
      codeRef.Code_System__c,
      codeRef.Code__c,
      codeRef.Display__c,
      codeRef.Id,
      'Take 1 tablet by mouth daily',
      10,
      'mg',
      'Once daily',
      'Oral',
      'Order',
      'Active',
      null
    );
    Test.stopTest();

    MedicationRequest__c stored = [
      SELECT
        Patient__c,
        Status__c,
        Intent__c,
        Medication_Ref__c,
        Medication_Code_System__c,
        Medication_Code__c,
        Medication_Display__c,
        Dosage_Text__c,
        Dose_Quantity__c,
        Dose_Unit__c,
        Frequency__c,
        Route__c,
        Authored_On__c
      FROM MedicationRequest__c
      WHERE Id = :created.Id
    ];
    System.assertEquals(
      patient.Id,
      stored.Patient__c,
      'Order should belong to the patient'
    );
    System.assertEquals(
      'Active',
      stored.Status__c,
      'New order should be Active'
    );
    System.assertEquals(
      'Order',
      stored.Intent__c,
      'New row should be an order'
    );
    System.assertEquals(
      codeRef.Id,
      stored.Medication_Ref__c,
      'Lookup should point at the Code Reference'
    );
    System.assertEquals(
      codeRef.Code_System__c,
      stored.Medication_Code_System__c,
      'Code system should persist'
    );
    System.assertEquals(
      codeRef.Code__c,
      stored.Medication_Code__c,
      'Snapshot code should match the Code Reference'
    );
    System.assertEquals(
      codeRef.Display__c,
      stored.Medication_Display__c,
      'Snapshot display should match the Code Reference'
    );
    System.assertEquals(
      'Take 1 tablet by mouth daily',
      stored.Dosage_Text__c,
      'Dosage text should persist'
    );
    System.assertEquals(
      10,
      stored.Dose_Quantity__c,
      'Dose quantity should persist'
    );
    System.assertEquals('mg', stored.Dose_Unit__c, 'Dose unit should persist');
    System.assertEquals(
      'Once daily',
      stored.Frequency__c,
      'Frequency should persist'
    );
    System.assertEquals('Oral', stored.Route__c, 'Route should persist');
    System.assertNotEquals(
      null,
      stored.Authored_On__c,
      'Add should stamp authored on'
    );
  }

  @IsTest
  static void addMedicationRejectsBlankPatientDisplayOrWrongSystem() {
    Patient__c patient = insertPatient('MRN-MED-4');
    Boolean missingPatient = false;
    Boolean missingDisplay = false;
    Boolean wrongSystem = false;

    Test.startTest();
    try {
      MedicationPanelController.addMedication(
        null,
        'RxNorm',
        '197361',
        'Lisinopril',
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null
      );
    } catch (AuraHandledException e) {
      missingPatient = true;
    }
    try {
      MedicationPanelController.addMedication(
        patient.Id,
        'RxNorm',
        '197361',
        '',
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null
      );
    } catch (AuraHandledException e) {
      missingDisplay = true;
    }
    try {
      MedicationPanelController.addMedication(
        patient.Id,
        'SNOMED',
        '387517004',
        'Paracetamol',
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null
      );
    } catch (AuraHandledException e) {
      wrongSystem = true;
    }
    Test.stopTest();

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
      wrongSystem,
      'Non-RxNorm system should be rejected'
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM MedicationRequest__c WHERE Patient__c = :patient.Id],
      'Rejected adds must not insert rows'
    );
  }

  @IsTest
  static void renewAndDiscontinueUpdateOrderStatusInBulk() {
    Patient__c patient = insertPatient('MRN-MED-5');
    MedicationRequest__c first = insertRequest(
      patient.Id,
      'Active',
      'RxNorm',
      '197361',
      'Lisinopril 10 MG Oral Tablet'
    );
    MedicationRequest__c second = insertRequest(
      patient.Id,
      'On Hold',
      'RxNorm',
      '617318',
      'Atorvastatin 40 MG Oral Tablet'
    );
    Practitioner__c prescriber = new Practitioner__c(
      Last_Name__c = 'Renewing prescriber',
      Active__c = true
    );
    insert prescriber;
    update new MedicationRequest__c(
      Id = second.Id,
      Requester__c = prescriber.Id,
      Dosage_Text__c = 'Take one tablet daily',
      Dispense_Quantity__c = 30
    );
    MedicationRequest__c alreadyStopped = insertRequest(
      patient.Id,
      'Stopped',
      'RxNorm',
      '310965',
      'Ibuprofen 200 MG Oral Tablet'
    );

    Test.startTest();
    MedicationPanelController.renewOrders(null);
    MedicationPanelController.renewOrders(new List<Id>());
    MedicationPanelController.renewOrders(new List<Id>{ second.Id });
    MedicationPanelController.discontinueOrders(null);
    MedicationPanelController.discontinueOrders(new List<Id>());
    MedicationPanelController.discontinueOrders(
      new List<Id>{ first.Id, alreadyStopped.Id }
    );
    Test.stopTest();

    Map<Id, MedicationRequest__c> stored = new Map<Id, MedicationRequest__c>(
      [
        SELECT Status__c, Authored_On__c
        FROM MedicationRequest__c
        WHERE Id IN :new List<Id>{ first.Id, second.Id, alreadyStopped.Id }
      ]
    );
    System.assertEquals(
      'Stopped',
      stored.get(first.Id).Status__c,
      'Active order should discontinue to Stopped'
    );
    System.assertEquals(
      'Active',
      stored.get(second.Id).Status__c,
      'On Hold order should renew to Active'
    );
    System.assertNotEquals(
      null,
      stored.get(second.Id).Authored_On__c,
      'Renew should stamp authored on'
    );
    System.assertEquals(
      'Stopped',
      stored.get(alreadyStopped.Id).Status__c,
      'Already stopped order should stay Stopped'
    );
    System.assertEquals(
      1,
      MedicationPanelController.getMedications(patient.Id).activeOrders.size(),
      'Only the renewed order should remain active'
    );
    System.assertEquals(
      second.Id,
      MedicationPanelController.getMedications(patient.Id).activeOrders[0].Id,
      'Renewed order should be the remaining active row'
    );
  }

  @IsTest
  static void deleteOrdersAndReportedMedicationsRemoveRows() {
    Patient__c patient = insertPatient('MRN-MED-6');
    MedicationRequest__c order = insertRequest(
      patient.Id,
      'Active',
      'RxNorm',
      '197361',
      'Lisinopril 10 MG Oral Tablet'
    );
    MedicationStatement__c reported = insertStatement(
      patient.Id,
      'Active',
      'Patient Reported',
      'RxNorm',
      '310965',
      'Ibuprofen 200 MG Oral Tablet'
    );

    Test.startTest();
    MedicationPanelController.deleteOrders(null);
    MedicationPanelController.deleteOrders(new List<Id>());
    MedicationPanelController.deleteReportedMedications(null);
    MedicationPanelController.deleteReportedMedications(new List<Id>());
    MedicationPanelController.deleteOrders(new List<Id>{ order.Id });
    MedicationPanelController.deleteReportedMedications(
      new List<Id>{ reported.Id }
    );
    Test.stopTest();

    System.assertEquals(
      0,
      [SELECT COUNT() FROM MedicationRequest__c WHERE Id = :order.Id],
      'Order should be deleted'
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM MedicationStatement__c WHERE Id = :reported.Id],
      'Reported medication should be deleted'
    );
  }

  @IsTest
  static void activePrescriptionDetailsCannotBeClearedThroughStandardEdits() {
    Patient__c patient = insertPatient('MED-RX-GUARD');
    Practitioner__c prescriber = new Practitioner__c(
      Last_Name__c = 'Prescriber',
      Active__c = true
    );
    insert prescriber;
    MedicationRequest__c request = new MedicationRequest__c(
      Patient__c = patient.Id,
      Status__c = 'Active',
      Intent__c = 'Order',
      Medication_Display__c = 'Medication',
      Requester__c = prescriber.Id,
      Dosage_Text__c = 'Take one daily',
      Dispense_Quantity__c = 30
    );
    insert request;
    System.assertEquals(
      false,
      Database.update(
          new MedicationRequest__c(Id = request.Id, Requester__c = null),
          false
        )
        .isSuccess(),
      'An active prescription cannot lose its prescriber'
    );
    System.assertEquals(
      false,
      Database.update(
          new MedicationRequest__c(Id = request.Id, Dosage_Text__c = null),
          false
        )
        .isSuccess(),
      'An active prescription cannot lose its SIG'
    );
    System.assertEquals(
      false,
      Database.update(
          new MedicationRequest__c(
            Id = request.Id,
            Dispense_Quantity__c = null
          ),
          false
        )
        .isSuccess(),
      'An active prescription cannot lose its dispensing quantity'
    );
    MedicationRequest__c stored = [
      SELECT Requester__c, Dosage_Text__c, Dispense_Quantity__c
      FROM MedicationRequest__c
      WHERE Id = :request.Id
    ];
    System.assertEquals(prescriber.Id, stored.Requester__c);
    System.assertEquals('Take one daily', stored.Dosage_Text__c);
    System.assertEquals(30, stored.Dispense_Quantity__c);
  }

  @IsTest
  static void plansAndProposalsCannotBeActivatedOrPrintedAsPrescriptions() {
    Patient__c patient = insertPatient('MED-RX-INTENT');
    Practitioner__c prescriber = new Practitioner__c(
      Last_Name__c = 'Prescriber',
      Active__c = true
    );
    insert prescriber;
    List<MedicationRequest__c> drafts = new List<MedicationRequest__c>();
    List<MedicationRequest__c> activePlans = new List<MedicationRequest__c>();
    for (String intent : new List<String>{ 'Plan', 'Proposal' }) {
      drafts.add(
        new MedicationRequest__c(
          Patient__c = patient.Id,
          Status__c = 'Draft',
          Intent__c = intent,
          Medication_Display__c = intent + ' draft',
          Requester__c = prescriber.Id,
          Dosage_Text__c = 'Take one daily',
          Dispense_Quantity__c = 30
        )
      );
      activePlans.add(
        new MedicationRequest__c(
          Patient__c = patient.Id,
          Status__c = 'Active',
          Intent__c = intent,
          Medication_Display__c = intent + ' plan',
          Requester__c = prescriber.Id,
          Dosage_Text__c = 'Take one daily',
          Dispense_Quantity__c = 30
        )
      );
    }
    insert drafts;
    insert activePlans;
    for (MedicationRequest__c draft : drafts) {
      Boolean rejected = false;
      try {
        MedicationPanelController.activatePrescription(draft.Id);
      } catch (AuraHandledException e) {
        rejected = true;
      }
      System.assertEquals(
        true,
        rejected,
        'Only Order intent can be activated as a prescription'
      );
      System.assertEquals(
        'Draft',
        [SELECT Status__c FROM MedicationRequest__c WHERE Id = :draft.Id]
        .Status__c
      );
    }
    List<Id> requestIds = new List<Id>();
    for (MedicationRequest__c row : activePlans)
      requestIds.add(row.Id);
    System.assertEquals(
      0,
      ClinicalDocumentService.getPrescriptionPad(patient.Id, requestIds)
        .prescriptions.size(),
      'Active planning records must not appear on a prescription pad'
    );
  }

  @IsTest
  static void readOnlyUserCannotCreateOrActivatePrescriptions() {
    User reader = prescriptionAccessUser('rxread', false);
    Patient__c patient;
    MedicationRequest__c draft;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      patient = insertPatient('MED-RX-READ-ONLY');
      draft = insertRequest(
        patient.Id,
        'Draft',
        'RxNorm',
        '197361',
        'Lisinopril draft'
      );
    }
    MedicationPanelController.PrescriptionInput input = draftInput(patient.Id);
    System.runAs(reader) {
      System.assertEquals(
        true,
        MedicationRequest__c.SObjectType.getDescribe().isAccessible()
      );
      System.assertEquals(
        false,
        MedicationRequest__c.SObjectType.getDescribe().isCreateable()
      );
      System.assertEquals(
        false,
        MedicationRequest__c.SObjectType.getDescribe().isUpdateable()
      );
      assertPrescriptionAccessDenied(input, draft.Id);
    }
    System.assertEquals(
      1,
      [SELECT COUNT() FROM MedicationRequest__c WHERE Patient__c = :patient.Id],
      'Denied save must not insert another prescription'
    );
    System.assertEquals(
      'Draft',
      [SELECT Status__c FROM MedicationRequest__c WHERE Id = :draft.Id]
      .Status__c,
      'Denied activation must not change the draft'
    );
  }

  @IsTest
  static void objectWriteAccessDoesNotBypassPrescriptionFieldPermissions() {
    User writer = prescriptionAccessUser('rxfields', true);
    Patient__c patient;
    MedicationRequest__c draft;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      patient = insertPatient('MED-RX-FLS');
      draft = insertRequest(
        patient.Id,
        'Draft',
        'RxNorm',
        '197361',
        'Lisinopril draft'
      );
    }
    System.runAs(writer) {
      System.assertEquals(
        true,
        MedicationRequest__c.SObjectType.getDescribe().isCreateable()
      );
      System.assertEquals(
        true,
        MedicationRequest__c.SObjectType.getDescribe().isUpdateable()
      );
      System.assertEquals(
        false,
        MedicationRequest__c.Status__c.getDescribe().isUpdateable(),
        'Fixture deliberately grants object permissions without clinical field permissions'
      );
      assertPrescriptionAccessDenied(draftInput(patient.Id), draft.Id);
    }
    System.assertEquals(
      1,
      [SELECT COUNT() FROM MedicationRequest__c WHERE Patient__c = :patient.Id]
    );
    System.assertEquals(
      'Draft',
      [SELECT Status__c FROM MedicationRequest__c WHERE Id = :draft.Id]
      .Status__c
    );
  }

  private static void assertPrescriptionAccessDenied(
    MedicationPanelController.PrescriptionInput input,
    Id draftId
  ) {
    Boolean saveDenied = false;
    Boolean activationDenied = false;
    try {
      MedicationPanelController.addPrescription(input);
    } catch (AuraHandledException e) {
      saveDenied = true;
    }
    try {
      MedicationPanelController.activatePrescription(draftId);
    } catch (AuraHandledException e) {
      activationDenied = true;
    }
    System.assertEquals(
      true,
      saveDenied,
      'Creation must enforce object and populated-field permissions'
    );
    System.assertEquals(
      true,
      activationDenied,
      'Activation must enforce object and status/authored field permissions before reading a draft'
    );
  }

  private static MedicationPanelController.PrescriptionInput draftInput(
    Id patientId
  ) {
    MedicationPanelController.PrescriptionInput input = new MedicationPanelController.PrescriptionInput();
    input.patientId = patientId;
    input.codeSystem = 'RxNorm';
    input.code = '197361';
    input.display = 'Lisinopril draft';
    input.status = 'Draft';
    input.intent = 'Order';
    input.dispenseQuantity = 30;
    input.pharmacy = 'Local pharmacy';
    return input;
  }

  private static User prescriptionAccessUser(String alias, Boolean writing) {
    Profile profile = [
      SELECT Id
      FROM Profile
      WHERE Name IN ('Minimum Access - Salesforce', 'Standard User')
      ORDER BY Name
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
    PermissionSet access = new PermissionSet(
      Name = 'Prescription_' + alias + '_Test',
      Label = 'Prescription ' + alias + ' Test'
    );
    insert access;
    // MedicationRequest inherits record sharing from its Patient parent.
    insert new ObjectPermissions(
      ParentId = access.Id,
      SobjectType = Patient__c.SObjectType.getDescribe().getName(),
      PermissionsRead = true
    );
    insert new ObjectPermissions(
      ParentId = access.Id,
      SobjectType = MedicationRequest__c.SObjectType.getDescribe().getName(),
      PermissionsRead = true,
      PermissionsCreate = writing,
      PermissionsEdit = writing
    );
    insert new PermissionSetAssignment(
      AssigneeId = user.Id,
      PermissionSetId = access.Id
    );
    return user;
  }

  private static Patient__c insertPatient(String mrn) {
    Patient__c patient = new Patient__c(
      MRN__c = mrn,
      Last_Name__c = 'Medications'
    );
    insert patient;
    return patient;
  }

  private static MedicationRequest__c insertRequest(
    Id patientId,
    String status,
    String codeSystem,
    String code,
    String display
  ) {
    MedicationRequest__c request = new MedicationRequest__c(
      Patient__c = patientId,
      Status__c = status,
      Intent__c = 'Order',
      Medication_Code_System__c = codeSystem,
      Medication_Code__c = code,
      Medication_Display__c = display
    );
    insert request;
    return request;
  }

  private static MedicationStatement__c insertStatement(
    Id patientId,
    String status,
    String source,
    String codeSystem,
    String code,
    String display
  ) {
    MedicationStatement__c statement = new MedicationStatement__c(
      Patient__c = patientId,
      Status__c = status,
      Source__c = source,
      Medication_Code_System__c = codeSystem,
      Medication_Code__c = code,
      Medication_Display__c = display
    );
    insert statement;
    return statement;
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
