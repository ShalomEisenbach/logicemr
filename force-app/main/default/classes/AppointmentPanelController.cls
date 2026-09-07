public with sharing class AppointmentPanelController {
    private static final Integer MAX_RESULTS = 50;

    @AuraEnabled(cacheable=true)
    public static List<Appointment__c> getAppointments(Id patientId) {
        if (patientId == null) {
            return new List<Appointment__c>();
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
