# Scheduling objects and sharing

LogicEMR scheduling maps to FHIR Schedule, Slot, and Appointment.

| Object           | FHIR        | Sharing                              |
| ---------------- | ----------- | ------------------------------------ |
| `Schedule__c`    | Schedule    | Public Read Only (infrastructure)    |
| `Slot__c`        | Slot        | Controlled by Parent (`Schedule__c`) |
| `Appointment__c` | Appointment | Private                              |

`Schedule__c` and `Slot__c` keep Auto Number names (`SCH-{00000000}`, `SLOT-{00000000}`). `Appointment__c` Name is Text, composed by `NameFormatterHandler` from `Name_Format.Appointment` as `{Patient__r.Name} - {Start__c}`.

## Permission sets

Access ships as permission sets only. Assign **LogicEMR Scheduler** to the scheduling desk, **LogicEMR Clinician** to clinical staff, and **LogicEMR Admin** to package administrators.

| Permission set     | Appointment                                | Schedule / Slot                   | Patient / Practitioner                      |
| ------------------ | ------------------------------------------ | --------------------------------- | ------------------------------------------- |
| LogicEMR Scheduler | CRUD + View All / Modify All               | CRUD + View All / Modify All      | Read (Patient includes View All for lookup) |
| LogicEMR Clinician | Read + Create + Edit (View All; no Delete) | Read                              | Existing clinical access                    |
| LogicEMR Admin     | Full CRUD + View All / Modify All          | Full CRUD + View All / Modify All | Existing admin access                       |

The LogicEMR Scheduling app keeps the default navigation focused on **Home**, the calendar-only **Scheduling** page, **Schedule Creator**, **Appointments**, and **Patient Search**. Raw Schedule, Slot, Patient, Practitioner, and Organization tabs remain available through Salesforce navigation when needed but are not displayed by default.

## Appointment sharing

`Appointment__c` is organization-wide default **Private**. Access is granted at **object level** via permission sets — not scoped per patient.

The scheduling desk (`LogicEMR Scheduler`) and admins can see and update every appointment. Clinicians can see the book and update appointments to arrive patients or record a no-show. Booking, rescheduling, and cancellation through the app also require Slot edit permission, which belongs to Scheduler and Admin. Clinicians who perform desk scheduling need the Scheduler permission set.

This is intentional: a scheduling desk works across the day’s book, not only the patients on a given user’s care team.

Patient-scoped appointment sharing (mirroring the care-team model used for clinical chart objects) can be added later if a client requires it. That would mean dropping object-level View All / Modify All for appointments and introducing care-team (or equivalent) Apex/sharing-set grants instead.

Slots use `writeRequiresMasterRead` so staff with read access to a Schedule can create and update its Slots without owning the Schedule record.

## Scheduling integrity

Public scheduling mutations enforce object and field permissions before changing data. Internal computed fields, including PTO placeholder provenance and notification occurrence snapshots, remain read-only to staff.

Provider and schedule locks serialize slot generation, painting, time off, and booking. Generation skips any interval overlapping an existing slot across that provider's active schedules, even after duration or hours change; touching endpoints are allowed. Booking also locks the patient and rejects overlapping active provider or patient appointments, inactive schedules/providers, and active time off.

The Appointment before trigger enforces positive active intervals and patient/provider reservation conflicts for raw Salesforce and API DML as well. New reserved appointments, changed intervals/resources, and reactivation are checked under patient/provider locks, including conflicts within a bulk transaction and appointments hidden from the caller. Slotless imports remain supported. Raw No Show is rejected before the start time, and cancellation is rejected when the current or previous linked encounter has clinical work In Progress or Finished. Status-only arrival, fulfillment, valid cancellation, and notification timestamps preserve existing workflows; legacy scheduling issues can be reconciled without blocking those transitions. Raw Slot edits, provider-PTO booking policy, and cancellation's linked-encounter status reconciliation remain controller-level behavior.

Time-off edits and removals reconcile the union of active scoped and provider-wide ranges. Overlapping time off keeps slots blocked until the final applicable range is removed, while manual blocks and Busy slots remain intact. PTO-only placeholders are deleted on release rather than becoming availability outside weekly hours. Booking releases and cancellations restore either Free or the applicable PTO block.

Appointment locks make repeated arrival return the same encounter. Cancelling a Planned or Arrived linked encounter sets it Cancelled; appointments with clinical work In Progress or Finished must be resolved through the clinical workflow. No Show is available after the appointment start time. Finished encounter fulfillment is handled by the encounter completion workflow.

## Appointment communications

Patient confirmations, reminders (email/SMS), and print slips are documented in [appointment-communications.md](appointment-communications.md).
