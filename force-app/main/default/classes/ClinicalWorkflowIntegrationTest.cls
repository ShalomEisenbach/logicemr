@IsTest
private class ClinicalWorkflowIntegrationTest {
  private static final String SCHEDULER_ALIAS = 'wfsched';
  private static final String CLINICIAN_ALIAS = 'wfclin';
  private static final String BILLING_ALIAS = 'wfbill';

  @TestSetup
  static void assignActualStaffPermissions() {
    List<Profile> profiles = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Minimum Access - Salesforce'
      LIMIT 1
    ];
    System.assertEquals(
      1,
      profiles.size(),
      'This regression requires the Minimum Access - Salesforce profile; a broader profile would conceal staff permission gaps.'
    );
    List<User> staff = new List<User>{
      staffUser(SCHEDULER_ALIAS, profiles[0].Id),
      staffUser(CLINICIAN_ALIAS, profiles[0].Id),
      staffUser(BILLING_ALIAS, profiles[0].Id)
    };
    insert staff;
    Map<String, Id> permissionIds = new Map<String, Id>();
    for (PermissionSet permissions : [
      SELECT Id, Name
      FROM PermissionSet
      WHERE
        Name IN ('LogicEMR_Scheduler', 'LogicEMR_Clinician', 'LogicEMR_Billing')
    ]) {
      permissionIds.put(permissions.Name, permissions.Id);
    }
    System.assertEquals(
      3,
      permissionIds.size(),
      'All three deployed staff permission sets must exist.'
    );
    insert new List<PermissionSetAssignment>{
      new PermissionSetAssignment(
        AssigneeId = staff[0].Id,
        PermissionSetId = permissionIds.get('LogicEMR_Scheduler')
      ),
      new PermissionSetAssignment(
        AssigneeId = staff[1].Id,
        PermissionSetId = permissionIds.get('LogicEMR_Clinician')
      ),
      new PermissionSetAssignment(
        AssigneeId = staff[2].Id,
        PermissionSetId = permissionIds.get('LogicEMR_Billing')
      )
    };
  }

  @IsTest
  static void schedulerClinicianAndBillingCompleteVisitWithoutExternalServices() {
    User scheduler = staff(SCHEDULER_ALIAS);
    User clinician = staff(CLINICIAN_ALIAS);
    User billing = staff(BILLING_ALIAS);
    Fixture fixture = createLocalFixture(scheduler, clinician, billing);
    Test.setMock(HttpCalloutMock.class, new RejectExternalCallouts());
    Id appointmentId;
    Id encounterId;
    Id noteId;

    Test.startTest();
    System.runAs(scheduler) {
      System.assertEquals(
        false,
        FeatureManagement.checkPermission('LogicEMR_Manage_Claims')
      );
      AppointmentBookingController.BookingResult booked = AppointmentBookingController.bookAppointment(
        fixture.patientId,
        fixture.slotId,
        'Checkup',
        'Disposable clinical workflow regression'
      );
      appointmentId = booked.appointmentId;
      System.assertEquals(
        'Booked',
        [SELECT Status__c FROM Appointment__c WHERE Id = :appointmentId]
        .Status__c
      );
      AppointmentCalendarController.ActionResult arrived = AppointmentCalendarController.arriveAppointment(
        appointmentId
      );
      encounterId = arrived.encounterId;
      System.assertNotEquals(null, encounterId);
      System.assertEquals(
        encounterId,
        AppointmentCalendarController.arriveAppointment(appointmentId)
          .encounterId,
        'A repeated arrival must return the same encounter.'
      );
      System.assertEquals(
        1,
        [SELECT COUNT() FROM Encounter__c WHERE Patient__c = :fixture.patientId]
      );
    }

    System.runAs(clinician) {
      System.assertEquals(
        false,
        FeatureManagement.checkPermission('LogicEMR_Manage_Claims')
      );
      EncounterWorkspaceController.transitionStatus(encounterId, 'In Progress');
      System.assertEquals(
        'Unknown',
        AllergyPanelController.getReviewState(fixture.patientId).status
      );
      AllergyPanelController.reviewAllergies(fixture.patientId, true);
      EncounterWorkspaceController.addDiagnosis(
        encounterId,
        'ICD-10',
        'J06.9',
        'Acute upper respiratory infection',
        null,
        'Principal',
        1
      );
      VitalsCaptureController.saveVitals(
        encounterId,
        new List<VitalsCaptureController.VitalInput>{
          vital('temp', 36.8, 'Cel'),
          vital('height', 175, 'cm'),
          vital('weight', 70, 'kg')
        }
      );
      NoteEditorController.NoteEditorState draft = NoteEditorController.saveDraft(
        encounterId,
        null,
        'Progress Note',
        'Test visit assessment and plan.'
      );
      noteId = NoteEditorController.signNote(
          encounterId,
          draft.noteId,
          'Progress Note',
          'Test visit assessment and plan, confirmed.'
        )
        .noteId;
      Database.insert(
        new Procedure__c(
          Patient__c = fixture.patientId,
          Encounter__c = encounterId,
          Performer__c = fixture.practitionerId,
          Procedure_Code_System__c = 'CPT',
          Procedure_Code__c = '99213',
          Procedure_Display__c = 'Established patient office visit',
          Status__c = 'Completed',
          Performed_DateTime__c = Datetime.now()
        ),
        AccessLevel.USER_MODE
      );
      for (
        EncounterCompletionService.ChecklistItem item : EncounterCompletionService.getChecklist(
            encounterId
          )
          .items
      ) {
        System.assertEquals(true, item.complete, item.label);
      }
      Boolean claimsDenied = false;
      try {
        ClaimReadinessController.getWorkspace(encounterId);
      } catch (AuraHandledException expected) {
        claimsDenied = true;
      }
      System.assertEquals(
        true,
        claimsDenied,
        'A clinician without Manage Claims cannot use the billing workspace.'
      );
    }

    System.runAs(billing) {
      System.assertEquals(
        true,
        FeatureManagement.checkPermission('LogicEMR_Manage_Claims')
      );
      System.assertEquals(
        false,
        Encounter__c.SObjectType.getDescribe().isUpdateable()
      );
      assertBillingClinicalMutationsDenied(
        fixture.patientId,
        encounterId,
        noteId
      );
    }
    System.runAs(clinician) {
      EncounterWorkspaceController.transitionStatus(encounterId, 'Finished');
      Encounter__c pending = [
        SELECT End__c, Completion_Handoff_Status__c
        FROM Encounter__c
        WHERE Id = :encounterId
      ];
      System.assertNotEquals(null, pending.End__c);
      System.assertEquals('Pending', pending.Completion_Handoff_Status__c);
    }
    Test.stopTest();

    Encounter__c finished = [
      SELECT
        Status__c,
        Start__c,
        End__c,
        Completion_Handoff_Status__c,
        Completion_Handoff_Error__c
      FROM Encounter__c
      WHERE Id = :encounterId
    ];
    System.assertEquals('Finished', finished.Status__c);
    System.assert(finished.End__c >= finished.Start__c);
    System.assertEquals(
      'Completed',
      finished.Completion_Handoff_Status__c,
      finished.Completion_Handoff_Error__c == null
        ? 'Automatic billing handoff should complete.'
        : finished.Completion_Handoff_Error__c
    );
    Appointment__c fulfilled = [
      SELECT Status__c, Encounter__c
      FROM Appointment__c
      WHERE Id = :appointmentId
    ];
    System.assertEquals('Fulfilled', fulfilled.Status__c);
    System.assertEquals(encounterId, fulfilled.Encounter__c);
    ClinicalNote__c signed = [
      SELECT Status__c, Signed_By__c, Signed_Date__c, Author__c
      FROM ClinicalNote__c
      WHERE Id = :noteId
    ];
    System.assertEquals('Signed', signed.Status__c);
    System.assertEquals(clinician.Id, signed.Signed_By__c);
    System.assertNotEquals(null, signed.Signed_Date__c);
    System.assertEquals(fixture.practitionerId, signed.Author__c);
    Patient__c reviewed = [
      SELECT
        Allergy_Review_Status__c,
        Allergy_Reviewed_By__c,
        Email__c,
        Phone__c,
        SMS_Opt_In__c
      FROM Patient__c
      WHERE Id = :fixture.patientId
    ];
    System.assertEquals(
      'No known allergies',
      reviewed.Allergy_Review_Status__c
    );
    System.assertEquals(clinician.Id, reviewed.Allergy_Reviewed_By__c);
    System.assertEquals(null, reviewed.Email__c);
    System.assertEquals(null, reviewed.Phone__c);
    System.assertEquals(false, reviewed.SMS_Opt_In__c);
    Observation__c temperature = [
      SELECT Value_Quantity__c, Value_Unit__c
      FROM Observation__c
      WHERE Encounter__c = :encounterId AND Observation_Code__c = '8310-5'
    ];
    System.assertEquals(
      36.8,
      temperature.Value_Quantity__c,
      'Denied billing mutations must not change clinical measurements.'
    );
    System.assertEquals('Cel', temperature.Value_Unit__c);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM ClinicalNote__c WHERE Encounter__c = :encounterId]
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Superbill__c WHERE Encounter__c = :encounterId]
    );
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Appointment_Communication__c
        WHERE
          Appointment__c = :appointmentId
          AND Status__c IN ('Sent', 'Queued')
      ],
      'Blank recipient contacts must prevent external notifications.'
    );

    System.runAs(billing) {
      ClaimReadinessController.Workspace workspace = ClaimReadinessController.getWorkspace(
        encounterId
      );
      System.assertEquals('Needs Review', workspace.superbill.Status__c);
      System.assertEquals(
        0,
        workspace.issues.size(),
        String.join(workspace.issues, '; ')
      );
      System.assertEquals(1, workspace.diagnoses.size());
      System.assertEquals('J06.9', workspace.diagnoses[0].Diagnosis_Code__c);
      System.assertEquals(1, workspace.charges.size());
      System.assertEquals('99213', workspace.charges[0].Procedure_Code__c);
      System.assertEquals(
        fixture.rateId,
        workspace.charges[0].Fee_Schedule_Rate__c
      );
      System.assertEquals(175, workspace.totalCharges);
      ClaimReadinessController.Workspace ready = ClaimReadinessController.markReady(
        workspace.superbill.Id
      );
      System.assertEquals(true, ready.ready);
      System.assertEquals('Ready', ready.superbill.Status__c);
      System.assertNotEquals(null, ready.superbill.Ready_Date__c);
    }
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Claim_Submission__c],
      'This workflow ends at local readiness, before claim transmission.'
    );
  }

  private static void assertBillingClinicalMutationsDenied(
    Id patientId,
    Id encounterId,
    Id noteId
  ) {
    Integer denied = 0;
    try {
      NoteEditorController.saveDraft(
        encounterId,
        null,
        'Progress Note',
        'Unauthorized billing draft'
      );
    } catch (AuraHandledException expected) {
      denied++;
    }
    try {
      NoteEditorController.signNote(
        encounterId,
        null,
        'Progress Note',
        'Unauthorized billing signature'
      );
    } catch (AuraHandledException expected) {
      denied++;
    }
    try {
      NoteEditorController.createAddendum(
        noteId,
        'Unauthorized billing addendum',
        false
      );
    } catch (AuraHandledException expected) {
      denied++;
    }
    try {
      VitalsCaptureController.saveVitals(
        encounterId,
        new List<VitalsCaptureController.VitalInput>{ vital('temp', 38, 'Cel') }
      );
    } catch (AuraHandledException expected) {
      denied++;
    }
    try {
      AllergyPanelController.reviewAllergies(patientId, true);
    } catch (AuraHandledException expected) {
      denied++;
    }
    MedicationPanelController.PrescriptionInput prescription = new MedicationPanelController.PrescriptionInput();
    prescription.patientId = patientId;
    prescription.codeSystem = 'RxNorm';
    prescription.code = '197361';
    prescription.display = 'Disposable test prescription';
    prescription.status = 'Draft';
    prescription.intent = 'Order';
    try {
      MedicationPanelController.addPrescription(prescription);
    } catch (AuraHandledException expected) {
      denied++;
    }
    try {
      EncounterWorkspaceController.transitionStatus(encounterId, 'Finished');
    } catch (AuraHandledException expected) {
      denied++;
    }
    System.assertEquals(
      7,
      denied,
      'Billing must be denied valid clinical write requests even when the patient is shared.'
    );
    System.assertEquals(
      'In Progress',
      [SELECT Status__c FROM Encounter__c WHERE Id = :encounterId].Status__c
    );
  }

  private static Fixture createLocalFixture(
    User scheduler,
    User clinician,
    User billing
  ) {
    Fixture fixture = new Fixture();
    Patient__c patient = new Patient__c(
      MRN__c = 'MRN-WORKFLOW-INTEGRATION',
      First_Name__c = 'Workflow',
      Last_Name__c = 'Disposable',
      Date_of_Birth__c = Date.newInstance(1985, 5, 12),
      Sex_at_Birth__c = 'Female',
      Status__c = 'Active',
      Street__c = '10 Test Street',
      City__c = 'Boston',
      State__c = 'MA',
      Postal_Code__c = '02108',
      Country__c = 'US',
      Email__c = null,
      Phone__c = null,
      SMS_Opt_In__c = false
    );
    insert patient;
    fixture.patientId = patient.Id;
    Practitioner__c practitioner = new Practitioner__c(
      First_Name__c = 'Workflow',
      Last_Name__c = 'Clinician',
      User__c = clinician.Id,
      Active__c = true,
      NPI__c = '1999999984',
      Taxonomy_Code__c = '207Q00000X'
    );
    insert practitioner;
    fixture.practitionerId = practitioner.Id;
    CareTeam__c team = new CareTeam__c(
      Patient__c = patient.Id,
      Status__c = 'Active'
    );
    insert team;
    List<CareTeamMember__c> members = new List<CareTeamMember__c>();
    for (User member : new List<User>{ scheduler, clinician, billing }) {
      members.add(
        new CareTeamMember__c(
          Care_Team__c = team.Id,
          Practitioner__c = practitioner.Id,
          User__c = member.Id,
          Role__c = 'Other',
          Access_Level__c = 'Edit',
          Active__c = true
        )
      );
    }
    insert members;
    Schedule__c schedule = new Schedule__c(
      Practitioner__c = practitioner.Id,
      Active__c = true,
      Slot_Duration_Minutes__c = 20,
      Location_Name__c = 'Workflow Test Clinic'
    );
    insert schedule;
    Datetime slotStart = Datetime.now().addMinutes(30);
    Slot__c slot = new Slot__c(
      Schedule__c = schedule.Id,
      Start__c = slotStart,
      End__c = slotStart.addMinutes(20),
      Status__c = 'Free'
    );
    insert slot;
    fixture.slotId = slot.Id;
    insert new Organization__c(
      Name = 'Workflow Test Clinic',
      NPI__c = '1888888875',
      EIN__c = '12-3456789',
      Taxonomy_Code__c = '261QP2300X',
      Active__c = true,
      Is_Default_Billing__c = true,
      Street__c = '100 Test Avenue',
      City__c = 'Boston',
      State__c = 'MA',
      Postal_Code__c = '02108',
      Country__c = 'US'
    );
    Payer__c payer = new Payer__c(
      Name = 'Workflow Local Payer',
      Type__c = 'Commercial',
      Payer_Identifier__c = 'WORKFLOW-LOCAL',
      Active__c = true
    );
    insert payer;
    insert new Coverage__c(
      Patient__c = patient.Id,
      Payer__c = payer.Id,
      Member_Id__c = 'WORKFLOW-LOCAL-MEMBER',
      Relationship_to_Subscriber__c = 'Self',
      Subscriber_Name__c = 'Workflow Disposable',
      Status__c = 'Active',
      Priority__c = 'Primary',
      Effective_Start__c = Date.today().addDays(-2),
      Effective_End__c = Date.today().addYears(1)
    );
    Fee_Schedule__c feeSchedule = new Fee_Schedule__c(
      Name = 'Workflow Local Fee Schedule',
      Schedule_Type__c = 'Payer',
      Payer__c = payer.Id,
      Priority__c = 100,
      Active__c = true
    );
    insert feeSchedule;
    Fee_Schedule_Rate__c rate = new Fee_Schedule_Rate__c(
      Fee_Schedule__c = feeSchedule.Id,
      Procedure_Code_System__c = 'CPT',
      Procedure_Code__c = '99213',
      Procedure_Display__c = 'Established patient office visit',
      Rate_Amount__c = 175,
      Effective_Start__c = Date.today().addYears(-1),
      Active__c = true
    );
    insert rate;
    fixture.rateId = rate.Id;
    return fixture;
  }

  private static VitalsCaptureController.VitalInput vital(
    String key,
    Decimal value,
    String unit
  ) {
    VitalsCaptureController.VitalInput input = new VitalsCaptureController.VitalInput();
    input.key = key;
    input.value = value;
    input.unit = unit;
    return input;
  }

  private static User staff(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }

  private static User staffUser(String alias, Id profileId) {
    return new User(
      Alias = alias,
      LastName = alias,
      Email = alias + '@logicemr.test',
      Username = alias + '.' + Crypto.getRandomInteger() + '@logicemr.test',
      ProfileId = profileId,
      TimeZoneSidKey = 'America/New_York',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
  }

  private class Fixture {
    Id patientId;
    Id practitionerId;
    Id slotId;
    Id rateId;
  }

  private class RejectExternalCallouts implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      System.assert(
        false,
        'The local clinical workflow must not invoke an external endpoint.'
      );
      return new HttpResponse();
    }
  }
}
