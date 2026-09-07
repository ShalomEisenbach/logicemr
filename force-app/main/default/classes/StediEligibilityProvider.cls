public with sharing class StediEligibilityProvider implements EligibilityProvider {
    public EligibilityResult check(EligibilityRequest req) {
        EligibilityResult result = new EligibilityResult();
        if (req == null) {
            result.status = 'Error';
            result.error = 'Eligibility request is required.';
            return result;
        }

        Eligibility_Setting__mdt setting;
        try {
            setting = EligibilityProviderFactory.getActiveSetting();
        } catch (Exception e) {
            result.status = 'Error';
            result.error = e.getMessage();
            return result;
        }
        if (setting == null || String.isBlank(setting.Named_Credential__c)) {
            result.status = 'Error';
            result.error = 'Named Credential is not configured on the active Eligibility Setting.';
            return result;
        }

        String serviceType = String.isNotBlank(req.serviceType)
            ? req.serviceType
            : setting.Default_Service_Type__c;
        Map<String, Object> payload = new Map<String, Object>{
            'patient' => req.patient,
            'coverage' => req.coverage,
            'payerId' => req.payerId,
            'serviceType' => serviceType
        };

        HttpRequest httpReq = new HttpRequest();
        httpReq.setEndpoint('callout:' + setting.Named_Credential__c);
        httpReq.setMethod('POST');
        httpReq.setHeader('Content-Type', 'application/json');
        httpReq.setBody(JSON.serialize(payload));
        httpReq.setTimeout(120000);

        try {
            HttpResponse response = new Http().send(httpReq);
            result.rawResponse = response.getBody();
            Integer statusCode = response.getStatusCode();
            if (statusCode >= 200 && statusCode < 300) {
                result.status = 'Active';
            } else {
                result.status = 'Error';
                result.error = 'HTTP ' + statusCode;
            }
        } catch (Exception e) {
            result.status = 'Error';
            result.error = e.getMessage();
        }
        return result;
    }
}
