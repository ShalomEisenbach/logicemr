public with sharing class ProviderHomeController {
    private static final Integer LIST_LIMIT = 10;
    private static final Set<String> CLOSED_ENCOUNTER_STATUSES = new Set<String>{
        'Finished',
        'Cancelled'
    };
    private static final Set<String> REVIEWABLE_REPORT_STATUSES = new Set<String>{
        'Preliminary',
        'Final'
    };
    private static final String NOTE_STATUS_DRAFT = 'Draft';

    public class HomePayload {
        @AuraEnabled
        public HomeMetrics metrics;
        @AuraEnabled
        public HomeLists lists;
        @AuraEnabled
        public List<Patient__c> recentPatients;
    }

    public class HomeMetrics {
        @AuraEnabled
        public Integer myActivePatients;
        @AuraEnabled
        public Integer openEncounters;
        @AuraEnabled
        public Integer resultsToReview;
        @AuraEnabled
        public Integer unsignedNotes;
    }

    public class HomeLists {
        @AuraEnabled
        public List<Encounter__c> todaysEncounters;
        @AuraEnabled
        public List<DiagnosticReport__c> resultsToReview;
        @AuraEnabled
        public List<ClinicalNote__c> unsignedNotes;
    }

    @AuraEnabled(cacheable=true)
    public static HomePayload getHome() {
        Id userId = UserInfo.getUserId();
        Id practitionerId = resolvePractitionerId(userId);
        Set<Id> patientIds = resolveCareTeamPatientIds(userId);

        HomePayload payload = emptyPayload();
        payload.metrics.myActivePatients = patientIds.size();
        payload.metrics.openEncounters = countOpenEncounters(patientIds, practitionerId);
        payload.metrics.resultsToReview = countResultsToReview(patientIds);
        payload.metrics.unsignedNotes = countUnsignedNotes(practitionerId);
        payload.lists.todaysEncounters = queryTodaysEncounters(patientIds, practitionerId);
        payload.lists.resultsToReview = queryResultsToReview(patientIds);
        payload.lists.unsignedNotes = queryUnsignedNotes(practitionerId);
        payload.recentPatients = queryRecentPatients();
        return payload;
    }

    private static HomePayload emptyPayload() {
        HomePayload payload = new HomePayload();
        payload.metrics = new HomeMetrics();
        payload.metrics.myActivePatients = 0;
        payload.metrics.openEncounters = 0;
        payload.metrics.resultsToReview = 0;
        payload.metrics.unsignedNotes = 0;
        payload.lists = new HomeLists();
        payload.lists.todaysEncounters = new List<Encounter__c>();
        payload.lists.resultsToReview = new List<DiagnosticReport__c>();
        payload.lists.unsignedNotes = new List<ClinicalNote__c>();
        payload.recentPatients = new List<Patient__c>();
        return payload;
    }

    private static Id resolvePractitionerId(Id userId) {
        List<Practitioner__c> rows = [
            SELECT Id
            FROM Practitioner__c
            WHERE User__c = :userId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Id;
    }

    private static Set<Id> resolveCareTeamPatientIds(Id userId) {
        Set<Id> patientIds = new Set<Id>();
        for (CareTeamMember__c member : [
            SELECT Care_Team__r.Patient__c
            FROM CareTeamMember__c
            WHERE User__c = :userId AND Active__c = TRUE
        ]) {
            if (member.Care_Team__r != null && member.Care_Team__r.Patient__c != null) {
                patientIds.add(member.Care_Team__r.Patient__c);
            }
        }
        return patientIds;
    }

    private static Integer countOpenEncounters(Set<Id> patientIds, Id practitionerId) {
        if (patientIds.isEmpty() && practitionerId == null) {
            return 0;
        }
        if (patientIds.isEmpty()) {
            return [
                SELECT COUNT()
                FROM Encounter__c
                WHERE Practitioner__c = :practitionerId AND Status__c NOT IN :CLOSED_ENCOUNTER_STATUSES
            ];
        }
        if (practitionerId == null) {
            return [
                SELECT COUNT()
                FROM Encounter__c
                WHERE Patient__c IN :patientIds AND Status__c NOT IN :CLOSED_ENCOUNTER_STATUSES
            ];
        }
        return [
            SELECT COUNT()
            FROM Encounter__c
            WHERE
                Status__c NOT IN :CLOSED_ENCOUNTER_STATUSES
                AND (Patient__c IN :patientIds OR Practitioner__c = :practitionerId)
        ];
    }

    private static List<Encounter__c> queryTodaysEncounters(Set<Id> patientIds, Id practitionerId) {
        if (patientIds.isEmpty() && practitionerId == null) {
            return new List<Encounter__c>();
        }
        Datetime startOfDay = Datetime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0));
        Datetime startOfNextDay = startOfDay.addDays(1);
        if (patientIds.isEmpty()) {
            return [
                SELECT
                    Id,
                    Name,
                    Status__c,
                    Class__c,
                    Start__c,
                    Reason__c,
                    Patient__c,
                    Patient__r.Name,
                    Patient__r.First_Name__c,
                    Patient__r.Last_Name__c
                FROM Encounter__c
                WHERE
                    Practitioner__c = :practitionerId
                    AND Start__c >= :startOfDay
                    AND Start__c < :startOfNextDay
                ORDER BY Start__c DESC NULLS LAST
                LIMIT :LIST_LIMIT
            ];
        }
        if (practitionerId == null) {
            return [
                SELECT
                    Id,
                    Name,
                    Status__c,
                    Class__c,
                    Start__c,
                    Reason__c,
                    Patient__c,
                    Patient__r.Name,
                    Patient__r.First_Name__c,
                    Patient__r.Last_Name__c
                FROM Encounter__c
                WHERE
                    Patient__c IN :patientIds
                    AND Start__c >= :startOfDay
                    AND Start__c < :startOfNextDay
                ORDER BY Start__c DESC NULLS LAST
                LIMIT :LIST_LIMIT
            ];
        }
        return [
            SELECT
                Id,
                Name,
                Status__c,
                Class__c,
                Start__c,
                Reason__c,
                Patient__c,
                Patient__r.Name,
                Patient__r.First_Name__c,
                Patient__r.Last_Name__c
            FROM Encounter__c
            WHERE
                (Patient__c IN :patientIds OR Practitioner__c = :practitionerId)
                AND Start__c >= :startOfDay
                AND Start__c < :startOfNextDay
            ORDER BY Start__c DESC NULLS LAST
            LIMIT :LIST_LIMIT
        ];
    }

    private static Integer countResultsToReview(Set<Id> patientIds) {
        if (patientIds.isEmpty()) {
            return 0;
        }
        return [
            SELECT COUNT()
            FROM DiagnosticReport__c
            WHERE
                Patient__c IN :patientIds
                AND Reviewed__c = FALSE
                AND Status__c IN :REVIEWABLE_REPORT_STATUSES
        ];
    }

    private static List<DiagnosticReport__c> queryResultsToReview(Set<Id> patientIds) {
        if (patientIds.isEmpty()) {
            return new List<DiagnosticReport__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Report_Display__c,
                Status__c,
                Category__c,
                Issued__c,
                Effective_DateTime__c,
                Patient__c,
                Patient__r.Name,
                Patient__r.First_Name__c,
                Patient__r.Last_Name__c
            FROM DiagnosticReport__c
            WHERE
                Patient__c IN :patientIds
                AND Reviewed__c = FALSE
                AND Status__c IN :REVIEWABLE_REPORT_STATUSES
            ORDER BY Issued__c DESC NULLS LAST, Effective_DateTime__c DESC NULLS LAST
            LIMIT :LIST_LIMIT
        ];
    }

    private static Integer countUnsignedNotes(Id practitionerId) {
        if (practitionerId == null) {
            return 0;
        }
        return [
            SELECT COUNT()
            FROM ClinicalNote__c
            WHERE Author__c = :practitionerId AND Status__c = :NOTE_STATUS_DRAFT
        ];
    }

    private static List<ClinicalNote__c> queryUnsignedNotes(Id practitionerId) {
        if (practitionerId == null) {
            return new List<ClinicalNote__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Note_Type__c,
                Status__c,
                LastModifiedDate,
                Patient__c,
                Patient__r.Name,
                Patient__r.First_Name__c,
                Patient__r.Last_Name__c
            FROM ClinicalNote__c
            WHERE Author__c = :practitionerId AND Status__c = :NOTE_STATUS_DRAFT
            ORDER BY LastModifiedDate DESC
            LIMIT :LIST_LIMIT
        ];
    }

    private static List<Patient__c> queryRecentPatients() {
        return [
            SELECT
                Id,
                Name,
                First_Name__c,
                Last_Name__c,
                MRN__c,
                Date_of_Birth__c,
                Status__c,
                LastViewedDate
            FROM Patient__c
            WHERE LastViewedDate != NULL
            ORDER BY LastViewedDate DESC
            LIMIT :LIST_LIMIT
        ];
    }
}
