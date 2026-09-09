public with sharing class PatientBannerController {
    private static final String CATEGORY_VITALS = 'Vital Signs';
    private static final String CODE_SYSTOLIC = '8480-6';
    private static final String CODE_DIASTOLIC = '8462-4';
    private static final String CODE_HR = '8867-4';
    private static final String CODE_RR = '9279-1';
    private static final String CODE_TEMP = '8310-5';
    private static final String CODE_SPO2 = '59408-5';
    private static final String CODE_WEIGHT = '29463-7';
    private static final Integer MAX_RESULTS = 200;

    private static final Set<String> VITAL_CODES = new Set<String>{
        CODE_SYSTOLIC,
        CODE_DIASTOLIC,
        CODE_HR,
        CODE_RR,
        CODE_TEMP,
        CODE_SPO2,
        CODE_WEIGHT
    };

    public class LatestVitals {
        @AuraEnabled
        public List<VitalItem> items { get; set; }
        @AuraEnabled
        public Datetime recordedAt { get; set; }
    }

    public class VitalItem {
        @AuraEnabled
        public String key { get; set; }
        @AuraEnabled
        public String label { get; set; }
        @AuraEnabled
        public String value { get; set; }
    }

    public class ActiveCoverage {
        @AuraEnabled
        public Id coverageId { get; set; }
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public String payerName { get; set; }
        @AuraEnabled
        public String planName { get; set; }
        @AuraEnabled
        public String memberId { get; set; }
        @AuraEnabled
        public String priority { get; set; }
        @AuraEnabled
        public String status { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static LatestVitals getLatestVitals(Id patientId) {
        LatestVitals result = new LatestVitals();
        result.items = new List<VitalItem>();
        if (patientId == null) {
            return result;
        }

        List<Observation__c> rows = [
            SELECT
                Observation_Code__c,
                Value_Quantity__c,
                Value_String__c,
                Value_Unit__c,
                Effective_DateTime__c
            FROM Observation__c
            WHERE
                Patient__c = :patientId
                AND Category__c = :CATEGORY_VITALS
                AND Observation_Code__c IN :VITAL_CODES
            ORDER BY Effective_DateTime__c DESC NULLS LAST
            LIMIT :MAX_RESULTS
        ];

        Map<String, Observation__c> latestByCode = new Map<String, Observation__c>();
        for (Observation__c row : rows) {
            if (!latestByCode.containsKey(row.Observation_Code__c)) {
                latestByCode.put(row.Observation_Code__c, row);
            }
        }

        Observation__c systolic = latestByCode.get(CODE_SYSTOLIC);
        Observation__c diastolic = latestByCode.get(CODE_DIASTOLIC);
        VitalItem bloodPressure = buildBloodPressure(systolic, diastolic);
        if (bloodPressure != null) {
            result.items.add(bloodPressure);
        }
        addIfPresent(result.items, latestByCode.get(CODE_HR), 'hr', 'HR');
        addIfPresent(result.items, latestByCode.get(CODE_RR), 'rr', 'RR');
        addIfPresent(result.items, latestByCode.get(CODE_TEMP), 'temp', 'Temp');
        addIfPresent(result.items, latestByCode.get(CODE_SPO2), 'spo2', 'SpO2');
        addIfPresent(result.items, latestByCode.get(CODE_WEIGHT), 'weight', 'Wt');

        result.recordedAt = mostRecent(latestByCode.values());
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static ActiveCoverage getActiveCoverage(Id patientId) {
        if (patientId == null) {
            return null;
        }
        List<Coverage__c> rows = [
            SELECT Name, Payer__r.Name, Plan_Name__c, Member_Id__c, Priority__c, Status__c
            FROM Coverage__c
            WHERE Patient__c = :patientId AND Status__c = 'Active'
            ORDER BY Priority__c ASC NULLS LAST, Effective_Start__c DESC NULLS LAST
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return null;
        }
        Coverage__c row = rows[0];
        ActiveCoverage coverage = new ActiveCoverage();
        coverage.coverageId = row.Id;
        coverage.name = String.isNotBlank(row.Name)
            ? row.Name
            : formatCoverageName(row.Plan_Name__c, row.Status__c, row.Name);
        coverage.payerName = row.Payer__r == null ? null : row.Payer__r.Name;
        coverage.planName = row.Plan_Name__c;
        coverage.memberId = row.Member_Id__c;
        coverage.priority = row.Priority__c;
        coverage.status = row.Status__c;
        return coverage;
    }

    private static String formatCoverageName(String planName, String status, String fallback) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(planName)) {
            parts.add(planName);
        }
        if (String.isNotBlank(status)) {
            parts.add(status);
        }
        return parts.isEmpty() ? fallback : String.join(parts, ' - ');
    }

    private static VitalItem buildBloodPressure(Observation__c systolic, Observation__c diastolic) {
        String sysValue = formatAmount(systolic);
        String diaValue = formatAmount(diastolic);
        if (String.isBlank(sysValue) && String.isBlank(diaValue)) {
            return null;
        }

        String combined;
        if (String.isNotBlank(sysValue) && String.isNotBlank(diaValue)) {
            combined = sysValue + '/' + diaValue;
        } else if (String.isNotBlank(sysValue)) {
            combined = sysValue;
        } else {
            combined = diaValue;
        }

        String unit = firstNonBlank(
            new List<String>{ unitOf(systolic), unitOf(diastolic), 'mmHg' }
        );
        VitalItem item = new VitalItem();
        item.key = 'bp';
        item.label = 'BP';
        item.value = withUnit(combined, unit);
        return item;
    }

    private static void addIfPresent(
        List<VitalItem> items,
        Observation__c row,
        String key,
        String label
    ) {
        String amount = formatAmount(row);
        if (String.isBlank(amount)) {
            return;
        }
        VitalItem item = new VitalItem();
        item.key = key;
        item.label = label;
        item.value = withUnit(amount, unitOf(row));
        items.add(item);
    }

    private static String formatAmount(Observation__c row) {
        if (row == null) {
            return '';
        }
        if (row.Value_Quantity__c != null) {
            return row.Value_Quantity__c.stripTrailingZeros().toPlainString();
        }
        return row.Value_String__c == null ? '' : row.Value_String__c;
    }

    private static String unitOf(Observation__c row) {
        return row == null || String.isBlank(row.Value_Unit__c) ? '' : displayUnit(row.Value_Unit__c);
    }

    private static String displayUnit(String unit) {
        if (unit == 'Cel') {
            return '°C';
        }
        if (unit == 'F' || unit == '[degF]') {
            return '°F';
        }
        return unit;
    }

    private static String withUnit(String amount, String unit) {
        return String.isBlank(unit) ? amount : amount + ' ' + unit;
    }

    private static String firstNonBlank(List<String> values) {
        for (String value : values) {
            if (String.isNotBlank(value)) {
                return value;
            }
        }
        return '';
    }

    private static Datetime mostRecent(List<Observation__c> rows) {
        Datetime latest;
        for (Observation__c row : rows) {
            if (row.Effective_DateTime__c == null) {
                continue;
            }
            if (latest == null || row.Effective_DateTime__c > latest) {
                latest = row.Effective_DateTime__c;
            }
        }
        return latest;
    }
}
