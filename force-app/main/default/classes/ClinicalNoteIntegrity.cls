public with sharing class ClinicalNoteIntegrity {
  private static final List<Schema.SObjectField> CLINICAL_FIELDS = new List<Schema.SObjectField>{
    ClinicalNote__c.Patient__c,
    ClinicalNote__c.Encounter__c,
    ClinicalNote__c.Author__c,
    ClinicalNote__c.Note_Type__c,
    ClinicalNote__c.Body__c,
    ClinicalNote__c.Status__c,
    ClinicalNote__c.Signed_Date__c,
    ClinicalNote__c.Signed_By__c,
    ClinicalNote__c.Addendum_To__c
  };

  public static void beforeSave(
    List<ClinicalNote__c> notes,
    Map<Id, ClinicalNote__c> oldMap
  ) {
    Set<Id> parentIds = new Set<Id>();
    for (ClinicalNote__c note : notes) {
      if (note.Addendum_To__c != null) {
        parentIds.add(note.Addendum_To__c);
      }
    }
    Map<Id, ClinicalNote__c> parents = new Map<Id, ClinicalNote__c>(
      [
        SELECT Id, Patient__c, Encounter__c, Status__c
        FROM ClinicalNote__c
        WHERE Id IN :parentIds
      ]
    );
    for (ClinicalNote__c note : notes) {
      ClinicalNote__c prior = oldMap == null ? null : oldMap.get(note.Id);
      if (prior != null && prior.Status__c == 'Signed') {
        for (Schema.SObjectField field : CLINICAL_FIELDS) {
          String apiName = field.getDescribe().getName();
          if (note.get(apiName) != prior.get(apiName)) {
            note.addError(
              'Signed notes cannot be changed. Create an addendum instead.'
            );
            break;
          }
        }
        continue;
      }
      if (note.Addendum_To__c != null) {
        ClinicalNote__c parent = parents.get(note.Addendum_To__c);
        if (
          parent == null ||
          parent.Status__c != 'Signed' ||
          parent.Patient__c != note.Patient__c ||
          parent.Encounter__c != note.Encounter__c ||
          parent.Id == note.Id
        ) {
          note.addError(
            'An addendum must refer to a signed note for the same patient and encounter.'
          );
        }
      }
      if (note.Status__c == 'Signed') {
        if (!hasClinicalContent(note.Body__c)) {
          note.addError('Enter clinical note content before signing.');
          continue;
        }
        note.Signed_By__c = UserInfo.getUserId();
        note.Signed_Date__c = Datetime.now();
      } else {
        note.Signed_By__c = null;
        note.Signed_Date__c = null;
      }
    }
  }

  private static Boolean hasClinicalContent(String body) {
    if (String.isBlank(body)) {
      return false;
    }
    // Rich-text persistence can decode &nbsp; into a Unicode separator before triggers run.
    // Decode after stripping markup so a clinician's escaped comparison text remains content.
    String content = body.replaceAll('(?s)<!--.*?-->', '')
      .replaceAll('<[^>]*>', '')
      .unescapeHtml4()
      .replaceAll('[\\s\\p{Z}\\p{Cf}]', '');
    return !String.isBlank(content);
  }

  public static void beforeDelete(List<ClinicalNote__c> notes) {
    for (ClinicalNote__c note : notes) {
      if (note.Status__c == 'Signed') {
        note.addError(
          'Signed notes cannot be deleted. Create an addendum instead.'
        );
      }
    }
  }
}
