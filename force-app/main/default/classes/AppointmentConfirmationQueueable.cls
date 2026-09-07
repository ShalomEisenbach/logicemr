public with sharing class AppointmentConfirmationQueueable implements Queueable {
    private final List<Id> appointmentIds;

    public AppointmentConfirmationQueueable(List<Id> appointmentIds) {
        this.appointmentIds = appointmentIds == null ? new List<Id>() : new List<Id>(appointmentIds);
    }

    public void execute(QueueableContext context) {
        if (appointmentIds.isEmpty()) {
            return;
        }
        AppointmentCommunicationService.sendForAppointments(
            appointmentIds,
            AppointmentCommunicationService.TYPE_CONFIRMATION,
            AppointmentCommunicationService.TRIGGER_AUTOMATED,
            null,
            true
        );
    }
}
