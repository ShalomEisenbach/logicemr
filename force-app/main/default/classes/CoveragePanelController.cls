public with sharing class CoveragePanelController {
    private static final Integer MAX_RESULTS = 200;
    private static final String STATUS_ACTIVE = 'Active';
    private static final String STATUS_INACTIVE = 'Inactive';
    private static final Set<String> ALLOWED_TYPES = new Set<String>{ 'Medical', 'Dental', 'Vision', 'Pharmacy' };
    private static final Set<String> ALLOWED_RELATIONSHIPS = new Set<String>{ 'Self', 'Spouse', 'Child', 'Other' };
    private static final Set<String> ALLOWED_STATUSES = new Set<String>{ 'Active', 'Inactive', 'Draft' };
    private static final Set<String> ALLOWED_PRIORITIES = new Set<String>{ 'Primary', 'Secondary', 'Tertiary' };

    @AuraEnabled(cacheable=true)
    public static List<Coverage__c> getCoverages(Id patientId) {
        if (patientId == null) {
            return new List<Coverage__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Payer__c,
                Payer__r.Name,
                Member_Id__c,
                Group_Number__c,
                Plan_Name__c,
                Type__c,
                Relationship_to_Subscriber__c,
                Subscriber_Name__c,
                Status__c,
                Effective_Start__c,
                Effective_End__c,
                Priority__c
            FROM Coverage__c
            WHERE Patient__c = :patientId
            ORDER BY Priority__c ASC NULLS LAST, Status__c ASC, Effective_Start__c DESC NULLS LAST
            LIMIT :MAX_RESULTS
        ];
    }

    @AuraEnabled
    public static Coverage__c saveCoverage(
        Id coverageId,
        Id patientId,
        Id payerId,
        String memberId,
        String groupNumber,
        String planName,
        String coverageType,
        String relationshipToSubscriber,
        String subscriberName,
        String status,
        Date effectiveStart,
        Date effectiveEnd,
        String priority
    ) {
        if (payerId == null) {
            throw new AuraHandledException('Payer is required.');
        }
        if (effectiveStart != null && effectiveEnd != null && effectiveEnd < effectiveStart) {
            throw new AuraHandledException('Effective End must be on or after Effective Start.');
        }

        String resolvedType = normalizePicklist(coverageType, ALLOWED_TYPES, 'Type');
        String resolvedRelationship = normalizePicklist(
            relationshipToSubscriber,
            ALLOWED_RELATIONSHIPS,
            'Relationship to Subscriber'
        );
        String resolvedPriority = normalizePicklist(priority, ALLOWED_PRIORITIES, 'Priority');

        Coverage__c coverage;
        if (coverageId == null) {
            if (patientId == null) {
                throw new AuraHandledException('Patient Id is required.');
            }
            String resolvedStatus = String.isBlank(status) ? STATUS_ACTIVE : status;
            coverage = new Coverage__c(
                Patient__c = patientId,
                Payer__c = payerId,
                Member_Id__c = memberId,
                Group_Number__c = groupNumber,
                Plan_Name__c = planName,
                Type__c = resolvedType,
                Relationship_to_Subscriber__c = resolvedRelationship,
                Subscriber_Name__c = subscriberName,
                Status__c = normalizeRequiredStatus(resolvedStatus),
                Effective_Start__c = effectiveStart,
                Effective_End__c = effectiveEnd,
                Priority__c = resolvedPriority
            );
            insert coverage;
        } else {
            List<Coverage__c> existingRows = [
                SELECT Id, Patient__c, Status__c
                FROM Coverage__c
                WHERE Id = :coverageId
                LIMIT 1
            ];
            if (existingRows.isEmpty()) {
                throw new AuraHandledException('Coverage was not found.');
            }
            coverage = existingRows[0];
            String resolvedStatus = String.isBlank(status) ? coverage.Status__c : status;
            coverage.Payer__c = payerId;
            coverage.Member_Id__c = memberId;
            coverage.Group_Number__c = groupNumber;
            coverage.Plan_Name__c = planName;
            coverage.Type__c = resolvedType;
            coverage.Relationship_to_Subscriber__c = resolvedRelationship;
            coverage.Subscriber_Name__c = subscriberName;
            coverage.Status__c = normalizeRequiredStatus(resolvedStatus);
            coverage.Effective_Start__c = effectiveStart;
            coverage.Effective_End__c = effectiveEnd;
            coverage.Priority__c = resolvedPriority;
            update coverage;
        }
        return coverage;
    }

    @AuraEnabled
    public static void inactivateCoverages(List<Id> coverageIds) {
        if (coverageIds == null || coverageIds.isEmpty()) {
            return;
        }

        List<Coverage__c> coverages = [
            SELECT Id, Status__c
            FROM Coverage__c
            WHERE Id IN :coverageIds AND Status__c != :STATUS_INACTIVE
        ];
        for (Coverage__c coverage : coverages) {
            coverage.Status__c = STATUS_INACTIVE;
        }
        if (!coverages.isEmpty()) {
            update coverages;
        }
    }

    private static String normalizePicklist(String value, Set<String> allowed, String fieldLabel) {
        if (String.isBlank(value)) {
            return null;
        }
        if (!allowed.contains(value)) {
            throw new AuraHandledException(fieldLabel + ' is not a valid value.');
        }
        return value;
    }

    private static String normalizeRequiredStatus(String status) {
        if (String.isBlank(status) || !ALLOWED_STATUSES.contains(status)) {
            throw new AuraHandledException('Status is not a valid coverage status.');
        }
        return status;
    }
}
