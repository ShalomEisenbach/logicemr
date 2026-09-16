public without sharing class ClaimAcknowledgmentService {
  private static final String REPORT_PATH = '/2024-04-01/change/medicalnetwork/reports/v2/';
  private static final Integer PAYLOAD_MAX = 131072;
  private static final Integer MESSAGE_MAX = 32768;

  public class ClaimAcknowledgmentException extends Exception {
  }

  public class IngestionResult {
    @AuraEnabled
    public Integer processed { get; set; }
    @AuraEnabled
    public Integer matched { get; set; }
    @AuraEnabled
    public Integer unmatched { get; set; }

    public IngestionResult() {
      processed = 0;
      matched = 0;
      unmatched = 0;
    }
  }

  private class ParsedAcknowledgment {
    String transactionId;
    Integer claimIndex;
    String patientControlNumber;
    String claimTransactionBatchNumber;
    String payerClaimControlNumber;
    String senderType;
    String senderName;
    String status;
    Date effectiveDate;
    Set<String> codes = new Set<String>();
    Set<String> messages = new Set<String>();
    Boolean rejected = false;
    Boolean accepted = false;
    Boolean received = false;
  }

  public static IngestionResult retrieveAndIngest(String transactionId) {
    validateTransactionId(transactionId);
    ClaimSubmissionConfig config = ClaimSubmissionProviderFactory.getActiveConfig();
    HttpRequest request = new HttpRequest();
    request.setMethod('GET');
    request.setEndpoint(
      'callout:' +
      config.namedCredential +
      REPORT_PATH +
      EncodingUtil.urlEncode(transactionId, 'UTF-8') +
      '/277'
    );
    request.setTimeout(120000);
    HttpResponse response = new Http().send(request);
    if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
      throw error(
        'Unable to retrieve Stedi 277CA transaction ' +
        transactionId +
        ' (HTTP ' +
        response.getStatusCode() +
        ').'
      );
    }
    return ingestReport(transactionId, response.getBody());
  }

  @TestVisible
  private static IngestionResult ingestReport(
    String transactionId,
    String rawJson
  ) {
    validateTransactionId(transactionId);
    if (String.isBlank(rawJson))
      throw error('The 277CA report was empty.');

    Map<String, Object> root;
    try {
      root = asMap(JSON.deserializeUntyped(rawJson));
    } catch (Exception e) {
      throw error('The 277CA report was not valid JSON.');
    }
    if (root == null)
      throw error('The 277CA report must be a JSON object.');

    String reportTransactionId = stringValue(asMap(root.get('meta'))?.get('transactionId'));
    if (
      String.isNotBlank(reportTransactionId) &&
      !reportTransactionId.equalsIgnoreCase(transactionId)
    ) {
      throw error('The 277CA report transaction identifier did not match the requested transaction.');
    }

    List<ParsedAcknowledgment> parsed = parseReport(transactionId, root);
    if (parsed.isEmpty())
      throw error('The 277CA report did not contain any claim acknowledgments.');

    Set<String> patientControlNumbers = new Set<String>();
    Set<String> batchNumbers = new Set<String>();
    for (ParsedAcknowledgment item : parsed) {
      if (String.isNotBlank(item.patientControlNumber))
        patientControlNumbers.add(item.patientControlNumber);
      if (String.isNotBlank(item.claimTransactionBatchNumber))
        batchNumbers.add(item.claimTransactionBatchNumber);
    }

    List<Claim_Submission__c> submissions = [
      SELECT
        Id,
        Superbill__c,
        Patient_Control_Number__c,
        Correlation_Id__c,
        CreatedDate
      FROM Claim_Submission__c
      WHERE
        Patient_Control_Number__c IN :patientControlNumbers
        OR Correlation_Id__c IN :batchNumbers
      ORDER BY CreatedDate DESC
    ];
    Map<String, Claim_Submission__c> byPatientControl = new Map<String, Claim_Submission__c>();
    Map<String, Claim_Submission__c> byCorrelation = new Map<String, Claim_Submission__c>();
    for (Claim_Submission__c submission : submissions) {
      putFirst(byPatientControl, submission.Patient_Control_Number__c, submission);
      putFirst(byCorrelation, submission.Correlation_Id__c, submission);
    }

    Datetime processedAt = Datetime.now();
    List<Claim_Acknowledgment__c> records = new List<Claim_Acknowledgment__c>();
    Set<Id> matchedSubmissionIds = new Set<Id>();
    IngestionResult result = new IngestionResult();
    for (ParsedAcknowledgment item : parsed) {
      Claim_Submission__c submission = byPatientControl.get(
        normalize(item.patientControlNumber)
      );
      if (
        submission == null &&
        String.isBlank(item.patientControlNumber)
      ) {
        submission = byCorrelation.get(
          normalize(item.claimTransactionBatchNumber)
        );
      }
      Claim_Acknowledgment__c record = new Claim_Acknowledgment__c(
        Acknowledgment_Key__c = acknowledgmentKey(
          transactionId,
          item.claimIndex
        ),
        Transaction_Id__c = transactionId,
        Claim_Submission__c = submission?.Id,
        Superbill__c = submission?.Superbill__c,
        Match_Status__c = submission == null ? 'Unmatched' : 'Matched',
        Status__c = item.status,
        Sender_Type__c = item.senderType,
        Sender_Name__c = truncate(item.senderName, 255),
        Patient_Control_Number__c = truncate(
          item.patientControlNumber,
          40
        ),
        Claim_Transaction_Batch_Number__c = truncate(
          item.claimTransactionBatchNumber,
          100
        ),
        Payer_Claim_Control_Number__c = truncate(
          item.payerClaimControlNumber,
          100
        ),
        Effective_Date__c = item.effectiveDate,
        Processed_At__c = processedAt,
        Status_Codes__c = truncate(joinSorted(item.codes), MESSAGE_MAX),
        Message__c = truncate(joinSorted(item.messages), MESSAGE_MAX),
        Raw_Payload__c = truncate(rawJson, PAYLOAD_MAX)
      );
      records.add(record);
      result.processed++;
      if (submission == null) {
        result.unmatched++;
      } else {
        result.matched++;
        matchedSubmissionIds.add(submission.Id);
      }
    }
    upsert records Acknowledgment_Key__c;
    updateSubmissionSummaries(matchedSubmissionIds);
    return result;
  }

  public static String reopenRejectedClaim(Id submissionId) {
    if (submissionId == null)
      throw error('Claim Submission Id is required.');
    List<Claim_Submission__c> submissions = [
      SELECT
        Id,
        Superbill__c,
        Status__c,
        Acknowledgment_Status__c,
        Acknowledgment_Message__c
      FROM Claim_Submission__c
      WHERE Id = :submissionId
      LIMIT 1
      FOR UPDATE
    ];
    if (submissions.isEmpty())
      throw error('Claim submission was not found.');
    Claim_Submission__c submission = submissions[0];
    if (
      submission.Status__c != 'Submitted' ||
      submission.Acknowledgment_Status__c != 'Rejected'
    ) {
      throw error('Only a claim rejected in a 277CA can be reopened.');
    }
    Claim_Submission__c latestSubmission = [
      SELECT Id
      FROM Claim_Submission__c
      WHERE Superbill__c = :submission.Superbill__c
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    if (latestSubmission.Id != submission.Id) {
      throw error('Only the latest rejected claim submission can be reopened.');
    }
    Superbill__c superbill = [
      SELECT Id, Status__c
      FROM Superbill__c
      WHERE Id = :submission.Superbill__c
      LIMIT 1
      FOR UPDATE
    ];
    if (superbill.Status__c != 'Exported') {
      throw error('Only the exported rejected claim can be reopened.');
    }
    superbill.Status__c = 'Needs Review';
    superbill.Ready_Date__c = null;
    superbill.Validation_Messages__c = truncate(
      submission.Acknowledgment_Message__c,
      MESSAGE_MAX
    );
    update superbill;
    return superbill.Status__c;
  }

  private static List<ParsedAcknowledgment> parseReport(
    String transactionId,
    Map<String, Object> root
  ) {
    List<ParsedAcknowledgment> result = new List<ParsedAcknowledgment>();
    Integer claimIndex = 0;
    for (Object transactionValue : asList(root.get('transactions'))) {
      Map<String, Object> transactionData = asMap(transactionValue);
      for (Object payerValue : asList(transactionData?.get('payers'))) {
        Map<String, Object> payer = asMap(payerValue);
        String senderName = stringValue(payer?.get('organizationName'));
        String senderType = senderType(
          stringValue(payer?.get('entityIdentifierCodeValue'))
        );
        for (
          Object statusTransactionValue : asList(
            payer?.get('claimStatusTransactions')
          )
        ) {
          Map<String, Object> statusTransaction = asMap(statusTransactionValue);
          String batchNumber = stringValue(
            statusTransaction?.get('claimTransactionBatchNumber')
          );
          for (
            Object detailValue : asList(
              statusTransaction?.get('claimStatusDetails')
            )
          ) {
            Map<String, Object> detail = asMap(detailValue);
            for (
              Object patientValue : asList(
                detail?.get('patientClaimStatusDetails')
              )
            ) {
              Map<String, Object> patient = asMap(patientValue);
              for (Object claimValue : asList(patient?.get('claims'))) {
                Map<String, Object> claim = asMap(claimValue);
                Map<String, Object> claimStatus = asMap(
                  claim?.get('claimStatus')
                );
                if (claimStatus == null)
                  continue;
                ParsedAcknowledgment parsed = new ParsedAcknowledgment();
                parsed.transactionId = transactionId;
                parsed.claimIndex = claimIndex++;
                parsed.patientControlNumber = firstNonblank(
                  stringValue(
                    claimStatus.get('referencedTransactionTraceNumber')
                  ),
                  stringValue(claimStatus.get('patientAccountNumber'))
                );
                parsed.claimTransactionBatchNumber = batchNumber;
                parsed.payerClaimControlNumber = stringValue(
                  claimStatus.get('tradingPartnerClaimNumber')
                );
                parsed.senderName = senderName;
                parsed.senderType = senderType;
                parseClaimStatuses(parsed, claimStatus);
                parseServiceLines(parsed, claim);
                parsed.status = classification(parsed);
                result.add(parsed);
              }
            }
          }
        }
      }
    }
    return result;
  }

  private static void parseClaimStatuses(
    ParsedAcknowledgment parsed,
    Map<String, Object> claimStatus
  ) {
    for (
      Object informationValue : asList(
        claimStatus.get('informationClaimStatuses')
      )
    ) {
      Map<String, Object> information = asMap(informationValue);
      if (information == null)
        continue;
      String actionCode = stringValue(
        information.get('statusInformationActionCode')
      );
      applyAction(parsed, actionCode);
      if (String.isNotBlank(actionCode)) {
        parsed.codes.add('Action ' + actionCode);
      }
      Date effective = parseDate(
        stringValue(information.get('statusInformationEffectiveDate'))
      );
      if (
        effective != null &&
        (parsed.effectiveDate == null || effective > parsed.effectiveDate)
      ) {
        parsed.effectiveDate = effective;
      }
      addMessage(parsed.messages, stringValue(information.get('statusMessage')));
      parseStatuses(
        parsed,
        asList(information.get('informationStatuses')),
        null
      );
    }
  }

  private static void parseServiceLines(
    ParsedAcknowledgment parsed,
    Map<String, Object> claim
  ) {
    for (Object lineValue : asList(claim.get('serviceLines'))) {
      Map<String, Object> line = asMap(lineValue);
      if (line == null)
        continue;
      String lineNumber = stringValue(line.get('lineItemControlNumber'));
      for (
        Object claimStatusValue : asList(line.get('serviceClaimStatuses'))
      ) {
        Map<String, Object> claimStatus = asMap(claimStatusValue);
        parseStatuses(
          parsed,
          asList(claimStatus?.get('serviceStatuses')),
          String.isBlank(lineNumber) ? 'Service line' : 'Line ' + lineNumber
        );
      }
    }
  }

  private static void parseStatuses(
    ParsedAcknowledgment parsed,
    List<Object> statuses,
    String prefix
  ) {
    for (Object statusValue : statuses) {
      Map<String, Object> status = asMap(statusValue);
      if (status == null)
        continue;
      String category = stringValue(
        status.get('healthCareClaimStatusCategoryCode')
      );
      String statusCode = stringValue(status.get('statusCode'));
      String entity = stringValue(status.get('entityIdentifierCodeValue'));
      String description = stringValue(status.get('statusCodeValue'));
      applyCategory(parsed, category);
      List<String> codeParts = new List<String>();
      if (String.isNotBlank(category))
        codeParts.add(category);
      if (String.isNotBlank(statusCode))
        codeParts.add(statusCode);
      if (!codeParts.isEmpty())
        parsed.codes.add(
          String.join(codeParts, '/') +
          (String.isBlank(entity) ? '' : ' (' + entity + ')')
        );
      if (String.isNotBlank(description)) {
        addMessage(
          parsed.messages,
          (String.isBlank(prefix) ? '' : prefix + ': ') +
          description +
          (String.isBlank(entity) ? '' : ' (' + entity + ')')
        );
      }
    }
  }

  private static void applyAction(
    ParsedAcknowledgment parsed,
    String actionCode
  ) {
    if (actionCode == 'U')
      parsed.rejected = true;
    if (actionCode == 'WQ')
      parsed.accepted = true;
  }

  private static void applyCategory(
    ParsedAcknowledgment parsed,
    String category
  ) {
    if (new Set<String>{ 'A3', 'A7', 'A8' }.contains(category)) {
      parsed.rejected = true;
    } else if (category == 'A2') {
      parsed.accepted = true;
    } else if (new Set<String>{ 'A0', 'A1' }.contains(category)) {
      parsed.received = true;
    }
  }

  private static String classification(ParsedAcknowledgment parsed) {
    if (parsed.rejected)
      return 'Rejected';
    if (parsed.accepted)
      return 'Accepted';
    if (parsed.received)
      return 'Received';
    return 'Unknown';
  }

  private static void updateSubmissionSummaries(Set<Id> submissionIds) {
    if (submissionIds.isEmpty())
      return;
    Map<Id, Claim_Acknowledgment__c> bestBySubmission = new Map<Id, Claim_Acknowledgment__c>();
    for (Claim_Acknowledgment__c acknowledgment : [
      SELECT
        Claim_Submission__c,
        Status__c,
        Sender_Type__c,
        Message__c,
        Payer_Claim_Control_Number__c,
        Effective_Date__c,
        Processed_At__c
      FROM Claim_Acknowledgment__c
      WHERE Claim_Submission__c IN :submissionIds
      ORDER BY Processed_At__c ASC
    ]) {
      Claim_Acknowledgment__c current = bestBySubmission.get(
        acknowledgment.Claim_Submission__c
      );
      if (current == null || preferred(acknowledgment, current)) {
        bestBySubmission.put(
          acknowledgment.Claim_Submission__c,
          acknowledgment
        );
      }
    }
    List<Claim_Submission__c> updates = new List<Claim_Submission__c>();
    for (Id submissionId : bestBySubmission.keySet()) {
      Claim_Acknowledgment__c best = bestBySubmission.get(submissionId);
      updates.add(
        new Claim_Submission__c(
          Id = submissionId,
          Acknowledgment_Status__c = best.Status__c,
          Last_Acknowledgment_At__c = best.Processed_At__c,
          Acknowledgment_Message__c = best.Message__c,
          Payer_Claim_Control_Number__c = best.Payer_Claim_Control_Number__c
        )
      );
    }
    update updates;
  }

  private static Boolean preferred(
    Claim_Acknowledgment__c candidate,
    Claim_Acknowledgment__c current
  ) {
    Integer candidateRank = statusRank(candidate.Status__c);
    Integer currentRank = statusRank(current.Status__c);
    if (candidateRank != currentRank)
      return candidateRank > currentRank;
    Integer candidateSender = candidate.Sender_Type__c == 'Payer' ? 1 : 0;
    Integer currentSender = current.Sender_Type__c == 'Payer' ? 1 : 0;
    if (candidateSender != currentSender)
      return candidateSender > currentSender;
    if (
      candidate.Effective_Date__c != current.Effective_Date__c &&
      candidate.Effective_Date__c != null
    ) {
      return current.Effective_Date__c == null ||
        candidate.Effective_Date__c > current.Effective_Date__c;
    }
    return candidate.Processed_At__c >= current.Processed_At__c;
  }

  private static Integer statusRank(String status) {
    if (status == 'Rejected')
      return 4;
    if (status == 'Accepted')
      return 3;
    if (status == 'Received')
      return 2;
    return 1;
  }

  private static void putFirst(
    Map<String, Claim_Submission__c> target,
    String key,
    Claim_Submission__c submission
  ) {
    String normalized = normalize(key);
    if (String.isNotBlank(normalized) && !target.containsKey(normalized))
      target.put(normalized, submission);
  }

  private static String normalize(String value) {
    return String.isBlank(value) ? null : value.trim().toLowerCase();
  }

  private static String acknowledgmentKey(
    String transactionId,
    Integer claimIndex
  ) {
    return EncodingUtil.convertToHex(
        Crypto.generateDigest(
          'SHA-256',
          Blob.valueOf(transactionId.toLowerCase() + ':' + claimIndex)
        )
      )
      .toUpperCase();
  }

  private static void validateTransactionId(String transactionId) {
    if (
      String.isBlank(transactionId) ||
      !Pattern.matches(
        '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        transactionId
      )
    ) {
      throw error('A valid Stedi transaction Id is required.');
    }
  }

  private static Date parseDate(String value) {
    if (String.isBlank(value) || !Pattern.matches('^\\d{8}$', value))
      return null;
    try {
      return Date.newInstance(
        Integer.valueOf(value.substring(0, 4)),
        Integer.valueOf(value.substring(4, 6)),
        Integer.valueOf(value.substring(6, 8))
      );
    } catch (Exception e) {
      return null;
    }
  }

  private static String senderType(String value) {
    if (value == 'Clearinghouse' || value == 'Payer')
      return value;
    return 'Unknown';
  }

  private static String firstNonblank(String first, String second) {
    return String.isNotBlank(first) ? first : second;
  }

  private static String joinSorted(Set<String> values) {
    if (values == null || values.isEmpty())
      return null;
    List<String> sorted = new List<String>(values);
    sorted.sort();
    return String.join(sorted, '\n');
  }

  private static void addMessage(Set<String> messages, String value) {
    if (String.isNotBlank(value))
      messages.add(value.trim());
  }

  private static Map<String, Object> asMap(Object value) {
    return value instanceof Map<String, Object>
      ? (Map<String, Object>) value
      : null;
  }

  private static List<Object> asList(Object value) {
    return value instanceof List<Object>
      ? (List<Object>) value
      : new List<Object>();
  }

  private static String stringValue(Object value) {
    return value == null ? null : String.valueOf(value);
  }

  private static String truncate(String value, Integer maximum) {
    if (value == null || value.length() <= maximum)
      return value;
    return value.substring(0, maximum);
  }

  private static ClaimAcknowledgmentException error(String message) {
    return new ClaimAcknowledgmentException(message);
  }
}
