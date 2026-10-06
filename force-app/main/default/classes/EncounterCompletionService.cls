public with sharing class EncounterCompletionService {
  @TestVisible
  private static Set<Id> failBillingForTests = new Set<Id>();

  public class ChecklistItem {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Boolean complete;
  }
  public class Checklist {
    @AuraEnabled
    public List<ChecklistItem> items;
    @AuraEnabled
    public String handoffStatus;
    @AuraEnabled
    public String handoffError;
    @AuraEnabled
    public Boolean canRetry;
  }

  public static void beforeSave(
    List<Encounter__c> rows,
    Map<Id, Encounter__c> oldMap
  ) {
    for (Encounter__c row : rows) {
      Encounter__c prior = oldMap == null ? null : oldMap.get(row.Id);
      if (
        row.Status__c == 'Finished' &&
        (prior == null ||
        prior.Status__c != 'Finished')
      ) {
        if (row.End__c == null) {
          row.End__c = Datetime.now();
        }
        if (row.Start__c != null && row.End__c < row.Start__c) {
          row.addError('Encounter end must be on or after its start.');
        }
        row.Completion_Handoff_Status__c = 'Pending';
        row.Completion_Handoff_Queued_At__c = Datetime.now();
        row.Completion_Handoff_Error__c = null;
      }
    }
  }

  public static void afterSave(
    List<Encounter__c> rows,
    Map<Id, Encounter__c> oldMap
  ) {
    List<Id> completedIds = new List<Id>();
    for (Encounter__c row : rows) {
      Encounter__c prior = oldMap == null ? null : oldMap.get(row.Id);
      if (
        row.Status__c == 'Finished' &&
        (prior == null ||
        prior.Status__c != 'Finished')
      ) {
        completedIds.add(row.Id);
      }
    }
    if (!completedIds.isEmpty()) {
      enqueue(completedIds);
    }
  }

  private static void enqueue(List<Id> encounterIds) {
    // AsyncInfo is unavailable in trigger execution, including triggers invoked by a queueable.
    // Enqueue itself enforces inherited stack depth; a catchable rejection leaves a retryable handoff.
    if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
      try {
        if (System.isQueueable()) {
          System.enqueueJob(new EncounterCompletionQueueable(encounterIds));
        } else {
          AsyncOptions options = new AsyncOptions();
          options.MaximumQueueableStackDepth = 100;
          System.enqueueJob(
            new EncounterCompletionQueueable(encounterIds),
            options
          );
        }
      } catch (System.AsyncException e) {
        // Keep the completed visit committed if the platform cannot accept its handoff.
        markQueueUnavailable(encounterIds);
      }
    } else {
      markQueueUnavailable(encounterIds);
    }
  }

  public static void markQueueUnavailable(List<Id> encounterIds) {
    if (encounterIds == null || encounterIds.isEmpty()) {
      return;
    }
    List<Encounter__c> updates = new List<Encounter__c>();
    for (Encounter__c encounter : [
      SELECT Id, Status__c, Completion_Handoff_Status__c
      FROM Encounter__c
      WHERE Id IN :encounterIds
      FOR UPDATE
    ]) {
      if (
        encounter.Status__c != 'Finished' ||
        encounter.Completion_Handoff_Status__c == 'Completed'
      ) {
        continue;
      }
      updates.add(
        new Encounter__c(
          Id = encounter.Id,
          Completion_Handoff_Status__c = 'Failed',
          Completion_Handoff_Error__c = 'Completion handoff could not be queued. Retry completion handoff.'
        )
      );
    }
    if (!updates.isEmpty()) {
      Database.update(updates, false);
    }
  }

  // Called in a separate transaction: a billing/configuration error must never roll back a completed visit.
  public static void process(List<Id> encounterIds) {
    if (encounterIds == null || encounterIds.isEmpty()) {
      return;
    }
    if (encounterIds.size() > 2) {
      throw new CompletionException(
        'Completion worker batches must contain at most two encounters.'
      );
    }
    for (Id encounterId : encounterIds) {
      List<String> failures = new List<String>();
      List<Appointment__c> appointments = new List<Appointment__c>();
      // Scheduling mutations lock the appointment before the encounter. Use the same order.
      try {
        appointments = [
          SELECT Id, Status__c
          FROM Appointment__c
          WHERE Encounter__c = :encounterId
          FOR UPDATE
        ];
      } catch (Exception e) {
        failures.add('Appointment completion failed.');
      }
      List<Encounter__c> rows = [
        SELECT Id, Status__c, Completion_Handoff_Status__c
        FROM Encounter__c
        WHERE Id = :encounterId
        LIMIT 1
        FOR UPDATE
      ];
      if (
        rows.isEmpty() ||
        rows[0].Status__c != 'Finished' ||
        rows[0].Completion_Handoff_Status__c == 'Completed'
      ) {
        continue;
      }
      try {
        List<Appointment__c> appointmentUpdates = new List<Appointment__c>();
        for (Appointment__c appointment : appointments) {
          if (
            appointment.Status__c == 'Fulfilled' ||
            appointment.Status__c == 'Cancelled' ||
            appointment.Status__c == 'No Show'
          ) {
            continue;
          }
          appointment.Status__c = 'Fulfilled';
          appointmentUpdates.add(appointment);
        }
        if (!appointmentUpdates.isEmpty()) {
          update appointmentUpdates;
        }
      } catch (Exception e) {
        failures.add('Appointment completion failed.');
      }
      Savepoint billingSavepoint = Database.setSavepoint();
      try {
        if (failBillingForTests.contains(encounterId)) {
          throw new CompletionException('Test billing failure');
        }
        if (
          [
            SELECT COUNT()
            FROM Superbill__c
            WHERE Encounter__c = :encounterId
          ] == 0
        ) {
          ClaimReadinessController.prepareForFinishedEncounter(encounterId);
        }
      } catch (Exception e) {
        Database.rollback(billingSavepoint);
        failures.add(
          'Billing handoff failed. Review billing configuration and retry.'
        );
      }
      Database.update(
        new Encounter__c(
          Id = encounterId,
          Completion_Handoff_Status__c = failures.isEmpty()
            ? 'Completed'
            : 'Failed',
          Completion_Handoff_Error__c = failures.isEmpty()
            ? null
            : String.join(failures, ' ')
        ),
        false
      );
    }
  }

  @AuraEnabled(cacheable=true)
  public static Checklist getChecklist(Id encounterId) {
    List<Encounter__c> rows = [
      SELECT
        Id,
        Practitioner__c,
        Patient__r.Allergy_Review_Status__c,
        Completion_Handoff_Status__c,
        Completion_Handoff_Error__c,
        Completion_Handoff_Queued_At__c,
        Status__c
      FROM Encounter__c
      WHERE Id = :encounterId
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw new AuraHandledException('Encounter was not found.');
    }
    Encounter__c encounter = rows[0];
    Checklist checklist = new Checklist();
    checklist.items = new List<ChecklistItem>();
    checklist.items.add(
      item('Attending assigned', encounter.Practitioner__c != null)
    );
    checklist.items.add(
      item(
        'Allergies reviewed',
        encounter.Patient__r.Allergy_Review_Status__c != null &&
          encounter.Patient__r.Allergy_Review_Status__c != 'Unknown'
      )
    );
    checklist.items.add(
      item(
        'Encounter diagnosis recorded',
        [
          SELECT COUNT()
          FROM EncounterDiagnosis__c
          WHERE Encounter__c = :encounterId
        ] > 0
      )
    );
    checklist.items.add(
      item(
        'Clinical note signed',
        [
          SELECT COUNT()
          FROM ClinicalNote__c
          WHERE Encounter__c = :encounterId AND Status__c = 'Signed'
        ] > 0
      )
    );
    checklist.handoffStatus = encounter.Completion_Handoff_Status__c;
    checklist.handoffError = encounter.Completion_Handoff_Error__c;
    checklist.canRetry =
      encounter.Status__c == 'Finished' &&
      encounter.Completion_Handoff_Status__c != 'Completed' &&
      !recentlyQueued(encounter);
    return checklist;
  }

  @AuraEnabled
  public static void retryHandoff(Id encounterId) {
    if (!Encounter__c.SObjectType.getDescribe().isUpdateable()) {
      throw new AuraHandledException('You cannot update encounters.');
    }
    List<Encounter__c> rows = [
      SELECT
        Id,
        Status__c,
        Completion_Handoff_Status__c,
        Completion_Handoff_Queued_At__c
      FROM Encounter__c
      WHERE Id = :encounterId
      LIMIT 1
      FOR UPDATE
    ];
    if (rows.isEmpty() || rows[0].Status__c != 'Finished') {
      throw new AuraHandledException(
        'Only finished encounters can retry completion handoff.'
      );
    }
    if (rows[0].Completion_Handoff_Status__c == 'Completed') {
      throw new AuraHandledException(
        'Completion handoff is already completed.'
      );
    }
    if (recentlyQueued(rows[0])) {
      throw new AuraHandledException('Completion handoff is already pending.');
    }
    update new Encounter__c(
      Id = encounterId,
      Completion_Handoff_Status__c = 'Pending',
      Completion_Handoff_Error__c = null,
      Completion_Handoff_Queued_At__c = Datetime.now()
    );
    enqueue(new List<Id>{ encounterId });
  }

  private static ChecklistItem item(String label, Boolean complete) {
    ChecklistItem result = new ChecklistItem();
    result.label = label;
    result.complete = complete;
    return result;
  }
  private static Boolean recentlyQueued(Encounter__c encounter) {
    return encounter.Completion_Handoff_Status__c == 'Pending' &&
      encounter.Completion_Handoff_Queued_At__c != null &&
      encounter.Completion_Handoff_Queued_At__c >
      Datetime.now().addMinutes(-15);
  }
  private class CompletionException extends Exception {
  }
}
