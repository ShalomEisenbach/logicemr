public with sharing class EncounterWorkspaceController {
  @TestVisible
  private static final String STATUS_PLANNED = 'Planned';
  @TestVisible
  private static final String STATUS_ARRIVED = 'Arrived';
  @TestVisible
  private static final String STATUS_IN_PROGRESS = 'In Progress';
  @TestVisible
  private static final String STATUS_FINISHED = 'Finished';
  private static final Integer MAX_DIAGNOSES = 200;
  private static final String CATEGORY_ENCOUNTER_DX = 'Encounter Diagnosis';
  private static final String STATUS_ACTIVE = 'Active';
  private static final Set<String> ALLOWED_CODE_SYSTEMS = new Set<String>{
    'ICD-10',
    'SNOMED'
  };

  private static final Map<String, String> NEXT_STATUS = new Map<String, String>{
    STATUS_PLANNED => STATUS_ARRIVED,
    STATUS_ARRIVED => STATUS_IN_PROGRESS,
    STATUS_IN_PROGRESS => STATUS_FINISHED
  };

  public class DiagnosisRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public Id conditionId;
    @AuraEnabled
    public String display;
    @AuraEnabled
    public String code;
    @AuraEnabled
    public String codeSystem;
    @AuraEnabled
    public String diagnosisType;
    @AuraEnabled
    public Decimal rank;
    @AuraEnabled
    public String status;
  }

  @AuraEnabled
  public static Encounter__c transitionStatus(
    Id encounterId,
    String newStatus
  ) {
    if (encounterId == null) {
      throw new AuraHandledException('Encounter Id is required.');
    }
    if (String.isBlank(newStatus)) {
      throw new AuraHandledException('New status is required.');
    }
    if (
      !Encounter__c.SObjectType.getDescribe().isUpdateable() ||
      !Encounter__c.Status__c.getDescribe().isUpdateable()
    ) {
      throw permissionDenied();
    }

    List<Encounter__c> rows = [
      SELECT Id, Status__c
      FROM Encounter__c
      WHERE Id = :encounterId
      LIMIT 1
      FOR UPDATE
    ];
    if (rows.isEmpty()) {
      throw new AuraHandledException('Encounter was not found.');
    }

    Encounter__c encounter = rows[0];
    if (!isValidTransition(encounter.Status__c, newStatus)) {
      throw new AuraHandledException(
        'Cannot change status from ' +
          String.valueOf(encounter.Status__c) +
          ' to ' +
          newStatus +
          '.'
      );
    }

    encounter.Status__c = newStatus;
    update as user encounter;
    return encounter;
  }

  @AuraEnabled(cacheable=true)
  public static Boolean isValidTransition(
    String currentStatus,
    String newStatus
  ) {
    if (String.isBlank(currentStatus) || String.isBlank(newStatus)) {
      return false;
    }
    return NEXT_STATUS.get(currentStatus) == newStatus;
  }

  @AuraEnabled(cacheable=true)
  public static List<DiagnosisRow> getDiagnoses(Id encounterId) {
    List<DiagnosisRow> rows = new List<DiagnosisRow>();
    if (encounterId == null) {
      return rows;
    }

    for (EncounterDiagnosis__c link : [
      SELECT
        Id,
        Type__c,
        Rank__c,
        Condition__c,
        Condition__r.Diagnosis_Display__c,
        Condition__r.Diagnosis_Code__c,
        Condition__r.Diagnosis_Code_System__c,
        Condition__r.Clinical_Status__c
      FROM EncounterDiagnosis__c
      WHERE Encounter__c = :encounterId
      ORDER BY Rank__c ASC NULLS LAST, Type__c ASC NULLS LAST
      LIMIT :MAX_DIAGNOSES
    ]) {
      DiagnosisRow row = new DiagnosisRow();
      row.id = link.Id;
      row.conditionId = link.Condition__c;
      row.display = link.Condition__r.Diagnosis_Display__c;
      row.code = link.Condition__r.Diagnosis_Code__c;
      row.codeSystem = link.Condition__r.Diagnosis_Code_System__c;
      row.diagnosisType = link.Type__c;
      row.rank = link.Rank__c;
      row.status = link.Condition__r.Clinical_Status__c;
      rows.add(row);
    }
    return rows;
  }

  @AuraEnabled
  public static EncounterDiagnosis__c addDiagnosis(
    Id encounterId,
    String codeSystem,
    String code,
    String display,
    Id codeReferenceId,
    String diagnosisType,
    Decimal rank
  ) {
    if (encounterId == null) {
      throw new AuraHandledException('Encounter Id is required.');
    }
    if (String.isBlank(display)) {
      throw new AuraHandledException('Diagnosis display is required.');
    }
    if (
      String.isBlank(codeSystem) || !ALLOWED_CODE_SYSTEMS.contains(codeSystem)
    ) {
      throw new AuraHandledException('Code system must be ICD-10 or SNOMED.');
    }

    List<Encounter__c> encounters = [
      SELECT Id, Patient__c
      FROM Encounter__c
      WHERE Id = :encounterId
      LIMIT 1
    ];
    if (encounters.isEmpty()) {
      throw new AuraHandledException('Encounter was not found.');
    }

    Condition__c condition = new Condition__c(
      Patient__c = encounters[0].Patient__c,
      Encounter__c = encounterId,
      Category__c = CATEGORY_ENCOUNTER_DX,
      Clinical_Status__c = STATUS_ACTIVE,
      Diagnosis_Ref__c = codeReferenceId,
      Diagnosis_Code_System__c = codeSystem,
      Diagnosis_Code__c = code,
      Diagnosis_Display__c = display
    );
    EncounterDiagnosis__c link = new EncounterDiagnosis__c(
      Encounter__c = encounterId,
      Type__c = diagnosisType,
      Rank__c = rank
    );
    requireCreateAccess(condition);
    requireCreateAccess(link);
    if (!EncounterDiagnosis__c.Condition__c.getDescribe().isCreateable()) {
      throw permissionDenied();
    }
    Savepoint diagnosisSavepoint = Database.setSavepoint();
    try {
      insert as user condition;
      link.Condition__c = condition.Id;
      insert as user link;
    } catch (Exception error) {
      Database.rollback(diagnosisSavepoint);
      throw error;
    }
    return link;
  }

  @AuraEnabled
  public static void deleteDiagnoses(List<Id> encounterDiagnosisIds) {
    if (encounterDiagnosisIds == null || encounterDiagnosisIds.isEmpty()) {
      return;
    }
    if (
      !EncounterDiagnosis__c.SObjectType.getDescribe().isDeletable() ||
      !Condition__c.SObjectType.getDescribe().isDeletable()
    ) {
      throw permissionDenied();
    }

    List<EncounterDiagnosis__c> links = [
      SELECT Id, Condition__c
      FROM EncounterDiagnosis__c
      WHERE Id IN :encounterDiagnosisIds
    ];
    Set<Id> conditionIds = new Set<Id>();
    for (EncounterDiagnosis__c link : links) {
      if (link.Condition__c != null) {
        conditionIds.add(link.Condition__c);
      }
    }
    Savepoint diagnosisSavepoint = Database.setSavepoint();
    try {
      delete as user links;
      if (!conditionIds.isEmpty()) {
        List<Condition__c> conditions = [
          SELECT Id
          FROM Condition__c
          WHERE Id IN :conditionIds AND Category__c = :CATEGORY_ENCOUNTER_DX
        ];
        delete as user conditions;
      }
    } catch (Exception error) {
      Database.rollback(diagnosisSavepoint);
      throw error;
    }
  }

  private static void requireCreateAccess(SObject record) {
    Schema.DescribeSObjectResult description = record.getSObjectType()
      .getDescribe();
    if (!description.isCreateable()) {
      throw permissionDenied();
    }
    Map<String, Schema.SObjectField> fields = description.fields.getMap();
    for (String fieldName : record.getPopulatedFieldsAsMap().keySet()) {
      if (!fields.get(fieldName).getDescribe().isCreateable()) {
        throw permissionDenied();
      }
    }
  }

  private static AuraHandledException permissionDenied() {
    String message = 'Clinical encounter changes require permission to edit the affected records and fields.';
    AuraHandledException error = new AuraHandledException(message);
    error.setMessage(message);
    return error;
  }
}
