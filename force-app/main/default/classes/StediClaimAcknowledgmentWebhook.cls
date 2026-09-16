@RestResource(urlMapping='/logicemr/v1/claim-acknowledgments/stedi/*')
global with sharing class StediClaimAcknowledgmentWebhook {
  private static final String MANAGE_CLAIMS_PERMISSION = 'LogicEMR_Manage_Claims';
  private static final String SECRET_HEADER = 'X-LogicEMR-Webhook-Secret';
  @TestVisible
  private static Boolean manageClaimsOverride;

  @HttpPost
  global static void receive() {
    if (!hasManageClaimsPermission()) {
      respond(403, 'The integration user cannot manage LogicEMR claims.');
      return;
    }
    Map<String, Object> event;
    try {
      event = (Map<String, Object>) JSON.deserializeUntyped(
        RestContext.request.requestBody.toString()
      );
    } catch (Exception e) {
      respond(400, 'Webhook payload must be valid JSON.');
      return;
    }
    Map<String, Object> detail = asMap(event.get('detail'));
    if (detail.isEmpty()) {
      detail = event;
    }
    Map<String, Object> x12 = asMap(detail.get('x12'));
    String transactionType = stringValue(x12.get('transactionSetIdentifier'));
    String direction = stringValue(detail.get('direction'));
    String transactionId = stringValue(detail.get('transactionId'));
    if (
      transactionType != '277' ||
      String.isBlank(direction) ||
      !direction.equalsIgnoreCase('INBOUND')
    ) {
      respond(202, 'Event ignored because it is not an inbound 277 transaction.');
      return;
    }
    if (
      String.isBlank(transactionId) ||
      !Pattern.matches(
        '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        transactionId
      )
    ) {
      respond(400, 'A valid Stedi transaction Id is required.');
      return;
    }
    Id jobId = System.enqueueJob(
      new ClaimAcknowledgmentQueueable(transactionId)
    );
    RestContext.response.addHeader('Content-Type', 'application/json');
    RestContext.response.statusCode = 202;
    RestContext.response.responseBody = Blob.valueOf(
      JSON.serialize(
        new Map<String, Object>{
          'accepted' => true,
          'transactionId' => transactionId,
          'jobId' => jobId
        }
      )
    );
  }

  private static Boolean hasManageClaimsPermission() {
    Boolean hasPermission = manageClaimsOverride != null
      ? manageClaimsOverride
      : FeatureManagement.checkPermission(MANAGE_CLAIMS_PERMISSION);
    if (hasPermission) {
      return true;
    }
    String suppliedSecret = RestContext.request.headers.get(SECRET_HEADER);
    if (String.isBlank(suppliedSecret)) {
      return false;
    }
    try {
      String expectedHash = ClaimSubmissionProviderFactory.getActiveConfig()
        .webhookSecretHash;
      if (
        String.isBlank(expectedHash) ||
        !Pattern.matches('^[0-9a-fA-F]{64}$', expectedHash)
      ) {
        return false;
      }
      String suppliedHash = EncodingUtil.convertToHex(
        Crypto.generateDigest('SHA-256', Blob.valueOf(suppliedSecret))
      );
      return expectedHash.equalsIgnoreCase(suppliedHash);
    } catch (Exception e) {
      return false;
    }
  }

  private static void respond(Integer statusCode, String message) {
    RestContext.response.addHeader('Content-Type', 'application/json');
    RestContext.response.statusCode = statusCode;
    RestContext.response.responseBody = Blob.valueOf(
      JSON.serialize(new Map<String, Object>{ 'message' => message })
    );
  }

  private static String stringValue(Object value) {
    return value == null ? null : String.valueOf(value);
  }

  private static Map<String, Object> asMap(Object value) {
    return value instanceof Map<String, Object>
      ? (Map<String, Object>) value
      : new Map<String, Object>();
  }
}
