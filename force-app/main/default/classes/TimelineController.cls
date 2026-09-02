public with sharing class TimelineController {
    private static final Integer MAX_RESULTS = 200;
    private static final String TYPE_ENCOUNTER = 'Encounter';
    private static final String TYPE_CONDITION = 'Condition';
    private static final String TYPE_OBSERVATION = 'Observation';
    private static final String TYPE_MEDICATION_REQUEST = 'MedicationRequest';
    private static final String TYPE_PROCEDURE = 'Procedure';

    /**
     * LWC event contract is { type, dateTime, title, subtitle, recordId }.
     * Apex cannot declare a member named dateTime (collides with Datetime),
     * so the date is eventDateTime and the LWC aliases it to dateTime.
     */
    public class TimelineEvent implements Comparable {
        @AuraEnabled
        public String type;
        @AuraEnabled
        public Datetime eventDateTime;
        @AuraEnabled
        public String title;
        @AuraEnabled
        public String subtitle;
        @AuraEnabled
        public Id recordId;

        public Integer compareTo(Object other) {
            TimelineEvent that = (TimelineEvent) other;
            if (this.eventDateTime == that.eventDateTime) {
                return 0;
            }
            if (this.eventDateTime == null) {
                return 1;
            }
            if (that.eventDateTime == null) {
                return -1;
            }
            if (this.eventDateTime > that.eventDateTime) {
                return -1;
            }
            return 1;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<TimelineEvent> getEvents(Id patientId) {
        List<TimelineEvent> events = new List<TimelineEvent>();
        if (patientId == null) {
            return events;
        }

        Set<Id> patientIds = new Set<Id>{ patientId };
        events.addAll(fromEncounters(queryEncounters(patientIds)));
        events.addAll(fromConditions(queryConditions(patientIds)));
        events.addAll(fromObservations(queryObservations(patientIds)));
        events.addAll(fromMedicationRequests(queryMedicationRequests(patientIds)));
        events.addAll(fromProcedures(queryProcedures(patientIds)));
        events.sort();
        return events;
    }

    private static List<Encounter__c> queryEncounters(Set<Id> patientIds) {
        return [
            SELECT Id, Name, Status__c, Class__c, Start__c, Reason__c
            FROM Encounter__c
            WHERE Patient__c IN :patientIds
            ORDER BY Start__c DESC NULLS LAST
            LIMIT :MAX_RESULTS
        ];
    }

    private static List<Condition__c> queryConditions(Set<Id> patientIds) {
        return [
            SELECT Id, Name, Diagnosis_Display__c, Clinical_Status__c, Category__c, Onset_Date__c
            FROM Condition__c
            WHERE Patient__c IN :patientIds
            ORDER BY Onset_Date__c DESC NULLS LAST
            LIMIT :MAX_RESULTS
        ];
    }

    private static List<Observation__c> queryObservations(Set<Id> patientIds) {
        return [
            SELECT
                Id,
                Name,
                Observation_Display__c,
                Status__c,
                Category__c,
                Effective_DateTime__c,
                Value_Quantity__c,
                Value_Unit__c,
                Value_String__c
            FROM Observation__c
            WHERE Patient__c IN :patientIds
            ORDER BY Effective_DateTime__c DESC NULLS LAST
            LIMIT :MAX_RESULTS
        ];
    }

    private static List<MedicationRequest__c> queryMedicationRequests(Set<Id> patientIds) {
        return [
            SELECT Id, Name, Medication_Display__c, Status__c, Dosage_Text__c, Authored_On__c
            FROM MedicationRequest__c
            WHERE Patient__c IN :patientIds
            ORDER BY Authored_On__c DESC NULLS LAST
            LIMIT :MAX_RESULTS
        ];
    }

    private static List<Procedure__c> queryProcedures(Set<Id> patientIds) {
        return [
            SELECT Id, Name, Procedure_Display__c, Status__c, Category__c, Performed_DateTime__c
            FROM Procedure__c
            WHERE Patient__c IN :patientIds
            ORDER BY Performed_DateTime__c DESC NULLS LAST
            LIMIT :MAX_RESULTS
        ];
    }

    private static List<TimelineEvent> fromEncounters(List<Encounter__c> rows) {
        List<TimelineEvent> events = new List<TimelineEvent>();
        for (Encounter__c row : rows) {
            events.add(
                buildEvent(
                    TYPE_ENCOUNTER,
                    row.Start__c,
                    firstNonBlank(new List<String>{ row.Reason__c, row.Class__c, row.Name }),
                    joinSubtitle(row.Status__c, row.Class__c),
                    row.Id
                )
            );
        }
        return events;
    }

    private static List<TimelineEvent> fromConditions(List<Condition__c> rows) {
        List<TimelineEvent> events = new List<TimelineEvent>();
        for (Condition__c row : rows) {
            events.add(
                buildEvent(
                    TYPE_CONDITION,
                    toDateTime(row.Onset_Date__c),
                    firstNonBlank(new List<String>{ row.Diagnosis_Display__c, row.Name }),
                    joinSubtitle(row.Clinical_Status__c, row.Category__c),
                    row.Id
                )
            );
        }
        return events;
    }

    private static List<TimelineEvent> fromObservations(List<Observation__c> rows) {
        List<TimelineEvent> events = new List<TimelineEvent>();
        for (Observation__c row : rows) {
            events.add(
                buildEvent(
                    TYPE_OBSERVATION,
                    row.Effective_DateTime__c,
                    firstNonBlank(new List<String>{ row.Observation_Display__c, row.Name }),
                    observationSubtitle(row),
                    row.Id
                )
            );
        }
        return events;
    }

    private static List<TimelineEvent> fromMedicationRequests(List<MedicationRequest__c> rows) {
        List<TimelineEvent> events = new List<TimelineEvent>();
        for (MedicationRequest__c row : rows) {
            events.add(
                buildEvent(
                    TYPE_MEDICATION_REQUEST,
                    row.Authored_On__c,
                    firstNonBlank(new List<String>{ row.Medication_Display__c, row.Name }),
                    joinSubtitle(row.Status__c, row.Dosage_Text__c),
                    row.Id
                )
            );
        }
        return events;
    }

    private static List<TimelineEvent> fromProcedures(List<Procedure__c> rows) {
        List<TimelineEvent> events = new List<TimelineEvent>();
        for (Procedure__c row : rows) {
            events.add(
                buildEvent(
                    TYPE_PROCEDURE,
                    row.Performed_DateTime__c,
                    firstNonBlank(new List<String>{ row.Procedure_Display__c, row.Name }),
                    joinSubtitle(row.Status__c, row.Category__c),
                    row.Id
                )
            );
        }
        return events;
    }

    private static TimelineEvent buildEvent(
        String type,
        Datetime occurredAt,
        String title,
        String subtitle,
        Id recordId
    ) {
        TimelineEvent event = new TimelineEvent();
        event.type = type;
        event.eventDateTime = occurredAt;
        event.title = title;
        event.subtitle = subtitle;
        event.recordId = recordId;
        return event;
    }

    private static String observationSubtitle(Observation__c row) {
        if (row.Value_Quantity__c != null) {
            String quantity = row.Value_Quantity__c.stripTrailingZeros().toPlainString();
            if (String.isBlank(row.Value_Unit__c)) {
                return joinSubtitle(quantity, row.Status__c);
            }
            return joinSubtitle(quantity + ' ' + row.Value_Unit__c, row.Status__c);
        }
        if (!String.isBlank(row.Value_String__c)) {
            return joinSubtitle(row.Value_String__c, row.Status__c);
        }
        return joinSubtitle(row.Status__c, row.Category__c);
    }

    private static Datetime toDateTime(Date value) {
        if (value == null) {
            return null;
        }
        return Datetime.newInstance(value, Time.newInstance(0, 0, 0, 0));
    }

    private static String firstNonBlank(List<String> values) {
        for (String value : values) {
            if (!String.isBlank(value)) {
                return value;
            }
        }
        return null;
    }

    private static String joinSubtitle(String left, String right) {
        if (String.isBlank(left)) {
            return right;
        }
        if (String.isBlank(right) || left == right) {
            return left;
        }
        return left + ' · ' + right;
    }
}
