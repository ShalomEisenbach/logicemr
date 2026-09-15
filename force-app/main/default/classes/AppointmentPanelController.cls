public with sharing class AppointmentPanelController {
    private static final Integer MAX_RESULTS = 50;
    private static final Set<String> PRE_ARRIVAL_STATUSES = new Set<String>{ 'Proposed', 'Booked' };

    @AuraEnabled(cacheable=true)
    public static List<Appointment__c> getAppointments(Id patientId, Boolean upcomingOnly) {
        if (patientId == null) {
            return new List<Appointment__c>();
        }
        if (upcomingOnly == null || upcomingOnly) {
            Datetime startOfToday = Datetime.newInstance(
                Date.today(),
                Time.newInstance(0, 0, 0, 0)
            );
            return [
                SELECT
                    Id,
                    Name,
                    Status__c,
                    Appointment_Type__c,
                    Reason__c,
                    Start__c,
                    End__c,
                    Location_Name__c,
                    Practitioner__c,
                    Practitioner__r.First_Name__c,
                    Practitioner__r.Last_Name__c,
                    Encounter__c
                FROM Appointment__c
                WHERE
                    Patient__c = :patientId
                    AND Start__c >= :startOfToday
                    AND Status__c IN :PRE_ARRIVAL_STATUSES
                ORDER BY Start__c ASC NULLS LAST
                LIMIT :MAX_RESULTS
            ];
        }
        return [
            SELECT
                Id,
                Name,
                Status__c,
                Appointment_Type__c,
                Reason__c,
                Start__c,
                End__c,
                Location_Name__c,
                Practitioner__c,
                Practitioner__r.First_Name__c,
                Practitioner__r.Last_Name__c,
                Encounter__c
            FROM Appointment__c
            WHERE Patient__c = :patientId
            ORDER BY Start__c DESC NULLS LAST
            LIMIT :MAX_RESULTS
        ];
    }
}
