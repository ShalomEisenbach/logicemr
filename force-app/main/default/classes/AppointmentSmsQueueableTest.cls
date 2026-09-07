@IsTest
private class AppointmentSmsQueueableTest {
    @IsTest
    static void marksLogFailedOnHttpError() {
        Patient__c patient = new Patient__c(
            MRN__c = 'MRN-SMS-1',
            First_Name__c = 'Sms',
            Last_Name__c = 'Fail',
            Phone__c = '5550100999',
            SMS_Opt_In__c = true
        );
        insert patient;
        Practitioner__c practitioner = new Practitioner__c(First_Name__c = 'P', Last_Name__c = 'R');
        insert practitioner;
        AppointmentCommunicationHandler.bypass = true;
        Appointment__c appointment = new Appointment__c(
            Patient__c = patient.Id,
            Practitioner__c = practitioner.Id,
            Start__c = Datetime.now().addDays(1),
            End__c = Datetime.now().addDays(1).addMinutes(15),
            Status__c = 'Booked'
        );
        insert appointment;
        AppointmentCommunicationHandler.bypass = false;

        Appointment_Communication__c logRow = new Appointment_Communication__c(
            Appointment__c = appointment.Id,
            Patient__c = patient.Id,
            Type__c = 'Confirmation',
            Channel__c = 'SMS',
            Status__c = 'Sent',
            Triggered_By__c = 'Manual',
            Sent_At__c = Datetime.now(),
            Recipient__c = '5550100999',
            Body__c = 'Test body'
        );
        insert logRow;

        AppointmentCommunicationService.SmsJob job = new AppointmentCommunicationService.SmsJob();
        job.communicationId = logRow.Id;
        job.appointmentId = appointment.Id;
        job.toNumber = '5550100999';
        job.body = 'Test body';
        job.namedCredential = 'LogicEMR_Twilio';
        job.accountSid = 'ACtest';
        job.fromNumber = '+15551234567';

        Test.setMock(HttpCalloutMock.class, new TwilioFailureMock());
        Test.startTest();
        System.enqueueJob(new AppointmentSmsQueueable(new List<AppointmentCommunicationService.SmsJob>{ job }));
        Test.stopTest();

        Appointment_Communication__c refreshed = [
            SELECT Status__c, Error_Message__c
            FROM Appointment_Communication__c
            WHERE Id = :logRow.Id
        ];
        System.assertEquals('Failed', refreshed.Status__c, 'Failed Twilio response should mark log Failed');
        System.assert(
            String.isNotBlank(refreshed.Error_Message__c),
            'Failure should store an error message'
        );
    }

    private class TwilioFailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(401);
            response.setBody('{"message":"Authenticate","code":20003}');
            return response;
        }
    }
}
