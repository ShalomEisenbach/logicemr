public with sharing class AppointmentSharingHandler {
    public static void recalculate(List<Appointment__c> appointments) {
        if (appointments == null || appointments.isEmpty()) {
            return;
        }
        new SharingOperations().recalculate(appointments);
    }

    private without sharing class SharingOperations {
        public void recalculate(List<Appointment__c> appointments) {
            Set<Id> appointmentIds = new Set<Id>();
            for (Appointment__c appointment : appointments) {
                if (appointment.Id != null) {
                    appointmentIds.add(appointment.Id);
                }
            }
            if (appointmentIds.isEmpty()) {
                return;
            }

            List<Appointment__Share> existing = [
                SELECT Id
                FROM Appointment__Share
                WHERE
                    ParentId IN :appointmentIds
                    AND RowCause = :Schema.Appointment__Share.RowCause.Practitioner_Access__c
            ];
            if (!existing.isEmpty()) {
                delete existing;
            }

            List<Appointment__Share> desired = new List<Appointment__Share>();
            for (Appointment__c appointment : [
                SELECT Id, OwnerId, Practitioner__r.User__c
                FROM Appointment__c
                WHERE Id IN :appointmentIds
            ]) {
                Id practitionerUserId = appointment.Practitioner__r == null
                    ? null
                    : appointment.Practitioner__r.User__c;
                if (practitionerUserId == null || practitionerUserId == appointment.OwnerId) {
                    continue;
                }
                desired.add(
                    new Appointment__Share(
                        ParentId = appointment.Id,
                        UserOrGroupId = practitionerUserId,
                        AccessLevel = 'Edit',
                        RowCause = Schema.Appointment__Share.RowCause.Practitioner_Access__c
                    )
                );
            }
            if (!desired.isEmpty()) {
                insert desired;
            }
        }
    }
}
