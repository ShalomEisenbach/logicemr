public with sharing class EligibilityCheckController {
  private static final Integer MAX_CHECKS = 50;
  private static final String RUN_ELIGIBILITY_PERMISSION = 'LogicEMR_Run_Eligibility';

  @TestVisible
  static Boolean runEligibilityOverride;

  public class QueueResult {
    @AuraEnabled
    public List<QueueRow> rows = new List<QueueRow>();
    @AuraEnabled
    public Boolean hasMore;
  }

  public class QueueRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String patient;
    @AuraEnabled
    public String payer;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Datetime checkedAt;
    @AuraEnabled
    public String mode;
    @AuraEnabled
    public String traceId;
    @AuraEnabled
    public String error;
    @AuraEnabled
    public Boolean canRetry;
  }

  // Imperative and uncached so polling always sees newly completed callouts.
  @AuraEnabled
  public static QueueResult getWorkQueue(
    String outcome,
    String payer,
    String patient,
    Date startDate,
    Date endDate
  ) {
    requireRunEligibility();
    if (startDate != null && endDate != null && startDate > endDate) {
      throw auraError('Start date must be on or before end date.');
    }
    List<String> conditions = new List<String>();
    Map<String, Object> binds = new Map<String, Object>();
    if (outcome == 'Success') {
      conditions.add('Status__c IN (\'Active\', \'Inactive\')');
    } else if (outcome == 'Error' || outcome == 'Pending') {
      conditions.add('Status__c = :outcome');
      binds.put('outcome', outcome);
    } else if (String.isNotBlank(outcome) && outcome != 'All') {
      throw auraError('Choose a valid outcome.');
    }
    if (String.isNotBlank(payer)) {
      conditions.add(
        '(Coverage__r.Payer__r.Name LIKE :payer OR Coverage__r.Payer__r.Payer_Identifier__c LIKE :payer)'
      );
      binds.put('payer', searchPattern(payer));
    }
    if (String.isNotBlank(patient)) {
      conditions.add(
        '(Patient__r.Name LIKE :patient OR Patient__r.First_Name__c LIKE :patient OR Patient__r.Last_Name__c LIKE :patient OR Patient__r.MRN__c LIKE :patient)'
      );
      binds.put('patient', searchPattern(patient));
    }
    if (startDate != null) {
      binds.put(
        'startAt',
        Datetime.newInstance(startDate, Time.newInstance(0, 0, 0, 0))
      );
      conditions.add(
        '(Checked_Date__c >= :startAt OR (Checked_Date__c = NULL AND CreatedDate >= :startAt))'
      );
    }
    if (endDate != null) {
      binds.put(
        'endAt',
        Datetime.newInstance(endDate.addDays(1), Time.newInstance(0, 0, 0, 0))
      );
      conditions.add(
        '(Checked_Date__c < :endAt OR (Checked_Date__c = NULL AND CreatedDate < :endAt))'
      );
    }
    String query =
      'SELECT Id, Name, Patient__c, Patient__r.Name, Coverage__c, Coverage__r.Patient__c, ' +
      'Coverage__r.Payer__r.Name, Status__c, Checked_Date__c, CreatedDate, Application_Mode__c, ' +
      'Stedi_Trace_Id__c, Error_Message__c FROM Eligibility_Check__c';
    if (!conditions.isEmpty()) {
      query += ' WHERE ' + String.join(conditions, ' AND ');
    }
    query += ' ORDER BY CreatedDate DESC, Id DESC LIMIT 101';
    List<Eligibility_Check__c> checks = Database.queryWithBinds(
      query,
      binds,
      AccessLevel.USER_MODE
    );
    QueueResult result = new QueueResult();
    result.hasMore = checks.size() > 100;
    for (Integer i = 0; i < Math.min(checks.size(), 100); i++) {
      Eligibility_Check__c check = checks[i];
      QueueRow row = new QueueRow();
      row.id = check.Id;
      row.name = check.Name;
      row.patient = check.Patient__r?.Name;
      row.payer = check.Coverage__r?.Payer__r?.Name;
      row.status = check.Status__c;
      row.checkedAt = check.Checked_Date__c == null
        ? check.CreatedDate
        : check.Checked_Date__c;
      row.mode = String.isBlank(check.Application_Mode__c)
        ? 'Unknown'
        : check.Application_Mode__c;
      row.traceId = check.Stedi_Trace_Id__c;
      row.error = check.Error_Message__c;
      row.canRetry =
        check.Status__c == 'Error' &&
        check.Coverage__c != null &&
        check.Patient__c != null &&
        check.Coverage__r.Patient__c == check.Patient__c;
      result.rows.add(row);
    }
    return result;
  }

  private static String searchPattern(String value) {
    return '%' +
      value.trim()
        .replace('\\', '\\\\')
        .replace('%', '\\%')
        .replace('_', '\\_') +
      '%';
  }

  @AuraEnabled
  public static Eligibility_Check__c retryCheck(Id checkId) {
    requireRunEligibility();
    if (checkId == null) {
      throw auraError('Eligibility check Id is required.');
    }
    List<Eligibility_Check__c> checks = [
      SELECT
        Id,
        Status__c,
        Patient__c,
        Coverage__c,
        Coverage__r.Patient__c,
        Service_Type__c,
        Service_Date__c
      FROM Eligibility_Check__c
      WHERE Id = :checkId
      WITH USER_MODE
      LIMIT 1
    ];
    if (checks.isEmpty()) {
      throw auraError('Eligibility check was not found.');
    }
    Eligibility_Check__c check = checks[0];
    if (check.Status__c != 'Error') {
      throw auraError('Only failed eligibility checks can be retried.');
    }
    if (
      check.Coverage__c == null ||
      check.Patient__c == null ||
      check.Coverage__r.Patient__c != check.Patient__c
    ) {
      throw auraError(
        'The original patient and coverage must be available to retry.'
      );
    }
    try {
      return EligibilityService.runCheck(
        check.Patient__c,
        check.Coverage__c,
        check.Service_Type__c,
        check.Service_Date__c
      );
    } catch (Exception e) {
      throw auraError(e.getMessage());
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<Eligibility_Check__c> getChecks(Id coverageId) {
    if (coverageId == null) {
      return new List<Eligibility_Check__c>();
    }
    return [
      SELECT
        Id,
        Name,
        Status__c,
        Plan_Name__c,
        Copay__c,
        Deductible__c,
        Deductible_Remaining__c,
        Coinsurance_Percent__c,
        Out_of_Pocket_Max__c,
        Service_Type__c,
        Service_Date__c,
        Checked_Date__c,
        Provider_Used__c,
        Error_Message__c,
        Patient__c,
        Coverage__c
      FROM Eligibility_Check__c
      WHERE Coverage__c = :coverageId
      ORDER BY Checked_Date__c DESC NULLS LAST, CreatedDate DESC
      LIMIT :MAX_CHECKS
    ];
  }

  @AuraEnabled
  public static Eligibility_Check__c runCheck(Id coverageId) {
    return runCheckForService(coverageId, null);
  }

  @AuraEnabled
  public static Eligibility_Check__c runCheckForService(
    Id coverageId,
    Date serviceDate
  ) {
    requireRunEligibility();
    if (coverageId == null) {
      throw auraError('Coverage Id is required.');
    }
    List<Coverage__c> coverages = [
      SELECT Id, Patient__c
      FROM Coverage__c
      WHERE Id = :coverageId
      LIMIT 1
    ];
    if (coverages.isEmpty()) {
      throw auraError('Coverage was not found.');
    }
    try {
      return EligibilityService.runCheck(
        coverages[0].Patient__c,
        coverages[0].Id,
        null,
        serviceDate
      );
    } catch (Exception e) {
      throw auraError(e.getMessage());
    }
  }

  private static void requireRunEligibility() {
    Boolean allowed = runEligibilityOverride != null
      ? runEligibilityOverride
      : FeatureManagement.checkPermission(RUN_ELIGIBILITY_PERMISSION);
    if (!allowed) {
      throw auraError('You do not have permission to run eligibility checks.');
    }
  }

  private static AuraHandledException auraError(String message) {
    AuraHandledException error = new AuraHandledException(message);
    error.setMessage(message);
    return error;
  }
}
