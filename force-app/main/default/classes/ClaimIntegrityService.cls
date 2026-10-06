public with sharing class ClaimIntegrityService {
  private static final Set<String> FROZEN = new Set<String>{
    'Ready',
    'Exported',
    'Voided'
  };
  private static Set<Id> workflowTransitions = new Set<Id>();

  public static void saveTransition(Superbill__c superbill) {
    workflowTransitions.add(superbill.Id);
    try {
      update superbill;
    } finally {
      workflowTransitions.remove(superbill.Id);
    }
  }

  public static void enforceSuperbillUpdates(
    List<Superbill__c> rows,
    Map<Id, Superbill__c> oldMap
  ) {
    Set<String> transitionFields = new Set<String>{
      Superbill__c.Status__c.getDescribe().getName(),
      Superbill__c.Ready_Date__c.getDescribe().getName(),
      Superbill__c.Validation_Messages__c.getDescribe().getName()
    };
    Map<String, Schema.SObjectField> fields = Superbill__c.SObjectType.getDescribe()
      .fields.getMap();
    for (Superbill__c row : rows) {
      Superbill__c old = oldMap.get(row.Id);
      if (!FROZEN.contains(old.Status__c))
        continue;
      Boolean permittedTransition =
        workflowTransitions.contains(row.Id) &&
        ((old.Status__c == 'Ready' &&
        new Set<String>{ 'Needs Review', 'Exported' }
          .contains(row.Status__c)) ||
        (old.Status__c == 'Exported' &&
        row.Status__c == 'Needs Review'));
      for (String field : fields.keySet()) {
        Schema.DescribeFieldResult description = fields.get(field)
          .getDescribe();
        if (!description.isCustom() || description.isCalculated())
          continue;
        if (
          row.get(field) != old.get(field) &&
          !(permittedTransition &&
          transitionFields.contains(description.getName()))
        ) {
          row.addError(
            'Approved claim records are immutable. Use the billing workflow to reopen an eligible claim.'
          );
          break;
        }
      }
    }
  }

  public static void enforceSuperbillDeletes(List<Superbill__c> rows) {
    for (Superbill__c row : rows) {
      if (FROZEN.contains(row.Status__c))
        row.addError('Approved claim records cannot be deleted.');
    }
  }

  public static void enforceChildChanges(
    List<SObject> rows,
    List<SObject> previousRows
  ) {
    Set<Id> parentIds = new Set<Id>();
    for (SObject row : rows)
      parentIds.add((Id) row.get('Superbill__c'));
    if (previousRows != null) {
      for (SObject row : previousRows)
        parentIds.add((Id) row.get('Superbill__c'));
    }
    parentIds.remove(null);
    Map<Id, Superbill__c> parents = new Map<Id, Superbill__c>(
      [SELECT Id, Status__c FROM Superbill__c WHERE Id IN :parentIds FOR UPDATE]
    );
    Map<Id, Id> oldParents = new Map<Id, Id>();
    if (previousRows != null) {
      for (SObject row : previousRows)
        oldParents.put((Id) row.get('Id'), (Id) row.get('Superbill__c'));
    }
    for (SObject row : rows) {
      Superbill__c parent = parents.get((Id) row.get('Superbill__c'));
      Superbill__c oldParent = parents.get(oldParents.get((Id) row.get('Id')));
      if (
        (parent != null && FROZEN.contains(parent.Status__c)) ||
        (oldParent != null && FROZEN.contains(oldParent.Status__c))
      ) {
        row.addError(
          'Charges and diagnoses on approved claims are immutable. Reopen the claim through the billing workflow first.'
        );
      }
    }
  }

  public static void requireNoQueuedSubmission(
    Id superbillId,
    Id excludedSubmissionId
  ) {
    if (
      [
        SELECT COUNT()
        FROM Claim_Submission__c
        WHERE
          Superbill__c = :superbillId
          AND Status__c = 'Queued'
          AND Id != :excludedSubmissionId
      ] > 0
    ) {
      throw new ClaimSubmissionProviderFactory.ClaimSubmissionException(
        'This superbill already has a queued submission.'
      );
    }
  }
}
