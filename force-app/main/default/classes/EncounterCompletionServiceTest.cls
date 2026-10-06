@IsTest
private class EncounterCompletionServiceTest {
  @IsTest
  static void finishViaStandardUpdateStampsEndFulfillsAppointmentAndInitializesOneBill() {
    Encounter__c encounter = encounter('In Progress', 'COMPLETE-UPDATE');
    Appointment__c appointment = new Appointment__c(
      Patient__c = encounter.Patient__c,
      Encounter__c = encounter.Id,
      Status__c = 'Arrived',
      Start__c = Datetime.now().addHours(-1),
      End__c = Datetime.now().addMinutes(-30)
    );
    insert appointment;
    Test.startTest();
    update new Encounter__c(Id = encounter.Id, Status__c = 'Finished');
    Encounter__c pending = [
      SELECT Status__c, End__c, Completion_Handoff_Status__c
      FROM Encounter__c
      WHERE Id = :encounter.Id
    ];
    System.assertNotEquals(
      null,
      pending.End__c,
      'Every completion entry point must record the end'
    );
    System.assertEquals('Pending', pending.Completion_Handoff_Status__c);
    Test.stopTest();
    System.assertEquals(
      'Fulfilled',
      [SELECT Status__c FROM Appointment__c WHERE Id = :appointment.Id]
      .Status__c
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Superbill__c WHERE Encounter__c = :encounter.Id]
    );
    System.assertEquals(
      'Completed',
      [
        SELECT Completion_Handoff_Status__c
        FROM Encounter__c
        WHERE Id = :encounter.Id
      ]
      .Completion_Handoff_Status__c
    );
    EncounterCompletionService.process(new List<Id>{ encounter.Id });
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Superbill__c WHERE Encounter__c = :encounter.Id],
      'Retry processing is idempotent'
    );
  }

  @IsTest
  static void duplicateAndStaleWorkersPreserveCompletedHandoffAndExistingBill() {
    Encounter__c row = encounter('In Progress', 'COMPLETE-IDEMPOTENT');
    Test.startTest();
    update new Encounter__c(Id = row.Id, Status__c = 'Finished');
    Test.stopTest();
    Encounter__c completed = [
      SELECT End__c, Completion_Handoff_Status__c
      FROM Encounter__c
      WHERE Id = :row.Id
    ];
    System.assertEquals('Completed', completed.Completion_Handoff_Status__c);
    Superbill__c bill = [
      SELECT Id
      FROM Superbill__c
      WHERE Encounter__c = :row.Id
    ];
    // If a duplicate worker reprocesses a completed handoff, this injected failure would downgrade it.
    EncounterCompletionService.failBillingForTests.add(row.Id);
    new EncounterCompletionQueueable(new List<Id>{ row.Id }).execute(null);
    EncounterCompletionService.process(new List<Id>{ row.Id, row.Id });
    EncounterCompletionService.markQueueUnavailable(new List<Id>{ row.Id });
    Boolean completedRetryRejected = false;
    try {
      EncounterCompletionService.retryHandoff(row.Id);
    } catch (AuraHandledException e) {
      completedRetryRejected = true;
    }
    System.assertEquals(true, completedRetryRejected);
    Encounter__c unchanged = [
      SELECT End__c, Completion_Handoff_Status__c, Completion_Handoff_Error__c
      FROM Encounter__c
      WHERE Id = :row.Id
    ];
    System.assertEquals('Completed', unchanged.Completion_Handoff_Status__c);
    System.assertEquals(null, unchanged.Completion_Handoff_Error__c);
    System.assertEquals(completed.End__c, unchanged.End__c);
    List<Superbill__c> bills = [
      SELECT Id
      FROM Superbill__c
      WHERE Encounter__c = :row.Id
    ];
    System.assertEquals(1, bills.size());
    System.assertEquals(bill.Id, bills[0].Id);
    System.assertEquals(
      false,
      EncounterCompletionService.getChecklist(row.Id).canRetry
    );
  }

  @IsTest
  static void directFinishedInsertUsesSameHandoffAndPreservesExistingBill() {
    Test.startTest();
    Encounter__c encounter = encounter('Finished', 'COMPLETE-INSERT');
    Superbill__c existing = new Superbill__c(
      Encounter__c = encounter.Id,
      Encounter_Key__c = String.valueOf(encounter.Id),
      Patient__c = encounter.Patient__c,
      Status__c = 'Needs Review',
      Place_of_Service_Code__c = '22'
    );
    insert existing;
    Test.stopTest();
    System.assertNotEquals(
      null,
      [SELECT End__c FROM Encounter__c WHERE Id = :encounter.Id].End__c
    );
    System.assertEquals(
      '22',
      [
        SELECT Place_of_Service_Code__c
        FROM Superbill__c
        WHERE Id = :existing.Id
      ]
      .Place_of_Service_Code__c,
      'Existing snapshot must not be refreshed by automatic completion'
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Superbill__c WHERE Encounter__c = :encounter.Id]
    );
  }

  @IsTest
  static void independentBillingFailureDoesNotUndoVisitOrAppointmentOrOtherEncounter() {
    Encounter__c first = encounter('Finished', 'COMPLETE-FAIL');
    Encounter__c second = encounter('Finished', 'COMPLETE-GOOD');
    Appointment__c appointment = new Appointment__c(
      Patient__c = first.Patient__c,
      Encounter__c = first.Id,
      Status__c = 'Arrived',
      Start__c = Datetime.now().addHours(-1),
      End__c = Datetime.now().addMinutes(-30)
    );
    insert appointment;
    EncounterCompletionService.failBillingForTests.add(first.Id);
    EncounterCompletionService.process(new List<Id>{ first.Id, second.Id });
    Encounter__c failed = [
      SELECT
        Status__c,
        End__c,
        Completion_Handoff_Status__c,
        Completion_Handoff_Error__c
      FROM Encounter__c
      WHERE Id = :first.Id
    ];
    System.assertEquals('Finished', failed.Status__c);
    System.assertNotEquals(null, failed.End__c);
    System.assertEquals('Failed', failed.Completion_Handoff_Status__c);
    System.assertEquals(
      'Billing handoff failed. Review billing configuration and retry.',
      failed.Completion_Handoff_Error__c,
      'Error messages do not include patient or exception details'
    );
    System.assertEquals(
      'Fulfilled',
      [SELECT Status__c FROM Appointment__c WHERE Id = :appointment.Id]
      .Status__c,
      'Billing rollback must leave appointment completion intact'
    );
    System.assertEquals(
      'Completed',
      [
        SELECT Completion_Handoff_Status__c
        FROM Encounter__c
        WHERE Id = :second.Id
      ]
      .Completion_Handoff_Status__c
    );
    System.assertEquals(
      true,
      EncounterCompletionService.getChecklist(first.Id).canRetry
    );
  }

  @IsTest
  static void completionChecklistTracksClinicalReconciliationAndSigns() {
    Encounter__c encounter = encounter('In Progress', 'COMPLETE-CHECK');
    EncounterCompletionService.Checklist initial = EncounterCompletionService.getChecklist(
      encounter.Id
    );
    for (EncounterCompletionService.ChecklistItem item : initial.items)
      System.assertEquals(false, item.complete);
    Practitioner__c practitioner = new Practitioner__c(
      Last_Name__c = 'Attending'
    );
    insert practitioner;
    update new Encounter__c(
      Id = encounter.Id,
      Practitioner__c = practitioner.Id
    );
    update new Patient__c(
      Id = encounter.Patient__c,
      Allergy_Review_Status__c = 'No known allergies'
    );
    EncounterWorkspaceController.addDiagnosis(
      encounter.Id,
      'ICD-10',
      'I10',
      'Hypertension',
      null,
      'Principal',
      1
    );
    NoteEditorController.signNote(
      encounter.Id,
      null,
      'Progress Note',
      'Visit assessment and plan.'
    );
    for (
      EncounterCompletionService.ChecklistItem item : EncounterCompletionService.getChecklist(
          encounter.Id
        )
        .items
    )
      System.assertEquals(true, item.complete, item.label);
  }

  @IsTest
  static void retryRejectsOpenOrRecentlyQueuedAndAcceptsFailedHandoff() {
    Encounter__c open = encounter('In Progress', 'COMPLETE-OPEN');
    Encounter__c finished = encounter('Finished', 'COMPLETE-RETRY');
    Boolean openRejected = false;
    Boolean pendingRejected = false;
    try {
      EncounterCompletionService.retryHandoff(open.Id);
    } catch (AuraHandledException e) {
      openRejected = true;
    }
    try {
      EncounterCompletionService.retryHandoff(finished.Id);
    } catch (AuraHandledException e) {
      pendingRejected = true;
    }
    System.assertEquals(true, openRejected);
    System.assertEquals(true, pendingRejected);
    EncounterCompletionService.markQueueUnavailable(
      new List<Id>{ finished.Id }
    );
    Test.startTest();
    EncounterCompletionService.retryHandoff(finished.Id);
    Test.stopTest();
    System.assertEquals(
      'Completed',
      [
        SELECT Completion_Handoff_Status__c
        FROM Encounter__c
        WHERE Id = :finished.Id
      ]
      .Completion_Handoff_Status__c
    );
  }

  @IsTest
  static void invalidEndAndOversizedWorkerBatchAreRejected() {
    Encounter__c encounter = encounter('In Progress', 'COMPLETE-END');
    Database.SaveResult invalid = Database.update(
      new Encounter__c(
        Id = encounter.Id,
        Status__c = 'Finished',
        End__c = Datetime.now().addDays(-2)
      ),
      false
    );
    System.assertEquals(false, invalid.isSuccess());
    Boolean oversized = false;
    try {
      EncounterCompletionService.process(
        new List<Id>{ encounter.Id, encounter.Id, encounter.Id }
      );
    } catch (Exception e) {
      oversized = true;
    }
    System.assertEquals(
      true,
      oversized,
      'Worker must not risk unbounded billing queries in one transaction'
    );
  }

  @IsTest
  static void finishingInsideQueueableWithUsedChildSlotCommitsAndLeavesRetryableHandoff() {
    Encounter__c first = encounter('In Progress', 'COMPLETE-ASYNC-1');
    Encounter__c second = encounter('In Progress', 'COMPLETE-ASYNC-2');
    Set<Id> ids = new Set<Id>{ first.Id, second.Id };
    Test.startTest();
    AsyncOptions options = new AsyncOptions();
    options.MaximumQueueableStackDepth = 2;
    System.enqueueJob(
      new FinishWithUsedChildSlot(new List<Id>{ first.Id, second.Id }),
      options
    );
    Test.stopTest();
    for (Encounter__c row : [
      SELECT Status__c, End__c, Completion_Handoff_Status__c
      FROM Encounter__c
      WHERE Id IN :ids
    ]) {
      System.assertEquals(
        'Finished',
        row.Status__c,
        'Exhausted queue capacity must not roll back visit completion'
      );
      System.assertNotEquals(null, row.End__c);
      System.assertEquals(
        'Failed',
        row.Completion_Handoff_Status__c,
        'A used queueable child slot must become an explicit retryable failure'
      );
    }
  }

  @IsTest
  static void finishingAtMaximumQueueableDepthCommitsAcceptedHandoff() {
    Encounter__c row = encounter('In Progress', 'COMPLETE-ASYNC-MAX');
    Test.startTest();
    AsyncOptions options = new AsyncOptions();
    options.MaximumQueueableStackDepth = 1;
    System.enqueueJob(new FinishAtMaximumDepth(row.Id), options);
    Test.stopTest();
    Encounter__c finished = [
      SELECT Status__c, End__c, Completion_Handoff_Status__c
      FROM Encounter__c
      WHERE Id = :row.Id
    ];
    System.assertEquals('Finished', finished.Status__c);
    System.assertNotEquals(null, finished.End__c);
    System.assertEquals(
      'Completed',
      finished.Completion_Handoff_Status__c,
      'A trigger handoff accepted by the platform must complete without rolling back the visit'
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Superbill__c WHERE Encounter__c = :row.Id]
    );
    System.assertEquals(
      false,
      EncounterCompletionService.getChecklist(row.Id).canRetry
    );
  }

  @IsTest
  static void workerAtMaximumDepthCommitsBatchAndLeavesRemainingRetryable() {
    Encounter__c first = encounter('In Progress', 'COMPLETE-WORKER-1');
    Encounter__c second = encounter('In Progress', 'COMPLETE-WORKER-2');
    Encounter__c remaining = encounter('In Progress', 'COMPLETE-WORKER-3');
    Set<Id> processedIds = new Set<Id>{ first.Id, second.Id };
    Test.startTest();
    AsyncOptions options = new AsyncOptions();
    options.MaximumQueueableStackDepth = 2;
    System.enqueueJob(
      new FinishWithQueuedWorker(
        new List<Id>{ first.Id, second.Id, remaining.Id }
      ),
      options
    );
    Test.stopTest();
    for (Encounter__c processed : [
      SELECT Completion_Handoff_Status__c
      FROM Encounter__c
      WHERE Id IN :processedIds
    ]) {
      System.assertEquals('Completed', processed.Completion_Handoff_Status__c);
    }
    System.assertEquals(
      2,
      [SELECT COUNT() FROM Superbill__c WHERE Encounter__c IN :processedIds],
      'The current batch must commit before handling unavailable chain depth'
    );
    System.assertEquals(
      'Failed',
      [
        SELECT Completion_Handoff_Status__c
        FROM Encounter__c
        WHERE Id = :remaining.Id
      ]
      .Completion_Handoff_Status__c
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Superbill__c WHERE Encounter__c = :remaining.Id]
    );
    System.assertEquals(
      true,
      EncounterCompletionService.getChecklist(remaining.Id).canRetry
    );
  }

  private class FinishWithQueuedWorker implements Queueable {
    private List<Id> encounterIds;
    FinishWithQueuedWorker(List<Id> ids) {
      encounterIds = ids;
    }
    public void execute(QueueableContext context) {
      // Reserve the only child slot for this explicit worker before finishing the visits.
      // The trigger cannot enqueue additional automatic workers, and this child inherits depth 2.
      System.enqueueJob(new EncounterCompletionQueueable(encounterIds));
      List<Encounter__c> updates = new List<Encounter__c>();
      for (Id encounterId : encounterIds) {
        updates.add(new Encounter__c(Id = encounterId, Status__c = 'Finished'));
      }
      update updates;
      for (Encounter__c row : [
        SELECT Completion_Handoff_Status__c
        FROM Encounter__c
        WHERE Id IN :encounterIds
      ]) {
        System.assertEquals(
          'Failed',
          row.Completion_Handoff_Status__c,
          'The fixture must not enqueue a second handoff for any encounter'
        );
      }
    }
  }

  private class FinishAtMaximumDepth implements Queueable {
    private Id encounterId;
    FinishAtMaximumDepth(Id id) {
      encounterId = id;
    }
    public void execute(QueueableContext context) {
      update new Encounter__c(Id = encounterId, Status__c = 'Finished');
    }
  }

  private class FinishWithUsedChildSlot implements Queueable {
    private List<Id> encounterIds;
    FinishWithUsedChildSlot(List<Id> ids) {
      encounterIds = ids;
    }
    public void execute(QueueableContext context) {
      System.enqueueJob(new NoopJob());
      List<Encounter__c> updates = new List<Encounter__c>();
      for (Id encounterId : encounterIds)
        updates.add(new Encounter__c(Id = encounterId, Status__c = 'Finished'));
      update updates;
    }
  }
  private class NoopJob implements Queueable {
    public void execute(QueueableContext context) {
    }
  }

  private static Encounter__c encounter(String status, String mrn) {
    Patient__c patient = new Patient__c(
      MRN__c = mrn,
      Last_Name__c = 'Completion'
    );
    insert patient;
    Encounter__c row = new Encounter__c(
      Patient__c = patient.Id,
      Status__c = status,
      Class__c = 'Outpatient',
      Start__c = Datetime.now().addHours(-1)
    );
    insert row;
    return row;
  }
}
