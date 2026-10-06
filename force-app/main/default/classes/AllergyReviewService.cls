public with sharing class AllergyReviewService {
  public static final String UNKNOWN = 'Unknown';
  public static final String NONE_KNOWN = 'No known allergies';
  public static final String RECORDED = 'Allergies recorded';

  public static void validatePatients(
    List<Patient__c> patients,
    Map<Id, Patient__c> oldMap
  ) {
    Set<Id> changedIds = new Set<Id>();
    List<Patient__c> changed = new List<Patient__c>();
    for (Patient__c patient : patients) {
      Patient__c prior = oldMap == null ? null : oldMap.get(patient.Id);
      if (
        prior == null ||
        patient.Allergy_Review_Status__c != prior.Allergy_Review_Status__c ||
        patient.Allergy_Reviewed_At__c != prior.Allergy_Reviewed_At__c ||
        patient.Allergy_Reviewed_By__c != prior.Allergy_Reviewed_By__c
      ) {
        changed.add(patient);
        if (patient.Id != null)
          changedIds.add(patient.Id);
      }
    }
    if (changed.isEmpty())
      return;
    Set<Id> withAllergies = activePatientIds(changedIds);
    for (Patient__c patient : changed) {
      String status = patient.Allergy_Review_Status__c;
      if (status == NONE_KNOWN && withAllergies.contains(patient.Id)) {
        patient.addError(
          'Active allergies must be reconciled before recording no known allergies.'
        );
      } else if (status == RECORDED && !withAllergies.contains(patient.Id)) {
        patient.addError(
          'Add an active allergy before confirming allergies recorded.'
        );
      } else if (status == NONE_KNOWN || status == RECORDED) {
        patient.Allergy_Reviewed_At__c = System.now();
        patient.Allergy_Reviewed_By__c = UserInfo.getUserId();
      } else {
        patient.Allergy_Review_Status__c = UNKNOWN;
        patient.Allergy_Reviewed_At__c = null;
        patient.Allergy_Reviewed_By__c = null;
      }
    }
  }

  private static Set<Id> activePatientIds(Set<Id> patientIds) {
    Set<Id> result = new Set<Id>();
    if (!patientIds.isEmpty()) {
      for (AggregateResult row : [
        SELECT Patient__c patientId
        FROM AllergyIntolerance__c
        WHERE Patient__c IN :patientIds AND Clinical_Status__c = 'Active'
        GROUP BY Patient__c
      ]) {
        result.add((Id) row.get('patientId'));
      }
    }
    return result;
  }

  public static void invalidate(
    List<AllergyIntolerance__c> changed,
    List<AllergyIntolerance__c> prior
  ) {
    Set<Id> patientIds = new Set<Id>();
    if (changed != null)
      for (AllergyIntolerance__c row : changed)
        patientIds.add(row.Patient__c);
    if (prior != null)
      for (AllergyIntolerance__c row : prior)
        patientIds.add(row.Patient__c);
    patientIds.remove(null);
    if (patientIds.isEmpty())
      return;
    List<Patient__c> patients = [
      SELECT
        Id,
        Allergy_Review_Status__c,
        Allergy_Reviewed_At__c,
        Allergy_Reviewed_By__c
      FROM Patient__c
      WHERE Id IN :patientIds
      FOR UPDATE
    ];
    for (Patient__c patient : patients) {
      patient.Allergy_Review_Status__c = UNKNOWN;
      patient.Allergy_Reviewed_At__c = null;
      patient.Allergy_Reviewed_By__c = null;
    }
    update patients;
  }
}
