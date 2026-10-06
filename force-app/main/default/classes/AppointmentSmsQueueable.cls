public with sharing class AppointmentSmsQueueable implements Queueable, Database.AllowsCallouts {
  private static final Integer CHUNK_SIZE = 50;
  private final List<AppointmentCommunicationService.SmsJob> jobs;

  public AppointmentSmsQueueable(
    List<AppointmentCommunicationService.SmsJob> jobs
  ) {
    this.jobs = jobs == null
      ? new List<AppointmentCommunicationService.SmsJob>()
      : new List<AppointmentCommunicationService.SmsJob>(jobs);
  }

  public void execute(QueueableContext context) {
    if (jobs.isEmpty()) {
      return;
    }
    Set<Id> communicationIds = new Set<Id>();
    Set<Id> appointmentIds = new Set<Id>();
    Integer chunkEnd = Math.min(jobs.size(), CHUNK_SIZE);
    for (Integer index = 0; index < chunkEnd; index++) {
      AppointmentCommunicationService.SmsJob job = jobs[index];
      if (job != null) {
        communicationIds.add(job.communicationId);
        appointmentIds.add(job.appointmentId);
      }
    }
    Map<Id, Appointment_Communication__c> logs = new Map<Id, Appointment_Communication__c>(
      [
        SELECT
          Id,
          Appointment__c,
          Appointment_Start__c,
          Type__c,
          Status__c,
          Triggered_By__c
        FROM Appointment_Communication__c
        WHERE Id IN :communicationIds
      ]
    );
    Map<Id, Appointment__c> appointments = new Map<Id, Appointment__c>(
      [
        SELECT
          Id,
          Start__c,
          Status__c,
          Patient__r.Phone__c,
          Patient__r.SMS_Opt_In__c
        FROM Appointment__c
        WHERE Id IN :appointmentIds
      ]
    );
    List<Appointment_Communication__c> updates = new List<Appointment_Communication__c>();
    List<Appointment_Communication__c> accepted = new List<Appointment_Communication__c>();
    Set<Id> processedLogs = new Set<Id>();
    for (Integer index = 0; index < chunkEnd; index++) {
      AppointmentCommunicationService.SmsJob job = jobs[index];
      if (
        job == null ||
        job.communicationId == null ||
        processedLogs.contains(job.communicationId)
      ) {
        continue;
      }
      processedLogs.add(job.communicationId);
      Appointment_Communication__c logRow = logs.get(job.communicationId);
      if (
        logRow == null ||
        logRow.Status__c != AppointmentCommunicationService.STATUS_QUEUED
      ) {
        continue;
      }
      Appointment__c appointment = appointments.get(job.appointmentId);
      Appointment_Communication__c updateRow = new Appointment_Communication__c(
        Id = logRow.Id
      );
      Datetime expectedStart = logRow.Appointment_Start__c;
      if (
        appointment == null ||
        logRow.Appointment__c != job.appointmentId ||
        appointment.Start__c != expectedStart ||
        (appointment.Status__c != 'Booked' &&
        !(logRow.Triggered_By__c == 'Manual' &&
        appointment.Status__c == 'Proposed'))
      ) {
        updateRow.Status__c = AppointmentCommunicationService.STATUS_SKIPPED;
        updateRow.Error_Message__c = 'Appointment was rescheduled or is no longer eligible.';
        updates.add(updateRow);
        continue;
      }
      if (
        appointment.Patient__r == null ||
        appointment.Patient__r.SMS_Opt_In__c != true ||
        appointment.Patient__r.Phone__c != job.toNumber
      ) {
        updateRow.Status__c = AppointmentCommunicationService.STATUS_SKIPPED;
        updateRow.Error_Message__c = 'SMS consent or patient phone changed before sending.';
        updates.add(updateRow);
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
          updateRow.Status__c = AppointmentCommunicationService.STATUS_FAILED;
          updateRow.Error_Message__c = clipError(
            'Twilio HTTP ' + statusCode + ': ' + response.getBody()
          );
        } else {
          updateRow.Status__c = AppointmentCommunicationService.STATUS_SENT;
          updateRow.Sent_At__c = Datetime.now();
          // Keep the occurrence and message type for the post-callout stamp check.
          updateRow.Appointment__c = logRow.Appointment__c;
          updateRow.Appointment_Start__c = expectedStart;
          updateRow.Type__c = logRow.Type__c;
          accepted.add(updateRow);
        }
      } catch (Exception e) {
        updateRow.Status__c = AppointmentCommunicationService.STATUS_FAILED;
        updateRow.Error_Message__c = clipError(e.getMessage());
      }
      updates.add(updateRow);
    }
    // All callouts finish before DML. A late response cannot stamp a rescheduled occurrence.
    stampAccepted(accepted);
    if (!updates.isEmpty()) {
      update updates;
    }
    if (jobs.size() > chunkEnd) {
      List<AppointmentCommunicationService.SmsJob> remaining = new List<AppointmentCommunicationService.SmsJob>();
      for (Integer index = chunkEnd; index < jobs.size(); index++) {
        remaining.add(jobs[index]);
      }
      System.enqueueJob(new AppointmentSmsQueueable(remaining));
    }
  }

  private static void stampAccepted(
    List<Appointment_Communication__c> accepted
  ) {
    Set<Id> appointmentIds = new Set<Id>();
    for (Appointment_Communication__c row : accepted) {
      appointmentIds.add(row.Appointment__c);
    }
    if (appointmentIds.isEmpty()) {
      return;
    }
    Map<Id, Appointment__c> current = new Map<Id, Appointment__c>(
      [
        SELECT Id, Start__c, Status__c
        FROM Appointment__c
        WHERE Id IN :appointmentIds
        FOR UPDATE
      ]
    );
    Map<Id, Appointment__c> stamps = new Map<Id, Appointment__c>();
    for (Appointment_Communication__c row : accepted) {
      Appointment__c appointment = current.get(row.Appointment__c);
      if (
        appointment == null ||
        appointment.Start__c != row.Appointment_Start__c ||
        (appointment.Status__c != 'Booked' &&
        appointment.Status__c != 'Proposed')
      ) {
        continue;
      }
      Appointment__c stamp = stamps.get(appointment.Id);
      if (stamp == null) {
        stamp = new Appointment__c(Id = appointment.Id);
        stamps.put(appointment.Id, stamp);
      }
      if (row.Type__c == AppointmentCommunicationService.TYPE_REMINDER) {
        stamp.Reminder_Sent_At__c = row.Sent_At__c;
      } else {
        stamp.Confirmation_Sent_At__c = row.Sent_At__c;
      }
    }
    Boolean priorBypass = AppointmentCommunicationHandler.bypass;
    AppointmentCommunicationHandler.bypass = true;
    try {
      if (!stamps.isEmpty()) {
        update stamps.values();
      }
    } finally {
      AppointmentCommunicationHandler.bypass = priorBypass;
    }
  }

  private static String clipError(String message) {
    return message != null &&
      message.length() > 32768
      ? message.substring(0, 32768)
      : message;
  }
}
