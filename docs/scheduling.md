# Scheduling objects and sharing

LogicEMR scheduling maps to FHIR Schedule, Slot, and Appointment.

| Object | FHIR | Sharing |
| --- | --- | --- |
| `Schedule__c` | Schedule | Public Read Only (infrastructure) |
| `Slot__c` | Slot | Controlled by Parent (`Schedule__c`) |
| `Appointment__c` | Appointment | Private |

`Schedule__c` and `Slot__c` keep Auto Number names (`SCH-{00000000}`, `SLOT-{00000000}`). `Appointment__c` Name is Text, composed by `NameFormatterHandler` from `Name_Format.Appointment` as `{Patient__r.Name} - {Start__c}`.

## Permission sets

Access ships as permission sets only. Assign **LogicEMR Scheduler** to the scheduling desk, **LogicEMR Clinician** to clinical staff, and **LogicEMR Admin** to package administrators.

| Permission set | Appointment | Schedule / Slot | Patient / Practitioner |
| --- | --- | --- | --- |
| LogicEMR Scheduler | CRUD + View All / Modify All | CRUD + View All / Modify All | Read (Patient includes View All for lookup) |
| LogicEMR Clinician | Read + Create (View All; no Edit) | Read | Existing clinical access |
| LogicEMR Admin | Full CRUD + View All / Modify All | Full CRUD + View All / Modify All | Existing admin access |

The LogicEMR app navigation groups a **Scheduling** app page (today’s and upcoming appointments, active schedules) with the `Appointment__c` and `Schedule__c` tabs.

## Appointment sharing

`Appointment__c` is organization-wide default **Private**. Access is granted at **object level** via permission sets — not scoped per patient.

The scheduling desk (`LogicEMR Scheduler`) and admins can see and update every appointment. Clinicians can see the book and create appointments; they cannot edit or delete existing ones.

This is intentional: a scheduling desk works across the day’s book, not only the patients on a given user’s care team.

Patient-scoped appointment sharing (mirroring the care-team model used for clinical chart objects) can be added later if a client requires it. That would mean dropping object-level View All / Modify All for appointments and introducing care-team (or equivalent) Apex/sharing-set grants instead.

Slots use `writeRequiresMasterRead` so staff with read access to a Schedule can create and update its Slots without owning the Schedule record.

## Appointment communications

Patient confirmations, reminders (email/SMS), and print slips are documented in [appointment-communications.md](appointment-communications.md).
