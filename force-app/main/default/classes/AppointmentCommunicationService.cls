public with sharing class AppointmentCommunicationService {
  public static final String TYPE_CONFIRMATION = 'Confirmation';
  public static final String TYPE_REMINDER = 'Reminder';
  public static final String CHANNEL_EMAIL = 'Email';
  public static final String CHANNEL_SMS = 'SMS';
  public static final String CHANNEL_PRINT = 'Print';
  public static final String STATUS_SENT = 'Sent';
  public static final String STATUS_QUEUED = 'Queued';
  public static final String STATUS_FAILED = 'Failed';
  public static final String STATUS_SKIPPED = 'Skipped';
  public static final String TRIGGER_AUTOMATED = 'Automated';
  public static final String TRIGGER_MANUAL = 'Manual';
  public static final String APPT_BOOKED = 'Booked';
  public static final String APPT_PROPOSED = 'Proposed';

  private static final Pattern TOKEN_PATTERN = Pattern.compile(
    '\\{([^{}]+)\\}'
  );
  private static final String CONFIG_DEVELOPER_NAME = 'Default';
  private static final Integer MAX_AUTOMATED_ATTEMPTS = 3;

  @TestVisible
  private static Appointment_Comm_Config__mdt testConfigOverride;
  @TestVisible
  private static Boolean skipEmailSend = false;
  @TestVisible
  private static Boolean skipSmsEnqueue = false;

  public class ChannelAvailability {
    @AuraEnabled
    public Boolean emailAvailable;
    @AuraEnabled
    public Boolean smsAvailable;
    @AuraEnabled
    public Boolean canSend;
    @AuraEnabled
    public String emailRecipient;
    @AuraEnabled
    public String smsRecipient;
    @AuraEnabled
    public String appointmentStatus;
  }

  public class SendResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Integer sentCount;
    @AuraEnabled
    public Integer queuedCount;
    @AuraEnabled
    public Integer skippedCount;
    @AuraEnabled
    public Integer failedCount;
  }

  public class PrintPayload {
    @AuraEnabled
    public Id appointmentId;
    @AuraEnabled
    public Id patientId;
    @AuraEnabled
    public String patientName;
    @AuraEnabled
    public String mrn;
    @AuraEnabled
    public Datetime startTime;
    @AuraEnabled
    public Datetime endTime;
    @AuraEnabled
    public String practitionerName;
    @AuraEnabled
    public String locationName;
    @AuraEnabled
    public String appointmentType;
    @AuraEnabled
    public String reason;
    @AuraEnabled
    public String status;
  }

  public class SmsJob {
    public Id communicationId;
    public Id appointmentId;
    public String toNumber;
    public String body;
    public String namedCredential;
    public String accountSid;
    public String fromNumber;
    public Datetime appointmentStart;
  }

  public static Appointment_Comm_Config__mdt getConfig() {
    if (testConfigOverride != null) {
      return testConfigOverride;
    }
    Map<String, Appointment_Comm_Config__mdt> allRows = Appointment_Comm_Config__mdt.getAll();
    if (allRows.containsKey(CONFIG_DEVELOPER_NAME)) {
      return allRows.get(CONFIG_DEVELOPER_NAME);
    }
    for (Appointment_Comm_Config__mdt row : allRows.values()) {
      return row;
    }
    Appointment_Comm_Config__mdt fallback = new Appointment_Comm_Config__mdt();
    fallback.Email_Enabled__c = true;
    fallback.SMS_Enabled__c = false;
    fallback.Auto_Send_Confirmation__c = true;
    fallback.Auto_Send_Reminder__c = true;
    fallback.Reminder_Hours_Before__c = 24;
    fallback.Twilio_Named_Credential__c = 'LogicEMR_Twilio';
    return fallback;
  }

  public static ChannelAvailability getChannelAvailability(Id appointmentId) {
    ChannelAvailability result = new ChannelAvailability();
    result.emailAvailable = false;
    result.smsAvailable = false;
    result.canSend =
      Schema.sObjectType.Appointment__c.isUpdateable() &&
      Schema.sObjectType.Appointment_Communication__c.isCreateable();
    if (appointmentId == null) {
      return result;
    }
    List<Appointment__c> rows = [
      SELECT
        Id,
        Status__c,
        Patient__r.Email__c,
        Patient__r.Phone__c,
        Patient__r.SMS_Opt_In__c
      FROM Appointment__c
      WHERE Id = :appointmentId
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      return result;
    }
    Appointment__c appointment = rows[0];
    result.appointmentStatus = appointment.Status__c;
    Appointment_Comm_Config__mdt config = getConfig();
    result.emailRecipient = appointment.Patient__r != null
      ? appointment.Patient__r.Email__c
      : null;
    result.smsRecipient = appointment.Patient__r != null
      ? appointment.Patient__r.Phone__c
      : null;
    result.emailAvailable =
      config.Email_Enabled__c == true &&
      String.isNotBlank(result.emailRecipient);
    result.smsAvailable =
      isSmsConfigured(config) &&
      String.isNotBlank(result.smsRecipient) &&
      appointment.Patient__r != null &&
      appointment.Patient__r.SMS_Opt_In__c == true;
    return result;
  }

  public static void requireManualNotificationAccess(Boolean printing) {
    SchedulingIntegrityService.requireWrite(
      Appointment_Communication__c.SObjectType,
      true,
      new List<Schema.SObjectField>{
        Appointment_Communication__c.Appointment__c,
        Appointment_Communication__c.Patient__c,
        Appointment_Communication__c.Type__c,
        Appointment_Communication__c.Channel__c,
        Appointment_Communication__c.Triggered_By__c,
        Appointment_Communication__c.Recipient__c,
        Appointment_Communication__c.Subject__c,
        Appointment_Communication__c.Body__c
      }
    );
    if (printing != true) {
      SchedulingIntegrityService.requireWrite(
        Appointment__c.SObjectType,
        false,
        new List<Schema.SObjectField>()
      );
    }
  }

  public static SendResult sendConfirmation(
    Id appointmentId,
    Boolean automated,
    List<String> channels
  ) {
    return sendForAppointments(
      new List<Id>{ appointmentId },
      TYPE_CONFIRMATION,
      automated == true ? TRIGGER_AUTOMATED : TRIGGER_MANUAL,
      channels,
      automated == true
    );
  }

  public static SendResult sendReminder(
    Id appointmentId,
    Boolean automated,
    List<String> channels
  ) {
    return sendForAppointments(
      new List<Id>{ appointmentId },
      TYPE_REMINDER,
      automated == true ? TRIGGER_AUTOMATED : TRIGGER_MANUAL,
      channels,
      automated == true
    );
  }

  public static SendResult sendForAppointments(
    List<Id> appointmentIds,
    String messageType,
    String triggeredBy,
    List<String> requestedChannels,
    Boolean automated
  ) {
    SendResult result = new SendResult();
    result.success = true;
    result.sentCount = 0;
    result.queuedCount = 0;
    result.skippedCount = 0;
    result.failedCount = 0;
    if (appointmentIds == null || appointmentIds.isEmpty()) {
      result.message = 'No appointments to notify.';
      return result;
    }

    Appointment_Comm_Config__mdt config = getConfig();
    if (automated == true) {
      if (
        messageType == TYPE_CONFIRMATION &&
        config.Auto_Send_Confirmation__c != true
      ) {
        result.message = 'Automated confirmations are disabled.';
        return result;
      }
      if (
        messageType == TYPE_REMINDER &&
        config.Auto_Send_Reminder__c != true
      ) {
        result.message = 'Automated reminders are disabled.';
        return result;
      }
    }

    Map<Id, Appointment__c> appointments = new Map<Id, Appointment__c>(
      [
        SELECT
          Id,
          Name,
          Status__c,
          Start__c,
          End__c,
          Location_Name__c,
          Appointment_Type__c,
          Reason__c,
          Confirmation_Sent_At__c,
          Reminder_Sent_At__c,
          Patient__c,
          Patient__r.Name,
          Patient__r.First_Name__c,
          Patient__r.Email__c,
          Patient__r.Phone__c,
          Patient__r.SMS_Opt_In__c,
          Patient__r.MRN__c,
          Practitioner__c,
          Practitioner__r.Name,
          Practitioner__r.First_Name__c,
          Practitioner__r.Last_Name__c
        FROM Appointment__c
        WHERE Id IN :appointmentIds
        FOR UPDATE
      ]
    );

    Map<String, Appointment_Message_Template__mdt> templates = loadTemplates(
      messageType
    );
    Map<String, ChannelHistory> history = loadChannelHistory(
      appointments,
      messageType
    );
    List<Appointment_Communication__c> logs = new List<Appointment_Communication__c>();
    List<SmsJob> smsJobs = new List<SmsJob>();
    List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
    List<Integer> emailLogIndexes = new List<Integer>();
    Map<Id, Appointment__c> stampUpdates = new Map<Id, Appointment__c>();
    Id orgWideEmailId = resolveOrgWideEmailId(config);

    Set<Id> processedAppointmentIds = new Set<Id>();
    for (Id appointmentId : appointmentIds) {
      if (processedAppointmentIds.contains(appointmentId)) {
        continue;
      }
      processedAppointmentIds.add(appointmentId);
      Appointment__c appointment = appointments.get(appointmentId);
      if (appointment == null) {
        result.skippedCount++;
        continue;
      }
      if (!isEligibleStatus(appointment.Status__c, automated)) {
        logs.add(
          buildLog(
            appointment,
            messageType,
            CHANNEL_EMAIL,
            STATUS_SKIPPED,
            triggeredBy,
            null,
            null,
            null,
            'Appointment status is not eligible for ' + messageType + '.'
          )
        );
        result.skippedCount++;
        continue;
      }
      Boolean legacyStamp = messageType == TYPE_CONFIRMATION
        ? appointment.Confirmation_Sent_At__c != null
        : appointment.Reminder_Sent_At__c != null;
      if (
        automated == true &&
        legacyStamp &&
        !history.containsKey(channelKey(appointment.Id, CHANNEL_EMAIL)) &&
        !history.containsKey(channelKey(appointment.Id, CHANNEL_SMS))
      ) {
        // Preserve notifications sent before occurrence/channel tracking was introduced.
        result.skippedCount++;
        continue;
      }

      List<String> channels = resolveChannels(
        requestedChannels,
        automated,
        config,
        appointment
      );
      Boolean anySent = false;
      if (channels.isEmpty()) {
        logs.add(
          buildLog(
            appointment,
            messageType,
            CHANNEL_EMAIL,
            STATUS_SKIPPED,
            triggeredBy,
            null,
            null,
            null,
            'No eligible channels for this patient.'
          )
        );
        result.skippedCount++;
        continue;
      }

      Map<String, String> tokens = buildTokens(appointment);
      for (String channel : channels) {
        ChannelHistory prior = history.get(channelKey(appointment.Id, channel));
        if (
          prior != null &&
          (prior.queued ||
          (automated == true &&
          (prior.sent || prior.failedCount >= MAX_AUTOMATED_ATTEMPTS)))
        ) {
          result.skippedCount++;
          continue;
        }
        Appointment_Message_Template__mdt template = templates.get(channel);
        String subject = mergeTemplate(
          template != null ? template.Subject__c : null,
          tokens
        );
        String body = mergeTemplate(
          template != null && String.isNotBlank(template.Body__c)
            ? template.Body__c
            : defaultBody(messageType, channel),
          tokens
        );
        if (channel == CHANNEL_EMAIL) {
          if (
            config.Email_Enabled__c != true ||
            appointment.Patient__r == null ||
            String.isBlank(appointment.Patient__r.Email__c)
          ) {
            logs.add(
              buildLog(
                appointment,
                messageType,
                CHANNEL_EMAIL,
                STATUS_SKIPPED,
                triggeredBy,
                appointment.Patient__r != null
                  ? appointment.Patient__r.Email__c
                  : null,
                subject,
                body,
                'Email is not available for this patient.'
              )
            );
            result.skippedCount++;
            continue;
          }
          Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
          mail.setToAddresses(
            new List<String>{ appointment.Patient__r.Email__c }
          );
          mail.setSubject(
            String.isNotBlank(subject)
              ? subject
              : messageType + ' for your appointment'
          );
          mail.setHtmlBody(body);
          mail.setSaveAsActivity(false);
          if (orgWideEmailId != null) {
            mail.setOrgWideEmailAddressId(orgWideEmailId);
          }
          emails.add(mail);
          emailLogIndexes.add(logs.size());
          logs.add(
            buildLog(
              appointment,
              messageType,
              CHANNEL_EMAIL,
              STATUS_SENT,
              triggeredBy,
              appointment.Patient__r.Email__c,
              mail.getSubject(),
              body,
              null
            )
          );
          anySent = true;
        } else if (channel == CHANNEL_SMS) {
          if (!canSendSms(config, appointment)) {
            logs.add(
              buildLog(
                appointment,
                messageType,
                CHANNEL_SMS,
                STATUS_SKIPPED,
                triggeredBy,
                appointment.Patient__r == null
                  ? null
                  : appointment.Patient__r.Phone__c,
                subject,
                body,
                'SMS is not available for this patient or Twilio is not configured.'
              )
            );
            result.skippedCount++;
            continue;
          }
          Appointment_Communication__c smsLog = buildLog(
            appointment,
            messageType,
            CHANNEL_SMS,
            STATUS_QUEUED,
            triggeredBy,
            appointment.Patient__r.Phone__c,
            subject,
            body,
            null
          );
          logs.add(smsLog);
          SmsJob job = new SmsJob();
          job.appointmentId = appointment.Id;
          job.toNumber = appointment.Patient__r.Phone__c;
          job.body = stripHtml(body);
          job.namedCredential = config.Twilio_Named_Credential__c;
          job.accountSid = config.Twilio_Account_Sid__c;
          job.fromNumber = config.Twilio_From_Number__c;
          job.appointmentStart = appointment.Start__c;
          smsJobs.add(job);
          result.queuedCount++;
        }
      }
      if (anySent) {
        Appointment__c stamp = stampUpdates.containsKey(appointment.Id)
          ? stampUpdates.get(appointment.Id)
          : new Appointment__c(Id = appointment.Id);
        if (messageType == TYPE_CONFIRMATION) {
          stamp.Confirmation_Sent_At__c = Datetime.now();
        } else if (messageType == TYPE_REMINDER) {
          stamp.Reminder_Sent_At__c = Datetime.now();
        }
        stampUpdates.put(appointment.Id, stamp);
      }
    }

    if (!emails.isEmpty() && skipEmailSend != true) {
      List<Messaging.SendEmailResult> emailResults = Messaging.sendEmail(
        emails,
        false
      );
      for (Integer i = 0; i < emailResults.size(); i++) {
        Messaging.SendEmailResult emailResult = emailResults[i];
        Integer logIndex = emailLogIndexes[i];
        if (emailResult.isSuccess()) {
          result.sentCount++;
        } else {
          result.failedCount++;
          result.sentCount = Math.max(0, result.sentCount);
          logs[logIndex].Status__c = STATUS_FAILED;
          logs[logIndex].Sent_At__c = null;
          List<String> errors = new List<String>();
          for (Messaging.SendEmailError err : emailResult.getErrors()) {
            errors.add(err.getMessage());
          }
          logs[logIndex].Error_Message__c = String.join(errors, '; ');
        }
      }
    } else if (!emails.isEmpty() && skipEmailSend == true) {
      result.sentCount += emails.size();
    }

    // Only stamp appointments that still have at least one Sent channel log.
    if (!stampUpdates.isEmpty()) {
      Set<Id> stillSent = new Set<Id>();
      for (Appointment_Communication__c logRow : logs) {
        if (logRow.Status__c == STATUS_SENT && logRow.Appointment__c != null) {
          stillSent.add(logRow.Appointment__c);
        }
      }
      for (Id appointmentId : new List<Id>(stampUpdates.keySet())) {
        if (!stillSent.contains(appointmentId)) {
          stampUpdates.remove(appointmentId);
        }
      }
    }

    if (!logs.isEmpty()) {
      insert logs;
    }

    List<SmsJob> jobsWithIds = new List<SmsJob>();
    Integer smsCursor = 0;
    for (Appointment_Communication__c logRow : logs) {
      if (
        logRow.Channel__c == CHANNEL_SMS &&
        logRow.Status__c == STATUS_QUEUED &&
        smsCursor < smsJobs.size()
      ) {
        SmsJob job = smsJobs[smsCursor];
        job.communicationId = logRow.Id;
        jobsWithIds.add(job);
        smsCursor++;
      }
    }
    if (!jobsWithIds.isEmpty() && skipSmsEnqueue != true) {
      System.enqueueJob(new AppointmentSmsQueueable(jobsWithIds));
    }

    if (!stampUpdates.isEmpty()) {
      Boolean priorBypass = AppointmentCommunicationHandler.bypass;
      AppointmentCommunicationHandler.bypass = true;
      try {
        update stampUpdates.values();
      } finally {
        AppointmentCommunicationHandler.bypass = priorBypass;
      }
    }

    result.success = result.failedCount == 0;
    result.message =
      'Sent ' +
      result.sentCount +
      ', queued ' +
      result.queuedCount +
      ', skipped ' +
      result.skippedCount +
      ', failed ' +
      result.failedCount +
      '.';
    return result;
  }

  public static PrintPayload getPrintPayload(Id appointmentId) {
    if (appointmentId == null) {
      throw new AuraHandledException('Appointment Id is required.');
    }
    List<Appointment__c> rows = [
      SELECT
        Id,
        Status__c,
        Start__c,
        End__c,
        Location_Name__c,
        Appointment_Type__c,
        Reason__c,
        Patient__c,
        Patient__r.Name,
        Patient__r.MRN__c,
        Practitioner__r.Name,
        Practitioner__r.First_Name__c,
        Practitioner__r.Last_Name__c
      FROM Appointment__c
      WHERE Id = :appointmentId
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw new AuraHandledException('Appointment was not found.');
    }
    Appointment__c appointment = rows[0];
    PrintPayload payload = new PrintPayload();
    payload.appointmentId = appointment.Id;
    payload.patientId = appointment.Patient__c;
    payload.patientName = appointment.Patient__r != null
      ? appointment.Patient__r.Name
      : '';
    payload.mrn = appointment.Patient__r != null
      ? appointment.Patient__r.MRN__c
      : '';
    payload.startTime = appointment.Start__c;
    payload.endTime = appointment.End__c;
    payload.practitionerName = formatPractitioner(appointment);
    payload.locationName = appointment.Location_Name__c;
    payload.appointmentType = appointment.Appointment_Type__c;
    payload.reason = appointment.Reason__c;
    payload.status = appointment.Status__c;
    return payload;
  }

  public static SendResult logPrint(Id appointmentId) {
    SendResult result = new SendResult();
    result.sentCount = 0;
    result.queuedCount = 0;
    result.skippedCount = 0;
    result.failedCount = 0;
    if (appointmentId == null) {
      result.success = false;
      result.message = 'Appointment Id is required.';
      return result;
    }
    List<Appointment__c> rows = [
      SELECT Id, Start__c, Patient__c, Patient__r.Name
      FROM Appointment__c
      WHERE Id = :appointmentId
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      result.success = false;
      result.message = 'Appointment was not found.';
      return result;
    }
    Appointment__c appointment = rows[0];
    insert buildLog(
      appointment,
      TYPE_CONFIRMATION,
      CHANNEL_PRINT,
      STATUS_SENT,
      TRIGGER_MANUAL,
      appointment.Patient__r != null ? appointment.Patient__r.Name : null,
      'Appointment printout',
      'Printed appointment slip',
      null
    );
    result.success = true;
    result.sentCount = 1;
    result.message = 'Print logged.';
    return result;
  }

  public static Boolean isSmsConfigured(Appointment_Comm_Config__mdt config) {
    return config != null &&
      config.SMS_Enabled__c == true &&
      String.isNotBlank(config.Twilio_Named_Credential__c) &&
      String.isNotBlank(config.Twilio_Account_Sid__c) &&
      String.isNotBlank(config.Twilio_From_Number__c);
  }

  private static Boolean canSendSms(
    Appointment_Comm_Config__mdt config,
    Appointment__c appointment
  ) {
    return isSmsConfigured(config) &&
      appointment.Patient__r != null &&
      String.isNotBlank(appointment.Patient__r.Phone__c) &&
      appointment.Patient__r.SMS_Opt_In__c == true;
  }

  private static Boolean isEligibleStatus(String status, Boolean automated) {
    if (status == APPT_BOOKED) {
      return true;
    }
    return automated != true && status == APPT_PROPOSED;
  }

  private class ChannelHistory {
    public Boolean sent = false;
    public Boolean queued = false;
    public Integer failedCount = 0;
  }

  private static String channelKey(Id appointmentId, String channel) {
    return String.valueOf(appointmentId) + ':' + channel;
  }

  private static Map<String, ChannelHistory> loadChannelHistory(
    Map<Id, Appointment__c> appointments,
    String messageType
  ) {
    // The caller already checked appointment visibility. Read channel state across
    // staff owners so a different sender cannot enqueue a duplicate pending SMS.
    return new CommunicationHistoryReader().load(appointments, messageType);
  }

  private without sharing class CommunicationHistoryReader {
    public Map<String, ChannelHistory> load(
      Map<Id, Appointment__c> appointments,
      String messageType
    ) {
      Map<String, ChannelHistory> result = new Map<String, ChannelHistory>();
      for (Appointment_Communication__c row : [
        SELECT
          Appointment__c,
          Appointment_Start__c,
          Channel__c,
          Status__c,
          CreatedDate
        FROM Appointment_Communication__c
        WHERE
          Appointment__c IN :appointments.keySet()
          AND Type__c = :messageType
          AND Channel__c IN ('Email', 'SMS')
          AND Status__c IN ('Sent', 'Queued', 'Failed')
      ]) {
        Appointment__c appointment = appointments.get(row.Appointment__c);
        if (appointment == null) {
          continue;
        }
        Datetime legacyStamp = messageType == TYPE_CONFIRMATION
          ? appointment.Confirmation_Sent_At__c
          : appointment.Reminder_Sent_At__c;
        Boolean currentOccurrence =
          row.Appointment_Start__c == appointment.Start__c;
        // Earlier SMS processing prematurely stamped the appointment even when
        // Twilio failed. Recognize logs written with that stamp so they can retry,
        // while preserving old successful channels and older occurrence history.
        Boolean stampedLegacyOccurrence =
          row.Appointment_Start__c == null &&
          legacyStamp != null &&
          row.CreatedDate >= legacyStamp.addMinutes(-5) &&
          row.CreatedDate <= legacyStamp.addMinutes(5);
        if (!currentOccurrence && !stampedLegacyOccurrence) {
          continue;
        }
        String key = channelKey(row.Appointment__c, row.Channel__c);
        ChannelHistory prior = result.get(key);
        if (prior == null) {
          prior = new ChannelHistory();
          result.put(key, prior);
        }
        prior.sent = prior.sent || row.Status__c == STATUS_SENT;
        prior.queued = prior.queued || row.Status__c == STATUS_QUEUED;
        if (row.Status__c == STATUS_FAILED) {
          prior.failedCount++;
        }
      }
      return result;
    }
  }

  private static List<String> resolveChannels(
    List<String> requestedChannels,
    Boolean automated,
    Appointment_Comm_Config__mdt config,
    Appointment__c appointment
  ) {
    List<String> channels = new List<String>();
    Set<String> requested = new Set<String>();
    if (requestedChannels != null) {
      for (String channel : requestedChannels) {
        if (String.isNotBlank(channel)) {
          requested.add(channel);
        }
      }
    }
    Boolean wantEmail =
      automated == true ||
      requested.isEmpty() ||
      requested.contains(CHANNEL_EMAIL);
    Boolean wantSms =
      automated == true ||
      requested.isEmpty() ||
      requested.contains(CHANNEL_SMS);
    if (
      wantEmail &&
      (config.Email_Enabled__c == true || requested.contains(CHANNEL_EMAIL))
    ) {
      channels.add(CHANNEL_EMAIL);
    }
    if (
      wantSms &&
      (config.SMS_Enabled__c == true || requested.contains(CHANNEL_SMS))
    ) {
      channels.add(CHANNEL_SMS);
    }
    // Manual with explicit empty after filter still empty — automated falls through to skip log
    if (automated != true && !requested.isEmpty()) {
      // Respect explicit channel selection only
      List<String> filtered = new List<String>();
      for (String channel : channels) {
        if (requested.contains(channel)) {
          filtered.add(channel);
        }
      }
      return filtered;
    }
    return channels;
  }

  private static Map<String, Appointment_Message_Template__mdt> loadTemplates(
    String messageType
  ) {
    Map<String, Appointment_Message_Template__mdt> byChannel = new Map<String, Appointment_Message_Template__mdt>();
    for (
      Appointment_Message_Template__mdt row : Appointment_Message_Template__mdt.getAll()
        .values()
    ) {
      if (row.Active__c != true || row.Type__c != messageType) {
        continue;
      }
      byChannel.put(row.Channel__c, row);
    }
    return byChannel;
  }

  private static Map<String, String> buildTokens(Appointment__c appointment) {
    Map<String, String> tokens = new Map<String, String>();
    tokens.put(
      'Patient_Name',
      appointment.Patient__r != null &&
        String.isNotBlank(appointment.Patient__r.Name)
        ? appointment.Patient__r.Name
        : ''
    );
    tokens.put(
      'First_Name',
      appointment.Patient__r != null &&
        String.isNotBlank(appointment.Patient__r.First_Name__c)
        ? appointment.Patient__r.First_Name__c
        : ''
    );
    tokens.put('Start', formatDatetime(appointment.Start__c));
    tokens.put('End', formatDatetime(appointment.End__c));
    tokens.put(
      'Location',
      String.isNotBlank(appointment.Location_Name__c)
        ? appointment.Location_Name__c
        : ''
    );
    tokens.put('Practitioner', formatPractitioner(appointment));
    tokens.put(
      'Appointment_Type',
      String.isNotBlank(appointment.Appointment_Type__c)
        ? appointment.Appointment_Type__c
        : ''
    );
    tokens.put(
      'Reason',
      String.isNotBlank(appointment.Reason__c) ? appointment.Reason__c : ''
    );
    return tokens;
  }

  private static String formatPractitioner(Appointment__c appointment) {
    if (appointment.Practitioner__r == null) {
      return '';
    }
    String first = appointment.Practitioner__r.First_Name__c;
    String last = appointment.Practitioner__r.Last_Name__c;
    String composed = ((first != null ? first : '') +
      ' ' +
      (last != null ? last : ''))
      .trim();
    if (String.isNotBlank(composed)) {
      return composed;
    }
    return String.isNotBlank(appointment.Practitioner__r.Name)
      ? appointment.Practitioner__r.Name
      : '';
  }

  private static String formatDatetime(Datetime value) {
    if (value == null) {
      return '';
    }
    return value.format();
  }

  private static String mergeTemplate(
    String template,
    Map<String, String> tokens
  ) {
    if (String.isBlank(template)) {
      return '';
    }
    String output = template;
    Matcher matcher = TOKEN_PATTERN.matcher(template);
    while (matcher.find()) {
      String key = matcher.group(1);
      String replacement = tokens.containsKey(key) && tokens.get(key) != null
        ? tokens.get(key)
        : '';
      output = output.replace('{' + key + '}', replacement);
    }
    return output;
  }

  private static String defaultBody(String messageType, String channel) {
    if (channel == CHANNEL_SMS) {
      return 'Your appointment ({Appointment_Type}) is scheduled for {Start} at {Location} with {Practitioner}.';
    }
    return '<p>Hello {First_Name},</p><p>Your ' +
      messageType.toLowerCase() +
      ' details:</p><p>{Start} with {Practitioner} at {Location}</p>';
  }

  private static String stripHtml(String value) {
    if (String.isBlank(value)) {
      return '';
    }
    return value.replaceAll('<[^>]+>', ' ').replaceAll('\\s+', ' ').trim();
  }

  private static Appointment_Communication__c buildLog(
    Appointment__c appointment,
    String messageType,
    String channel,
    String status,
    String triggeredBy,
    String recipient,
    String subject,
    String body,
    String errorMessage
  ) {
    return new Appointment_Communication__c(
      Appointment__c = appointment.Id,
      Patient__c = appointment.Patient__c,
      Type__c = messageType,
      Channel__c = channel,
      Status__c = status,
      Triggered_By__c = triggeredBy,
      Sent_At__c = status == STATUS_SENT ? Datetime.now() : null,
      Appointment_Start__c = appointment.Start__c,
      Recipient__c = recipient,
      Subject__c = subject,
      Body__c = body,
      Error_Message__c = errorMessage
    );
  }

  private static Id resolveOrgWideEmailId(Appointment_Comm_Config__mdt config) {
    if (config == null || String.isBlank(config.Org_Wide_Email_Address__c)) {
      return null;
    }
    String address = config.Org_Wide_Email_Address__c.trim();
    List<OrgWideEmailAddress> matches = [
      SELECT Id
      FROM OrgWideEmailAddress
      WHERE Address = :address
      LIMIT 1
    ];
    return matches.isEmpty() ? null : matches[0].Id;
  }
}
