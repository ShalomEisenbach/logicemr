@IsTest
private class SchedulingIntegrityServiceTest {
  private static final Date MONDAY = Date.newInstance(2026, 9, 7);

  @IsTest
  static void generationRejectsIntervalOverlapAcrossDurationAndSchedules() {
    Practitioner__c provider = provider();
    Schedule__c first = schedule(provider.Id, 30);
    Schedule__c second = schedule(provider.Id, 20);
    Slot__c existing = slot(first.Id, nine(), nine().addMinutes(30), 'Free');

    ScheduleManagementController.GenerationResult generated = ScheduleManagementController.generateSlots(
      second.Id,
      MONDAY,
      MONDAY
    );
    List<Slot__c> rows = [
      SELECT Start__c, End__c
      FROM Slot__c
      WHERE Schedule__c = :second.Id
      ORDER BY Start__c
    ];
    System.assertEquals(
      1,
      generated.created,
      'Only the 09:40 interval is clear of the existing 09:00-09:30 slot'
    );
    System.assertEquals(nine().addMinutes(40), rows[0].Start__c);
    System.assertEquals(
      2,
      generated.skippedExisting,
      'Both intervals overlapping the existing slot are skipped'
    );

    second.Slot_Duration_Minutes__c = 15;
    update second;
    generated = ScheduleManagementController.generateSlots(
      second.Id,
      MONDAY,
      MONDAY
    );
    System.assertEquals(
      0,
      generated.created,
      'Changing duration cannot introduce partial overlaps'
    );
    System.assertEquals(
      2,
      [SELECT COUNT() FROM Slot__c],
      'Both schedules retain only non-overlapping intervals'
    );
  }

  @IsTest
  static void overlappingTimeOffAndEditReconcileWithoutLosingManualBlocks() {
    Practitioner__c provider = provider();
    Schedule__c schedule = schedule(provider.Id, 20);
    ScheduleManagementController.generateSlots(schedule.Id, MONDAY, MONDAY);
    List<Slot__c> rows = [
      SELECT Id, Start__c
      FROM Slot__c
      WHERE Schedule__c = :schedule.Id
      ORDER BY Start__c
    ];
    rows[2].Status__c = 'Blocked';
    rows[2].Block_Reason__c = 'Equipment maintenance';
    update rows[2];
    ScheduleManagementController.UnavailabilityResult first = timeOff(
      null,
      provider.Id,
      schedule.Id,
      nine(),
      nine().addMinutes(40)
    );
    ScheduleManagementController.UnavailabilityResult second = timeOff(
      null,
      provider.Id,
      schedule.Id,
      nine().addMinutes(20),
      nine().addHours(1)
    );
    ScheduleManagementController.removeUnavailability(first.unavailability.id);
    Map<Id, Slot__c> afterRemoval = new Map<Id, Slot__c>(
      [
        SELECT Id, Status__c, Unavailability__c, Block_Reason__c
        FROM Slot__c
        WHERE Schedule__c = :schedule.Id
      ]
    );
    System.assertEquals('Free', afterRemoval.get(rows[0].Id).Status__c);
    System.assertEquals(
      'Blocked',
      afterRemoval.get(rows[1].Id).Status__c,
      'Remaining PTO still blocks the overlap'
    );
    System.assertEquals(
      second.unavailability.id,
      afterRemoval.get(rows[1].Id).Unavailability__c
    );
    System.assertEquals(
      'Equipment maintenance',
      afterRemoval.get(rows[2].Id).Block_Reason__c,
      'PTO cannot overwrite a manual block'
    );

    timeOff(
      second.unavailability.id,
      provider.Id,
      schedule.Id,
      nine().addHours(2),
      nine().addHours(3)
    );
    System.assertEquals(
      'Free',
      [SELECT Status__c FROM Slot__c WHERE Id = :rows[1].Id].Status__c,
      'Moving PTO releases its old range'
    );
    System.assertEquals(
      3,
      [SELECT COUNT() FROM Slot__c WHERE Generated_By_Unavailability__c = TRUE]
    );
    ScheduleManagementController.removeUnavailability(second.unavailability.id);
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Slot__c WHERE Generated_By_Unavailability__c = TRUE],
      'Removing PTO deletes its placeholders rather than adding out-of-hours availability'
    );
    System.assertEquals(
      'Blocked',
      [SELECT Status__c FROM Slot__c WHERE Id = :rows[2].Id].Status__c
    );
  }

  @IsTest
  static void bookingRejectsProviderAndPatientOverlapButAllowsTouchingBoundary() {
    AppointmentCommunicationHandler.bypass = true;
    Patient__c patient = patient('OVERLAP');
    Patient__c otherPatient = patient('OTHER');
    Practitioner__c firstProvider = provider();
    Practitioner__c otherProvider = provider();
    Schedule__c first = schedule(firstProvider.Id, 20);
    Schedule__c overlappingSchedule = schedule(firstProvider.Id, 20);
    Schedule__c other = schedule(otherProvider.Id, 20);
    Slot__c booked = slot(first.Id, nine(), nine().addMinutes(20), 'Free');
    Slot__c providerOverlap = slot(
      overlappingSchedule.Id,
      nine().addMinutes(10),
      nine().addMinutes(30),
      'Free'
    );
    Slot__c patientOverlap = slot(
      other.Id,
      nine().addMinutes(10),
      nine().addMinutes(30),
      'Free'
    );
    Slot__c adjacent = slot(
      first.Id,
      nine().addMinutes(20),
      nine().addMinutes(40),
      'Free'
    );
    AppointmentBookingController.bookAppointment(
      patient.Id,
      booked.Id,
      'Checkup',
      null
    );
    System.assertEquals(
      true,
      bookingRejected(providerOverlap.Id, otherPatient.Id),
      'A second schedule cannot double-book the provider'
    );
    System.assertEquals(
      true,
      bookingRejected(patientOverlap.Id, patient.Id),
      'Another provider cannot double-book the patient'
    );
    AppointmentBookingController.bookAppointment(
      patient.Id,
      adjacent.Id,
      'Checkup',
      null
    );
    System.assertEquals(2, [SELECT COUNT() FROM Appointment__c]);
    System.assertEquals(
      'Free',
      [SELECT Status__c FROM Slot__c WHERE Id = :providerOverlap.Id].Status__c,
      'Rejected booking leaves the target slot unchanged'
    );
  }

  @IsTest
  static void rescheduleAndCancelRespectRemainingTimeOff() {
    AppointmentCommunicationHandler.bypass = true;
    Patient__c patient = patient('RESCHEDULE');
    Practitioner__c provider = provider();
    Schedule__c schedule = schedule(provider.Id, 20);
    Slot__c oldSlot = slot(schedule.Id, nine(), nine().addMinutes(20), 'Free');
    Slot__c nextSlot = slot(
      schedule.Id,
      nine().addHours(1),
      nine().addHours(1).addMinutes(20),
      'Free'
    );
    AppointmentBookingController.BookingResult booked = AppointmentBookingController.bookAppointment(
      patient.Id,
      oldSlot.Id,
      'Checkup',
      null
    );
    timeOff(null, provider.Id, schedule.Id, oldSlot.Start__c, oldSlot.End__c);
    AppointmentCalendarController.ActionResult moved = AppointmentCalendarController.rescheduleAppointment(
      booked.appointmentId,
      nextSlot.Id
    );
    System.assertEquals(
      'Blocked',
      moved.previousSlotStatus,
      'Busy slot returns to the active PTO block'
    );
    System.assertEquals(null, moved.freedSlotId);
    timeOff(null, provider.Id, schedule.Id, nextSlot.Start__c, nextSlot.End__c);
    AppointmentCalendarController.ActionResult cancelled = AppointmentCalendarController.cancelAppointment(
      booked.appointmentId
    );
    System.assertEquals('Blocked', cancelled.slotStatus);
    System.assertEquals(
      'Blocked',
      [SELECT Status__c FROM Slot__c WHERE Id = :nextSlot.Id].Status__c
    );
  }

  @IsTest
  static void arrivalIsIdempotentAndCancellationReconcilesEncounter() {
    AppointmentCommunicationHandler.bypass = true;
    Patient__c patient = patient('ARRIVAL');
    Practitioner__c provider = provider();
    Schedule__c schedule = schedule(provider.Id, 20);
    Slot__c selected = slot(schedule.Id, nine(), nine().addMinutes(20), 'Free');
    AppointmentBookingController.BookingResult booked = AppointmentBookingController.bookAppointment(
      patient.Id,
      selected.Id,
      'Checkup',
      null
    );
    AppointmentCalendarController.ActionResult first = AppointmentCalendarController.arriveAppointment(
      booked.appointmentId
    );
    AppointmentCalendarController.ActionResult again = AppointmentCalendarController.arriveAppointment(
      booked.appointmentId
    );
    System.assertEquals(first.encounterId, again.encounterId);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Encounter__c],
      'Repeated arrival returns the existing encounter'
    );
    AppointmentCalendarController.cancelAppointment(booked.appointmentId);
    System.assertEquals(
      'Cancelled',
      [SELECT Status__c FROM Encounter__c WHERE Id = :first.encounterId]
      .Status__c,
      'Cancellation also closes the arrived encounter'
    );
  }

  @IsTest
  static void clinicalWorkAndFutureNoShowRejectWithoutMutation() {
    AppointmentCommunicationHandler.bypass = true;
    Patient__c patient = patient('STATUS');
    Practitioner__c provider = provider();
    Schedule__c schedule = schedule(provider.Id, 20);
    Datetime future = Datetime.now().addDays(2);
    Slot__c selected = slot(schedule.Id, future, future.addMinutes(20), 'Free');
    AppointmentBookingController.BookingResult booked = AppointmentBookingController.bookAppointment(
      patient.Id,
      selected.Id,
      'Checkup',
      null
    );
    Boolean futureNoShowRejected = false;
    try {
      AppointmentCalendarController.markNoShow(booked.appointmentId);
    } catch (AuraHandledException error) {
      futureNoShowRejected = true;
    }
    System.assert(
      futureNoShowRejected,
      'Future appointments cannot be marked No Show'
    );
    AppointmentCalendarController.ActionResult arrived = AppointmentCalendarController.arriveAppointment(
      booked.appointmentId
    );
    update new Encounter__c(
      Id = arrived.encounterId,
      Status__c = 'In Progress'
    );
    Boolean cancellationRejected = false;
    try {
      AppointmentCalendarController.cancelAppointment(booked.appointmentId);
    } catch (AuraHandledException error) {
      cancellationRejected = true;
    }
    System.assert(
      cancellationRejected,
      'Clinical work must be resolved before cancelling'
    );
    System.assertEquals(
      'Arrived',
      [SELECT Status__c FROM Appointment__c WHERE Id = :booked.appointmentId]
      .Status__c
    );
    System.assertEquals(
      'Busy',
      [SELECT Status__c FROM Slot__c WHERE Id = :selected.Id].Status__c
    );
  }

  @IsTest
  static void bookingRejectsInactiveAndTimeOffSchedules() {
    AppointmentCommunicationHandler.bypass = true;
    Patient__c patient = patient('INACTIVE');
    Practitioner__c provider = provider();
    Schedule__c schedule = schedule(provider.Id, 20);
    Slot__c selected = slot(schedule.Id, nine(), nine().addMinutes(20), 'Free');
    schedule.Active__c = false;
    update schedule;
    System.assert(bookingRejected(selected.Id, patient.Id));
    schedule.Active__c = true;
    update schedule;
    insert new Schedule_Unavailability__c(
      Practitioner__c = provider.Id,
      Schedule__c = schedule.Id,
      Start__c = selected.Start__c,
      End__c = selected.End__c,
      Active__c = true
    );
    System.assert(
      bookingRejected(selected.Id, patient.Id),
      'A stale Free slot cannot bypass active time off'
    );
    System.assertEquals(0, [SELECT COUNT() FROM Appointment__c]);
  }

  @IsTest
  static void lowPrivilegeUserCannotMutateSchedulingOrSendNotifications() {
    User reader = lowPrivilegeUser('schdeny');
    insert reader;
    PermissionSet readOnly = new PermissionSet(
      Name = 'Scheduling_Integrity_Read_Only_Test',
      Label = 'Scheduling Integrity Read Only Test'
    );
    insert readOnly;
    List<ObjectPermissions> objectAccess = new List<ObjectPermissions>();
    for (
      Schema.SObjectType objectType : new List<Schema.SObjectType>{
        Schedule__c.SObjectType,
        Slot__c.SObjectType,
        Appointment__c.SObjectType,
        Encounter__c.SObjectType,
        Appointment_Communication__c.SObjectType
      }
    ) {
      objectAccess.add(
        new ObjectPermissions(
          ParentId = readOnly.Id,
          SobjectType = objectType.getDescribe().getName(),
          PermissionsRead = true
        )
      );
    }
    insert objectAccess;
    insert new PermissionSetAssignment(
      AssigneeId = reader.Id,
      PermissionSetId = readOnly.Id
    );
    System.runAs(reader) {
      Integer rejected = 0;
      try {
        ScheduleManagementController.saveSchedule(
          null,
          null,
          null,
          20,
          MONDAY,
          MONDAY,
          true,
          null
        );
      } catch (AuraHandledException error) {
        System.assert(error.getMessage().contains('permission'));
        rejected++;
      }
      try {
        ScheduleManagementController.generateSlots(null, MONDAY, MONDAY);
      } catch (AuraHandledException error) {
        System.assert(error.getMessage().contains('permission'));
        rejected++;
      }
      try {
        ScheduleManagementController.toggleSlotStatus(null);
      } catch (AuraHandledException error) {
        System.assert(error.getMessage().contains('permission'));
        rejected++;
      }
      try {
        AppointmentBookingController.bookAppointment(
          null,
          null,
          'Checkup',
          null
        );
      } catch (AuraHandledException error) {
        System.assert(error.getMessage().contains('permission'));
        rejected++;
      }
      try {
        AppointmentCalendarController.arriveAppointment(null);
      } catch (AuraHandledException error) {
        System.assert(error.getMessage().contains('permission'));
        rejected++;
      }
      try {
        AppointmentCommunicationController.sendReminder(null, null);
      } catch (AuraHandledException error) {
        System.assert(error.getMessage().contains('permission'));
        rejected++;
      }
      try {
        AppointmentCommunicationController.logPrint(null);
      } catch (AuraHandledException error) {
        System.assert(error.getMessage().contains('permission'));
        rejected++;
      }
      System.assertEquals(
        7,
        rejected,
        'Every public mutation denies insufficient object permissions before querying or changing data'
      );
    }
  }

  @IsTest
  static void schedulerPermissionsPermitBookingAndArrival() {
    User scheduler = lowPrivilegeUser('schallow');
    insert scheduler;
    PermissionSet permissions = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'LogicEMR_Scheduler'
    ];
    insert new PermissionSetAssignment(
      AssigneeId = scheduler.Id,
      PermissionSetId = permissions.Id
    );
    System.runAs(scheduler) {
      AppointmentCommunicationHandler.bypass = true;
      Patient__c patient = patient('PERMISSION');
      Practitioner__c provider = provider();
      ScheduleManagementController.HoursView mondayHours = new ScheduleManagementController.HoursView();
      mondayHours.dayOfWeek = '1';
      mondayHours.startTime = '09:00';
      mondayHours.endTime = '10:00';
      ScheduleManagementController.ScheduleView view = ScheduleManagementController.saveSchedule(
        null,
        provider.Id,
        'Permissions Clinic',
        20,
        MONDAY,
        MONDAY,
        true,
        new List<ScheduleManagementController.HoursView>{ mondayHours }
      );
      Slot__c selected = slot(view.id, nine(), nine().addMinutes(20), 'Free');
      AppointmentBookingController.BookingResult booked = AppointmentBookingController.bookAppointment(
        patient.Id,
        selected.Id,
        'Checkup',
        null
      );
      AppointmentCalendarController.ActionResult arrived = AppointmentCalendarController.arriveAppointment(
        booked.appointmentId
      );
      System.assertNotEquals(
        null,
        arrived.encounterId,
        'The scheduling permission set includes the fields needed for arrival'
      );
      AppointmentCalendarController.cancelAppointment(booked.appointmentId);
      System.assertEquals(
        'Cancelled',
        [SELECT Status__c FROM Encounter__c WHERE Id = :arrived.encounterId]
        .Status__c
      );
    }
  }

  @IsTest
  static void slotObjectEditDoesNotBypassFieldPermissions() {
    User editor = lowPrivilegeUser('schfield');
    insert editor;
    PermissionSet permissions = new PermissionSet(
      Name = 'Scheduling_Integrity_Field_Test',
      Label = 'Scheduling Integrity Field Test'
    );
    insert permissions;
    insert new List<ObjectPermissions>{
      new ObjectPermissions(
        ParentId = permissions.Id,
        SobjectType = Schedule__c.SObjectType.getDescribe().getName(),
        PermissionsRead = true
      ),
      new ObjectPermissions(
        ParentId = permissions.Id,
        SobjectType = Slot__c.SObjectType.getDescribe().getName(),
        PermissionsRead = true,
        PermissionsEdit = true
      )
    };
    insert new PermissionSetAssignment(
      AssigneeId = editor.Id,
      PermissionSetId = permissions.Id
    );
    System.runAs(editor) {
      Boolean rejected = false;
      try {
        ScheduleManagementController.toggleSlotStatus(null);
      } catch (AuraHandledException error) {
        rejected = error.getMessage().contains('permission to change');
      }
      System.assert(
        rejected,
        'Object edit access alone cannot bypass Status/Block Reason field permissions'
      );
    }
  }

  private static User lowPrivilegeUser(String alias) {
    Profile profile = [
      SELECT Id
      FROM Profile
      WHERE Name IN ('Minimum Access - Salesforce', 'Standard User')
      ORDER BY Name
      LIMIT 1
    ];
    return new User(
      Alias = alias,
      LastName = alias,
      Email = alias + '@logicemr.test',
      Username = alias +
        '.' +
        String.valueOf(Crypto.getRandomInteger()) +
        '@logicemr.test',
      ProfileId = profile.Id,
      TimeZoneSidKey = 'America/New_York',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
  }

  private static Boolean bookingRejected(Id slotId, Id patientId) {
    try {
      AppointmentBookingController.bookAppointment(
        patientId,
        slotId,
        'Checkup',
        null
      );
      return false;
    } catch (AuraHandledException error) {
      return true;
    }
  }
  private static Practitioner__c provider() {
    Practitioner__c row = new Practitioner__c(
      First_Name__c = 'Integrity',
      Last_Name__c = 'Provider',
      Active__c = true
    );
    insert row;
    return row;
  }
  private static Patient__c patient(String suffix) {
    Patient__c row = new Patient__c(
      MRN__c = 'MRN-INTEGRITY-' + suffix,
      Last_Name__c = suffix
    );
    insert row;
    return row;
  }
  private static Schedule__c schedule(Id providerId, Integer duration) {
    Schedule__c row = new Schedule__c(
      Practitioner__c = providerId,
      Active__c = true,
      Slot_Duration_Minutes__c = duration
    );
    insert row;
    insert new Schedule_Hours__c(
      Schedule__c = row.Id,
      Day_Of_Week__c = '1',
      Start_Time__c = Time.newInstance(9, 0, 0, 0),
      End_Time__c = Time.newInstance(10, 0, 0, 0)
    );
    return row;
  }
  private static Slot__c slot(
    Id scheduleId,
    Datetime startTime,
    Datetime endTime,
    String status
  ) {
    Slot__c row = new Slot__c(
      Schedule__c = scheduleId,
      Start__c = startTime,
      End__c = endTime,
      Status__c = status
    );
    insert row;
    return row;
  }
  private static Datetime nine() {
    return Datetime.newInstance(MONDAY, Time.newInstance(9, 0, 0, 0));
  }
  private static ScheduleManagementController.UnavailabilityResult timeOff(
    Id existingId,
    Id providerId,
    Id scheduleId,
    Datetime startTime,
    Datetime endTime
  ) {
    return ScheduleManagementController.applyUnavailability(
      existingId,
      providerId,
      scheduleId,
      startTime,
      endTime,
      false,
      'PTO',
      true
    );
  }
}
