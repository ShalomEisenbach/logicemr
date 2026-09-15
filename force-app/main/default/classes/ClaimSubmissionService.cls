public with sharing class ClaimSubmissionService {
  private static final Set<String> PENDING_STATUSES = new Set<String>{
    'Queued'
  };
  private static final Integer PAYLOAD_MAX = 131072;
  private static final Integer ERROR_MAX = 32768;
  private static final Integer PROVIDER_STATUS_MAX = 80;
  private static final Integer PROVIDER_REFERENCE_MAX = 100;
  private static final Integer STALE_QUEUE_MINUTES = 15;
  @TestVisible
  private static Boolean skipEnqueue;

  public static Claim_Submission__c queue(Id superbillId) {
    if (superbillId == null)
      throw error('Superbill Id is required.');
    ClaimSubmissionConfig config = ClaimSubmissionProviderFactory.getActiveConfig();
    List<Superbill__c> superbills = [
      SELECT Id, Status__c
      FROM Superbill__c
      WHERE Id = :superbillId
      LIMIT 1
      FOR UPDATE
    ];
    if (superbills.isEmpty())
      throw error('Superbill was not found.');
    if (superbills[0].Status__c != 'Ready') {
      throw error('Only a Ready superbill can be submitted.');
    }
    if (
      [
        SELECT COUNT()
        FROM Claim_Submission__c
        WHERE Superbill__c = :superbillId AND Status__c IN :PENDING_STATUSES
      ] > 0
    ) {
      throw error('This superbill already has a queued submission.');
    }

    ClaimExportService.build(superbillId);
    Claim_Submission__c submission = new Claim_Submission__c(
      Superbill__c = superbillId,
      Status__c = 'Queued',
      Attempt_Number__c = 0,
      Idempotency_Key__c = randomHex(32),
      Patient_Control_Number__c = randomHex(17),
      Provider_Used__c = config.providerName,
      Queued_At__c = Datetime.now()
    );
    insert submission;
    enqueue(submission, config);
    return getById(submission.Id);
  }

  public static Claim_Submission__c retry(Id submissionId) {
    if (submissionId == null)
      throw error('Claim Submission Id is required.');
    ClaimSubmissionConfig config = ClaimSubmissionProviderFactory.getActiveConfig();
    List<Claim_Submission__c> rows = [
      SELECT
        Id,
        Superbill__c,
        Superbill__r.Status__c,
        Status__c,
        Queued_At__c,
        Async_Job_Id__c
      FROM Claim_Submission__c
      WHERE Id = :submissionId
      LIMIT 1
      FOR UPDATE
    ];
    if (rows.isEmpty())
      throw error('Claim submission was not found.');
    Claim_Submission__c submission = rows[0];
    if (submission.Status__c != 'Failed' && !isRecoverableQueue(submission)) {
      throw error(
        'Only a failed or stale queued transport attempt can be retried.'
      );
    }
    if (submission.Superbill__r.Status__c != 'Ready')
      throw error('The parent superbill must still be Ready.');
    submission.Status__c = 'Queued';
    submission.Provider_Used__c = config.providerName;
    submission.Error_Message__c = null;
    submission.Queued_At__c = Datetime.now();
    update submission;
    enqueue(submission, config);
    return getById(submission.Id);
  }

  public static void process(Id submissionId, ClaimSubmissionConfig config) {
    List<Claim_Submission__c> rows = [
      SELECT
        Id,
        Superbill__c,
        Status__c,
        Attempt_Number__c,
        Idempotency_Key__c,
        Patient_Control_Number__c
      FROM Claim_Submission__c
      WHERE Id = :submissionId
      LIMIT 1
    ];
    if (rows.isEmpty() || rows[0].Status__c != 'Queued')
      return;
    Claim_Submission__c submission = rows[0];
    ClaimSubmissionResult result;
    try {
      VendorNeutralClaim claim = ClaimExportService.build(
        submission.Superbill__c
      );
      result = ClaimSubmissionProviderFactory.getProvider(config.providerName)
        .submit(
          claim,
          config,
          submission.Idempotency_Key__c,
          submission.Patient_Control_Number__c
        );
      if (result == null) {
        result = failedResult('Claim submission provider returned no result.');
      }
    } catch (Exception e) {
      result = failedResult(e.getMessage());
    }

    submission.Attempt_Number__c =
      (submission.Attempt_Number__c == null
        ? 0
        : submission.Attempt_Number__c) + 1;
    submission.Last_Attempt_At__c = Datetime.now();
    submission.Status__c = result.success
      ? 'Submitted'
      : (result.rejected ? 'Rejected' : 'Failed');
    submission.Request_Payload__c = truncate(
      result.requestPayload,
      PAYLOAD_MAX
    );
    submission.Response_Payload__c = truncate(
      result.responsePayload,
      PAYLOAD_MAX
    );
    submission.Error_Message__c = result.success
      ? null
      : truncate(result.errorMessage, ERROR_MAX);
    submission.Http_Status_Code__c = result.httpStatusCode;
    submission.Provider_Status__c = truncate(
      result.providerStatus,
      PROVIDER_STATUS_MAX
    );
    submission.Correlation_Id__c = truncate(
      result.correlationId,
      PROVIDER_REFERENCE_MAX
    );
    submission.Clearinghouse_Claim_Id__c = truncate(
      result.clearinghouseClaimId,
      PROVIDER_REFERENCE_MAX
    );
    submission.Control_Number__c = truncate(
      result.controlNumber,
      PROVIDER_REFERENCE_MAX
    );
    if (result.success)
      submission.Submitted_At__c = Datetime.now();
    update submission;

    if (result.success) {
      List<Superbill__c> superbills = [
        SELECT Id, Status__c
        FROM Superbill__c
        WHERE Id = :submission.Superbill__c
        LIMIT 1
      ];
      if (!superbills.isEmpty() && superbills[0].Status__c == 'Ready') {
        superbills[0].Status__c = 'Exported';
        update superbills[0];
      }
    }
  }

  public static Claim_Submission__c getById(Id submissionId) {
    return [
      SELECT
        Id,
        Name,
        Superbill__c,
        Status__c,
        Attempt_Number__c,
        Idempotency_Key__c,
        Patient_Control_Number__c,
        Provider_Used__c,
        Async_Job_Id__c,
        Http_Status_Code__c,
        Provider_Status__c,
        Correlation_Id__c,
        Clearinghouse_Claim_Id__c,
        Control_Number__c,
        Queued_At__c,
        Last_Attempt_At__c,
        Submitted_At__c,
        Error_Message__c,
        Request_Payload__c,
        Response_Payload__c
      FROM Claim_Submission__c
      WHERE Id = :submissionId
      LIMIT 1
    ];
  }

  private static ClaimSubmissionResult failedResult(String message) {
    ClaimSubmissionResult result = new ClaimSubmissionResult();
    result.errorMessage = message;
    return result;
  }

  private static void enqueue(
    Claim_Submission__c submission,
    ClaimSubmissionConfig config
  ) {
    submission.Async_Job_Id__c = skipEnqueue == true
      ? 'TEST_JOB'
      : String.valueOf(
          System.enqueueJob(new ClaimSubmissionQueueable(submission.Id, config))
        );
    update submission;
  }

  private static Boolean isRecoverableQueue(Claim_Submission__c submission) {
    if (
      submission.Status__c != 'Queued' ||
      submission.Queued_At__c == null ||
      submission.Queued_At__c > Datetime.now().addMinutes(-STALE_QUEUE_MINUTES)
    ) {
      return false;
    }
    if (String.isBlank(submission.Async_Job_Id__c))
      return true;

    try {
      Id jobId = (Id) submission.Async_Job_Id__c;
      List<AsyncApexJob> jobs = [
        SELECT Status
        FROM AsyncApexJob
        WHERE Id = :jobId
        LIMIT 1
      ];
      if (jobs.isEmpty())
        return true;
      return new Set<String>{ 'Aborted', 'Completed', 'Failed' }
        .contains(jobs[0].Status);
    } catch (Exception e) {
      return true;
    }
  }

  private static String randomHex(Integer length) {
    String seed =
      String.valueOf(Datetime.now().getTime()) +
      ':' +
      EncodingUtil.convertToHex(Crypto.generateAesKey(128)) +
      ':' +
      String.valueOf(Crypto.getRandomInteger());
    String value = EncodingUtil.convertToHex(
        Crypto.generateDigest('SHA-256', Blob.valueOf(seed))
      )
      .toUpperCase();
    return value.substring(0, length);
  }

  private static String truncate(String value, Integer maximum) {
    if (value == null || value.length() <= maximum)
      return value;
    return value.substring(0, maximum);
  }

  private static ClaimSubmissionProviderFactory.ClaimSubmissionException error(
    String message
  ) {
    return new ClaimSubmissionProviderFactory.ClaimSubmissionException(message);
  }
}
