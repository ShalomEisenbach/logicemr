@IsTest
private class AppointmentCommunicationServiceTest {
  @IsTest
  static void sendConfirmationEmailsAndSkipsSmsWithoutOptIn() {
    Patient__c patient = insertPatient(
      'MRN-COMM-1',
      'ada@example.com',
      '555-010-0001',
      false
    );
    Appointment__c appointment = insertBookedAppointment(
      patient.Id,
      Datetime.now().addDays(1)
    );

    AppointmentCommunicationService.skipEmailSend = true;
    AppointmentCommunicationService.skipSmsEnqueue = true;
    Appointment_Comm_Config__mdt config = baseConfig(true, true);
    AppointmentCommunicationService.testConfigOverride = config;

    Test.startTest();
    AppointmentCommunicationService.SendResult result = AppointmentCommunicationService.sendConfirmation(
      appointment.Id,
      false,
      new List<String>{ 'Email', 'SMS' }
    );
    Test.stopTest();

    System.assertEquals(
      true,
      result.success,
      'Email-only send should succeed: ' + result.message
    );
    System.assertEquals(
      1,
      result.sentCount,
      'One email should be counted as sent'
    );
    System.assert(
      result.skippedCount >= 1,
      'SMS without opt-in should be skipped: ' + result.message
    );

    Appointment__c stamped = [
      SELECT Confirmation_Sent_At__c
      FROM Appointment__c
      WHERE Id = :appointment.Id
    ];
    System.assertNotEquals(
      null,
      stamped.Confirmation_Sent_At__c,
      'Confirmation timestamp should be set'
    );

    List<Appointment_Communication__c> logs = [
      SELECT Channel__c, Status__c, Type__c, Triggered_By__c, Recipient__c
      FROM Appointment_Communication__c
      WHERE Appointment__c = :appointment.Id
      ORDER BY Channel__c
    ];
    System.assert(
      logs.size() >= 1,
      'At least one communication log should exist'
    );
    Boolean foundEmail = false;
    Boolean foundSmsSkip = false;
    for (Appointment_Communication__c row : logs) {
      if (row.Channel__c == 'Email' && row.Status__c == 'Sent') {
        foundEmail = true;
        System.assertEquals(
          'ada@example.com',
          row.Recipient__c,
          'Email recipient should match'
        );
        System.assertEquals(
          'Manual',
          row.Triggered_By__c,
          'Manual send should be tagged'
        );
      }
      if (row.Channel__c == 'SMS' && row.Status__c == 'Skipped') {
        foundSmsSkip = true;
      }
    }
    System.assertEquals(true, foundEmail, 'Email Sent log expected');
    System.assertEquals(
      true,
      foundSmsSkip,
      'SMS Skipped log expected without opt-in'
    );
  }

  @IsTest
  static void sendSkipsWhenNoEmail() {
    Patient__c patient = insertPatient('MRN-COMM-2', null, null, false);
    Appointment__c appointment = insertBookedAppointment(
      patient.Id,
      Datetime.now().addDays(2)
    );
    AppointmentCommunicationService.skipEmailSend = true;
    AppointmentCommunicationService.testConfigOverride = baseConfig(
      true,
      false
    );

    Test.startTest();
    AppointmentCommunicationService.SendResult result = AppointmentCommunicationService.sendConfirmation(
      appointment.Id,
      true,
      null
    );
    Test.stopTest();

    System.assertEquals(0, result.sentCount, 'No channels should send');
    System.assert(result.skippedCount >= 1, 'Should record a skip');
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Appointment__c
        WHERE Id = :appointment.Id AND Confirmation_Sent_At__c != NULL
      ],
      'Timestamp should not set when nothing was sent'
    );
  }

  @IsTest
  static void getChannelAvailabilityAndPrintPayload() {
    Patient__c patient = insertPatient(
      'MRN-COMM-3',
      'print@example.com',
      '555-010-0003',
      true
    );
    Appointment__c appointment = insertBookedAppointment(
      patient.Id,
      Datetime.now().addDays(3)
    );
    AppointmentCommunicationService.testConfigOverride = baseConfig(
      true,
      false
    );

    AppointmentCommunicationService.ChannelAvailability availability = AppointmentCommunicationService.getChannelAvailability(
      appointment.Id
    );
    System.assertEquals(
      true,
      availability.emailAvailable,
      'Email should be available'
    );
    System.assertEquals(
      false,
      availability.smsAvailable,
      'SMS disabled in config'
    );
    System.assertEquals(
      'print@example.com',
      availability.emailRecipient,
      'Recipient email'
    );

    AppointmentCommunicationService.PrintPayload payload = AppointmentCommunicationService.getPrintPayload(
      appointment.Id
    );
    System.assertEquals(
      appointment.Id,
      payload.appointmentId,
      'Payload appointment id'
    );
    System.assertEquals(patient.Id, payload.patientId, 'Payload patient id');
    System.assertEquals('Booked', payload.status, 'Payload status');

    AppointmentCommunicationService.SendResult printResult = AppointmentCommunicationService.logPrint(
      appointment.Id
    );
    System.assertEquals(true, printResult.success, 'Print log should succeed');
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Appointment_Communication__c
        WHERE
          Appointment__c = :appointment.Id
          AND Channel__c = 'Print'
          AND Status__c = 'Sent'
      ],
      'Print channel log expected'
    );
  }

  @IsTest
  static void enqueueSmsJobWithMockCallout() {
    Patient__c patient = insertPatient(
      'MRN-COMM-4',
      'sms@example.com',
      '5550100004',
      true
    );
    Appointment__c appointment = insertBookedAppointment(
      patient.Id,
      Datetime.now().addDays(4)
    );
    AppointmentCommunicationService.skipEmailSend = true;
    AppointmentCommunicationService.skipSmsEnqueue = false;
    AppointmentCommunicationService.testConfigOverride = baseConfig(true, true);

    Test.setMock(HttpCalloutMock.class, new TwilioSuccessMock());
    Test.startTest();
    AppointmentCommunicationService.SendResult result = AppointmentCommunicationService.sendReminder(
      appointment.Id,
      false,
      new List<String>{ 'SMS' }
    );
    System.assertEquals(
      null,
      [
        SELECT Reminder_Sent_At__c
        FROM Appointment__c
        WHERE Id = :appointment.Id
      ]
      .Reminder_Sent_At__c,
      'Enqueuing SMS must not stamp the appointment before Twilio accepts it'
    );
    Appointment_Communication__c pending = [
      SELECT Status__c, Sent_At__c
      FROM Appointment_Communication__c
      WHERE Appointment__c = :appointment.Id AND Channel__c = 'SMS'
    ];
    System.assertEquals('Queued', pending.Status__c);
    System.assertEquals(null, pending.Sent_At__c);
    Test.stopTest();

    System.assertEquals(0, result.sentCount, 'A queued SMS is not yet sent');
    System.assertEquals(
      1,
      result.queuedCount,
      'SMS should be reported as queued: ' + result.message
    );
    Appointment__c stamped = [
      SELECT Reminder_Sent_At__c
      FROM Appointment__c
      WHERE Id = :appointment.Id
    ];
    System.assertNotEquals(
      null,
      stamped.Reminder_Sent_At__c,
      'Reminder timestamp should be set'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Appointment_Communication__c
        WHERE
          Appointment__c = :appointment.Id
          AND Channel__c = 'SMS'
          AND Status__c = 'Sent'
      ],
      'SMS Sent log expected after successful Twilio mock'
    );
  }

  @IsTest
  static void controllerDelegates() {
    Patient__c patient = insertPatient(
      'MRN-COMM-5',
      'ctrl@example.com',
      '555-010-0005',
      false
    );
    Appointment__c appointment = insertBookedAppointment(
      patient.Id,
      Datetime.now().addDays(5)
    );
    AppointmentCommunicationService.skipEmailSend = true;
    AppointmentCommunicationService.testConfigOverride = baseConfig(
      true,
      false
    );

    Test.startTest();
    AppointmentCommunicationService.ChannelAvailability availability = AppointmentCommunicationController.getChannelAvailability(
      appointment.Id
    );
    AppointmentCommunicationService.SendResult sent = AppointmentCommunicationController.sendConfirmation(
      appointment.Id,
      new List<String>{ 'Email' }
    );
    AppointmentCommunicationService.PrintPayload payload = AppointmentCommunicationController.getPrintPayload(
      appointment.Id
    );
    AppointmentCommunicationService.SendResult printed = AppointmentCommunicationController.logPrint(
      appointment.Id
    );
    Test.stopTest();

    System.assertEquals(
      true,
      availability.emailAvailable,
      'Controller availability'
    );
    System.assertEquals(true, sent.success, 'Controller send confirmation');
    System.assertEquals(
      appointment.Id,
      payload.appointmentId,
      'Controller print payload'
    );
    System.assertEquals(true, printed.success, 'Controller print log');
  }

  @IsTest
  static void pendingSmsAndDuplicateInputsCannotEnqueueTwice() {
    Patient__c patient = insertPatient(
      'MRN-COMM-DUPLICATE',
      null,
      '5550100111',
      true
    );
    Appointment__c appointment = insertBookedAppointment(
      patient.Id,
      Datetime.now().addDays(1)
    );
    AppointmentCommunicationService.testConfigOverride = baseConfig(
      false,
      true
    );
    AppointmentCommunicationService.skipSmsEnqueue = true;
    AppointmentCommunicationService.SendResult first = AppointmentCommunicationService.sendForAppointments(
      new List<Id>{ appointment.Id, appointment.Id },
      'Reminder',
      'Automated',
      null,
      true
    );
    AppointmentCommunicationService.SendResult second = AppointmentCommunicationService.sendReminder(
      appointment.Id,
      false,
      new List<String>{ 'SMS' }
    );
    System.assertEquals(
      1,
      first.queuedCount,
      'Duplicate IDs in a batch are processed once'
    );
    System.assertEquals(
      0,
      second.queuedCount,
      'A pending SMS blocks a second manual or automated enqueue'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Appointment_Communication__c
        WHERE Appointment__c = :appointment.Id
      ]
    );
    System.assertEquals(
      null,
      [
        SELECT Reminder_Sent_At__c
        FROM Appointment__c
        WHERE Id = :appointment.Id
      ]
      .Reminder_Sent_At__c
    );
  }

  @IsTest
  static void failedSmsRetriesWithoutResendingEmailAndStopsAtThreeFailures() {
    Patient__c patient = insertPatient(
      'MRN-COMM-RETRY',
      'retry@example.com',
      '5550100222',
      true
    );
    Appointment__c appointment = insertBookedAppointment(
      patient.Id,
      Datetime.now().addDays(1)
    );
    AppointmentCommunicationService.testConfigOverride = baseConfig(true, true);
    AppointmentCommunicationService.skipSmsEnqueue = true;
    AppointmentCommunicationService.skipEmailSend = true;
    AppointmentCommunicationHandler.bypass = true;
    update new Appointment__c(
      Id = appointment.Id,
      Reminder_Sent_At__c = Datetime.now()
    );
    AppointmentCommunicationHandler.bypass = false;
    insert history(appointment, 'Email', 'Sent', true);
    insert history(appointment, 'SMS', 'Failed', true);
    AppointmentCommunicationService.SendResult retry = AppointmentCommunicationService.sendReminder(
      appointment.Id,
      true,
      null
    );
    System.assertEquals(
      0,
      retry.sentCount,
      'A successful email is not resent when SMS failed'
    );
    System.assertEquals(
      1,
      retry.queuedCount,
      'The failed SMS gets another attempt despite the email stamp'
    );
    Appointment_Communication__c queued = [
      SELECT Id
      FROM Appointment_Communication__c
      WHERE Appointment__c = :appointment.Id AND Status__c = 'Queued'
    ];
    queued.Status__c = 'Failed';
    update queued;
    insert history(appointment, 'SMS', 'Failed', true);
    AppointmentCommunicationService.SendResult capped = AppointmentCommunicationService.sendReminder(
      appointment.Id,
      true,
      null
    );
    System.assertEquals(
      0,
      capped.queuedCount,
      'Three failed attempts cap automatic retries'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Appointment_Communication__c
        WHERE Appointment__c = :appointment.Id AND Channel__c = 'Email'
      ]
    );
    System.assertEquals(
      3,
      [
        SELECT COUNT()
        FROM Appointment_Communication__c
        WHERE
          Appointment__c = :appointment.Id
          AND Channel__c = 'SMS'
          AND Status__c = 'Failed'
      ]
    );
  }

  @IsTest
  static void rescheduledOccurrenceCanNotifyAgain() {
    Patient__c patient = insertPatient(
      'MRN-COMM-OCCURRENCE',
      null,
      '5550100333',
      true
    );
    Appointment__c appointment = insertBookedAppointment(
      patient.Id,
      Datetime.now().addDays(1)
    );
    AppointmentCommunicationService.testConfigOverride = baseConfig(
      false,
      true
    );
    AppointmentCommunicationService.skipSmsEnqueue = true;
    insert history(appointment, 'SMS', 'Sent', true);
    AppointmentCommunicationHandler.bypass = true;
    appointment.Start__c = appointment.Start__c.addDays(1);
    appointment.End__c = appointment.End__c.addDays(1);
    appointment.Reminder_Sent_At__c = null;
    update appointment;
    AppointmentCommunicationHandler.bypass = false;
    AppointmentCommunicationService.SendResult result = AppointmentCommunicationService.sendReminder(
      appointment.Id,
      true,
      null
    );
    System.assertEquals(
      1,
      result.queuedCount,
      'Previous occurrence history cannot suppress the new appointment time'
    );
    System.assertEquals(
      appointment.Start__c,
      [
        SELECT Appointment_Start__c
        FROM Appointment_Communication__c
        WHERE Appointment__c = :appointment.Id AND Status__c = 'Queued'
      ]
      .Appointment_Start__c
    );
  }

  @IsTest
  static void legacyFailedSmsRecoversFromPrematureStamp() {
    Patient__c patient = insertPatient(
      'MRN-COMM-LEGACY',
      'legacy@example.com',
      '5550100444',
      true
    );
    Appointment__c appointment = insertBookedAppointment(
      patient.Id,
      Datetime.now().addDays(1)
    );
    AppointmentCommunicationService.testConfigOverride = baseConfig(true, true);
    AppointmentCommunicationService.skipSmsEnqueue = true;
    AppointmentCommunicationService.skipEmailSend = true;
    AppointmentCommunicationHandler.bypass = true;
    update new Appointment__c(
      Id = appointment.Id,
      Reminder_Sent_At__c = Datetime.now()
    );
    AppointmentCommunicationHandler.bypass = false;
    insert history(appointment, 'SMS', 'Failed', false);
    insert history(appointment, 'Email', 'Sent', false);
    AppointmentCommunicationService.SendResult result = AppointmentCommunicationService.sendReminder(
      appointment.Id,
      true,
      null
    );
    System.assertEquals(
      0,
      result.sentCount,
      'A legacy successful email stays deduplicated'
    );
    System.assertEquals(
      1,
      result.queuedCount,
      'A legacy failed SMS can retry despite the incorrect old appointment stamp'
    );
  }

  private static Appointment_Communication__c history(
    Appointment__c appointment,
    String channel,
    String status,
    Boolean snapshot
  ) {
    return new Appointment_Communication__c(
      Appointment__c = appointment.Id,
      Patient__c = appointment.Patient__c,
      Type__c = 'Reminder',
      Channel__c = channel,
      Status__c = status,
      Triggered_By__c = 'Automated',
      Appointment_Start__c = snapshot ? appointment.Start__c : null,
      Sent_At__c = status == 'Sent' ? Datetime.now() : null
    );
  }

  private static Appointment_Comm_Config__mdt baseConfig(
    Boolean emailEnabled,
    Boolean smsEnabled
  ) {
    Appointment_Comm_Config__mdt config = new Appointment_Comm_Config__mdt();
    config.Email_Enabled__c = emailEnabled;
    config.SMS_Enabled__c = smsEnabled;
    config.Auto_Send_Confirmation__c = true;
    config.Auto_Send_Reminder__c = true;
    config.Reminder_Hours_Before__c = 24;
    config.Twilio_Named_Credential__c = 'LogicEMR_Twilio';
    config.Twilio_Account_Sid__c = 'ACtestsid';
    config.Twilio_From_Number__c = '+15551234567';
    return config;
  }

  private static Patient__c insertPatient(
    String mrn,
    String email,
    String phone,
    Boolean smsOptIn
  ) {
    Patient__c patient = new Patient__c(
      MRN__c = mrn,
      First_Name__c = 'Ada',
      Last_Name__c = 'Comm',
      Email__c = email,
      Phone__c = phone,
      SMS_Opt_In__c = smsOptIn
    );
    insert patient;
    return patient;
  }

  private static Appointment__c insertBookedAppointment(
    Id patientId,
    Datetime startTime
  ) {
    Practitioner__c practitioner = new Practitioner__c(
      First_Name__c = 'Doc',
      Last_Name__c = 'Who'
    );
    insert practitioner;
    AppointmentCommunicationHandler.bypass = true;
    Appointment__c appointment = new Appointment__c(
      Patient__c = patientId,
      Practitioner__c = practitioner.Id,
      Start__c = startTime,
      End__c = startTime.addMinutes(30),
      Status__c = 'Booked',
      Appointment_Type__c = 'Checkup',
      Location_Name__c = 'Clinic A',
      Reason__c = 'Follow-up'
    );
    insert appointment;
    AppointmentCommunicationHandler.bypass = false;
    return appointment;
  }

  private class TwilioSuccessMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(201);
      response.setBody('{"sid":"SMxxxxxxxx","status":"queued"}');
      return response;
    }
  }
}
