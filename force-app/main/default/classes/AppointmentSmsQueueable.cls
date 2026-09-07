public with sharing class AppointmentSmsQueueable implements Queueable, Database.AllowsCallouts {
    private final List<AppointmentCommunicationService.SmsJob> jobs;

    public AppointmentSmsQueueable(List<AppointmentCommunicationService.SmsJob> jobs) {
        this.jobs = jobs == null
            ? new List<AppointmentCommunicationService.SmsJob>()
            : new List<AppointmentCommunicationService.SmsJob>(jobs);
    }

    public void execute(QueueableContext context) {
        if (jobs.isEmpty()) {
            return;
        }
        List<Appointment_Communication__c> updates = new List<Appointment_Communication__c>();
        for (AppointmentCommunicationService.SmsJob job : jobs) {
            if (job == null || job.communicationId == null) {
                continue;
            }
            try {
                HttpRequest request = new HttpRequest();
                String endpoint =
                    'callout:' +
                    job.namedCredential +
                    '/2010-04-01/Accounts/' +
                    EncodingUtil.urlEncode(job.accountSid, 'UTF-8') +
                    '/Messages.json';
                request.setEndpoint(endpoint);
                request.setMethod('POST');
                request.setHeader('Content-Type', 'application/x-www-form-urlencoded');
                request.setBody(
                    'To=' +
                    EncodingUtil.urlEncode(job.toNumber, 'UTF-8') +
                    '&From=' +
                    EncodingUtil.urlEncode(job.fromNumber, 'UTF-8') +
                    '&Body=' +
                    EncodingUtil.urlEncode(job.body == null ? '' : job.body, 'UTF-8')
                );
                request.setTimeout(120000);
                HttpResponse response = new Http().send(request);
                Integer statusCode = response.getStatusCode();
                if (statusCode < 200 || statusCode >= 300) {
                    updates.add(
                        new Appointment_Communication__c(
                            Id = job.communicationId,
                            Status__c = AppointmentCommunicationService.STATUS_FAILED,
                            Error_Message__c = 'Twilio HTTP ' + statusCode + ': ' + response.getBody()
                        )
                    );
                }
            } catch (Exception e) {
                updates.add(
                    new Appointment_Communication__c(
                        Id = job.communicationId,
                        Status__c = AppointmentCommunicationService.STATUS_FAILED,
                        Error_Message__c = e.getMessage()
                    )
                );
            }
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }
}
