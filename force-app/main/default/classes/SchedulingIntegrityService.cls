public with sharing class SchedulingIntegrityService {
  private static final Set<String> RESERVED_STATUSES = new Set<String>{
    'Proposed',
    'Booked',
    'Arrived'
  };

  public static void beforeAppointments(
    List<Appointment__c> records,
    Map<Id, Appointment__c> oldMap
  ) {
    new ReservationIntegrity().validate(records, oldMap);
  }

  public static Boolean intervalsOverlap(
    Datetime leftStart,
    Datetime leftEnd,
    Datetime rightStart,
    Datetime rightEnd
  ) {
    return leftStart != null &&
      leftEnd != null &&
      rightStart != null &&
      rightEnd != null &&
      leftStart < rightEnd &&
      leftEnd > rightStart;
  }

  // These checks must include reservations hidden from the caller. Only generic row
  // errors leave this internal reader; no other appointment or patient data is exposed.
  private without sharing class ReservationIntegrity {
    public void validate(
      List<Appointment__c> records,
      Map<Id, Appointment__c> oldMap
    ) {
      if (records == null || records.isEmpty())
        return;
      validateStatusTransitions(records, oldMap);
      Set<Integer> candidates = new Set<Integer>();
      Set<Id> patientIds = new Set<Id>();
      Set<Id> providerIds = new Set<Id>();
      Set<Id> updatedIds = new Set<Id>();
      Datetime earliest;
      Datetime latest;
      for (Integer index = 0; index < records.size(); index++) {
        Appointment__c row = records[index];
        if (row.Id != null)
          updatedIds.add(row.Id);
        Appointment__c prior = oldMap == null ? null : oldMap.get(row.Id);
        Boolean intervalChanged =
          prior == null ||
          row.Start__c != prior.Start__c ||
          row.End__c != prior.End__c;
        Boolean resourceChanged =
          prior == null ||
          row.Patient__c != prior.Patient__c ||
          row.Practitioner__c != prior.Practitioner__c;
        Boolean newlyReserved =
          RESERVED_STATUSES.contains(row.Status__c) &&
          (prior == null || !RESERVED_STATUSES.contains(prior.Status__c));
        // Status-only arrival, completion, cancellation and notification stamping must
        // continue to work even on legacy records that need scheduling reconciliation.
        if (!intervalChanged && !resourceChanged && !newlyReserved)
          continue;
        Boolean reserved = RESERVED_STATUSES.contains(row.Status__c);
        if (
          (row.Start__c == null) != (row.End__c == null) ||
          (row.Start__c != null &&
          row.End__c <= row.Start__c) ||
          (reserved && row.Start__c == null)
        ) {
          row.addError(
            'Appointment start and end must define a positive time interval.'
          );
          continue;
        }
        if (!reserved || row.hasErrors())
          continue;
        candidates.add(index);
        patientIds.add(row.Patient__c);
        providerIds.add(row.Practitioner__c);
        if (prior != null) {
          patientIds.add(prior.Patient__c);
          providerIds.add(prior.Practitioner__c);
        }
        if (earliest == null || row.Start__c < earliest)
          earliest = row.Start__c;
        if (latest == null || row.End__c > latest)
          latest = row.End__c;
      }
      if (candidates.isEmpty())
        return;
      patientIds.remove(null);
      providerIds.remove(null);
      // Same resource lock order as controller booking: patient, then provider.
      if (!patientIds.isEmpty()) {
        List<Patient__c> patients = [
          SELECT Id
          FROM Patient__c
          WHERE Id IN :patientIds
          FOR UPDATE
        ];
      }
      if (!providerIds.isEmpty()) {
        List<Practitioner__c> providers = [
          SELECT Id
          FROM Practitioner__c
          WHERE Id IN :providerIds
          FOR UPDATE
        ];
      }
      List<Appointment__c> existing = [
        SELECT Id, Patient__c, Practitioner__c, Start__c, End__c, Status__c
        FROM Appointment__c
        WHERE
          Id NOT IN :updatedIds
          AND Status__c IN :RESERVED_STATUSES
          AND Start__c < :latest
          AND End__c > :earliest
          AND (Patient__c IN :patientIds
          OR Practitioner__c IN :providerIds)
      ];
      Boolean newErrors = true;
      while (newErrors) {
        newErrors = false;
        for (Integer index : candidates) {
          Appointment__c candidate = records[index];
          if (candidate.hasErrors())
            continue;
          Boolean conflict = false;
          for (Appointment__c stored : existing) {
            if (collides(candidate, stored)) {
              conflict = true;
              break;
            }
          }
          if (!conflict) {
            for (
              Integer peerIndex = 0; peerIndex < records.size(); peerIndex++
            ) {
              if (peerIndex == index)
                continue;
              Appointment__c peer = records[peerIndex];
              // A failed bulk update retains its original reservation. Iterate until
              // no newly rejected move can invalidate an otherwise accepted move.
              if (peer.hasErrors())
                peer = oldMap == null ? null : oldMap.get(peer.Id);
              if (peer == null || !RESERVED_STATUSES.contains(peer.Status__c))
                continue;
              if (collides(candidate, peer)) {
                conflict = true;
                if (
                  candidates.contains(peerIndex) &&
                  !records[peerIndex].hasErrors()
                ) {
                  records[peerIndex]
                    .addError(
                      'The provider or patient already has an overlapping appointment.'
                    );
                }
                break;
              }
            }
          }
          if (conflict) {
            candidate.addError(
              'The provider or patient already has an overlapping appointment.'
            );
            newErrors = true;
          }
        }
      }
    }

    private Boolean collides(Appointment__c left, Appointment__c right) {
      Boolean samePatient =
        left.Patient__c != null &&
        left.Patient__c == right.Patient__c;
      Boolean sameProvider =
        left.Practitioner__c != null &&
        left.Practitioner__c == right.Practitioner__c;
      return (samePatient || sameProvider) &&
        intervalsOverlap(
          left.Start__c,
          left.End__c,
          right.Start__c,
          right.End__c
        );
    }

    private void validateStatusTransitions(
      List<Appointment__c> records,
      Map<Id, Appointment__c> oldMap
    ) {
      Datetime nowValue = Datetime.now();
      Set<Id> encounterIds = new Set<Id>();
      for (Appointment__c row : records) {
        if (
          row.Status__c == 'No Show' &&
          (row.Start__c == null ||
          row.Start__c > nowValue)
        ) {
          row.addError(
            'A no-show can be recorded after the appointment start time.'
          );
        }
        Appointment__c prior = oldMap == null ? null : oldMap.get(row.Id);
        if (
          row.Status__c == 'Cancelled' &&
          (prior == null ||
          prior.Status__c != 'Cancelled')
        ) {
          encounterIds.add(row.Encounter__c);
          if (prior != null)
            encounterIds.add(prior.Encounter__c);
        }
      }
      encounterIds.remove(null);
      if (encounterIds.isEmpty())
        return;
      Map<Id, Encounter__c> encounters = new Map<Id, Encounter__c>(
        [
          SELECT Id, Status__c
          FROM Encounter__c
          WHERE Id IN :encounterIds
          FOR UPDATE
        ]
      );
      for (Appointment__c row : records) {
        Appointment__c prior = oldMap == null ? null : oldMap.get(row.Id);
        if (
          row.Status__c != 'Cancelled' ||
          (prior != null &&
          prior.Status__c == 'Cancelled')
        )
          continue;
        Encounter__c linked = encounters.get(row.Encounter__c);
        Encounter__c previous = prior == null
          ? null
          : encounters.get(prior.Encounter__c);
        if (hasClinicalWork(linked) || hasClinicalWork(previous)) {
          row.addError(
            'Clinical work has started. Resolve the encounter before cancelling this appointment.'
          );
        }
      }
    }

    private Boolean hasClinicalWork(Encounter__c encounter) {
      return encounter != null &&
        (encounter.Status__c == 'In Progress' ||
        encounter.Status__c == 'Finished');
    }
  }

  public static void requireWrite(
    Schema.SObjectType objectType,
    Boolean creating,
    List<Schema.SObjectField> fields
  ) {
    Schema.DescribeSObjectResult objectAccess = objectType.getDescribe();
    if (
      !objectAccess.isAccessible() ||
      (creating ? !objectAccess.isCreateable() : !objectAccess.isUpdateable())
    ) {
      throw error(
        'You do not have permission to ' +
          (creating ? 'create ' : 'update ') +
          objectAccess.getLabel() +
          ' records.'
      );
    }
    for (Schema.SObjectField field : fields) {
      Schema.DescribeFieldResult fieldAccess = field.getDescribe();
      if (
        creating ? !fieldAccess.isCreateable() : !fieldAccess.isUpdateable()
      ) {
        throw error(
          'You do not have permission to change ' +
            objectAccess.getLabel() +
            '.' +
            fieldAccess.getLabel() +
            '.'
        );
      }
    }
  }

  public static void requireDelete(Schema.SObjectType objectType) {
    if (!objectType.getDescribe().isDeletable()) {
      throw error(
        'You do not have permission to delete ' +
          objectType.getDescribe().getLabel() +
          ' records.'
      );
    }
  }

  public static void requireBookingAccess() {
    requireWrite(
      Appointment__c.SObjectType,
      true,
      new List<Schema.SObjectField>{
        Appointment__c.Patient__c,
        Appointment__c.Practitioner__c,
        Appointment__c.Slot__c,
        Appointment__c.Start__c,
        Appointment__c.End__c,
        Appointment__c.Location_Name__c,
        Appointment__c.Appointment_Type__c,
        Appointment__c.Reason__c,
        Appointment__c.Status__c
      }
    );
    requireWrite(
      Slot__c.SObjectType,
      false,
      new List<Schema.SObjectField>{ Slot__c.Status__c }
    );
    if (
      !Patient__c.SObjectType.getDescribe().isAccessible() ||
      !Practitioner__c.SObjectType.getDescribe().isAccessible()
    ) {
      throw error(
        'You do not have permission to access patient or provider scheduling records.'
      );
    }
  }

  public static void lockPractitioners(Set<Id> practitionerIds) {
    Set<Id> required = new Set<Id>(practitionerIds);
    required.remove(null);
    if (required.isEmpty()) {
      return;
    }
    List<Practitioner__c> locked = [
      SELECT Id
      FROM Practitioner__c
      WHERE Id IN :required
      FOR UPDATE
    ];
    if (locked.size() != required.size()) {
      throw error('Provider was not found.');
    }
  }

  public static void lockSlotProviders(Set<Id> slotIds) {
    Set<Id> practitionerIds = new Set<Id>();
    for (Slot__c slot : [
      SELECT Schedule__r.Practitioner__c
      FROM Slot__c
      WHERE Id IN :slotIds
    ]) {
      practitionerIds.add(slot.Schedule__r.Practitioner__c);
    }
    lockPractitioners(practitionerIds);
  }

  public static void lockPatient(Id patientId) {
    List<Patient__c> locked = [
      SELECT Id
      FROM Patient__c
      WHERE Id = :patientId
      FOR UPDATE
    ];
    if (locked.isEmpty()) {
      throw error('Patient was not found.');
    }
  }

  public static Schedule__c lockSchedule(Id scheduleId) {
    List<Schedule__c> original = [
      SELECT Id, Practitioner__c
      FROM Schedule__c
      WHERE Id = :scheduleId
    ];
    if (original.isEmpty()) {
      throw error('Schedule was not found.');
    }
    lockPractitioners(new Set<Id>{ original[0].Practitioner__c });
    List<Schedule__c> locked = [
      SELECT Id, Practitioner__c, Active__c
      FROM Schedule__c
      WHERE Id = :scheduleId
      FOR UPDATE
    ];
    if (
      locked.isEmpty() ||
      locked[0].Practitioner__c != original[0].Practitioner__c
    ) {
      throw error('The schedule changed. Refresh and try again.');
    }
    return locked[0];
  }

  public static void validateBooking(
    Slot__c slot,
    Id patientId,
    Id excludedAppointmentId
  ) {
    if (
      slot.Start__c == null ||
      slot.End__c == null ||
      slot.End__c <= slot.Start__c
    ) {
      throw error('This slot has an invalid time range.');
    }
    List<Schedule__c> schedules = [
      SELECT Id, Active__c, Practitioner__c, Practitioner__r.Active__c
      FROM Schedule__c
      WHERE Id = :slot.Schedule__c
    ];
    if (
      schedules.isEmpty() ||
      schedules[0].Active__c != true ||
      schedules[0].Practitioner__r.Active__c != true
    ) {
      throw error('This provider or schedule is no longer active.');
    }
    Id practitionerId = schedules[0].Practitioner__c;
    if (
      blockingUnavailability(
        practitionerId,
        slot.Schedule__c,
        slot.Start__c,
        slot.End__c
      ) != null
    ) {
      throw error('This provider is unavailable during the selected time.');
    }
    if (
      [
        SELECT COUNT()
        FROM Appointment__c
        WHERE
          Id != :excludedAppointmentId
          AND Status__c IN :RESERVED_STATUSES
          AND Start__c < :slot.End__c
          AND End__c > :slot.Start__c
          AND (Practitioner__c = :practitionerId
          OR Patient__c = :patientId)
      ] > 0
    ) {
      throw error(
        'The provider or patient already has an overlapping appointment. Choose another time.'
      );
    }
  }

  public static void releaseSlot(Slot__c slot, Id excludedAppointmentId) {
    if (
      [
        SELECT COUNT()
        FROM Appointment__c
        WHERE
          Slot__c = :slot.Id
          AND Id != :excludedAppointmentId
          AND Status__c != 'Cancelled'
      ] > 0
    ) {
      slot.Status__c = 'Busy';
      return;
    }
    Schedule_Unavailability__c block = blockingUnavailability(
      slot.Schedule__r.Practitioner__c,
      slot.Schedule__c,
      slot.Start__c,
      slot.End__c
    );
    slot.Status__c = block == null ? 'Free' : 'Blocked';
    slot.Unavailability__c = block == null ? null : block.Id;
    slot.Block_Reason__c = block == null ? null : block.Reason__c;
  }

  public static Schedule_Unavailability__c blockingUnavailability(
    Id practitionerId,
    Id scheduleId,
    Datetime startTime,
    Datetime endTime
  ) {
    List<Schedule_Unavailability__c> rows = [
      SELECT Id, Reason__c
      FROM Schedule_Unavailability__c
      WHERE
        Practitioner__c = :practitionerId
        AND Active__c = TRUE
        AND (Schedule__c = NULL
        OR Schedule__c = :scheduleId)
        AND Start__c < :endTime
        AND End__c > :startTime
      ORDER BY CreatedDate, Id
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  private static AuraHandledException error(String message) {
    AuraHandledException result = new AuraHandledException(message);
    result.setMessage(message);
    return result;
  }
}
