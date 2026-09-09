public with sharing class AlertBarController {
    private static final Integer MAX_RESULTS = 200;
    private static final Integer MAX_QUERY = 50;
    private static final Integer MAX_CHIPS = 8;
    private static final String STATUS_ACTIVE = 'Active';
    private static final String CATEGORY_PROBLEM = 'Problem List Item';
    private static final String CRITICALITY_HIGH = 'High';
    private static final Set<String> ABNORMAL_INTERPRETATIONS = new Set<String>{
        'High',
        'Low',
        'Critical',
        'Abnormal'
    };
    private static final Set<String> OPEN_PROCEDURE_STATUSES = new Set<String>{
        'Preparation',
        'In Progress',
        'On Hold'
    };

    public class ClinicalSummary {
        @AuraEnabled
        public List<SummarySection> sections;
    }

    public class SummarySection {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String emptyLabel;
        @AuraEnabled
        public String tone;
        @AuraEnabled
        public String variant;
        @AuraEnabled
        public Integer totalCount;
        @AuraEnabled
        public List<SummaryItem> items;
    }

    public class SummaryItem {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String objectApiName;
        @AuraEnabled
        public String flag;
        @AuraEnabled
        public String title;
        @AuraEnabled
        public String value;
        @AuraEnabled
        public String unit;
        @AuraEnabled
        public String detail;
        @AuraEnabled
        public Boolean emphasize;
    }

    @AuraEnabled(cacheable=true)
    public static Id resolvePatientId(Id recordId) {
        if (recordId == null) {
            return null;
        }

        Schema.SObjectType recordType = recordId.getSObjectType();
        if (recordType == Patient__c.SObjectType) {
            return recordId;
        }
        if (recordType == Encounter__c.SObjectType) {
            List<Encounter__c> encounters = [
                SELECT Patient__c
                FROM Encounter__c
                WHERE Id = :recordId
                LIMIT 1
            ];
            return encounters.isEmpty() ? null : encounters[0].Patient__c;
        }
        return null;
    }

    @AuraEnabled(cacheable=true)
    public static List<AllergyIntolerance__c> getActiveAllergies(Id recordId) {
        Id patientId = resolvePatientId(recordId);
        if (patientId == null) {
            return new List<AllergyIntolerance__c>();
        }
        return sortAllergies([
            SELECT Id, Allergen_Display__c, Allergen_Code__c, Criticality__c, Clinical_Status__c
            FROM AllergyIntolerance__c
            WHERE Patient__c = :patientId AND Clinical_Status__c = :STATUS_ACTIVE
            ORDER BY Allergen_Display__c ASC NULLS LAST
            LIMIT :MAX_RESULTS
        ]);
    }

    @AuraEnabled(cacheable=true)
    public static ClinicalSummary getClinicalSummary(Id recordId) {
        ClinicalSummary summary = new ClinicalSummary();
        summary.sections = new List<SummarySection>();
        Id patientId = resolvePatientId(recordId);
        if (patientId == null) {
            summary.sections.addAll(emptySections());
            return summary;
        }

        summary.sections.add(buildProblems(queryProblems(patientId)));
        summary.sections.add(buildAllergies(queryAllergies(patientId)));
        summary.sections.add(buildCoverages(queryCoverages(patientId)));
        summary.sections.add(buildMedications(queryMedicationOrders(patientId), queryReportedMedications(patientId)));
        summary.sections.add(buildFlowsheet(queryAbnormalFindings(patientId)));
        summary.sections.add(buildResults(queryResults(patientId)));
        summary.sections.add(buildProcedures(queryProcedures(patientId)));
        return summary;
    }

    private static List<SummarySection> emptySections() {
        return new List<SummarySection>{
            buildProblems(new List<Condition__c>()),
            buildAllergies(new List<AllergyIntolerance__c>()),
            buildCoverages(new List<Coverage__c>()),
            buildMedications(new List<MedicationRequest__c>(), new List<MedicationStatement__c>()),
            buildFlowsheet(new List<Observation__c>()),
            buildResults(new List<DiagnosticReport__c>()),
            buildProcedures(new List<Procedure__c>())
        };
    }

    private static List<Condition__c> queryProblems(Id patientId) {
        return [
            SELECT Id, Diagnosis_Display__c, Diagnosis_Code__c, Clinical_Status__c
            FROM Condition__c
            WHERE
                Patient__c = :patientId
                AND Category__c = :CATEGORY_PROBLEM
                AND Clinical_Status__c = :STATUS_ACTIVE
            ORDER BY Diagnosis_Display__c ASC NULLS LAST
            LIMIT :MAX_QUERY
        ];
    }

    private static List<AllergyIntolerance__c> queryAllergies(Id patientId) {
        return sortAllergies([
            SELECT Id, Allergen_Display__c, Allergen_Code__c, Criticality__c
            FROM AllergyIntolerance__c
            WHERE Patient__c = :patientId AND Clinical_Status__c = :STATUS_ACTIVE
            ORDER BY Allergen_Display__c ASC NULLS LAST
            LIMIT :MAX_QUERY
        ]);
    }

    private static List<Coverage__c> queryCoverages(Id patientId) {
        return [
            SELECT Id, Name, Plan_Name__c, Status__c, Priority__c, Payer__r.Name
            FROM Coverage__c
            WHERE Patient__c = :patientId AND Status__c = :STATUS_ACTIVE
            ORDER BY Priority__c ASC NULLS LAST, Effective_Start__c DESC NULLS LAST
            LIMIT :MAX_RESULTS
        ];
    }

    private static List<MedicationRequest__c> queryMedicationOrders(Id patientId) {
        return [
            SELECT Id, Medication_Display__c, Medication_Code__c, Dosage_Text__c, Status__c
            FROM MedicationRequest__c
            WHERE Patient__c = :patientId AND Status__c = :STATUS_ACTIVE
            ORDER BY Medication_Display__c ASC NULLS LAST
            LIMIT :MAX_QUERY
        ];
    }

    private static List<MedicationStatement__c> queryReportedMedications(Id patientId) {
        return [
            SELECT Id, Medication_Display__c, Medication_Code__c, Dosage_Text__c, Source__c, Status__c
            FROM MedicationStatement__c
            WHERE Patient__c = :patientId AND Status__c = :STATUS_ACTIVE
            ORDER BY Medication_Display__c ASC NULLS LAST
            LIMIT :MAX_QUERY
        ];
    }

    private static List<Observation__c> queryAbnormalFindings(Id patientId) {
        return [
            SELECT
                Id,
                Observation_Display__c,
                Observation_Code__c,
                Value_Quantity__c,
                Value_String__c,
                Value_Unit__c,
                Interpretation__c,
                Effective_DateTime__c
            FROM Observation__c
            WHERE Patient__c = :patientId AND Interpretation__c IN :ABNORMAL_INTERPRETATIONS
            ORDER BY Effective_DateTime__c DESC NULLS LAST
            LIMIT :MAX_QUERY
        ];
    }

    private static List<DiagnosticReport__c> queryResults(Id patientId) {
        return [
            SELECT Id, Report_Display__c, Report_Code__c, Status__c, Reviewed__c, Issued__c
            FROM DiagnosticReport__c
            WHERE Patient__c = :patientId
            ORDER BY Reviewed__c ASC, Issued__c DESC NULLS LAST, Report_Display__c ASC NULLS LAST
            LIMIT :MAX_QUERY
        ];
    }

    private static List<Procedure__c> queryProcedures(Id patientId) {
        return [
            SELECT Id, Procedure_Display__c, Procedure_Code__c, Status__c, Performed_DateTime__c
            FROM Procedure__c
            WHERE Patient__c = :patientId
            ORDER BY Performed_DateTime__c DESC NULLS LAST, Procedure_Display__c ASC NULLS LAST
            LIMIT :MAX_QUERY
        ];
    }

    private static SummarySection buildProblems(List<Condition__c> rows) {
        List<SummaryItem> items = new List<SummaryItem>();
        String objectApiName = objectName(Condition__c.SObjectType);
        for (Condition__c row : rows) {
            items.add(
                newItem(
                    row.Id,
                    firstNonBlank(row.Diagnosis_Display__c, row.Diagnosis_Code__c, 'Problem'),
                    objectApiName,
                    null,
                    row.Diagnosis_Display__c,
                    false
                )
            );
        }
        return newSection(
            'problems',
            'Problems',
            'No active problems',
            items.isEmpty() ? 'empty' : 'info',
            'chips',
            items
        );
    }

    private static SummarySection buildAllergies(List<AllergyIntolerance__c> rows) {
        List<SummaryItem> items = new List<SummaryItem>();
        String objectApiName = objectName(AllergyIntolerance__c.SObjectType);
        Boolean hasHigh = false;
        for (AllergyIntolerance__c row : rows) {
            Boolean isHigh = row.Criticality__c == CRITICALITY_HIGH;
            hasHigh = hasHigh || isHigh;
            items.add(
                newItem(
                    row.Id,
                    firstNonBlank(row.Allergen_Display__c, row.Allergen_Code__c, 'Allergy'),
                    objectApiName,
                    isHigh ? 'High' : null,
                    row.Criticality__c,
                    isHigh
                )
            );
        }
        String tone = 'empty';
        if (hasHigh) {
            tone = 'high';
        } else if (!items.isEmpty()) {
            tone = 'warning';
        }
        return newSection('allergies', 'Allergies', 'No known allergies', tone, 'chips', items);
    }

    private static SummarySection buildCoverages(List<Coverage__c> rows) {
        List<SummaryItem> items = new List<SummaryItem>();
        String objectApiName = objectName(Coverage__c.SObjectType);
        for (Coverage__c row : rows) {
            items.add(
                newItem(
                    row.Id,
                    coverageDisplayName(row),
                    objectApiName,
                    row.Priority__c,
                    firstNonBlank(row.Payer__r == null ? null : row.Payer__r.Name, row.Name),
                    false
                )
            );
        }
        return newSection(
            'coverage',
            'Coverage',
            'No active coverage',
            items.isEmpty() ? 'empty' : 'info',
            'chips',
            items,
            items.size()
        );
    }

    private static SummarySection buildMedications(
        List<MedicationRequest__c> orders,
        List<MedicationStatement__c> reported
    ) {
        List<SummaryItem> items = new List<SummaryItem>();
        String orderObject = objectName(MedicationRequest__c.SObjectType);
        String statementObject = objectName(MedicationStatement__c.SObjectType);
        for (MedicationRequest__c row : orders) {
            SummaryItem item = newItem(
                row.Id,
                firstNonBlank(row.Medication_Display__c, row.Medication_Code__c, 'Medication'),
                orderObject,
                null,
                firstNonBlank(row.Dosage_Text__c, row.Medication_Display__c),
                false
            );
            item.detail = row.Dosage_Text__c;
            items.add(item);
        }
        for (MedicationStatement__c row : reported) {
            SummaryItem item = newItem(
                row.Id,
                firstNonBlank(row.Medication_Display__c, row.Medication_Code__c, 'Medication'),
                statementObject,
                'Reported',
                firstNonBlank(row.Dosage_Text__c, row.Source__c, row.Medication_Display__c),
                false
            );
            item.detail = row.Dosage_Text__c;
            items.add(item);
        }
        return newSection(
            'medications',
            'Medications',
            'No active medications',
            items.isEmpty() ? 'empty' : 'success',
            'list',
            items
        );
    }

    private static SummarySection buildFlowsheet(List<Observation__c> rows) {
        Map<String, Observation__c> latestByKey = new Map<String, Observation__c>();
        for (Observation__c row : rows) {
            String key = String.valueOf(row.Observation_Code__c) + '|' + String.valueOf(row.Observation_Display__c);
            if (!latestByKey.containsKey(key)) {
                latestByKey.put(key, row);
            }
        }

        List<RankedObservation> ranked = new List<RankedObservation>();
        for (Observation__c row : latestByKey.values()) {
            ranked.add(new RankedObservation(row));
        }
        ranked.sort();

        List<SummaryItem> items = new List<SummaryItem>();
        String objectApiName = objectName(Observation__c.SObjectType);
        Boolean hasCritical = false;
        for (RankedObservation rankedRow : ranked) {
            Observation__c row = rankedRow.row;
            Boolean isCritical = row.Interpretation__c == 'Critical';
            hasCritical = hasCritical || isCritical;
            SummaryItem item = newItem(
                row.Id,
                metricLabel(row),
                objectApiName,
                row.Interpretation__c,
                firstNonBlank(row.Observation_Display__c, row.Observation_Code__c, row.Interpretation__c),
                isCritical
            );
            item.value = formatObservationValue(row);
            item.unit = displayUnit(row.Value_Unit__c);
            items.add(item);
        }
        String tone = 'empty';
        if (hasCritical) {
            tone = 'high';
        } else if (!items.isEmpty()) {
            tone = 'warning';
        }
        return newSection('flowsheet', 'Flowsheet', 'No abnormal findings', tone, 'metrics', items);
    }

    private static SummarySection buildResults(List<DiagnosticReport__c> rows) {
        List<SummaryItem> items = new List<SummaryItem>();
        String objectApiName = objectName(DiagnosticReport__c.SObjectType);
        Boolean hasUnreviewed = false;
        for (DiagnosticReport__c row : rows) {
            Boolean unreviewed = row.Reviewed__c != true;
            hasUnreviewed = hasUnreviewed || unreviewed;
            items.add(
                newItem(
                    row.Id,
                    firstNonBlank(row.Report_Display__c, row.Report_Code__c, 'Result'),
                    objectApiName,
                    unreviewed ? 'New' : null,
                    unreviewed ? 'Unreviewed' : row.Status__c,
                    false
                )
            );
        }
        String tone = 'empty';
        if (hasUnreviewed) {
            tone = 'attention';
        } else if (!items.isEmpty()) {
            tone = 'info';
        }
        return newSection('results', 'Results', 'No recent results', tone, 'chips', items);
    }

    private static SummarySection buildProcedures(List<Procedure__c> rows) {
        List<RankedProcedure> ranked = new List<RankedProcedure>();
        for (Procedure__c row : rows) {
            ranked.add(new RankedProcedure(row));
        }
        ranked.sort();

        List<SummaryItem> items = new List<SummaryItem>();
        String objectApiName = objectName(Procedure__c.SObjectType);
        Boolean hasOpen = false;
        for (RankedProcedure rankedRow : ranked) {
            Procedure__c row = rankedRow.row;
            Boolean isOpen = OPEN_PROCEDURE_STATUSES.contains(row.Status__c);
            hasOpen = hasOpen || isOpen;
            items.add(
                newItem(
                    row.Id,
                    firstNonBlank(row.Procedure_Display__c, row.Procedure_Code__c, 'Procedure'),
                    objectApiName,
                    isOpen ? row.Status__c : null,
                    row.Status__c,
                    false
                )
            );
        }
        String tone = 'empty';
        if (hasOpen) {
            tone = 'attention';
        } else if (!items.isEmpty()) {
            tone = 'info';
        }
        return newSection('procedures', 'Procedures', 'No procedures', tone, 'chips', items);
    }

    private static SummarySection newSection(
        String key,
        String label,
        String emptyLabel,
        String tone,
        String variant,
        List<SummaryItem> items
    ) {
        return newSection(key, label, emptyLabel, tone, variant, items, MAX_CHIPS);
    }

    private static SummarySection newSection(
        String key,
        String label,
        String emptyLabel,
        String tone,
        String variant,
        List<SummaryItem> items,
        Integer maxItems
    ) {
        SummarySection section = new SummarySection();
        section.key = key;
        section.label = label;
        section.emptyLabel = emptyLabel;
        section.tone = tone;
        section.variant = variant;
        section.totalCount = items.size();
        section.items = new List<SummaryItem>();
        Integer limitSize = Math.min(items.size(), maxItems);
        for (Integer i = 0; i < limitSize; i++) {
            section.items.add(items[i]);
        }
        return section;
    }

    private static String coverageDisplayName(Coverage__c row) {
        if (String.isNotBlank(row.Name)) {
            return row.Name;
        }
        List<String> parts = new List<String>();
        if (String.isNotBlank(row.Plan_Name__c)) {
            parts.add(row.Plan_Name__c);
        }
        if (String.isNotBlank(row.Status__c)) {
            parts.add(row.Status__c);
        }
        if (!parts.isEmpty()) {
            return String.join(parts, ' - ');
        }
        return firstNonBlank(row.Payer__r == null ? null : row.Payer__r.Name, 'Coverage');
    }

    private static SummaryItem newItem(
        Id recordId,
        String name,
        String objectApiName,
        String flag,
        String title,
        Boolean emphasize
    ) {
        SummaryItem item = new SummaryItem();
        item.id = recordId;
        item.name = name;
        item.objectApiName = objectApiName;
        item.flag = flag;
        item.title = title;
        item.emphasize = emphasize == true;
        return item;
    }

    private static String metricLabel(Observation__c row) {
        String mapped = metricLabelForCode(row.Observation_Code__c);
        if (String.isNotBlank(mapped)) {
            return mapped;
        }
        return abbreviateDisplay(firstNonBlank(row.Observation_Display__c, row.Observation_Code__c, 'Obs'));
    }

    private static String metricLabelForCode(String code) {
        if (code == '8480-6') {
            return 'SBP';
        }
        if (code == '8462-4') {
            return 'DBP';
        }
        if (code == '8867-4') {
            return 'HR';
        }
        if (code == '9279-1') {
            return 'RR';
        }
        if (code == '8310-5') {
            return 'Temp';
        }
        if (code == '59408-5') {
            return 'SpO2';
        }
        if (code == '29463-7') {
            return 'Wt';
        }
        if (code == '4548-4') {
            return 'A1c';
        }
        if (code == '2345-7' || code == '2339-0' || code == '1558-6') {
            return 'Glu';
        }
        if (code == '2089-1' || code == '18262-6') {
            return 'LDL';
        }
        if (code == '2085-9') {
            return 'HDL';
        }
        if (code == '2093-3') {
            return 'Chol';
        }
        if (code == '2571-8') {
            return 'Trig';
        }
        if (code == '2823-3') {
            return 'K';
        }
        if (code == '718-7') {
            return 'Hgb';
        }
        return null;
    }

    private static String abbreviateDisplay(String display) {
        if (String.isBlank(display) || display.length() <= 10) {
            return display;
        }
        Set<String> skip = new Set<String>{ 'of', 'the', 'and', 'in', 'a' };
        List<String> parts = display.split('\\s+');
        if (parts.size() >= 2) {
            String initials = '';
            for (String part : parts) {
                if (String.isBlank(part) || skip.contains(part.toLowerCase())) {
                    continue;
                }
                initials += part.substring(0, 1).toUpperCase();
            }
            if (initials.length() >= 2 && initials.length() <= 5) {
                return initials;
            }
        }
        return display;
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

    private static String formatObservationValue(Observation__c row) {
        if (row.Value_Quantity__c != null) {
            return row.Value_Quantity__c.stripTrailingZeros().toPlainString();
        }
        return row.Value_String__c;
    }

    private static List<AllergyIntolerance__c> sortAllergies(List<AllergyIntolerance__c> rows) {
        List<AllergyIntolerance__c> high = new List<AllergyIntolerance__c>();
        List<AllergyIntolerance__c> other = new List<AllergyIntolerance__c>();
        for (AllergyIntolerance__c row : rows) {
            if (row.Criticality__c == CRITICALITY_HIGH) {
                high.add(row);
            } else {
                other.add(row);
            }
        }
        high.addAll(other);
        return high;
    }

    private static String objectName(Schema.SObjectType sType) {
        return sType.getDescribe().getName();
    }

    private static String firstNonBlank(String first, String second) {
        return firstNonBlank(first, second, null);
    }

    private static String firstNonBlank(String first, String second, String fallback) {
        if (String.isNotBlank(first)) {
            return first;
        }
        if (String.isNotBlank(second)) {
            return second;
        }
        return fallback;
    }

    private static Integer interpretationRank(String interpretation) {
        if (interpretation == 'Critical') {
            return 0;
        }
        if (interpretation == 'High' || interpretation == 'Low') {
            return 1;
        }
        return 2;
    }

    private class RankedObservation implements Comparable {
        public Observation__c row;

        public RankedObservation(Observation__c row) {
            this.row = row;
        }

        public Integer compareTo(Object other) {
            RankedObservation that = (RankedObservation) other;
            Integer rankCompare = interpretationRank(row.Interpretation__c) -
                interpretationRank(that.row.Interpretation__c);
            if (rankCompare != 0) {
                return rankCompare;
            }
            Long leftTime = row.Effective_DateTime__c == null ? 0 : row.Effective_DateTime__c.getTime();
            Long rightTime = that.row.Effective_DateTime__c == null ? 0 : that.row.Effective_DateTime__c.getTime();
            if (rightTime > leftTime) {
                return 1;
            }
            if (rightTime < leftTime) {
                return -1;
            }
            return 0;
        }
    }

    private class RankedProcedure implements Comparable {
        public Procedure__c row;

        public RankedProcedure(Procedure__c row) {
            this.row = row;
        }

        public Integer compareTo(Object other) {
            RankedProcedure that = (RankedProcedure) other;
            Boolean leftOpen = OPEN_PROCEDURE_STATUSES.contains(row.Status__c);
            Boolean rightOpen = OPEN_PROCEDURE_STATUSES.contains(that.row.Status__c);
            if (leftOpen != rightOpen) {
                return leftOpen ? -1 : 1;
            }
            Long leftTime = row.Performed_DateTime__c == null ? 0 : row.Performed_DateTime__c.getTime();
            Long rightTime = that.row.Performed_DateTime__c == null ? 0 : that.row.Performed_DateTime__c.getTime();
            if (rightTime > leftTime) {
                return 1;
            }
            if (rightTime < leftTime) {
                return -1;
            }
            return 0;
        }
    }
}
