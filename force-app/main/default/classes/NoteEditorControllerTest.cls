@IsTest
private class NoteEditorControllerTest {
  @IsTest
  static void getActiveTemplatesReturnsActiveOnlyGroupedReady() {
    insert new List<NoteTemplate__c>{
      new NoteTemplate__c(
        Name = 'ROS Normal',
        Category__c = 'ROS',
        Shortcut__c = '.ros',
        Body__c = '<p>ROS negative.</p>',
        Active__c = true
      ),
      new NoteTemplate__c(
        Name = 'PE Normal',
        Category__c = 'Physical Exam',
        Shortcut__c = '.pe',
        Body__c = '<p>Exam unremarkable.</p>',
        Active__c = true
      ),
      new NoteTemplate__c(
        Name = 'Retired ROS',
        Category__c = 'ROS',
        Shortcut__c = '.oldros',
        Body__c = '<p>Retired.</p>',
        Active__c = false
      )
    };

    Test.startTest();
    List<NoteEditorController.NoteTemplateInfo> templates = NoteEditorController.getActiveTemplates();
    Test.stopTest();

    System.assertEquals(
      2,
      templates.size(),
      'Inactive templates must be excluded'
    );
    System.assertEquals(
      'ROS',
      templates[0].category,
      'Results should follow configured category picklist order'
    );
    System.assertEquals(
      'ROS Normal',
      templates[0].name,
      'ROS is first in the category picklist'
    );
    System.assertEquals(
      '.ros',
      templates[0].shortcut,
      'Shortcut should load for expansion'
    );
    System.assertEquals(
      '<p>ROS negative.</p>',
      templates[0].body,
      'Body should load for insert'
    );
    System.assertEquals(
      'PE Normal',
      templates[1].name,
      'Physical Exam should follow ROS'
    );
    for (NoteEditorController.NoteTemplateInfo row : templates) {
      System.assertNotEquals(
        '.oldros',
        row.shortcut,
        'Inactive shortcut must not be returned'
      );
    }
  }

  @IsTest
  static void getCurrentNoteReturnsEmptyDraftWhenNoneExist() {
    Encounter__c encounter = insertEncounter();

    Test.startTest();
    NoteEditorController.NoteEditorState state = NoteEditorController.getCurrentNote(
      encounter.Id
    );
    Test.stopTest();

    System.assertEquals(null, state.noteId, 'No note should exist yet');
    System.assertEquals(
      encounter.Id,
      state.encounterId,
      'Encounter should be stamped on the empty state'
    );
    System.assertEquals(
      encounter.Patient__c,
      state.patientId,
      'Patient should come from the encounter'
    );
    System.assertEquals(
      'Progress Note',
      state.noteType,
      'New notes default to Progress Note'
    );
    System.assertEquals('Draft', state.status, 'New notes start as Draft');
    System.assertEquals('', state.body, 'New notes should have an empty body');
    System.assertEquals(
      null,
      state.signedDate,
      'Unsigned notes have no signed date'
    );
  }

  @IsTest
  static void getCurrentNoteReturnsLatestDraftForEncounter() {
    Encounter__c encounter = insertEncounter();
    ClinicalNote__c older = insertDraft(encounter, 'Consult', '<p>Older</p>');
    ClinicalNote__c newer = insertDraft(encounter, 'H&P', '<p>Newer</p>');
    Test.setCreatedDate(older.Id, Datetime.newInstance(2024, 1, 1, 0, 0, 0));
    Test.setCreatedDate(newer.Id, Datetime.newInstance(2024, 1, 2, 0, 0, 0));
    newer.Body__c = '<p>Newest</p>';
    update newer;
    Encounter__c other = insertEncounter();
    insertDraft(other, 'Progress Note', '<p>Other encounter</p>');

    Test.startTest();
    NoteEditorController.NoteEditorState state = NoteEditorController.getCurrentNote(
      encounter.Id
    );
    Test.stopTest();

    System.assertEquals(
      newer.Id,
      state.noteId,
      'Most recently modified draft should be returned'
    );
    System.assertEquals('H&P', state.noteType, 'Draft note type should load');
    System.assertEquals('<p>Newest</p>', state.body, 'Draft body should load');
    System.assertEquals(
      'Draft',
      state.status,
      'Loaded note should still be Draft'
    );
    System.assertNotEquals(
      older.Id,
      state.noteId,
      'Older draft should not win'
    );
  }

  @IsTest
  static void saveDraftInsertsAndUpdatesWithoutSigning() {
    Encounter__c encounter = insertEncounter();
    Practitioner__c author = insertPractitionerForCurrentUser();

    Test.startTest();
    NoteEditorController.NoteEditorState created = NoteEditorController.saveDraft(
      encounter.Id,
      null,
      'Consult',
      '<p>Draft body</p>'
    );
    NoteEditorController.NoteEditorState updated = NoteEditorController.saveDraft(
      encounter.Id,
      created.noteId,
      'Discharge Summary',
      '<p>Updated body</p>'
    );
    Test.stopTest();

    ClinicalNote__c stored = [
      SELECT
        Patient__c,
        Encounter__c,
        Author__c,
        Note_Type__c,
        Body__c,
        Status__c,
        Signed_Date__c
      FROM ClinicalNote__c
      WHERE Id = :created.noteId
    ];
    System.assertEquals(
      created.noteId,
      updated.noteId,
      'Save should update the same draft'
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM ClinicalNote__c],
      'Draft save must not create a second row'
    );
    System.assertEquals(
      encounter.Patient__c,
      stored.Patient__c,
      'Patient must come from the encounter'
    );
    System.assertEquals(
      encounter.Id,
      stored.Encounter__c,
      'Encounter must be stamped'
    );
    System.assertEquals(
      author.Id,
      stored.Author__c,
      'Author should be the Practitioner linked to the running user'
    );
    System.assertEquals(
      'Discharge Summary',
      stored.Note_Type__c,
      'Updated note type should persist'
    );
    System.assertEquals(
      '<p>Updated body</p>',
      stored.Body__c,
      'Updated body should persist'
    );
    System.assertEquals(
      'Draft',
      stored.Status__c,
      'Save as Draft must leave Status as Draft'
    );
    System.assertEquals(
      null,
      stored.Signed_Date__c,
      'Save as Draft must not set Signed Date'
    );
    System.assertEquals(
      'Draft',
      updated.status,
      'Returned state should remain Draft'
    );
  }

  @IsTest
  static void signNoteSetsSignedStatusAndLocksFurtherEdits() {
    Encounter__c encounter = insertEncounter();

    Test.startTest();
    NoteEditorController.NoteEditorState signed = NoteEditorController.signNote(
      encounter.Id,
      null,
      'Progress Note',
      '<p>Ready to sign</p>'
    );
    Boolean saveThrew = false;
    Boolean resignThrew = false;
    try {
      NoteEditorController.saveDraft(
        encounter.Id,
        signed.noteId,
        'Progress Note',
        '<p>Changed after sign</p>'
      );
    } catch (AuraHandledException e) {
      saveThrew = true;
    }
    try {
      NoteEditorController.signNote(
        encounter.Id,
        signed.noteId,
        'Progress Note',
        '<p>Sign again</p>'
      );
    } catch (AuraHandledException e) {
      resignThrew = true;
    }
    Test.stopTest();

    ClinicalNote__c stored = [
      SELECT Status__c, Signed_Date__c, Body__c, Note_Type__c
      FROM ClinicalNote__c
      WHERE Id = :signed.noteId
    ];
    System.assertEquals(
      'Signed',
      stored.Status__c,
      'Sign must set Status to Signed'
    );
    System.assertNotEquals(
      null,
      stored.Signed_Date__c,
      'Sign must stamp Signed Date'
    );
    System.assertEquals(
      '<p>Ready to sign</p>',
      stored.Body__c,
      'Signed body should persist'
    );
    System.assertEquals(
      'Signed',
      signed.status,
      'Returned state should be Signed'
    );
    System.assertEquals(
      stored.Signed_Date__c,
      signed.signedDate,
      'Returned signed date should match the record'
    );
    System.assertEquals(
      true,
      saveThrew,
      'Signed notes cannot be saved as draft'
    );
    System.assertEquals(
      true,
      resignThrew,
      'Signed notes cannot be signed again'
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM ClinicalNote__c WHERE Status__c = 'Draft'],
      'Failed edits must not create a replacement draft'
    );
  }

  @IsTest
  static void persistNoteRejectsInvalidInputWithoutDml() {
    Patient__c patient = insertPatient('MRN-NOTE-BAD');
    Encounter__c encounter = insertEncounter();
    ClinicalNote__c otherEncounterNote = insertDraft(
      insertEncounter(),
      'Progress Note',
      '<p>Other</p>'
    );
    Boolean nullIdThrew = false;
    Boolean unknownThrew = false;
    Boolean missingNoteThrew = false;
    Boolean wrongEncounterThrew = false;
    Boolean badTypeThrew = false;

    Test.startTest();
    try {
      NoteEditorController.saveDraft(null, null, 'Progress Note', '<p>x</p>');
    } catch (AuraHandledException e) {
      nullIdThrew = true;
    }
    try {
      NoteEditorController.saveDraft(
        patient.Id,
        null,
        'Progress Note',
        '<p>x</p>'
      );
    } catch (AuraHandledException e) {
      unknownThrew = true;
    }
    try {
      NoteEditorController.saveDraft(
        encounter.Id,
        patient.Id,
        'Progress Note',
        '<p>x</p>'
      );
    } catch (AuraHandledException e) {
      missingNoteThrew = true;
    }
    try {
      NoteEditorController.saveDraft(
        encounter.Id,
        otherEncounterNote.Id,
        'Progress Note',
        '<p>x</p>'
      );
    } catch (AuraHandledException e) {
      wrongEncounterThrew = true;
    }
    try {
      NoteEditorController.signNote(
        encounter.Id,
        null,
        'Operative Note',
        '<p>x</p>'
      );
    } catch (AuraHandledException e) {
      badTypeThrew = true;
    }
    NoteEditorController.NoteEditorState blankType = NoteEditorController.saveDraft(
      encounter.Id,
      null,
      '',
      '<p>Defaulted type</p>'
    );
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
    System.assertEquals(
      true,
      missingNoteThrew,
      'Unknown note Id should be rejected'
    );
    System.assertEquals(
      true,
      wrongEncounterThrew,
      'Note from another encounter should be rejected'
    );
    System.assertEquals(
      true,
      badTypeThrew,
      'Invalid note type should be rejected'
    );
    System.assertEquals(
      'Progress Note',
      blankType.noteType,
      'Blank note type should default to Progress Note'
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM ClinicalNote__c WHERE Encounter__c = :encounter.Id],
      'Rejected saves must not insert rows on the target encounter'
    );
  }

  @IsTest
  static void getNotesReturnsAllNotesForEncounterNewestFirst() {
    Encounter__c encounter = insertEncounter();
    ClinicalNote__c older = insertDraft(encounter, 'Consult', '<p>Older</p>');
    ClinicalNote__c newer = insertDraft(encounter, 'H&P', '<p>Newer</p>');
    Test.setCreatedDate(older.Id, Datetime.newInstance(2024, 1, 1, 0, 0, 0));
    Test.setCreatedDate(newer.Id, Datetime.newInstance(2024, 1, 2, 0, 0, 0));
    newer.Body__c = '<p>Newest</p>';
    update newer;
    NoteEditorController.NoteEditorState signed = NoteEditorController.signNote(
      encounter.Id,
      null,
      'Other',
      '<p>Signed</p>'
    );
    Test.setCreatedDate(
      signed.noteId,
      Datetime.newInstance(2024, 1, 3, 0, 0, 0)
    );
    Encounter__c other = insertEncounter();
    insertDraft(other, 'Progress Note', '<p>Other encounter</p>');

    Test.startTest();
    List<NoteEditorController.NoteEditorState> notes = NoteEditorController.getNotes(
      encounter.Id
    );
    Boolean nullIdThrew = false;
    try {
      NoteEditorController.getNotes(null);
    } catch (AuraHandledException e) {
      nullIdThrew = true;
    }
    Test.stopTest();

    System.assertEquals(
      3,
      notes.size(),
      'All notes for the encounter should be returned'
    );
    System.assertEquals(
      signed.noteId,
      notes[0].noteId,
      'Most recently modified note should be first'
    );
    Set<Id> ids = new Set<Id>();
    for (NoteEditorController.NoteEditorState row : notes) {
      ids.add(row.noteId);
    }
    System.assertEquals(
      true,
      ids.contains(older.Id),
      'Older draft should be included'
    );
    System.assertEquals(
      true,
      ids.contains(newer.Id),
      'Updated draft should be included'
    );
    System.assertEquals(
      true,
      ids.contains(signed.noteId),
      'Signed note should be included'
    );
    System.assertEquals(
      true,
      nullIdThrew,
      'Null encounter Id should be rejected'
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM ClinicalNote__c WHERE Encounter__c = :other.Id],
      'Notes from another encounter must not be mixed in'
    );
  }

  @IsTest
  static void getNotesReturnsEmptyWhenNoneExist() {
    Encounter__c encounter = insertEncounter();

    Test.startTest();
    List<NoteEditorController.NoteEditorState> notes = NoteEditorController.getNotes(
      encounter.Id
    );
    Test.stopTest();

    System.assertEquals(
      0,
      notes.size(),
      'Encounters without notes should return an empty list'
    );
  }

  @IsTest
  static void getCurrentNoteReturnsSignedNoteWhenNoDraft() {
    Encounter__c encounter = insertEncounter();
    NoteEditorController.NoteEditorState signed = NoteEditorController.signNote(
      encounter.Id,
      null,
      'Other',
      '<p>Signed only</p>'
    );

    Test.startTest();
    NoteEditorController.NoteEditorState state = NoteEditorController.getCurrentNote(
      encounter.Id
    );
    Test.stopTest();

    System.assertEquals(
      signed.noteId,
      state.noteId,
      'Signed note should remain visible when no draft exists'
    );
    System.assertEquals(
      'Signed',
      state.status,
      'Signed status should load for display'
    );
    System.assertEquals(
      '<p>Signed only</p>',
      state.body,
      'Signed body should load for display'
    );
    System.assertEquals(
      'Other',
      state.noteType,
      'Signed note type should load for display'
    );
  }

  @IsTest
  static void standardDmlCannotAlterOrDeleteSignedClinicalContent() {
    Encounter__c encounter = insertEncounter();
    NoteEditorController.NoteEditorState signed = NoteEditorController.signNote(
      encounter.Id,
      null,
      'Progress Note',
      '<p>Original clinical record</p>'
    );
    ClinicalNote__c stored = [
      SELECT Body__c, Status__c, Signed_By__c, Signed_Date__c
      FROM ClinicalNote__c
      WHERE Id = :signed.noteId
    ];
    System.assertEquals(
      UserInfo.getUserId(),
      stored.Signed_By__c,
      'Signer provenance comes from the actual running user'
    );
    Database.SaveResult edit = Database.update(
      new ClinicalNote__c(Id = signed.noteId, Body__c = '<p>Changed</p>'),
      false
    );
    Database.SaveResult unsign = Database.update(
      new ClinicalNote__c(Id = signed.noteId, Status__c = 'Draft'),
      false
    );
    Database.DeleteResult removal = Database.delete(
      new ClinicalNote__c(Id = signed.noteId),
      false
    );
    System.assertEquals(
      false,
      edit.isSuccess(),
      'Standard record editing must not bypass the signed lock'
    );
    System.assertEquals(
      false,
      unsign.isSuccess(),
      'Signed notes cannot be returned to draft'
    );
    System.assertEquals(
      false,
      removal.isSuccess(),
      'Standard record deletion must not bypass the signed lock'
    );
    System.assertEquals(
      stored.Body__c,
      [SELECT Body__c FROM ClinicalNote__c WHERE Id = :signed.noteId].Body__c
    );
  }

  @IsTest
  static void addendumKeepsOriginalSignatureAndCanBeDraftedThenSigned() {
    Encounter__c encounter = insertEncounter();
    NoteEditorController.NoteEditorState original = NoteEditorController.signNote(
      encounter.Id,
      null,
      'Consult',
      '<p>Original assessment</p>'
    );
    NoteEditorController.NoteEditorState addendum = NoteEditorController.createAddendum(
      original.noteId,
      '<p>Additional clinical information</p>',
      false
    );
    System.assertEquals(original.noteId, addendum.addendumToId);
    System.assertEquals('Draft', addendum.status);
    NoteEditorController.NoteEditorState signed = NoteEditorController.signNote(
      encounter.Id,
      addendum.noteId,
      'Consult',
      '<p>Additional clinical information, confirmed</p>'
    );
    System.assertEquals(original.noteId, signed.addendumToId);
    System.assertEquals('Signed', signed.status);
    System.assertNotEquals(null, signed.signedByName);
    ClinicalNote__c unchanged = [
      SELECT Body__c, Signed_Date__c, Signed_By__c
      FROM ClinicalNote__c
      WHERE Id = :original.noteId
    ];
    System.assertEquals('<p>Original assessment</p>', unchanged.Body__c);
    System.assertEquals(original.signedDate, unchanged.Signed_Date__c);
    System.assertEquals(UserInfo.getUserId(), unchanged.Signed_By__c);
  }

  @IsTest
  static void emptySignAndCrossEncounterAddendumAreRejected() {
    Encounter__c encounter = insertEncounter();
    List<ClinicalNote__c> emptyNotes = new List<ClinicalNote__c>();
    for (
      String body : new List<String>{
        '<p>&nbsp;</p>',
        '<div><br></div>',
        '<p>&#160;&#xA0; </p>',
        '<p> </p>',
        '<p>&#8203;&#65279;</p>'
      }
    ) {
      emptyNotes.add(
        new ClinicalNote__c(
          Patient__c = encounter.Patient__c,
          Encounter__c = encounter.Id,
          Note_Type__c = 'Other',
          Body__c = body,
          Status__c = 'Signed'
        )
      );
    }
    for (Database.SaveResult result : Database.insert(emptyNotes, false)) {
      System.assertEquals(
        false,
        result.isSuccess(),
        'Formatting, encoded spaces and invisible characters alone are not signable content'
      );
    }
    ClinicalNote__c meaningful = new ClinicalNote__c(
      Patient__c = encounter.Patient__c,
      Encounter__c = encounter.Id,
      Note_Type__c = 'Other',
      Body__c = '<p>Glucose &lt; 100 &amp; stable.</p>',
      Status__c = 'Signed'
    );
    System.assertEquals(
      true,
      Database.insert(meaningful, false).isSuccess(),
      'Encoded comparison and clinical text remain signable'
    );
    NoteEditorController.NoteEditorState original = NoteEditorController.signNote(
      encounter.Id,
      null,
      'Consult',
      'Assessment'
    );
    Encounter__c other = insertEncounter();
    ClinicalNote__c invalid = new ClinicalNote__c(
      Patient__c = other.Patient__c,
      Encounter__c = other.Id,
      Addendum_To__c = original.noteId,
      Note_Type__c = 'Consult',
      Body__c = 'Wrong patient',
      Status__c = 'Draft'
    );
    System.assertEquals(
      false,
      Database.insert(invalid, false).isSuccess(),
      'Addenda must stay with their original patient and encounter'
    );
    ClinicalNote__c draft = insertDraft(encounter, 'Other', 'Draft');
    Boolean rejected = false;
    try {
      NoteEditorController.createAddendum(draft.Id, 'Not allowed', false);
    } catch (AuraHandledException e) {
      rejected = true;
    }
    System.assertEquals(true, rejected, 'Draft notes cannot receive addenda');
  }

  @IsTest
  static void billingRoleCannotCreateEditSignOrAddendClinicalNotes() {
    User billing;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      billing = insertNoteRoleUser('notebill', 'LogicEMR_Billing');
    }
    Encounter__c encounter = insertEncounter();
    ClinicalNote__c draft = insertDraft(encounter, 'Consult', 'Original draft');
    NoteEditorController.NoteEditorState signed = NoteEditorController.signNote(
      encounter.Id,
      null,
      'Consult',
      'Original signed note'
    );
    System.runAs(billing) {
      System.assert(
        FeatureManagement.checkPermission('LogicEMR_Manage_Claims'),
        'The caller has the actual Billing permission set'
      );
      System.assertEquals(
        false,
        ClinicalNote__c.SObjectType.getDescribe().isCreateable()
      );
      System.assertEquals(
        false,
        ClinicalNote__c.SObjectType.getDescribe().isUpdateable()
      );
      assertNoteWritesDenied(
        encounter.Id,
        draft.Id,
        signed.noteId,
        'Unauthorized replacement'
      );
    }
    assertOriginalNotesRemain(encounter.Id, draft.Id, signed.noteId);
  }

  @IsTest
  static void clinicianRoleCanDraftSignAndAddendWithDerivedSigner() {
    User clinician;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      clinician = insertNoteRoleUser('notecln', 'LogicEMR_Clinician');
    }
    Practitioner__c practitioner = new Practitioner__c(
      First_Name__c = 'Clinical',
      Last_Name__c = 'Author',
      User__c = clinician.Id,
      Active__c = true
    );
    insert practitioner;
    Encounter__c encounter = insertOwnedEncounter(
      clinician.Id,
      practitioner.Id
    );
    Test.startTest();
    System.runAs(clinician) {
      System.assert(ClinicalNote__c.SObjectType.getDescribe().isCreateable());
      System.assert(ClinicalNote__c.SObjectType.getDescribe().isUpdateable());
      System.assertEquals(
        false,
        ClinicalNote__c.Signed_By__c.getDescribe().isUpdateable(),
        'Signer is system-derived and does not require user-editable signature fields'
      );
      NoteEditorController.NoteEditorState draft = NoteEditorController.saveDraft(
        encounter.Id,
        null,
        'Progress Note',
        'First draft'
      );
      NoteEditorController.saveDraft(
        encounter.Id,
        draft.noteId,
        'Progress Note',
        'Reviewed draft'
      );
      NoteEditorController.NoteEditorState signed = NoteEditorController.signNote(
        encounter.Id,
        draft.noteId,
        'Progress Note',
        'Reviewed clinical assessment'
      );
      ClinicalNote__c stored = [
        SELECT Patient__c, Encounter__c, Author__c, Signed_By__c, Signed_Date__c
        FROM ClinicalNote__c
        WHERE Id = :signed.noteId
      ];
      System.assertEquals(encounter.Patient__c, stored.Patient__c);
      System.assertEquals(encounter.Id, stored.Encounter__c);
      System.assertEquals(practitioner.Id, stored.Author__c);
      System.assertEquals(clinician.Id, stored.Signed_By__c);
      System.assertNotEquals(null, stored.Signed_Date__c);
      NoteEditorController.NoteEditorState addendum = NoteEditorController.createAddendum(
        signed.noteId,
        'Additional findings',
        false
      );
      System.assertEquals('Draft', addendum.status);
      NoteEditorController.NoteEditorState signedAddendum = NoteEditorController.signNote(
        encounter.Id,
        addendum.noteId,
        'Progress Note',
        'Additional findings confirmed'
      );
      System.assertEquals(signed.noteId, signedAddendum.addendumToId);
      System.assertEquals('Signed', signedAddendum.status);
      NoteEditorController.NoteEditorState immediate = NoteEditorController.createAddendum(
        signed.noteId,
        'Second signed addendum',
        true
      );
      System.assertEquals('Signed', immediate.status);
      System.assertEquals(signed.noteId, immediate.addendumToId);
      System.assertEquals(
        clinician.Id,
        [SELECT Signed_By__c FROM ClinicalNote__c WHERE Id = :immediate.noteId]
        .Signed_By__c
      );
      System.assertEquals(
        'Reviewed clinical assessment',
        [SELECT Body__c FROM ClinicalNote__c WHERE Id = :signed.noteId].Body__c,
        'Addenda retain the original signed content'
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void readOnlyPatientShareCannotWriteClinicalNotes() {
    User clinician;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      clinician = insertNoteRoleUser('noteread', 'LogicEMR_Clinician');
    }
    Encounter__c encounter = insertEncounter();
    ClinicalNote__c draft = insertDraft(encounter, 'Consult', 'Original draft');
    NoteEditorController.NoteEditorState signed = NoteEditorController.signNote(
      encounter.Id,
      null,
      'Consult',
      'Original signed note'
    );
    insert new Patient__Share(
      ParentId = encounter.Patient__c,
      UserOrGroupId = clinician.Id,
      AccessLevel = 'Read',
      RowCause = Schema.Patient__Share.RowCause.Manual
    );
    Test.startTest();
    System.runAs(clinician) {
      System.assert(ClinicalNote__c.SObjectType.getDescribe().isCreateable());
      System.assert(ClinicalNote__c.SObjectType.getDescribe().isUpdateable());
      System.assert(ClinicalNote__c.Body__c.getDescribe().isUpdateable());
      UserRecordAccess access = [
        SELECT RecordId, HasReadAccess, HasEditAccess
        FROM UserRecordAccess
        WHERE UserId = :clinician.Id AND RecordId = :draft.Id
        LIMIT 1
      ];
      System.assert(
        access.HasReadAccess,
        'The shared clinical note is readable'
      );
      System.assertEquals(
        false,
        access.HasEditAccess,
        'The fixture has no record-level clinical edit access'
      );
      System.assertEquals(
        2,
        NoteEditorController.getNotes(encounter.Id).size()
      );
      for (Integer operation = 0; operation < 6; operation++) {
        Boolean denied = false;
        try {
          if (operation == 0)
            NoteEditorController.saveDraft(
              encounter.Id,
              null,
              'Consult',
              'Unauthorized'
            );
          else if (operation == 1)
            NoteEditorController.signNote(
              encounter.Id,
              null,
              'Consult',
              'Unauthorized'
            );
          else if (operation == 2)
            NoteEditorController.saveDraft(
              encounter.Id,
              draft.Id,
              'Consult',
              'Unauthorized'
            );
          else if (operation == 3)
            NoteEditorController.signNote(
              encounter.Id,
              draft.Id,
              'Consult',
              'Unauthorized'
            );
          else
            NoteEditorController.createAddendum(
              signed.noteId,
              'Unauthorized',
              operation == 5
            );
        } catch (DmlException error) {
          denied = true;
          System.assert(
            new Set<String>{
                'INSUFFICIENT_ACCESS_OR_READONLY',
                'INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY'
              }
              .contains(error.getDmlStatusCode(0)),
            'The mutation must be denied by record access'
          );
        }
        System.assert(
          denied,
          'Read-only clinical mutation ' + operation + ' must be denied'
        );
      }
    }
    Test.stopTest();
    assertOriginalNotesRemain(encounter.Id, draft.Id, signed.noteId);
  }

  @IsTest
  static void objectWriteAccessCannotBypassNoteBodyFieldPermissions() {
    User writer;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      writer = noteUser('notefls');
      insert writer;
      PermissionSet access = new PermissionSet(
        Name = 'Note_Body_Read_Only_Test',
        Label = 'Note body read only test'
      );
      insert access;
      String noteObject = qualifiedObjectName(ClinicalNote__c.SObjectType);
      insert new List<ObjectPermissions>{
        new ObjectPermissions(
          ParentId = access.Id,
          SobjectType = qualifiedObjectName(Patient__c.SObjectType),
          PermissionsRead = true
        ),
        new ObjectPermissions(
          ParentId = access.Id,
          SobjectType = qualifiedObjectName(Encounter__c.SObjectType),
          PermissionsRead = true
        ),
        new ObjectPermissions(
          ParentId = access.Id,
          SobjectType = noteObject,
          PermissionsRead = true,
          PermissionsCreate = true,
          PermissionsEdit = true
        )
      };
      String namespacePrefix = noteObject.substringBefore('ClinicalNote__c');
      List<FieldPermissions> fields = new List<FieldPermissions>();
      for (
        Schema.SObjectField token : new List<Schema.SObjectField>{
          ClinicalNote__c.Body__c,
          ClinicalNote__c.Note_Type__c,
          ClinicalNote__c.Status__c,
          ClinicalNote__c.Encounter__c,
          ClinicalNote__c.Author__c,
          ClinicalNote__c.Addendum_To__c
        }
      ) {
        String fieldName = token.getDescribe().getName();
        if (
          !String.isBlank(namespacePrefix) &&
          !fieldName.startsWith(namespacePrefix)
        )
          fieldName = namespacePrefix + fieldName;
        fields.add(
          new FieldPermissions(
            ParentId = access.Id,
            SobjectType = noteObject,
            Field = noteObject + '.' + fieldName,
            PermissionsRead = true,
            PermissionsEdit = token != ClinicalNote__c.Body__c
          )
        );
      }
      insert fields;
      insert new PermissionSetAssignment(
        AssigneeId = writer.Id,
        PermissionSetId = access.Id
      );
    }
    Encounter__c encounter = insertOwnedEncounter(writer.Id, null);
    ClinicalNote__c draft = insertDraft(encounter, 'Consult', 'Original draft');
    NoteEditorController.NoteEditorState signed = NoteEditorController.signNote(
      encounter.Id,
      null,
      'Consult',
      'Original signed note'
    );
    System.runAs(writer) {
      System.assert(ClinicalNote__c.SObjectType.getDescribe().isCreateable());
      System.assert(ClinicalNote__c.SObjectType.getDescribe().isUpdateable());
      System.assertEquals(
        false,
        ClinicalNote__c.Body__c.getDescribe().isCreateable()
      );
      System.assertEquals(
        false,
        ClinicalNote__c.Body__c.getDescribe().isUpdateable()
      );
      assertNoteWritesDenied(
        encounter.Id,
        draft.Id,
        signed.noteId,
        'Forbidden body'
      );
      Boolean clearDenied = false;
      try {
        NoteEditorController.saveDraft(encounter.Id, draft.Id, 'Consult', null);
      } catch (AuraHandledException e) {
        clearDenied = true;
      }
      System.assert(
        clearDenied,
        'Clearing a protected body also requires field edit access'
      );
    }
    assertOriginalNotesRemain(encounter.Id, draft.Id, signed.noteId);
  }

  private static void assertNoteWritesDenied(
    Id encounterId,
    Id draftId,
    Id signedId,
    String body
  ) {
    for (Integer operation = 0; operation < 6; operation++) {
      Boolean denied = false;
      try {
        if (operation == 0)
          NoteEditorController.saveDraft(encounterId, null, 'Consult', body);
        else if (operation == 1)
          NoteEditorController.signNote(encounterId, null, 'Consult', body);
        else if (operation == 2)
          NoteEditorController.saveDraft(encounterId, draftId, 'Consult', body);
        else if (operation == 3)
          NoteEditorController.signNote(encounterId, draftId, 'Consult', body);
        else
          NoteEditorController.createAddendum(signedId, body, operation == 5);
      } catch (AuraHandledException e) {
        denied = true;
      }
      System.assert(
        denied,
        'Clinical note mutation ' + operation + ' must enforce caller access'
      );
    }
  }

  private static void assertOriginalNotesRemain(
    Id encounterId,
    Id draftId,
    Id signedId
  ) {
    System.assertEquals(
      2,
      [SELECT COUNT() FROM ClinicalNote__c WHERE Encounter__c = :encounterId]
    );
    ClinicalNote__c draft = [
      SELECT Body__c, Status__c
      FROM ClinicalNote__c
      WHERE Id = :draftId
    ];
    System.assertEquals('Original draft', draft.Body__c);
    System.assertEquals('Draft', draft.Status__c);
    ClinicalNote__c signed = [
      SELECT Body__c, Status__c
      FROM ClinicalNote__c
      WHERE Id = :signedId
    ];
    System.assertEquals('Original signed note', signed.Body__c);
    System.assertEquals('Signed', signed.Status__c);
  }

  private static User insertNoteRoleUser(
    String alias,
    String permissionSetName
  ) {
    User user = noteUser(alias);
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

  private static User noteUser(String alias) {
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

  private static String qualifiedObjectName(Schema.SObjectType token) {
    String keyPrefix = token.getDescribe().getKeyPrefix();
    return [
      SELECT QualifiedApiName
      FROM EntityDefinition
      WHERE KeyPrefix = :keyPrefix
      LIMIT 1
    ]
    .QualifiedApiName;
  }

  private static Encounter__c insertOwnedEncounter(
    Id ownerId,
    Id practitionerId
  ) {
    Patient__c patient = new Patient__c(
      MRN__c = 'MRN-NOTE-' +
        String.valueOf(Math.abs(Crypto.getRandomInteger())),
      Last_Name__c = 'Notes',
      OwnerId = ownerId
    );
    insert patient;
    Encounter__c encounter = new Encounter__c(
      Patient__c = patient.Id,
      Practitioner__c = practitionerId,
      Status__c = 'In Progress',
      Class__c = 'Outpatient',
      Start__c = Datetime.now().addHours(-1)
    );
    insert encounter;
    return encounter;
  }

  private static ClinicalNote__c insertDraft(
    Encounter__c encounter,
    String noteType,
    String body
  ) {
    ClinicalNote__c note = new ClinicalNote__c(
      Patient__c = encounter.Patient__c,
      Encounter__c = encounter.Id,
      Note_Type__c = noteType,
      Body__c = body,
      Status__c = 'Draft'
    );
    insert note;
    return note;
  }

  private static Practitioner__c insertPractitionerForCurrentUser() {
    Practitioner__c practitioner = new Practitioner__c(
      Last_Name__c = 'Author',
      First_Name__c = 'Note',
      User__c = UserInfo.getUserId(),
      Active__c = true
    );
    insert practitioner;
    return practitioner;
  }

  private static Patient__c insertPatient(String mrn) {
    Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'Notes');
    insert patient;
    return patient;
  }

  private static Encounter__c insertEncounter() {
    Encounter__c encounter = new Encounter__c(
      Patient__c = insertPatient(
          'MRN-NOTE-' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        )
        .Id,
      Status__c = 'In Progress',
      Class__c = 'Outpatient',
      Start__c = Datetime.newInstance(2024, 3, 1, 9, 0, 0)
    );
    insert encounter;
    return encounter;
  }
}
