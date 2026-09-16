@IsTest
private class ClaimAcknowledgmentServiceTest {
  private static final String TX_ID = '71716ec5-0e96-462f-bb77-869941bb27ab';

  @IsTest
  static void ingestsMultipleClaimsIdempotentlyAndPrioritizesRejection() {
    Claim_Submission__c acceptedSubmission = createSubmission('PCN-ACCEPT');
    Claim_Submission__c rejectedSubmission = createSubmission('PCN-REJECT');

    Test.startTest();
    ClaimAcknowledgmentService.IngestionResult first = ClaimAcknowledgmentService.ingestReport(
      TX_ID,
      reportJson()
    );
    ClaimAcknowledgmentService.IngestionResult duplicate = ClaimAcknowledgmentService.ingestReport(
      TX_ID,
      reportJson()
    );
    Test.stopTest();

    System.assertEquals(2, first.processed);
    System.assertEquals(2, first.matched);
    System.assertEquals(0, first.unmatched);
    System.assertEquals(2, duplicate.matched);
    System.assertEquals(
      2,
      [SELECT COUNT() FROM Claim_Acknowledgment__c],
      'Reprocessing the same transaction must update rather than duplicate records'
    );

    Map<Id, Claim_Submission__c> stored = new Map<Id, Claim_Submission__c>([
      SELECT
        Acknowledgment_Status__c,
        Acknowledgment_Message__c,
        Payer_Claim_Control_Number__c,
        Last_Acknowledgment_At__c
      FROM Claim_Submission__c
      WHERE Id IN :new Set<Id>{ acceptedSubmission.Id, rejectedSubmission.Id }
    ]);
    System.assertEquals(
      'Accepted',
      stored.get(acceptedSubmission.Id).Acknowledgment_Status__c
    );
    System.assertEquals(
      'Rejected',
      stored.get(rejectedSubmission.Id).Acknowledgment_Status__c
    );
    System.assertEquals(
      'PAYER-REJECT',
      stored.get(rejectedSubmission.Id).Payer_Claim_Control_Number__c
    );
    System.assert(
      stored
        .get(rejectedSubmission.Id)
        .Acknowledgment_Message__c.contains('contract/member number')
    );
    System.assertNotEquals(
      null,
      stored.get(rejectedSubmission.Id).Last_Acknowledgment_At__c
    );
  }

  @IsTest
  static void retainsUnmatchedClaimsForOperations() {
    String payload = reportJson().replace('PCN-ACCEPT', 'NO-MATCH-1')
      .replace('PCN-REJECT', 'NO-MATCH-2');

    Test.startTest();
    ClaimAcknowledgmentService.IngestionResult result = ClaimAcknowledgmentService.ingestReport(
      TX_ID,
      payload
    );
    Test.stopTest();

    System.assertEquals(0, result.matched);
    System.assertEquals(2, result.unmatched);
    for (Claim_Acknowledgment__c acknowledgment : [
      SELECT Match_Status__c, Claim_Submission__c, Raw_Payload__c
      FROM Claim_Acknowledgment__c
    ]) {
      System.assertEquals('Unmatched', acknowledgment.Match_Status__c);
      System.assertEquals(null, acknowledgment.Claim_Submission__c);
      System.assert(acknowledgment.Raw_Payload__c.contains('transactions'));
    }
  }

  @IsTest
  static void serviceLineRejectionOverridesClaimAcceptance() {
    Claim_Submission__c submission = createSubmission('PCN-LINE-REJECT');

    ClaimAcknowledgmentService.ingestReport(TX_ID, serviceLineReportJson());

    Claim_Submission__c stored = [
      SELECT Acknowledgment_Status__c, Acknowledgment_Message__c
      FROM Claim_Submission__c
      WHERE Id = :submission.Id
    ];
    System.assertEquals('Rejected', stored.Acknowledgment_Status__c);
    System.assert(stored.Acknowledgment_Message__c.contains('Line 1:'));
  }

  @IsTest
  static void retrievesReportThroughNamedCredential() {
    Claim_Submission__c submission = createSubmission('PCN-ACCEPT');
    configureSubmission();
    Test.setMock(HttpCalloutMock.class, new ReportMock());

    Test.startTest();
    ClaimAcknowledgmentService.IngestionResult result = ClaimAcknowledgmentService.retrieveAndIngest(
      TX_ID
    );
    Test.stopTest();

    System.assertEquals(1, result.matched);
    System.assertEquals(1, result.unmatched);
    System.assertEquals(
      'Accepted',
      [
        SELECT Acknowledgment_Status__c
        FROM Claim_Submission__c
        WHERE Id = :submission.Id
      ].Acknowledgment_Status__c
    );
  }

  @IsTest
  static void rejectedExportCanBeReopenedForCorrection() {
    Claim_Submission__c submission = createSubmission('PCN-REJECT');
    ClaimAcknowledgmentService.ingestReport(TX_ID, reportJson());
    ClaimSubmissionController.manageClaimsOverride = true;

    Test.startTest();
    List<Claim_Acknowledgment__c> acknowledgments = ClaimSubmissionController.getAcknowledgments(
      submission.Superbill__c
    );
    String status = ClaimSubmissionController.reopenRejectedClaim(
      submission.Id
    );
    Test.stopTest();

    System.assertEquals(1, acknowledgments.size());
    System.assertEquals('Needs Review', status);
    System.assertEquals(
      'Needs Review',
      [SELECT Status__c FROM Superbill__c WHERE Id = :submission.Superbill__c]
      .Status__c
    );
  }

  @IsTest
  static void olderRejectedAttemptCannotReopenClaim() {
    Claim_Submission__c rejected = createSubmission('PCN-REJECT');
    Test.setCreatedDate(rejected.Id, Datetime.now().addMinutes(-1));
    ClaimAcknowledgmentService.ingestReport(TX_ID, reportJson());
    insert new Claim_Submission__c(
      Superbill__c = rejected.Superbill__c,
      Status__c = 'Submitted',
      Acknowledgment_Status__c = 'Pending',
      Attempt_Number__c = 2,
      Idempotency_Key__c = 'IDEMP-LATEST',
      Patient_Control_Number__c = 'PCN-LATEST',
      Correlation_Id__c = 'CORR-LATEST',
      Provider_Used__c = 'Stedi',
      Submitted_At__c = Datetime.now()
    );

    Boolean failed = false;
    try {
      ClaimAcknowledgmentService.reopenRejectedClaim(rejected.Id);
    } catch (ClaimAcknowledgmentService.ClaimAcknowledgmentException error) {
      failed = error.getMessage().contains('latest rejected');
    }
    System.assert(failed, 'An older rejected attempt must remain frozen');
  }

  @IsTest
  static void webhookFiltersEventsAndQueues277Retrieval() {
    configureSubmission();
    StediClaimAcknowledgmentWebhook.manageClaimsOverride = true;
    Test.setMock(HttpCalloutMock.class, new ReportMock());
    RestContext.request = new RestRequest();
    RestContext.response = new RestResponse();
    RestContext.request.requestBody = Blob.valueOf(
      JSON.serialize(
        new Map<String, Object>{
          'version' => '0',
          'id' => 'webhook-event-id',
          'detail-type' => 'transaction.processed.v2',
          'source' => 'stedi.core',
          'detail' => new Map<String, Object>{
            'direction' => 'INBOUND',
            'transactionId' => TX_ID,
            'x12' => new Map<String, Object>{
              'transactionSetIdentifier' => '277'
            }
          }
        }
      )
    );

    Test.startTest();
    StediClaimAcknowledgmentWebhook.receive();
    Test.stopTest();

    System.assertEquals(202, RestContext.response.statusCode);
    System.assert(
      RestContext.response.responseBody.toString().contains('accepted')
    );
  }

  @IsTest
  static void webhookAcceptsConfiguredSharedSecret() {
    configureSubmission();
    StediClaimAcknowledgmentWebhook.manageClaimsOverride = false;
    Test.setMock(HttpCalloutMock.class, new ReportMock());
    RestContext.request = new RestRequest();
    RestContext.response = new RestResponse();
    RestContext.request.headers.put(
      'X-LogicEMR-Webhook-Secret',
      'test-webhook-secret'
    );
    RestContext.request.requestBody = Blob.valueOf(webhookEventJson());

    Test.startTest();
    StediClaimAcknowledgmentWebhook.receive();
    Test.stopTest();

    System.assertEquals(202, RestContext.response.statusCode);
  }

  @IsTest
  static void webhookRejectsMissingAuthentication() {
    StediClaimAcknowledgmentWebhook.manageClaimsOverride = false;
    RestContext.request = new RestRequest();
    RestContext.response = new RestResponse();
    RestContext.request.requestBody = Blob.valueOf(webhookEventJson());

    StediClaimAcknowledgmentWebhook.receive();

    System.assertEquals(403, RestContext.response.statusCode);
  }

  @IsTest
  static void queueableClassifiesTransientReportFailures() {
    System.assert(
      ClaimAcknowledgmentQueueable.isRetryable(
        new CalloutException('Connection reset')
      )
    );
    System.assert(
      ClaimAcknowledgmentQueueable.isRetryable(
        new ClaimAcknowledgmentService.ClaimAcknowledgmentException(
          'Unable to retrieve report (HTTP 404).'
        )
      )
    );
    System.assert(
      ClaimAcknowledgmentQueueable.isRetryable(
        new ClaimAcknowledgmentService.ClaimAcknowledgmentException(
          'Unable to retrieve report (HTTP 503).'
        )
      )
    );
    System.assertEquals(
      false,
      ClaimAcknowledgmentQueueable.isRetryable(
        new ClaimAcknowledgmentService.ClaimAcknowledgmentException(
          'Unable to retrieve report (HTTP 400).'
        )
      )
    );
  }

  @IsTest
  static void rejectsInvalidReportsAndReopenRequests() {
    Claim_Submission__c submission = createSubmission('PCN-ACCEPT');
    assertIngestionFails('not-json', 'not valid JSON');
    assertIngestionFails(
      '{"meta":{"transactionId":"00000000-0000-0000-0000-000000000000"}}',
      'did not match'
    );
    Boolean reopenFailed = false;
    try {
      ClaimAcknowledgmentService.reopenRejectedClaim(submission.Id);
    } catch (ClaimAcknowledgmentService.ClaimAcknowledgmentException e) {
      reopenFailed = e.getMessage().contains('rejected in a 277CA');
    }
    System.assert(reopenFailed, 'Non-rejected claims must remain frozen');
  }

  private static void assertIngestionFails(String payload, String message) {
    Boolean failed = false;
    try {
      ClaimAcknowledgmentService.ingestReport(TX_ID, payload);
    } catch (ClaimAcknowledgmentService.ClaimAcknowledgmentException e) {
      failed = e.getMessage().contains(message);
    }
    System.assert(failed, message);
  }

  private static Claim_Submission__c createSubmission(String pcn) {
    Patient__c patient = new Patient__c(
      Name = '277CA Test Patient ' + pcn,
      MRN__c = 'MRN-' + pcn
    );
    insert patient;
    Encounter__c encounter = new Encounter__c(
      Patient__c = patient.Id,
      Status__c = 'Finished'
    );
    insert encounter;
    Superbill__c superbill = new Superbill__c(
      Encounter__c = encounter.Id,
      Encounter_Key__c = String.valueOf(encounter.Id),
      Patient__c = patient.Id,
      Status__c = 'Exported'
    );
    insert superbill;
    Claim_Submission__c submission = new Claim_Submission__c(
      Superbill__c = superbill.Id,
      Status__c = 'Submitted',
      Acknowledgment_Status__c = 'Pending',
      Attempt_Number__c = 1,
      Idempotency_Key__c = 'IDEMP-' + pcn,
      Patient_Control_Number__c = pcn,
      Correlation_Id__c = 'CORR-' + pcn,
      Provider_Used__c = 'Stedi',
      Submitted_At__c = Datetime.now()
    );
    insert submission;
    return submission;
  }

  private static void configureSubmission() {
    ClaimSubmissionProviderFactory.settingsOverride = new List<Claim_Submission_Setting__mdt>{
      new Claim_Submission_Setting__mdt(
        Active__c = true,
        Provider_Name__c = 'Stedi',
        Named_Credential__c = 'Stedi_Claims',
        Usage_Indicator__c = 'T',
        Submitter_Identifier__c = 'SUBMITTER',
        Submitter_Name__c = 'Logic Clinic',
        Contact_Name__c = 'Billing',
        Contact_Phone__c = '5555551212',
        Webhook_Secret_Hash__c = EncodingUtil.convertToHex(
          Crypto.generateDigest('SHA-256', Blob.valueOf('test-webhook-secret'))
        )
      )
    };
  }

  private static String reportJson() {
    return JSON.serialize(
      new Map<String, Object>{
        'meta' => new Map<String, Object>{ 'transactionId' => TX_ID },
        'transactions' => new List<Object>{
          new Map<String, Object>{
            'payers' => new List<Object>{
              new Map<String, Object>{
                'entityIdentifierCodeValue' => 'Payer',
                'organizationName' => 'TEST PAYER',
                'claimStatusTransactions' => new List<Object>{
                  new Map<String, Object>{
                    'claimTransactionBatchNumber' => 'CORR-PCN-ACCEPT',
                    'claimStatusDetails' => new List<Object>{
                      new Map<String, Object>{
                        'patientClaimStatusDetails' => new List<Object>{
                          new Map<String, Object>{
                            'claims' => new List<Object>{
                              claim(
                                'PCN-ACCEPT',
                                'PAYER-ACCEPT',
                                'A2',
                                '20',
                                'WQ',
                                'Accepted for adjudication.'
                              ),
                              claim(
                                'PCN-REJECT',
                                'PAYER-REJECT',
                                'A3',
                                '164',
                                'U',
                                'Entity\'s contract/member number.'
                              )
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    );
  }

  private static String webhookEventJson() {
    return JSON.serialize(
      new Map<String, Object>{
        'version' => '0',
        'id' => 'webhook-event-id',
        'detail-type' => 'transaction.processed.v2',
        'source' => 'stedi.core',
        'detail' => new Map<String, Object>{
          'direction' => 'INBOUND',
          'transactionId' => TX_ID,
          'x12' => new Map<String, Object>{
            'transactionSetIdentifier' => '277'
          }
        }
      }
    );
  }

  private static String serviceLineReportJson() {
    Map<String, Object> lineRejectedClaim = claim(
      'PCN-LINE-REJECT',
      null,
      'A2',
      '20',
      'WQ',
      'Accepted for adjudication.'
    );
    lineRejectedClaim.put(
      'serviceLines',
      new List<Object>{
        new Map<String, Object>{
          'lineItemControlNumber' => '1',
          'serviceClaimStatuses' => new List<Object>{
            new Map<String, Object>{
              'serviceStatuses' => new List<Object>{
                new Map<String, Object>{
                  'healthCareClaimStatusCategoryCode' => 'A7',
                  'statusCode' => '21',
                  'statusCodeValue' => 'Missing or invalid service information.'
                }
              }
            }
          }
        }
      }
    );
    return JSON.serialize(
      new Map<String, Object>{
        'meta' => new Map<String, Object>{ 'transactionId' => TX_ID },
        'transactions' => new List<Object>{
          new Map<String, Object>{
            'payers' => new List<Object>{
              new Map<String, Object>{
                'entityIdentifierCodeValue' => 'Payer',
                'organizationName' => 'TEST PAYER',
                'claimStatusTransactions' => new List<Object>{
                  new Map<String, Object>{
                    'claimStatusDetails' => new List<Object>{
                      new Map<String, Object>{
                        'patientClaimStatusDetails' => new List<Object>{
                          new Map<String, Object>{
                            'claims' => new List<Object>{ lineRejectedClaim }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    );
  }

  private static Map<String, Object> claim(
    String pcn,
    String payerClaimNumber,
    String category,
    String statusCode,
    String actionCode,
    String description
  ) {
    return new Map<String, Object>{
      'claimStatus' => new Map<String, Object>{
        'referencedTransactionTraceNumber' => pcn,
        'tradingPartnerClaimNumber' => payerClaimNumber,
        'informationClaimStatuses' => new List<Object>{
          new Map<String, Object>{
            'statusInformationActionCode' => actionCode,
            'statusInformationEffectiveDate' => '20260915',
            'informationStatuses' => new List<Object>{
              new Map<String, Object>{
                'healthCareClaimStatusCategoryCode' => category,
                'statusCode' => statusCode,
                'statusCodeValue' => description,
                'entityIdentifierCodeValue' => 'Insured or Subscriber'
              }
            }
          }
        }
      }
    };
  }

  private class ReportMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      System.assertEquals('GET', request.getMethod());
      System.assertEquals(
        'callout:Stedi_Claims/2024-04-01/change/medicalnetwork/reports/v2/' +
        TX_ID +
        '/277',
        request.getEndpoint()
      );
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody(reportJson());
      return response;
    }
  }

}
