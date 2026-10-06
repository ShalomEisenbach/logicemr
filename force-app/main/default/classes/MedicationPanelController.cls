public with sharing class MedicationPanelController {
  private static final Integer MAX_RESULTS = 200;
  private static final String STATUS_ACTIVE = 'Active';
  private static final String STATUS_STOPPED = 'Stopped';
  private static final String INTENT_ORDER = 'Order';
  private static final String CODE_SYSTEM_RXNORM = 'RxNorm';
  private static final Set<String> ALLOWED_ROUTES = new Set<String>{
    'Oral',
    'Intravenous',
    'Intramuscular',
    'Subcutaneous',
    'Topical',
    'Inhalation',
    'Transdermal',
    'Other'
  };
  private static final Set<String> ALLOWED_INTENTS = new Set<String>{
    'Order',
    'Plan',
    'Proposal'
  };
  private static final Set<String> ALLOWED_STATUSES = new Set<String>{
    'Active',
    'On Hold',
    'Cancelled',
    'Completed',
    'Stopped',
    'Draft'
  };

  public class MedicationPanelView {
    @AuraEnabled
    public List<MedicationRequest__c> activeOrders;
    @AuraEnabled
    public List<MedicationStatement__c> reportedMedications;
  }

  @AuraEnabled(cacheable=true)
  public static MedicationPanelView getMedications(Id patientId) {
    MedicationPanelView view = new MedicationPanelView();
    view.activeOrders = new List<MedicationRequest__c>();
    view.reportedMedications = new List<MedicationStatement__c>();
    if (patientId == null) {
      return view;
    }

    Set<Id> patientIds = new Set<Id>{ patientId };
    view.activeOrders = queryActiveOrders(patientIds);
    view.reportedMedications = queryReportedMedications(patientIds);
    return view;
  }

  @AuraEnabled
  public static MedicationRequest__c addMedication(
    Id patientId,
    String codeSystem,
    String code,
    String display,
    Id codeReferenceId,
    String dosageText,
    Decimal doseQuantity,
    String doseUnit,
    String frequency,
    String route,
    String intent,
    String status,
    Id requesterId
  ) {
    MedicationRequest__c request = buildMedication(
      patientId,
      codeSystem,
      code,
      display,
      codeReferenceId,
      dosageText,
      doseQuantity,
      doseUnit,
      frequency,
      route,
      intent,
      status,
      requesterId
    );
    requirePrescriptionAccess(request, true);
    insert request;
    return request;
  }

  private static MedicationRequest__c buildMedication(
    Id patientId,
    String codeSystem,
    String code,
    String display,
    Id codeReferenceId,
    String dosageText,
    Decimal doseQuantity,
    String doseUnit,
    String frequency,
    String route,
    String intent,
    String status,
    Id requesterId
  ) {
    if (patientId == null) {
      throw new AuraHandledException('Patient Id is required.');
    }
    if (String.isBlank(display)) {
      throw new AuraHandledException('Medication display is required.');
    }
    if (String.isBlank(codeSystem) || codeSystem != CODE_SYSTEM_RXNORM) {
      throw new AuraHandledException('Code system must be RxNorm.');
    }
    if (!String.isBlank(route) && !ALLOWED_ROUTES.contains(route)) {
      throw new AuraHandledException('Route is not a valid medication route.');
    }
    String resolvedIntent = String.isBlank(intent) ? INTENT_ORDER : intent;
    if (!ALLOWED_INTENTS.contains(resolvedIntent)) {
      throw new AuraHandledException(
        'Intent must be Order, Plan, or Proposal.'
      );
    }
    String resolvedStatus = String.isBlank(status) ? STATUS_ACTIVE : status;
    if (!ALLOWED_STATUSES.contains(resolvedStatus)) {
      throw new AuraHandledException(
        'Status is not a valid medication status.'
      );
    }

    MedicationRequest__c request = new MedicationRequest__c(
      Patient__c = patientId,
      Status__c = resolvedStatus,
      Intent__c = resolvedIntent,
      Medication_Ref__c = codeReferenceId,
      Medication_Code_System__c = codeSystem,
      Medication_Code__c = code,
      Medication_Display__c = display,
      Dosage_Text__c = dosageText,
      Dose_Quantity__c = doseQuantity,
      Dose_Unit__c = doseUnit,
      Frequency__c = frequency,
      Route__c = route,
      Requester__c = requesterId,
      Authored_On__c = System.now()
    );
    return request;
  }

  @AuraEnabled
  public static void renewOrders(List<Id> requestIds) {
    if (requestIds == null || requestIds.isEmpty()) {
      return;
    }
    requirePrescriptionAccess(
      new MedicationRequest__c(
        Status__c = STATUS_ACTIVE,
        Authored_On__c = System.now()
      ),
      false
    );

    Datetime authoredOn = System.now();
    List<MedicationRequest__c> requests = [
      SELECT Id, Status__c, Authored_On__c
      FROM MedicationRequest__c
      WHERE Id IN :requestIds
    ];
    for (MedicationRequest__c request : requests) {
      request.Status__c = STATUS_ACTIVE;
      request.Authored_On__c = authoredOn;
    }
    if (!requests.isEmpty()) {
      update requests;
    }
  }

  public class PrescriptionInput {
    @AuraEnabled
    public Id patientId;
    @AuraEnabled
    public String codeSystem;
    @AuraEnabled
    public String code;
    @AuraEnabled
    public String display;
    @AuraEnabled
    public Id codeReferenceId;
    @AuraEnabled
    public String dosageText;
    @AuraEnabled
    public Decimal doseQuantity;
    @AuraEnabled
    public String doseUnit;
    @AuraEnabled
    public String frequency;
    @AuraEnabled
    public String route;
    @AuraEnabled
    public String intent;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Id requesterId;
    @AuraEnabled
    public Decimal dispenseQuantity;
    @AuraEnabled
    public Integer refills;
    @AuraEnabled
    public String pharmacy;
    @AuraEnabled
    public Date startDate;
    @AuraEnabled
    public Date endDate;
  }

  @AuraEnabled
  public static MedicationRequest__c addPrescription(PrescriptionInput input) {
    if (input == null)
      throw new AuraHandledException('Prescription details are required.');
    if (input.dispenseQuantity != null && input.dispenseQuantity <= 0) {
      throw new AuraHandledException(
        'Dispense quantity must be greater than zero.'
      );
    }
    if (input.refills != null && (input.refills < 0 || input.refills > 999)) {
      throw new AuraHandledException('Refills must be between 0 and 999.');
    }
    if (
      input.endDate != null &&
      input.startDate != null &&
      input.endDate < input.startDate
    ) {
      throw new AuraHandledException(
        'End date must be on or after start date.'
      );
    }
    String status = String.isBlank(input.status) ? 'Draft' : input.status;
    if (
      status == STATUS_ACTIVE &&
      (String.isBlank(input.intent) || input.intent == INTENT_ORDER) &&
      (input.requesterId == null ||
      input.dispenseQuantity == null ||
      String.isBlank(input.dosageText))
    ) {
      throw new AuraHandledException(
        'Active prescriptions require a prescriber, dosage instructions, and dispense quantity.'
      );
    }
    MedicationRequest__c request = buildMedication(
      input.patientId,
      input.codeSystem,
      input.code,
      input.display,
      input.codeReferenceId,
      input.dosageText,
      input.doseQuantity,
      input.doseUnit,
      input.frequency,
      input.route,
      input.intent,
      status,
      input.requesterId
    );
    request.Dispense_Quantity__c = input.dispenseQuantity;
    request.Refills__c = input.refills == null ? 0 : input.refills;
    request.Pharmacy__c = input.pharmacy;
    request.Start_Date__c = input.startDate;
    request.End_Date__c = input.endDate;
    requirePrescriptionAccess(request, true);
    insert request;
    return request;
  }

  @AuraEnabled
  public static void activatePrescription(Id requestId) {
    requirePrescriptionAccess(
      new MedicationRequest__c(
        Status__c = STATUS_ACTIVE,
        Authored_On__c = System.now()
      ),
      false
    );
    MedicationRequest__c request = [
      SELECT
        Id,
        Status__c,
        Intent__c,
        Requester__c,
        Dosage_Text__c,
        Dispense_Quantity__c
      FROM MedicationRequest__c
      WHERE Id = :requestId
      FOR UPDATE
    ];
    if (request.Status__c != 'Draft')
      throw new AuraHandledException(
        'Only draft prescriptions can be activated.'
      );
    if (request.Intent__c != INTENT_ORDER)
      throw new AuraHandledException(
        'Only medication orders can be activated as prescriptions.'
      );
    if (
      request.Requester__c == null ||
      String.isBlank(request.Dosage_Text__c) ||
      request.Dispense_Quantity__c == null ||
      request.Dispense_Quantity__c <= 0
    ) {
      throw new AuraHandledException(
        'Enter a prescriber, dosage instructions, and dispense quantity before activating.'
      );
    }
    request.Status__c = STATUS_ACTIVE;
    request.Authored_On__c = System.now();
    update request;
  }

  private static void requirePrescriptionAccess(
    MedicationRequest__c request,
    Boolean creating
  ) {
    Schema.DescribeSObjectResult description = MedicationRequest__c.SObjectType.getDescribe();
    if (creating ? !description.isCreateable() : !description.isUpdateable()) {
      throw new AuraHandledException(
        'You do not have permission to save prescriptions.'
      );
    }
    Map<String, Schema.SObjectField> fields = description.fields.getMap();
    for (String fieldName : request.getPopulatedFieldsAsMap().keySet()) {
      if (fieldName == 'Id')
        continue;
      Schema.DescribeFieldResult field = fields.get(fieldName).getDescribe();
      if (creating ? !field.isCreateable() : !field.isUpdateable()) {
        throw new AuraHandledException(
          'You do not have permission to save prescription details.'
        );
      }
    }
  }

  public static void validatePrescriptionChanges(
    List<MedicationRequest__c> requests,
    Map<Id, MedicationRequest__c> oldMap
  ) {
    for (MedicationRequest__c request : requests) {
      if (
        request.Dispense_Quantity__c != null &&
        request.Dispense_Quantity__c <= 0
      ) {
        request.addError('Dispense quantity must be greater than zero.');
      }
      if (request.Refills__c != null && request.Refills__c < 0) {
        request.addError('Refills cannot be negative.');
      }
      if (
        request.Start_Date__c != null &&
        request.End_Date__c != null &&
        request.End_Date__c < request.Start_Date__c
      ) {
        request.addError('End date must be on or after start date.');
      }
      MedicationRequest__c prior = oldMap == null
        ? null
        : oldMap.get(request.Id);
      Boolean prescribingChanged =
        prior != null &&
        (prior.Status__c != STATUS_ACTIVE ||
        prior.Intent__c != request.Intent__c ||
        prior.Requester__c != request.Requester__c ||
        prior.Dosage_Text__c != request.Dosage_Text__c ||
        prior.Dispense_Quantity__c != request.Dispense_Quantity__c);
      if (
        prescribingChanged &&
        request.Status__c == STATUS_ACTIVE &&
        request.Intent__c == INTENT_ORDER &&
        (request.Requester__c == null ||
        String.isBlank(request.Dosage_Text__c) ||
        request.Dispense_Quantity__c == null)
      ) {
        request.addError(
          'Complete the prescriber, dosage instructions, and dispense quantity before activating.'
        );
      }
    }
  }

  @AuraEnabled
  public static void discontinueOrders(List<Id> requestIds) {
    if (requestIds == null || requestIds.isEmpty()) {
      return;
    }
    requirePrescriptionAccess(
      new MedicationRequest__c(Status__c = STATUS_STOPPED),
      false
    );

    List<MedicationRequest__c> requests = [
      SELECT Id, Status__c
      FROM MedicationRequest__c
      WHERE Id IN :requestIds AND Status__c != :STATUS_STOPPED
    ];
    for (MedicationRequest__c request : requests) {
      request.Status__c = STATUS_STOPPED;
    }
    if (!requests.isEmpty()) {
      update requests;
    }
  }

  @AuraEnabled
  public static void deleteOrders(List<Id> requestIds) {
    if (requestIds == null || requestIds.isEmpty()) {
      return;
    }
    if (!MedicationRequest__c.SObjectType.getDescribe().isDeletable()) {
      throw new AuraHandledException(
        'You do not have permission to delete medication orders.'
      );
    }
    delete [SELECT Id FROM MedicationRequest__c WHERE Id IN :requestIds];
  }

  @AuraEnabled
  public static void deleteReportedMedications(List<Id> statementIds) {
    if (statementIds == null || statementIds.isEmpty()) {
      return;
    }
    if (!MedicationStatement__c.SObjectType.getDescribe().isDeletable()) {
      throw new AuraHandledException(
        'You do not have permission to delete reported medications.'
      );
    }
    delete [SELECT Id FROM MedicationStatement__c WHERE Id IN :statementIds];
  }

  private static List<MedicationRequest__c> queryActiveOrders(
    Set<Id> patientIds
  ) {
    return [
      SELECT
        Id,
        Medication_Code_System__c,
        Medication_Code__c,
        Medication_Display__c,
        Status__c,
        Intent__c,
        Dosage_Text__c,
        Dose_Quantity__c,
        Dose_Unit__c,
        Frequency__c,
        Route__c,
        Authored_On__c,
        Dispense_Quantity__c,
        Refills__c,
        Pharmacy__c,
        Start_Date__c,
        End_Date__c
      FROM MedicationRequest__c
      WHERE
        Patient__c IN :patientIds
        AND Status__c IN ('Active', 'Draft', 'On Hold')
      ORDER BY Medication_Display__c ASC NULLS LAST
      LIMIT :MAX_RESULTS
    ];
  }

  private static List<MedicationStatement__c> queryReportedMedications(
    Set<Id> patientIds
  ) {
    return [
      SELECT
        Id,
        Medication_Code_System__c,
        Medication_Code__c,
        Medication_Display__c,
        Status__c,
        Source__c,
        Dosage_Text__c
      FROM MedicationStatement__c
      WHERE Patient__c IN :patientIds AND Status__c = :STATUS_ACTIVE
      ORDER BY Medication_Display__c ASC NULLS LAST
      LIMIT :MAX_RESULTS
    ];
  }
}
