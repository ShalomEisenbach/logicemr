public with sharing class StediEligibilityProvider implements EligibilityProvider {
    private static final String ELIGIBILITY_PATH = '/change/medicalnetwork/eligibility/v3';
    private static final String PAYER_SEARCH_PATH = '/2024-04-01/payers/search';
    private static final String PROVIDER_USED = 'Stedi';
    private static final Integer CALLOUT_TIMEOUT_MS = 120000;
    private static final Integer REQUEST_PAYLOAD_MAX = 131072;
    private static final Integer RAW_RESPONSE_MAX = 131072;
    private static final Integer ERROR_MESSAGE_MAX = 32768;
    private static final Integer PLAN_NAME_MAX = 120;
    private static final Set<String> ACTIVE_CODES = new Set<String>{ '1', '2', '3', '4', '5' };
    private static final Set<String> INACTIVE_CODES = new Set<String>{ '6', '7', '8' };
    private static final Set<String> TOTAL_TIME_CODES = new Set<String>{ '22', '23', '26' };
    private static final Set<String> REMAINING_TIME_CODES = new Set<String>{ '29' };

    public EligibilityResult check(EligibilityRequest req) {
        EligibilityResult result = new EligibilityResult();
        CheckContext ctx = new CheckContext();
        ctx.request = req;
        try {
            if (req == null) {
                return markError(result, 'Eligibility request is required.');
            }
            ctx.patientId = req.patient;
            ctx.coverageId = req.coverage;
            ctx.serviceType = req.serviceType;
            ctx.setting = EligibilityProviderFactory.getActiveSetting();
            if (ctx.setting == null || String.isBlank(ctx.setting.Named_Credential__c)) {
                markError(result, 'Named Credential is not configured on the active Eligibility Setting.');
                persistCheck(result, ctx);
                return result;
            }

            populateContext(ctx);
            if (String.isNotBlank(ctx.buildError)) {
                markError(result, ctx.buildError);
                persistCheck(result, ctx);
                return result;
            }

            ctx.requestJson = JSON.serialize(ctx.payload);
            HttpResponse response = sendJson(
                'POST',
                calloutUrl(ctx.setting.Named_Credential__c, ELIGIBILITY_PATH),
                ctx.requestJson
            );
            ctx.rawBody = response == null ? null : response.getBody();
            result.rawResponse = ctx.rawBody;

            Integer statusCode = response == null ? 0 : response.getStatusCode();
            if (statusCode < 200 || statusCode >= 300) {
                markError(result, httpErrorMessage(response));
            } else {
                applyParsedBenefits(result, ctx.rawBody);
            }
        } catch (Exception e) {
            markError(result, e.getMessage());
            if (String.isBlank(result.rawResponse) && String.isNotBlank(ctx.rawBody)) {
                result.rawResponse = ctx.rawBody;
            }
        }
        persistCheck(result, ctx);
        return result;
    }

    public List<EligibilityPayerMatch> searchPayers(String query) {
        Eligibility_Setting__mdt setting = EligibilityProviderFactory.getActiveSetting();
        if (setting == null || String.isBlank(setting.Named_Credential__c)) {
            throw new EligibilityProviderFactory.EligibilityException(
                'Named Credential is not configured on the active Eligibility Setting.'
            );
        }
        if (String.isBlank(query)) {
            return new List<EligibilityPayerMatch>();
        }

        String endpoint =
            calloutUrl(setting.Named_Credential__c, PAYER_SEARCH_PATH) +
            '?query=' +
            EncodingUtil.urlEncode(query, 'UTF-8');
        HttpResponse response = sendJson('GET', endpoint, null);
        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
            throw new EligibilityProviderFactory.EligibilityException(httpErrorMessage(response));
        }
        return parsePayerMatches(response.getBody());
    }

    private static void populateContext(CheckContext ctx) {
        EligibilityRequest req = ctx.request;
        ctx.patientId = req.patient;
        ctx.coverageId = req.coverage;
        ctx.serviceType = String.isNotBlank(req.serviceType)
            ? req.serviceType
            : (ctx.setting == null ? null : ctx.setting.Default_Service_Type__c);
        List<String> serviceTypeCodes = splitServiceTypes(ctx.serviceType);
        if (serviceTypeCodes.isEmpty()) {
            serviceTypeCodes.add('30');
            ctx.serviceType = '30';
        }

        Patient__c patient;
        Coverage__c coverage;
        if (req.coverage != null) {
            List<Coverage__c> coverages = [
                SELECT
                    Id,
                    Member_Id__c,
                    Subscriber_Name__c,
                    Relationship_to_Subscriber__c,
                    Plan_Name__c,
                    Patient__c,
                    Patient__r.First_Name__c,
                    Patient__r.Last_Name__c,
                    Patient__r.Date_of_Birth__c,
                    Payer__c,
                    Payer__r.Payer_Identifier__c,
                    Payer__r.Name
                FROM Coverage__c
                WHERE Id = :req.coverage
                LIMIT 1
            ];
            if (coverages.isEmpty()) {
                ctx.coverageId = null;
                ctx.buildError = 'Coverage was not found.';
                return;
            }
            coverage = coverages[0];
            ctx.coverageId = coverage.Id;
            if (req.patient != null && coverage.Patient__c != req.patient) {
                ctx.buildError = 'Coverage does not belong to the patient.';
                return;
            }
            ctx.patientId = coverage.Patient__c;
            patient = coverage.Patient__r;
            assignPatientName(ctx, patient);
        } else if (req.patient != null) {
            List<Patient__c> patients = [
                SELECT Id, First_Name__c, Last_Name__c, Date_of_Birth__c
                FROM Patient__c
                WHERE Id = :req.patient
                LIMIT 1
            ];
            if (patients.isEmpty()) {
                ctx.buildError = 'Patient was not found.';
                return;
            }
            patient = patients[0];
            ctx.patientId = patient.Id;
            assignPatientName(ctx, patient);
        } else {
            ctx.buildError = 'Patient or Coverage is required.';
            return;
        }

        String payerId = String.isNotBlank(req.payerId)
            ? req.payerId
            : (coverage == null || coverage.Payer__r == null ? null : coverage.Payer__r.Payer_Identifier__c);
        if (String.isBlank(payerId)) {
            ctx.buildError = 'Payer identifier is required. Set Payer__c.Payer_Identifier__c to the Stedi payer id.';
            return;
        }

        String npi = String.isNotBlank(req.providerNpi) ? req.providerNpi : findProviderNpi();
        if (String.isBlank(npi)) {
            ctx.buildError = 'Provider NPI is required.';
            return;
        }
        String organizationName = String.isNotBlank(req.providerOrganizationName)
            ? req.providerOrganizationName
            : UserInfo.getOrganizationName();
        if (String.isBlank(organizationName)) {
            // TODO: Replace with a packaged practice/organization record when that object exists.
            organizationName = 'Organization';
        }

        Map<String, Object> subscriber = new Map<String, Object>();
        if (patient != null && String.isNotBlank(patient.First_Name__c)) {
            subscriber.put('firstName', patient.First_Name__c);
        }
        if (patient != null && String.isNotBlank(patient.Last_Name__c)) {
            subscriber.put('lastName', patient.Last_Name__c);
        }
        if (patient != null && patient.Date_of_Birth__c != null) {
            subscriber.put('dateOfBirth', formatStediDate(patient.Date_of_Birth__c));
        }
        if (coverage != null && String.isNotBlank(coverage.Member_Id__c)) {
            subscriber.put('memberId', coverage.Member_Id__c);
        }
        if (subscriber.isEmpty()) {
            ctx.buildError = 'Subscriber name or member Id is required from Patient or Coverage.';
            return;
        }

        ctx.payload = new Map<String, Object>{
            'controlNumber' => newControlNumber(),
            'tradingPartnerServiceId' => payerId,
            'provider' => new Map<String, Object>{
                'organizationName' => organizationName,
                'npi' => npi
            },
            'subscriber' => subscriber,
            'encounter' => new Map<String, Object>{ 'serviceTypeCodes' => serviceTypeCodes }
        };
    }

    private static String findProviderNpi() {
        Id userId = UserInfo.getUserId();
        List<Practitioner__c> mine = [
            SELECT NPI__c
            FROM Practitioner__c
            WHERE User__c = :userId AND NPI__c != NULL
            LIMIT 1
        ];
        if (!mine.isEmpty()) {
            return mine[0].NPI__c;
        }
        List<Practitioner__c> anyActive = [
            SELECT NPI__c
            FROM Practitioner__c
            WHERE Active__c = TRUE AND NPI__c != NULL
            ORDER BY Last_Name__c NULLS LAST
            LIMIT 1
        ];
        return anyActive.isEmpty() ? null : anyActive[0].NPI__c;
    }

    private static HttpResponse sendJson(String method, String endpoint, String body) {
        HttpRequest httpReq = new HttpRequest();
        httpReq.setEndpoint(endpoint);
        httpReq.setMethod(method);
        httpReq.setTimeout(CALLOUT_TIMEOUT_MS);
        if (body != null) {
            httpReq.setHeader('Content-Type', 'application/json');
            httpReq.setBody(body);
        }
        return new Http().send(httpReq);
    }

    private static String calloutUrl(String namedCredential, String path) {
        return 'callout:' + namedCredential + path;
    }

    private static void applyParsedBenefits(EligibilityResult result, String rawBody) {
        result.rawResponse = rawBody;
        if (String.isBlank(rawBody)) {
            markError(result, 'Empty eligibility response.');
            return;
        }

        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(rawBody);
        } catch (Exception e) {
            markError(result, 'Unable to parse eligibility response.');
            return;
        }
        if (!(parsed instanceof Map<String, Object>)) {
            markError(result, 'Eligibility response was not a JSON object.');
            return;
        }

        Map<String, Object> root = (Map<String, Object>) parsed;
        String responseError = firstErrorMessage(root);
        List<Object> benefits = asList(root.get('benefitsInformation'));
        if (String.isNotBlank(responseError) && benefits.isEmpty()) {
            markError(result, responseError);
            return;
        }

        ParsedBenefits parsedBenefits = parseBenefits(root);
        result.status = parsedBenefits.status;
        result.plan = parsedBenefits.plan;
        result.copay = parsedBenefits.copay;
        result.coinsurance = parsedBenefits.coinsurance;
        result.deductible = parsedBenefits.deductible;
        result.deductibleRemaining = parsedBenefits.deductibleRemaining;
        result.oop = parsedBenefits.oop;
        if (String.isBlank(result.status)) {
            result.status = 'Active';
        }
    }

    private static ParsedBenefits parseBenefits(Map<String, Object> root) {
        ParsedBenefits parsed = new ParsedBenefits();
        List<ScoredBenefit> scored = new List<ScoredBenefit>();
        for (Object row : asList(root.get('benefitsInformation'))) {
            Map<String, Object> benefit = asMap(row);
            if (benefit.isEmpty()) {
                continue;
            }
            String code = toStringValue(benefit.get('code'));
            applyCoverageStatus(parsed, code, toStringValue(benefit.get('name')));
            if (String.isBlank(parsed.plan)) {
                parsed.plan = firstNonBlank(
                    new List<String>{
                        toStringValue(benefit.get('planCoverage')),
                        toStringValue(benefit.get('planName'))
                    }
                );
            }
            if (isUnknownBenefitCode(code)) {
                continue;
            }
            scored.add(new ScoredBenefit(benefit, code, scoreBenefit(benefit)));
        }

        applyPlanStatusFallback(parsed, asList(root.get('planStatus')));
        if (String.isBlank(parsed.plan)) {
            Map<String, Object> planInformation = asMap(root.get('planInformation'));
            parsed.plan = firstNonBlank(
                new List<String>{
                    toStringValue(planInformation.get('planName')),
                    toStringValue(planInformation.get('groupDescription'))
                }
            );
        }

        scored.sort();
        for (ScoredBenefit item : scored) {
            applyFinancialBenefit(parsed, item);
        }
        if (String.isBlank(parsed.status) && !scored.isEmpty()) {
            parsed.status = 'Active';
        }
        if (String.isBlank(parsed.status)) {
            parsed.status = 'Inactive';
        }
        return parsed;
    }

    private static void applyCoverageStatus(ParsedBenefits parsed, String code, String name) {
        String normalizedCode = code == null ? null : code.trim();
        String normalizedName = name == null ? '' : name.toLowerCase();
        if (ACTIVE_CODES.contains(normalizedCode) || normalizedName.contains('active coverage')) {
            parsed.status = 'Active';
            return;
        }
        if (parsed.status != 'Active' && (INACTIVE_CODES.contains(normalizedCode) || normalizedName == 'inactive')) {
            parsed.status = 'Inactive';
        }
    }

    private static void applyPlanStatusFallback(ParsedBenefits parsed, List<Object> planStatusRows) {
        if (planStatusRows.isEmpty()) {
            return;
        }
        for (Object row : planStatusRows) {
            Map<String, Object> statusRow = asMap(row);
            if (String.isBlank(parsed.status)) {
                applyCoverageStatus(parsed, toStringValue(statusRow.get('statusCode')), toStringValue(statusRow.get('status')));
            }
            if (String.isBlank(parsed.plan)) {
                parsed.plan = firstNonBlank(
                    new List<String>{
                        toStringValue(statusRow.get('planDetails')),
                        toStringValue(statusRow.get('planName'))
                    }
                );
            }
        }
    }

    private static Boolean isUnknownBenefitCode(String code) {
        if (String.isBlank(code)) {
            return true;
        }
        return !(ACTIVE_CODES.contains(code) ||
            INACTIVE_CODES.contains(code) ||
            code == 'A' ||
            code == 'B' ||
            code == 'C' ||
            code == 'G');
    }

    private static void applyFinancialBenefit(ParsedBenefits parsed, ScoredBenefit item) {
        if (item.code == 'B' && parsed.copay == null) {
            parsed.copay = toDecimal(item.benefit.get('benefitAmount'));
        } else if (item.code == 'A' && parsed.coinsurance == null) {
            parsed.coinsurance = normalizePercent(toDecimal(item.benefit.get('benefitPercent')));
        } else if (item.code == 'C') {
            Decimal amount = toDecimal(item.benefit.get('benefitAmount'));
            if (isRemaining(item.benefit) && parsed.deductibleRemaining == null) {
                parsed.deductibleRemaining = amount;
            } else if (parsed.deductible == null) {
                parsed.deductible = amount;
            }
        } else if (item.code == 'G' && parsed.oop == null && !isRemaining(item.benefit)) {
            parsed.oop = toDecimal(item.benefit.get('benefitAmount'));
        } else if (item.code == 'G' && parsed.oop == null) {
            parsed.oop = toDecimal(item.benefit.get('benefitAmount'));
        }
    }

    private static Boolean isRemaining(Map<String, Object> benefit) {
        String timeCode = toStringValue(benefit.get('timeQualifierCode'));
        String timeName = toStringValue(benefit.get('timeQualifier'));
        if (REMAINING_TIME_CODES.contains(timeCode)) {
            return true;
        }
        return timeName != null && timeName.toLowerCase().contains('remaining');
    }

    private static Integer scoreBenefit(Map<String, Object> benefit) {
        Integer score = 0;
        Set<String> serviceCodes = new Set<String>();
        for (Object code : asList(benefit.get('serviceTypeCodes'))) {
            String value = toStringValue(code);
            if (String.isNotBlank(value)) {
                serviceCodes.add(value);
            }
        }
        if (serviceCodes.contains('30')) {
            score += 8;
        } else if (!serviceCodes.isEmpty()) {
            score += 2;
        }
        String network = toStringValue(benefit.get('inPlanNetworkIndicatorCode'));
        if (network == 'Y') {
            score += 4;
        } else if (network == 'W') {
            score += 1;
        }
        if (toStringValue(benefit.get('coverageLevelCode')) == 'IND') {
            score += 2;
        }
        String timeCode = toStringValue(benefit.get('timeQualifierCode'));
        if (TOTAL_TIME_CODES.contains(timeCode)) {
            score += 1;
        }
        return score;
    }

    private static List<EligibilityPayerMatch> parsePayerMatches(String rawBody) {
        List<EligibilityPayerMatch> matches = new List<EligibilityPayerMatch>();
        if (String.isBlank(rawBody)) {
            return matches;
        }
        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(rawBody);
        } catch (Exception e) {
            return matches;
        }
        for (Object row : asList(asMap(parsed).get('items'))) {
            Map<String, Object> item = asMap(row);
            Map<String, Object> payer = asMap(item.get('payer'));
            if (payer.isEmpty()) {
                payer = asMap(item.get('matches'));
            }
            String payerId = firstNonBlank(
                new List<String>{ toStringValue(payer.get('stediId')), toStringValue(payer.get('primaryPayerId')) }
            );
            String name = firstNonBlank(
                new List<String>{ toStringValue(payer.get('displayName')), toStringValue(payer.get('name')) }
            );
            if (String.isBlank(payerId) && String.isBlank(name)) {
                continue;
            }
            matches.add(new EligibilityPayerMatch(payerId, name));
        }
        return matches;
    }

    private static void persistCheck(EligibilityResult result, CheckContext ctx) {
        if (ctx == null || ctx.patientId == null) {
            return;
        }
        result.plan = formatPlanName(result.plan, ctx.patientFirstName, ctx.patientLastName);
        Eligibility_Check__c record = new Eligibility_Check__c(
            Patient__c = ctx.patientId,
            Coverage__c = isCoverageId(ctx.coverageId) ? ctx.coverageId : null,
            Status__c = String.isNotBlank(result.status) ? result.status : 'Error',
            Plan_Name__c = result.plan,
            Copay__c = result.copay,
            Coinsurance_Percent__c = result.coinsurance,
            Deductible__c = result.deductible,
            Deductible_Remaining__c = result.deductibleRemaining,
            Out_of_Pocket_Max__c = result.oop,
            Service_Type__c = ctx.serviceType,
            Checked_Date__c = Datetime.now(),
            Provider_Used__c = PROVIDER_USED,
            Request_Payload__c = truncate(ctx.requestJson, REQUEST_PAYLOAD_MAX),
            Raw_Response__c = truncate(result.rawResponse, RAW_RESPONSE_MAX),
            Error_Message__c = truncate(result.error, ERROR_MESSAGE_MAX)
        );
        try {
            List<SObject> toInsert = Security.stripInaccessible(
                    AccessType.CREATABLE,
                    new List<Eligibility_Check__c>{ record }
                )
                .getRecords();
            insert toInsert;
            if (!toInsert.isEmpty()) {
                result.eligibilityCheckId = toInsert[0].Id;
            }
        } catch (Exception e) {
            if (String.isBlank(result.error)) {
                markError(result, e.getMessage());
            }
        }
    }

    private static EligibilityResult markError(EligibilityResult result, String message) {
        result.status = 'Error';
        result.error = message;
        return result;
    }

    private static String httpErrorMessage(HttpResponse response) {
        if (response == null) {
            return 'HTTP 0';
        }
        String body = response.getBody();
        String parsed = firstErrorMessage(asMap(tryParse(body)));
        if (String.isNotBlank(parsed)) {
            return parsed;
        }
        return String.isBlank(body) ? 'HTTP ' + response.getStatusCode() : 'HTTP ' + response.getStatusCode() + ': ' + body;
    }

    private static String firstErrorMessage(Map<String, Object> root) {
        if (root == null || root.isEmpty()) {
            return null;
        }
        List<String> parts = new List<String>();
        Object errorsValue = root.get('errors');
        if (errorsValue instanceof List<Object>) {
            for (Object row : (List<Object>) errorsValue) {
                Map<String, Object> errorRow = asMap(row);
                String part = firstNonBlank(
                    new List<String>{
                        toStringValue(errorRow.get('description')),
                        toStringValue(errorRow.get('message')),
                        toStringValue(errorRow.get('code'))
                    }
                );
                if (String.isNotBlank(part)) {
                    parts.add(part);
                }
            }
        } else if (errorsValue instanceof Map<String, Object>) {
            Map<String, Object> errorRow = (Map<String, Object>) errorsValue;
            String part = firstNonBlank(
                new List<String>{ toStringValue(errorRow.get('description')), toStringValue(errorRow.get('message')) }
            );
            if (String.isNotBlank(part)) {
                parts.add(part);
            }
        }
        if (parts.isEmpty()) {
            String single = firstNonBlank(
                new List<String>{ toStringValue(root.get('message')), toStringValue(root.get('error')) }
            );
            if (String.isNotBlank(single)) {
                parts.add(single);
            }
        }
        return parts.isEmpty() ? null : String.join(parts, '; ');
    }

    private static List<String> splitServiceTypes(String serviceType) {
        List<String> codes = new List<String>();
        if (String.isBlank(serviceType)) {
            return codes;
        }
        for (String part : serviceType.split(',')) {
            String trimmed = part == null ? null : part.trim();
            if (String.isNotBlank(trimmed)) {
                codes.add(trimmed);
            }
        }
        return codes;
    }

    private static String formatStediDate(Date value) {
        String month = value.month() < 10 ? '0' + String.valueOf(value.month()) : String.valueOf(value.month());
        String day = value.day() < 10 ? '0' + String.valueOf(value.day()) : String.valueOf(value.day());
        return String.valueOf(value.year()) + month + day;
    }

    private static String newControlNumber() {
        String digits = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        while (digits.length() < 9) {
            digits = '0' + digits;
        }
        return digits.left(9);
    }

    private static Decimal normalizePercent(Decimal value) {
        if (value == null) {
            return null;
        }
        if (value > 0 && value < 1) {
            return value * 100;
        }
        return value;
    }

    private static Decimal toDecimal(Object value) {
        if (value == null) {
            return null;
        }
        try {
            if (value instanceof Decimal) {
                return (Decimal) value;
            }
            if (value instanceof Integer) {
                return Decimal.valueOf((Integer) value);
            }
            if (value instanceof Long) {
                return Decimal.valueOf((Long) value);
            }
            if (value instanceof Double) {
                return Decimal.valueOf((Double) value);
            }
            String text = String.valueOf(value).trim();
            if (String.isBlank(text)) {
                return null;
            }
            return Decimal.valueOf(text);
        } catch (Exception e) {
            return null;
        }
    }

    private static String toStringValue(Object value) {
        if (value == null) {
            return null;
        }
        String text = String.valueOf(value).trim();
        return String.isBlank(text) ? null : text;
    }

    private static Map<String, Object> asMap(Object value) {
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : new Map<String, Object>();
    }

    private static List<Object> asList(Object value) {
        return value instanceof List<Object> ? (List<Object>) value : new List<Object>();
    }

    private static Object tryParse(String rawBody) {
        if (String.isBlank(rawBody)) {
            return null;
        }
        try {
            return JSON.deserializeUntyped(rawBody);
        } catch (Exception e) {
            return null;
        }
    }

    private static String firstNonBlank(List<String> values) {
        if (values == null) {
            return null;
        }
        for (String value : values) {
            if (String.isNotBlank(value)) {
                return value;
            }
        }
        return null;
    }

    private static void assignPatientName(CheckContext ctx, Patient__c patient) {
        if (patient == null) {
            return;
        }
        ctx.patientFirstName = patient.First_Name__c;
        ctx.patientLastName = patient.Last_Name__c;
    }

    private static String formatPlanName(String plan, String firstName, String lastName) {
        String base = truncate(plan, PLAN_NAME_MAX);
        if (String.isBlank(base)) {
            return base;
        }
        String person = joinPersonName(firstName, lastName);
        if (String.isBlank(person)) {
            return base;
        }
        String withName = base + ' (' + person + ')';
        return withName.length() <= PLAN_NAME_MAX ? withName : base;
    }

    private static String joinPersonName(String firstName, String lastName) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(firstName)) {
            parts.add(firstName.trim());
        }
        if (String.isNotBlank(lastName)) {
            parts.add(lastName.trim());
        }
        return String.join(parts, ' ');
    }

    private static Boolean isCoverageId(Id value) {
        return value != null && value.getSObjectType() == Coverage__c.SObjectType;
    }

    private static String truncate(String value, Integer maxLen) {
        if (value == null || value.length() <= maxLen) {
            return value;
        }
        return value.substring(0, maxLen);
    }

    private class CheckContext {
        EligibilityRequest request;
        Eligibility_Setting__mdt setting;
        Id patientId;
        Id coverageId;
        String patientFirstName;
        String patientLastName;
        String serviceType;
        String buildError;
        Map<String, Object> payload;
        String requestJson;
        String rawBody;
    }

    private class ParsedBenefits {
        String status;
        String plan;
        Decimal copay;
        Decimal coinsurance;
        Decimal deductible;
        Decimal deductibleRemaining;
        Decimal oop;
    }

    private class ScoredBenefit implements Comparable {
        Map<String, Object> benefit;
        String code;
        Integer score;

        ScoredBenefit(Map<String, Object> benefit, String code, Integer score) {
            this.benefit = benefit;
            this.code = code;
            this.score = score;
        }

        public Integer compareTo(Object other) {
            ScoredBenefit that = (ScoredBenefit) other;
            if (that.score == this.score) {
                return 0;
            }
            return that.score > this.score ? 1 : -1;
        }
    }
}
