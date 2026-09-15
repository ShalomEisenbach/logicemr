public with sharing class StediClaimSubmissionProvider implements ClaimSubmissionProvider {
    private static final String SUBMISSION_PATH = '/2024-04-01/change/medicalnetwork/professionalclaims/v3/submission';
    private static final Integer CALLOUT_TIMEOUT_MS = 120000;

    public ClaimSubmissionResult submit(
        VendorNeutralClaim claim,
        ClaimSubmissionConfig config,
        String idempotencyKey,
        String patientControlNumber
    ) {
        ClaimSubmissionResult result = new ClaimSubmissionResult();
        try {
            result.requestPayload = Stedi837PMapper.serialize(claim, config, patientControlNumber);
            HttpRequest request = new HttpRequest();
            request.setMethod('POST');
            request.setEndpoint('callout:' + config.namedCredential + SUBMISSION_PATH);
            request.setHeader('Content-Type', 'application/json');
            request.setHeader('Idempotency-Key', idempotencyKey);
            request.setTimeout(CALLOUT_TIMEOUT_MS);
            request.setBody(result.requestPayload);

            HttpResponse response = new Http().send(request);
            result.httpStatusCode = response.getStatusCode();
            result.responsePayload = response.getBody();
            parseResponse(result);
        } catch (Exception e) {
            result.success = false;
            result.rejected = false;
            result.errorMessage = e.getMessage();
        }
        return result;
    }

    private static void parseResponse(ClaimSubmissionResult result) {
        Map<String, Object> body = parseBody(result.responsePayload);
        result.providerStatus = stringValue(body.get('status'));
        result.controlNumber = stringValue(body.get('controlNumber'));
        Map<String, Object> claimReference = body.get('claimReference') instanceof Map<String, Object>
            ? (Map<String, Object>) body.get('claimReference')
            : new Map<String, Object>();
        result.correlationId = stringValue(claimReference.get('correlationId'));
        result.clearinghouseClaimId = stringValue(claimReference.get('rhclaimNumber'));

        Boolean httpSuccess = result.httpStatusCode >= 200 && result.httpStatusCode < 300;
        result.success = httpSuccess && result.providerStatus == 'SUCCESS';
        result.rejected = !result.success && result.httpStatusCode >= 400 && result.httpStatusCode < 500;
        if (!result.success) result.errorMessage = responseError(body, result.httpStatusCode, result.providerStatus);
    }

    private static Map<String, Object> parseBody(String value) {
        if (String.isBlank(value)) return new Map<String, Object>();
        try {
            Object parsed = JSON.deserializeUntyped(value);
            return parsed instanceof Map<String, Object> ? (Map<String, Object>) parsed : new Map<String, Object>();
        } catch (Exception e) {
            return new Map<String, Object>();
        }
    }

    private static String responseError(Map<String, Object> body, Integer statusCode, String providerStatus) {
        List<String> messages = new List<String>();
        Object errorsValue = body.get('errors');
        if (errorsValue instanceof List<Object>) {
            for (Object item : (List<Object>) errorsValue) {
                if (!(item instanceof Map<String, Object>)) continue;
                Map<String, Object> error = (Map<String, Object>) item;
                String description = stringValue(error.get('description'));
                String location = stringValue(error.get('location'));
                if (String.isNotBlank(description)) messages.add(description + (String.isBlank(location) ? '' : ' (' + location + ')'));
            }
        }
        if (messages.isEmpty()) {
            String message = stringValue(body.get('message'));
            if (String.isNotBlank(message)) messages.add(message);
        }
        if (!messages.isEmpty()) return String.join(messages, '; ');
        return 'Claim submission failed with HTTP ' + statusCode +
            (String.isBlank(providerStatus) ? '.' : ' and provider status ' + providerStatus + '.');
    }

    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }
}
