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
    Practitioner__c practitioner = new Practitioner__c(
      First_Name__c = 'P',
      Last_Name__c = 'R'
    );
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
      Status__c = 'Queued',
      Triggered_By__c = 'Manual',
      Appointment_Start__c = appointment.Start__c,
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
    System.enqueueJob(
      new AppointmentSmsQueueable(
        new List<AppointmentCommunicationService.SmsJob>{ job }
      )
    );
    Test.stopTest();

    Appointment_Communication__c refreshed = [
      SELECT Status__c, Error_Message__c, Sent_At__c
      FROM Appointment_Communication__c
      WHERE Id = :logRow.Id
    ];
    System.assertEquals(
      'Failed',
      refreshed.Status__c,
      'Failed Twilio response should mark log Failed'
    );
    System.assertEquals(
      null,
      refreshed.Sent_At__c,
      'A failed SMS must not have a sent timestamp'
    );
    System.assertEquals(
      null,
      [
        SELECT Confirmation_Sent_At__c
        FROM Appointment__c
        WHERE Id = :appointment.Id
      ]
      .Confirmation_Sent_At__c,
      'A failed SMS must not stamp the appointment'
    );
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

  @IsTest
  static void revokedConsentSkipsCalloutWithoutStamp() {
    AppointmentCommunicationService.SmsJob job = queuedFixture('CONSENT');
    Appointment__c appointment = [
      SELECT Patient__c
      FROM Appointment__c
      WHERE Id = :job.appointmentId
    ];
    update new Patient__c(Id = appointment.Patient__c, SMS_Opt_In__c = false);
    Test.setMock(HttpCalloutMock.class, new UnexpectedCalloutMock());
    Test.startTest();
    System.enqueueJob(
      new AppointmentSmsQueueable(
        new List<AppointmentCommunicationService.SmsJob>{ job }
      )
    );
    Test.stopTest();
    Appointment_Communication__c logRow = [
      SELECT Status__c, Sent_At__c, Error_Message__c
      FROM Appointment_Communication__c
      WHERE Id = :job.communicationId
    ];
    System.assertEquals('Skipped', logRow.Status__c);
    System.assertEquals(null, logRow.Sent_At__c);
    System.assert(logRow.Error_Message__c.contains('consent'));
    System.assertEquals(
      null,
      [
        SELECT Reminder_Sent_At__c
        FROM Appointment__c
        WHERE Id = :job.appointmentId
      ]
      .Reminder_Sent_At__c
    );
  }

  @IsTest
  static void staleOccurrenceSkipsCalloutWithoutStamp() {
    AppointmentCommunicationService.SmsJob job = queuedFixture('RESCHEDULE');
    AppointmentCommunicationHandler.bypass = true;
    Appointment__c appointment = [
      SELECT Start__c, End__c
      FROM Appointment__c
      WHERE Id = :job.appointmentId
    ];
    appointment.Start__c = appointment.Start__c.addDays(1);
    appointment.End__c = appointment.End__c.addDays(1);
    update appointment;
    AppointmentCommunicationHandler.bypass = false;
    Test.setMock(HttpCalloutMock.class, new UnexpectedCalloutMock());
    Test.startTest();
    System.enqueueJob(
      new AppointmentSmsQueueable(
        new List<AppointmentCommunicationService.SmsJob>{ job }
      )
    );
    Test.stopTest();
    Appointment_Communication__c logRow = [
      SELECT Status__c, Sent_At__c, Error_Message__c
      FROM Appointment_Communication__c
      WHERE Id = :job.communicationId
    ];
    System.assertEquals('Skipped', logRow.Status__c);
    System.assertEquals(null, logRow.Sent_At__c);
    System.assert(logRow.Error_Message__c.contains('rescheduled'));
    System.assertEquals(
      null,
      [
        SELECT Reminder_Sent_At__c
        FROM Appointment__c
        WHERE Id = :job.appointmentId
      ]
      .Reminder_Sent_At__c
    );
  }

  private static AppointmentCommunicationService.SmsJob queuedFixture(
    String suffix
  ) {
    Patient__c patient = new Patient__c(
      MRN__c = 'MRN-SMS-' + suffix,
      Last_Name__c = suffix,
      Phone__c = '5550100999',
      SMS_Opt_In__c = true
    );
    insert patient;
    Practitioner__c provider = new Practitioner__c(
      Last_Name__c = 'SMS Provider'
    );
    insert provider;
    AppointmentCommunicationHandler.bypass = true;
    Appointment__c appointment = new Appointment__c(
      Patient__c = patient.Id,
      Practitioner__c = provider.Id,
      Start__c = Datetime.now().addDays(1),
      End__c = Datetime.now().addDays(1).addMinutes(30),
      Status__c = 'Booked'
    );
    insert appointment;
    AppointmentCommunicationHandler.bypass = false;
    Appointment_Communication__c logRow = new Appointment_Communication__c(
      Appointment__c = appointment.Id,
      Patient__c = patient.Id,
      Type__c = 'Reminder',
      Channel__c = 'SMS',
      Status__c = 'Queued',
      Triggered_By__c = 'Automated',
      Appointment_Start__c = appointment.Start__c
    );
    insert logRow;
    AppointmentCommunicationService.SmsJob job = new AppointmentCommunicationService.SmsJob();
    job.communicationId = logRow.Id;
    job.appointmentId = appointment.Id;
    job.toNumber = patient.Phone__c;
    job.body = 'Reminder';
    job.namedCredential = 'LogicEMR_Twilio';
    job.accountSid = 'ACtest';
    job.fromNumber = '+15551234567';
    return job;
  }

  private class UnexpectedCalloutMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      System.assert(
        false,
        'An ineligible queued message must be stopped before any external callout'
      );
      return new HttpResponse();
    }
  }
}
