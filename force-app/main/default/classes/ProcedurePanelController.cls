public with sharing class ProcedurePanelController {
  private static final Integer MAX_RESULTS = 200;
  private static final String STATUS_COMPLETED = 'Completed';
  private static final Set<String> ALLOWED_CODE_SYSTEMS = new Set<String>{
    'CPT',
    'SNOMED'
  };

  @AuraEnabled(cacheable=true)
  public static List<Procedure__c> getProcedures(Id patientId) {
    if (patientId == null) {
      return new List<Procedure__c>();
    }
    return [
      SELECT
        Id,
        Procedure_Display__c,
        Procedure_Code__c,
        Procedure_Code_System__c,
        Category__c,
        Status__c,
        Performed_DateTime__c,
        Encounter__c,
        Encounter__r.Name,
        Notes__c
      FROM Procedure__c
      WHERE Patient__c = :patientId
      ORDER BY
        Performed_DateTime__c DESC NULLS LAST,
        Procedure_Display__c ASC NULLS LAST
      LIMIT :MAX_RESULTS
    ];
  }

  @AuraEnabled
  public static Procedure__c addProcedure(
    Id patientId,
    String codeSystem,
    String code,
    String display,
    Id codeReferenceId,
    String category,
    String status,
    Datetime performedDateTime,
    String notes
  ) {
    return createProcedure(
      patientId,
      null,
      codeSystem,
      code,
      display,
      codeReferenceId,
      category,
      status,
      performedDateTime,
      notes
    );
  }

  @AuraEnabled
  public static Procedure__c addLinkedProcedure(
    Id patientId,
    Id encounterId,
    String codeSystem,
    String code,
    String display,
    Id codeReferenceId,
    String category,
    String status,
    Datetime performedDateTime,
    String notes
  ) {
    return createProcedure(
      patientId,
      encounterId,
      codeSystem,
      code,
      display,
      codeReferenceId,
      category,
      status,
      performedDateTime,
      notes
    );
  }

  private static Procedure__c createProcedure(
    Id patientId,
    Id encounterId,
    String codeSystem,
    String code,
    String display,
    Id codeReferenceId,
    String category,
    String status,
    Datetime performedDateTime,
    String notes
  ) {
    if (patientId == null) {
      throw new AuraHandledException('Patient Id is required.');
    }
    if (String.isBlank(display)) {
      throw new AuraHandledException('Procedure display is required.');
    }
    if (
      String.isBlank(codeSystem) || !ALLOWED_CODE_SYSTEMS.contains(codeSystem)
    ) {
      throw new AuraHandledException('Code system must be CPT or SNOMED.');
    }
    if (!Procedure__c.SObjectType.getDescribe().isCreateable()) {
      throw handledError('You do not have permission to create procedures.');
    }

    Procedure__c procedure = new Procedure__c(
      Patient__c = patientId,
      Procedure_Code_System__c = codeSystem,
      Procedure_Display__c = display,
      Status__c = String.isBlank(status) ? STATUS_COMPLETED : status
    );
    if (encounterId != null)
      procedure.Encounter__c = encounterId;
    if (codeReferenceId != null)
      procedure.Procedure_Ref__c = codeReferenceId;
    if (code != null)
      procedure.Procedure_Code__c = code;
    if (category != null)
      procedure.Category__c = category;
    if (performedDateTime != null)
      procedure.Performed_DateTime__c = performedDateTime;
    if (notes != null)
      procedure.Notes__c = notes;
    Map<String, Schema.SObjectField> fields = Procedure__c.SObjectType.getDescribe()
      .fields.getMap();
    for (String fieldName : procedure.getPopulatedFieldsAsMap().keySet()) {
      if (!fields.get(fieldName).getDescribe().isCreateable()) {
        throw handledError(
          'You do not have permission to create these procedure details.'
        );
      }
    }
    if (encounterId != null) {
      List<Encounter__c> encounters;
      try {
        encounters = [
          SELECT Id, Patient__c
          FROM Encounter__c
          WHERE Id = :encounterId
          WITH USER_MODE
          LIMIT 1
        ];
      } catch (QueryException error) {
        throw handledError('Select an accessible encounter for this patient.');
      }
      if (encounters.isEmpty() || encounters[0].Patient__c != patientId) {
        throw handledError('Select an encounter for this patient.');
      }
    }
    try {
      insert as user procedure;
    } catch (DmlException error) {
      throw handledError(
        'Unable to save the procedure. Check your access and procedure details.'
      );
    }
    return procedure;
  }

  @AuraEnabled
  public static void completeProcedures(List<Id> procedureIds) {
    if (procedureIds == null || procedureIds.isEmpty()) {
      return;
    }
    if (
      !Procedure__c.SObjectType.getDescribe().isUpdateable() ||
      !Procedure__c.Status__c.getDescribe().isUpdateable()
    ) {
      throw handledError('You do not have permission to complete procedures.');
    }

    List<Procedure__c> existing = [
      SELECT Id, Status__c
      FROM Procedure__c
      WHERE Id IN :procedureIds AND Status__c != :STATUS_COMPLETED
      WITH USER_MODE
    ];
    List<Procedure__c> procedures = new List<Procedure__c>();
    for (Procedure__c procedure : existing) {
      procedures.add(
        new Procedure__c(Id = procedure.Id, Status__c = STATUS_COMPLETED)
      );
    }
    if (!procedures.isEmpty()) {
      try {
        update as user procedures;
      } catch (DmlException error) {
        throw handledError(
          'Unable to complete the procedure. Check your access.'
        );
      }
    }
  }

  @AuraEnabled
  public static void deleteProcedures(List<Id> procedureIds) {
    if (procedureIds == null || procedureIds.isEmpty()) {
      return;
    }
    if (!Procedure__c.SObjectType.getDescribe().isDeletable()) {
      throw handledError('You do not have permission to delete procedures.');
    }
    List<Procedure__c> procedures = [
      SELECT Id
      FROM Procedure__c
      WHERE Id IN :procedureIds
      WITH USER_MODE
    ];
    try {
      delete as user procedures;
    } catch (DmlException error) {
      throw handledError('Unable to delete the procedure. Check your access.');
    }
  }

  private static AuraHandledException handledError(String message) {
    AuraHandledException error = new AuraHandledException(message);
    error.setMessage(message);
    return error;
  }
}
