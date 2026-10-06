@IsTest
private class AppointmentIntegrityTriggerTest {
  @IsTest
  static void directImportsRejectPatientAndProviderOverlapWithoutSlots() {
    AppointmentCommunicationHandler.bypass = true;
    Patient__c firstPatient = patient('FIRST');
    Patient__c secondPatient = patient('SECOND');
    Practitioner__c firstProvider = provider();
    Practitioner__c secondProvider = provider();
    insert appointment(firstPatient.Id, firstProvider.Id, nine(), 'Booked');
    Database.SaveResult providerConflict = Database.insert(
      appointment(
        secondPatient.Id,
        firstProvider.Id,
        nine().addMinutes(10),
        'Booked'
      ),
      false
    );
    Database.SaveResult patientConflict = Database.insert(
      appointment(
        firstPatient.Id,
        secondProvider.Id,
        nine().addMinutes(10),
        'Proposed'
      ),
      false
    );
    System.assertEquals(
      false,
      providerConflict.isSuccess(),
      'Standard DML cannot double-book the provider'
    );
    System.assertEquals(
      false,
      patientConflict.isSuccess(),
      'Standard DML cannot double-book the patient'
    );
    System.assert(
      providerConflict.getErrors()[0]
        .getMessage()
        .contains('overlapping appointment')
    );
    Appointment__c adjacent = appointment(
      firstPatient.Id,
      firstProvider.Id,
      nine().addMinutes(20),
      'Booked'
    );
    adjacent.Source_System_Id__c = 'valid-import-without-slot';
    insert adjacent;
    System.assertEquals(
      2,
      [SELECT COUNT() FROM Appointment__c],
      'A valid slotless import and touching endpoint remain supported'
    );
  }

  @IsTest
  static void bulkInsertRejectsInternalConflictsAndKeepsIndependentRows() {
    AppointmentCommunicationHandler.bypass = true;
    Patient__c firstPatient = patient('BULK-FIRST');
    Patient__c secondPatient = patient('BULK-SECOND');
    Patient__c thirdPatient = patient('BULK-THIRD');
    Practitioner__c firstProvider = provider();
    Practitioner__c secondProvider = provider();
    List<Database.SaveResult> results = Database.insert(
      new List<Appointment__c>{
        appointment(firstPatient.Id, firstProvider.Id, nine(), 'Booked'),
        appointment(
          secondPatient.Id,
          firstProvider.Id,
          nine().addMinutes(10),
          'Booked'
        ),
        appointment(thirdPatient.Id, secondProvider.Id, nine(), 'Booked')
      },
      false
    );
    System.assertEquals(false, results[0].isSuccess());
    System.assertEquals(
      false,
      results[1].isSuccess(),
      'Conflicts in the same insert batch cannot bypass the database query'
    );
    System.assertEquals(
      true,
      results[2].isSuccess(),
      'An independent row succeeds with partial-save DML'
    );
    System.assertEquals(1, [SELECT COUNT() FROM Appointment__c]);
  }

  @IsTest
  static void intervalEditsAndReactivationValidateButArrivalDoesNotChangeReservation() {
    AppointmentCommunicationHandler.bypass = true;
    Patient__c patient = patient('UPDATE');
    Practitioner__c provider = provider();
    Appointment__c booked = appointment(
      patient.Id,
      provider.Id,
      nine(),
      'Booked'
    );
    Appointment__c other = appointment(
      patient.Id,
      provider.Id,
      nine().addHours(1),
      'Booked'
    );
    Appointment__c cancelled = appointment(
      patient.Id,
      provider.Id,
      nine().addMinutes(10),
      'Cancelled'
    );
    insert new List<Appointment__c>{ booked, other, cancelled };
    Database.SaveResult invalid = Database.update(
      new Appointment__c(Id = other.Id, End__c = other.Start__c),
      false
    );
    System.assertEquals(
      false,
      invalid.isSuccess(),
      'Zero and negative duration edits must fail'
    );
    Database.SaveResult overlap = Database.update(
      new Appointment__c(
        Id = other.Id,
        Start__c = nine().addMinutes(10),
        End__c = nine().addMinutes(30)
      ),
      false
    );
    System.assertEquals(false, overlap.isSuccess());
    Database.SaveResult reactivation = Database.update(
      new Appointment__c(Id = cancelled.Id, Status__c = 'Booked'),
      false
    );
    System.assertEquals(
      false,
      reactivation.isSuccess(),
      'A cancelled interval must be checked when it becomes reserved again'
    );
    update new Appointment__c(Id = booked.Id, Status__c = 'Arrived');
    update new Appointment__c(
      Id = booked.Id,
      Confirmation_Sent_At__c = Datetime.now()
    );
    update new Appointment__c(Id = booked.Id, Status__c = 'Fulfilled');
    System.assertEquals(
      'Fulfilled',
      [SELECT Status__c FROM Appointment__c WHERE Id = :booked.Id].Status__c,
      'Arrival, timestamp stamping and terminal status-only updates preserve their workflow'
    );
    System.assertEquals(
      other.Start__c,
      [SELECT Start__c FROM Appointment__c WHERE Id = :other.Id].Start__c
    );
  }

  @IsTest
  static void bulkRescheduleUsesFinalIntervalsAndProtectsFailedMoveOriginalReservation() {
    AppointmentCommunicationHandler.bypass = true;
    Patient__c patient = patient('SWAP');
    Practitioner__c provider = provider();
    Appointment__c first = appointment(
      patient.Id,
      provider.Id,
      nine(),
      'Booked'
    );
    Appointment__c second = appointment(
      patient.Id,
      provider.Id,
      nine().addMinutes(20),
      'Booked'
    );
    Appointment__c occupied = appointment(
      patient.Id,
      provider.Id,
      nine().addHours(1),
      'Booked'
    );
    insert new List<Appointment__c>{ first, second, occupied };
    first.Start__c = nine().addMinutes(20);
    first.End__c = nine().addMinutes(40);
    second.Start__c = nine();
    second.End__c = nine().addMinutes(20);
    update new List<Appointment__c>{ first, second };
    System.assertEquals(
      nine(),
      [SELECT Start__c FROM Appointment__c WHERE Id = :second.Id].Start__c,
      'A valid simultaneous interval swap uses the final batch state'
    );
    List<Database.SaveResult> results = Database.update(
      new List<Appointment__c>{
        new Appointment__c(
          Id = first.Id,
          Start__c = nine(),
          End__c = nine().addMinutes(20)
        ),
        new Appointment__c(
          Id = second.Id,
          Start__c = nine().addHours(1),
          End__c = nine().addHours(1).addMinutes(20)
        )
      },
      false
    );
    System.assertEquals(
      false,
      results[0].isSuccess(),
      'A move cannot use an interval retained by another failed move'
    );
    System.assertEquals(false, results[1].isSuccess());
    System.assertEquals(
      nine().addMinutes(20),
      [SELECT Start__c FROM Appointment__c WHERE Id = :first.Id].Start__c
    );
    System.assertEquals(
      nine(),
      [SELECT Start__c FROM Appointment__c WHERE Id = :second.Id].Start__c
    );
  }

  @IsTest
  static void activeAppointmentRequiresPositiveInterval() {
    AppointmentCommunicationHandler.bypass = true;
    Patient__c patient = patient('DURATION');
    Practitioner__c provider = provider();
    Appointment__c missingEnd = appointment(
      patient.Id,
      provider.Id,
      nine(),
      'Booked'
    );
    missingEnd.End__c = null;
    Appointment__c backwards = appointment(
      patient.Id,
      provider.Id,
      nine(),
      'Booked'
    );
    backwards.End__c = nine().addMinutes(-1);
    List<Database.SaveResult> results = Database.insert(
      new List<Appointment__c>{ missingEnd, backwards },
      false
    );
    System.assertEquals(false, results[0].isSuccess());
    System.assertEquals(false, results[1].isSuccess());
    System.assert(
      results[0].getErrors()[0].getMessage().contains('positive time interval')
    );
    System.assertEquals(0, [SELECT COUNT() FROM Appointment__c]);
  }

  @IsTest
  static void rawNoShowRejectsFutureAppointment() {
    AppointmentCommunicationHandler.bypass = true;
    Patient__c patient = patient('NO-SHOW');
    Practitioner__c provider = provider();
    Datetime future = Datetime.now().addDays(1);
    Appointment__c booked = appointment(
      patient.Id,
      provider.Id,
      future,
      'Booked'
    );
    insert booked;
    Database.SaveResult updateResult = Database.update(
      new Appointment__c(Id = booked.Id, Status__c = 'No Show'),
      false
    );
    Database.SaveResult insertResult = Database.insert(
      appointment(patient.Id, provider.Id, future.addHours(1), 'No Show'),
      false
    );
    System.assertEquals(false, updateResult.isSuccess());
    System.assertEquals(
      false,
      insertResult.isSuccess(),
      'API imports cannot record a future no-show'
    );
    System.assertEquals(
      'Booked',
      [SELECT Status__c FROM Appointment__c WHERE Id = :booked.Id].Status__c
    );
  }

  @IsTest
  static void rawCancellationCannotDetachAnEncounterWithClinicalWork() {
    AppointmentCommunicationHandler.bypass = true;
    Patient__c patient = patient('CANCEL');
    Practitioner__c provider = provider();
    Encounter__c encounter = new Encounter__c(
      Patient__c = patient.Id,
      Practitioner__c = provider.Id,
      Start__c = nine(),
      Status__c = 'In Progress',
      Class__c = 'Outpatient'
    );
    insert encounter;
    Appointment__c arrived = appointment(
      patient.Id,
      provider.Id,
      nine(),
      'Arrived'
    );
    arrived.Encounter__c = encounter.Id;
    insert arrived;
    Database.SaveResult result = Database.update(
      new Appointment__c(
        Id = arrived.Id,
        Status__c = 'Cancelled',
        Encounter__c = null
      ),
      false
    );
    System.assertEquals(
      false,
      result.isSuccess(),
      'Clearing the encounter lookup cannot bypass the clinical-start cancellation guard'
    );
    System.assert(
      result.getErrors()[0].getMessage().contains('Clinical work has started')
    );
    Appointment__c saved = [
      SELECT Status__c, Encounter__c
      FROM Appointment__c
      WHERE Id = :arrived.Id
    ];
    System.assertEquals('Arrived', saved.Status__c);
    System.assertEquals(encounter.Id, saved.Encounter__c);
  }

  private static Appointment__c appointment(
    Id patientId,
    Id providerId,
    Datetime startTime,
    String status
  ) {
    return new Appointment__c(
      Patient__c = patientId,
      Practitioner__c = providerId,
      Start__c = startTime,
      End__c = startTime.addMinutes(20),
      Status__c = status,
      Appointment_Type__c = 'Routine'
    );
  }
  private static Patient__c patient(String suffix) {
    Patient__c row = new Patient__c(
      MRN__c = 'MRN-RAW-APPOINTMENT-' + suffix,
      Last_Name__c = suffix
    );
    insert row;
    return row;
  }
  private static Practitioner__c provider() {
    Practitioner__c row = new Practitioner__c(
      Last_Name__c = 'Import Provider',
      Active__c = true
    );
    insert row;
    return row;
  }
  private static Datetime nine() {
    return Datetime.newInstance(2026, 9, 7, 9, 0, 0);
  }
}
