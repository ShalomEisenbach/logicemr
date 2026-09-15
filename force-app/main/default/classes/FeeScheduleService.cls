public with sharing class FeeScheduleService {
    private static final String OVERRIDE_PERMISSION = 'LogicEMR_Override_Charge_Rates';

    @TestVisible
    private static Boolean overrideRatesOverride;

    public class RateRequest {
        public String key;
        public String codeSystem;
        public String code;
        public Date serviceDate;
        public Decimal units;

        public RateRequest(String key, String codeSystem, String code, Date serviceDate, Decimal units) {
            this.key = key;
            this.codeSystem = codeSystem;
            this.code = code;
            this.serviceDate = serviceDate;
            this.units = units;
        }
    }

    public class RateQuote {
        @AuraEnabled
        public Boolean found;
        @AuraEnabled
        public Boolean expired;
        @AuraEnabled
        public Id rateId;
        @AuraEnabled
        public Decimal unitRate;
        @AuraEnabled
        public Decimal lineAmount;
        @AuraEnabled
        public String source;
        @AuraEnabled
        public String message;

        public RateQuote() {
            found = false;
            expired = false;
        }
    }

    public static Boolean canOverrideRates() {
        return overrideRatesOverride != null
            ? overrideRatesOverride
            : FeatureManagement.checkPermission(OVERRIDE_PERMISSION);
    }

    public static RateQuote quoteOne(
        Superbill__c superbill,
        String codeSystem,
        String code,
        Date serviceDate,
        Decimal units
    ) {
        List<RateRequest> requests = new List<RateRequest>{
            new RateRequest('quote', codeSystem, code, serviceDate, units)
        };
        return quote(superbill, requests).get('quote');
    }

    public static Map<String, RateQuote> quote(Superbill__c superbill, List<RateRequest> requests) {
        Map<String, RateQuote> results = new Map<String, RateQuote>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        Set<String> codeSystems = new Set<String>();
        Set<String> codes = new Set<String>();
        for (RateRequest request : requests) {
            RateQuote emptyQuote = new RateQuote();
            emptyQuote.message = 'No applicable fee schedule rate was found.';
            results.put(request.key, emptyQuote);
            if (String.isNotBlank(request.codeSystem) && String.isNotBlank(request.code)) {
                codeSystems.add(request.codeSystem.trim());
                codes.add(request.code.trim());
            }
        }
        if (superbill == null || codeSystems.isEmpty() || codes.isEmpty()) {
            return results;
        }

        Id payerId;
        String payerType;
        if (superbill.Coverage__c != null && superbill.Coverage__r != null) {
            payerId = superbill.Coverage__r.Payer__c;
            if (superbill.Coverage__r.Payer__r != null) {
                payerType = superbill.Coverage__r.Payer__r.Type__c;
            }
        }
        Boolean selfPay = payerId == null || payerType == 'Self-Pay';

        List<Fee_Schedule_Rate__c> candidates;
        if (selfPay) {
            candidates = [
                SELECT Id, Fee_Schedule__c, Fee_Schedule__r.Name, Fee_Schedule__r.Schedule_Type__c,
                       Fee_Schedule__r.Priority__c, Procedure_Code_System__c, Procedure_Code__c,
                       Rate_Amount__c, Effective_Start__c, Effective_End__c
                FROM Fee_Schedule_Rate__c
                WHERE Active__c = TRUE
                  AND Fee_Schedule__r.Active__c = TRUE
                  AND Fee_Schedule__r.Schedule_Type__c = 'Self-Pay'
                  AND Procedure_Code_System__c IN :codeSystems
                  AND Procedure_Code__c IN :codes
                ORDER BY Fee_Schedule__r.Priority__c ASC NULLS LAST,
                         Effective_Start__c DESC, CreatedDate DESC, Id ASC
            ];
        } else {
            candidates = [
                SELECT Id, Fee_Schedule__c, Fee_Schedule__r.Name, Fee_Schedule__r.Schedule_Type__c,
                       Fee_Schedule__r.Priority__c, Procedure_Code_System__c, Procedure_Code__c,
                       Rate_Amount__c, Effective_Start__c, Effective_End__c
                FROM Fee_Schedule_Rate__c
                WHERE Active__c = TRUE
                  AND Fee_Schedule__r.Active__c = TRUE
                  AND Fee_Schedule__r.Schedule_Type__c = 'Payer'
                  AND Fee_Schedule__r.Payer__c = :payerId
                  AND Procedure_Code_System__c IN :codeSystems
                  AND Procedure_Code__c IN :codes
                ORDER BY Fee_Schedule__r.Priority__c ASC NULLS LAST,
                         Effective_Start__c DESC, CreatedDate DESC, Id ASC
            ];
        }

        Map<String, List<Fee_Schedule_Rate__c>> candidatesByCode = new Map<String, List<Fee_Schedule_Rate__c>>();
        for (Fee_Schedule_Rate__c candidate : candidates) {
            String compositeKey = rateKey(candidate.Procedure_Code_System__c, candidate.Procedure_Code__c);
            if (!candidatesByCode.containsKey(compositeKey)) {
                candidatesByCode.put(compositeKey, new List<Fee_Schedule_Rate__c>());
            }
            candidatesByCode.get(compositeKey).add(candidate);
        }

        for (RateRequest request : requests) {
            if (String.isBlank(request.codeSystem) || String.isBlank(request.code) || request.serviceDate == null) {
                continue;
            }
            List<Fee_Schedule_Rate__c> matching = candidatesByCode.get(rateKey(request.codeSystem, request.code));
            if (matching == null) {
                continue;
            }
            Fee_Schedule_Rate__c selected;
            Fee_Schedule_Rate__c mostRecentExpired;
            for (Fee_Schedule_Rate__c candidate : matching) {
                if (candidate.Effective_Start__c <= request.serviceDate &&
                    (candidate.Effective_End__c == null || candidate.Effective_End__c >= request.serviceDate)) {
                    selected = candidate;
                    break;
                }
                if (candidate.Effective_End__c != null && candidate.Effective_End__c < request.serviceDate &&
                    mostRecentExpired == null) {
                    mostRecentExpired = candidate;
                }
            }

            RateQuote rateQuote = results.get(request.key);
            if (selected == null) {
                if (mostRecentExpired != null) {
                    rateQuote.expired = true;
                    rateQuote.message = 'The latest matching fee schedule rate expired on ' +
                        String.valueOf(mostRecentExpired.Effective_End__c) + '.';
                }
                continue;
            }
            rateQuote.found = true;
            rateQuote.rateId = selected.Id;
            rateQuote.unitRate = selected.Rate_Amount__c;
            rateQuote.lineAmount = calculateLineAmount(selected.Rate_Amount__c, request.units);
            rateQuote.source = buildSource(selected);
            rateQuote.message = null;
        }
        return results;
    }

    public static void applyAutomaticRate(Charge_Line__c charge, RateQuote rateQuote) {
        charge.Rate_Override__c = false;
        charge.Override_Reason__c = null;
        if (rateQuote != null && rateQuote.found) {
            charge.Fee_Schedule_Rate__c = rateQuote.rateId;
            charge.Applied_Unit_Rate__c = rateQuote.unitRate;
            charge.Charge_Amount__c = rateQuote.lineAmount;
            charge.Rate_Source__c = rateQuote.source;
        } else {
            charge.Fee_Schedule_Rate__c = null;
            charge.Applied_Unit_Rate__c = null;
            charge.Charge_Amount__c = null;
            charge.Rate_Source__c = null;
        }
    }

    public static void applyRequestedRate(
        Charge_Line__c charge,
        RateQuote rateQuote,
        Decimal requestedAmount,
        Boolean overrideRequested,
        String overrideReason
    ) {
        if (overrideRequested != true) {
            applyAutomaticRate(charge, rateQuote);
            return;
        }
        if (!canOverrideRates()) {
            throw new AuraHandledException('You do not have permission to override fee schedule rates.');
        }
        if (String.isBlank(overrideReason)) {
            throw new AuraHandledException('An override reason is required when changing a scheduled charge.');
        }
        if (requestedAmount == null || requestedAmount <= 0) {
            throw new AuraHandledException('An overridden charge amount must be greater than zero.');
        }

        charge.Fee_Schedule_Rate__c = rateQuote != null && rateQuote.found ? rateQuote.rateId : null;
        charge.Applied_Unit_Rate__c = rateQuote != null && rateQuote.found
            ? rateQuote.unitRate
            : calculateUnitRate(requestedAmount, charge.Units__c);
        charge.Charge_Amount__c = requestedAmount.setScale(2);
        charge.Rate_Source__c = rateQuote != null && rateQuote.found
            ? rateQuote.source
            : 'Override - no applicable fee schedule rate';
        charge.Rate_Override__c = true;
        charge.Override_Reason__c = overrideReason.trim();
    }

    public static void enforceChargeIntegrity(List<Charge_Line__c> charges) {
        Boolean overrideAllowed = canOverrideRates();
        for (Charge_Line__c charge : charges) {
            if (charge.Rate_Override__c == true) {
                if (!overrideAllowed) {
                    charge.addError('You do not have permission to override fee schedule rates.');
                } else if (String.isBlank(charge.Override_Reason__c)) {
                    charge.addError('An override reason is required for an overridden charge.');
                }
                continue;
            }
            if (String.isNotBlank(charge.Override_Reason__c)) {
                charge.addError('Override reason can only be set when Rate Override is selected.');
            }
            Decimal expected = calculateLineAmount(charge.Applied_Unit_Rate__c, charge.Units__c);
            if (expected != null &&
                (charge.Charge_Amount__c == null || expected.setScale(2) != charge.Charge_Amount__c.setScale(2))) {
                charge.addError('Charge amount must equal the applied unit rate times units unless an override is approved.');
            }
        }
    }

    private static Decimal calculateLineAmount(Decimal unitRate, Decimal units) {
        if (unitRate == null || units == null) return null;
        return (unitRate * units).setScale(2);
    }

    private static Decimal calculateUnitRate(Decimal amount, Decimal units) {
        if (amount == null || units == null || units == 0) return null;
        return (amount / units).setScale(2);
    }

    private static String rateKey(String codeSystem, String code) {
        return (String.isBlank(codeSystem) ? '' : codeSystem.trim().toUpperCase()) + '|' +
            (String.isBlank(code) ? '' : code.trim().toUpperCase());
    }

    private static String buildSource(Fee_Schedule_Rate__c rate) {
        String dates = String.valueOf(rate.Effective_Start__c) + ' to ' +
            (rate.Effective_End__c == null ? 'open' : String.valueOf(rate.Effective_End__c));
        return rate.Fee_Schedule__r.Name + ' - ' + dates;
    }
}
