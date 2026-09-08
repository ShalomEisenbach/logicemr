public with sharing class CoveragePanelController {
    private static final Integer MAX_RESULTS = 200;
    private static final String STATUS_ACTIVE = 'Active';
    private static final String STATUS_INACTIVE = 'Inactive';
    private static final String SIDE_FRONT = 'Front';
    private static final String SIDE_BACK = 'Back';
    private static final String TITLE_FRONT = 'ID Card Front';
    private static final String TITLE_BACK = 'ID Card Back';
    private static final Set<String> ALLOWED_TYPES = new Set<String>{ 'Medical', 'Dental', 'Vision', 'Pharmacy' };
    private static final Set<String> ALLOWED_RELATIONSHIPS = new Set<String>{ 'Self', 'Spouse', 'Child', 'Other' };
    private static final Set<String> ALLOWED_STATUSES = new Set<String>{ 'Active', 'Inactive', 'Draft' };
    private static final Set<String> ALLOWED_PRIORITIES = new Set<String>{ 'Primary', 'Secondary', 'Tertiary' };
    private static final Set<String> ALLOWED_SIDES = new Set<String>{ SIDE_FRONT, SIDE_BACK };
    private static final Set<String> IMAGE_EXTENSIONS = new Set<String>{
        'png',
        'jpg',
        'jpeg',
        'gif',
        'webp',
        'bmp'
    };

    public class CoverageRow {
        @AuraEnabled
        public Coverage__c coverage;
        @AuraEnabled
        public List<IdCardFile> idCardFiles;
        @AuraEnabled
        public String latestEligibilityStatus;
        @AuraEnabled
        public Datetime latestEligibilityChecked;
    }

    public class IdCardFile {
        @AuraEnabled
        public Id contentDocumentId;
        @AuraEnabled
        public Id contentVersionId;
        @AuraEnabled
        public String title;
        @AuraEnabled
        public String fileExtension;
        @AuraEnabled
        public String side;
        @AuraEnabled
        public Boolean isImage;
    }

    @AuraEnabled(cacheable=true)
    public static List<CoverageRow> getCoverages(Id patientId) {
        if (patientId == null) {
            return new List<CoverageRow>();
        }
        List<Coverage__c> coverages = [
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
        Set<Id> coverageIds = new Map<Id, Coverage__c>(coverages).keySet();
        Map<Id, List<IdCardFile>> filesByCoverage = loadIdCardFiles(coverageIds);
        Map<Id, Eligibility_Check__c> latestByCoverage = loadLatestEligibility(coverageIds);
        List<CoverageRow> rows = new List<CoverageRow>();
        for (Coverage__c coverage : coverages) {
            CoverageRow row = new CoverageRow();
            row.coverage = coverage;
            row.idCardFiles = filesByCoverage.containsKey(coverage.Id)
                ? filesByCoverage.get(coverage.Id)
                : new List<IdCardFile>();
            Eligibility_Check__c latest = latestByCoverage.get(coverage.Id);
            if (latest != null) {
                row.latestEligibilityStatus = latest.Status__c;
                row.latestEligibilityChecked = latest.Checked_Date__c;
            }
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static void labelIdCardFile(Id coverageId, Id contentDocumentId, String side) {
        String title = titleForSide(side);
        verifyLinkedDocument(coverageId, contentDocumentId);
        ContentDocument document = new ContentDocument(Id = contentDocumentId, Title = title);
        update document;
        deleteOtherIdCardFiles(coverageId, contentDocumentId, title);
    }

    @AuraEnabled
    public static void deleteIdCardFile(Id coverageId, Id contentDocumentId) {
        verifyLinkedDocument(coverageId, contentDocumentId);
        delete new ContentDocument(Id = contentDocumentId);
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

    private static Map<Id, Eligibility_Check__c> loadLatestEligibility(Set<Id> coverageIds) {
        Map<Id, Eligibility_Check__c> latestByCoverage = new Map<Id, Eligibility_Check__c>();
        if (coverageIds == null || coverageIds.isEmpty()) {
            return latestByCoverage;
        }
        for (Eligibility_Check__c check : [
            SELECT Coverage__c, Status__c, Checked_Date__c
            FROM Eligibility_Check__c
            WHERE Coverage__c IN :coverageIds
            ORDER BY Checked_Date__c DESC NULLS LAST, CreatedDate DESC
        ]) {
            if (!latestByCoverage.containsKey(check.Coverage__c)) {
                latestByCoverage.put(check.Coverage__c, check);
            }
        }
        return latestByCoverage;
    }

    private static Map<Id, List<IdCardFile>> loadIdCardFiles(Set<Id> coverageIds) {
        Map<Id, List<IdCardFile>> filesByCoverage = new Map<Id, List<IdCardFile>>();
        if (coverageIds == null || coverageIds.isEmpty()) {
            return filesByCoverage;
        }
        for (ContentDocumentLink link : [
            SELECT
                LinkedEntityId,
                ContentDocumentId,
                ContentDocument.Title,
                ContentDocument.FileExtension,
                ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :coverageIds
        ]) {
            if (link.ContentDocument == null) {
                continue;
            }
            String side = sideFromTitle(link.ContentDocument.Title);
            if (side == null) {
                continue;
            }
            IdCardFile file = new IdCardFile();
            file.contentDocumentId = link.ContentDocumentId;
            file.contentVersionId = link.ContentDocument.LatestPublishedVersionId;
            file.title = link.ContentDocument.Title;
            file.fileExtension = link.ContentDocument.FileExtension;
            file.side = side;
            file.isImage = isImageExtension(file.fileExtension);
            if (!filesByCoverage.containsKey(link.LinkedEntityId)) {
                filesByCoverage.put(link.LinkedEntityId, new List<IdCardFile>());
            }
            filesByCoverage.get(link.LinkedEntityId).add(file);
        }
        return filesByCoverage;
    }

    private static void verifyLinkedDocument(Id coverageId, Id contentDocumentId) {
        if (coverageId == null || contentDocumentId == null) {
            throw new AuraHandledException('Coverage and ID card file are required.');
        }
        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :coverageId AND ContentDocumentId = :contentDocumentId
            LIMIT 1
        ];
        if (links.isEmpty()) {
            throw new AuraHandledException('ID card file was not found on this coverage.');
        }
    }

    private static void deleteOtherIdCardFiles(Id coverageId, Id keepDocumentId, String title) {
        Set<Id> documentIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :coverageId AND ContentDocumentId != :keepDocumentId
        ]) {
            if (link.ContentDocument != null && title.equals(link.ContentDocument.Title)) {
                documentIds.add(link.ContentDocumentId);
            }
        }
        if (documentIds.isEmpty()) {
            return;
        }
        delete [SELECT Id FROM ContentDocument WHERE Id IN :documentIds];
    }

    private static String titleForSide(String side) {
        if (!ALLOWED_SIDES.contains(side)) {
            throw new AuraHandledException('ID card side must be Front or Back.');
        }
        return SIDE_FRONT.equals(side) ? TITLE_FRONT : TITLE_BACK;
    }

    private static String sideFromTitle(String title) {
        if (TITLE_FRONT.equals(title)) {
            return SIDE_FRONT;
        }
        if (TITLE_BACK.equals(title)) {
            return SIDE_BACK;
        }
        return null;
    }

    private static Boolean isImageExtension(String extension) {
        return String.isNotBlank(extension) && IMAGE_EXTENSIONS.contains(extension.toLowerCase());
    }
}
