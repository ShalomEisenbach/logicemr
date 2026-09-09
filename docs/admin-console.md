# LogicEMR Admin Console

The **Admin** tab opens a single Lightning page (`emrAdminConsole`) for package settings and admin tools. Assign **LogicEMR Admin**, which includes the custom permission `LogicEMR_Manage_Settings`. Without that permission the console component is hidden by a flexipage visibility rule, and Apex methods throw.

Clinician, Scheduler, Billing, and Mapping Admin do **not** receive the Admin Console. Mapping Admin keeps the existing Mapping Builder / Runner tabs.

## Sections

| Section | What it does |
| --- | --- |
| Overview | Health cards: Stedi / Twilio Named Credential presence, reminder and eligibility jobs, practitioners missing `User__c`, active note templates, code catalog count |
| Credentials | Read-only status and Setup instructions. **API keys are never entered here** |
| Eligibility | Edit active `Eligibility_Setting__mdt` (provider, Named Credential, service type, active) |
| Communications | Edit `Appointment_Comm_Config.Default` and the four `Appointment_Message_Template__mdt` rows |
| Note templates | CRUD on `NoteTemplate__c` via record edit form |
| Code sets | Embeds `emrCodeSetImport`; link to Code Reference home |
| Name formats | View / edit `Name_Format__mdt` format strings |
| Practitioners | Link `Practitioner__c.User__c` (paste User Id, Save) |
| Schedules | Embeds `emrScheduleManagement` |
| Mapping | Embeds `emrMappingBuilder` and `emrMappingRunner` |
| Jobs | Schedule / abort reminder and eligibility jobs; run eligibility now; enqueue name and catalog-link backfills |
| Data quality | Embeds `emrDuplicatePatients` |

## Custom metadata saves

Eligibility, communications, message templates, and name formats save through `Metadata.Operations.enqueueDeployment`. The running user needs **Customize Application**. The UI toasts that the deploy is queued; click **Refresh** on Overview after it finishes.

Do not put Stedi or Twilio secrets in Custom Metadata. Twilio Account SID and From Number are configuration, not the Auth Token.

## Credentials (still Setup)

### Stedi

1. Setup → Named Credentials → External Credentials → **Stedi Eligibility**.
2. Principal **`Stedi_API`** with parameter **`ApiKey`** = Stedi API key.
3. Grant External Credential Principal Access `Stedi_Eligibility-Stedi_API` on LogicEMR Admin, Clinician, and Billing.

See [eligibility-setup.md](eligibility-setup.md).

### Twilio

1. Create Named Credential matching `Appointment_Comm_Config.Default.Twilio_Named_Credential__c` (default `LogicEMR_Twilio`).
2. URL `https://api.twilio.com`, Password Authentication, Username = Account SID, Password = Auth Token, Generate Authorization Header enabled.
3. Enable SMS and set SID / From on the Communications section.

See [appointment-communications.md](appointment-communications.md).

## Jobs

| Job | Default | Console actions |
| --- | --- | --- |
| `LogicEMR Appointment Reminders` | Hourly (`0 0 * * * ?`) | Schedule / Abort |
| `Eligibility Re-verify` | Daily 2am (`0 0 2 * * ?`) | Schedule / Abort / Run now |
| Name backfill | On demand | Pick object → enqueue `NameBackfillBatch` |
| Catalog link backfill | On demand | Pick coded object → enqueue `CatalogLinkBackfillBatch` |

Skip name and catalog backfills on empty orgs. See [name-format.md](name-format.md) and [reporting.md](reporting.md).

## Related

- Apex: `AdminConsoleController`, `AdminConsoleDeployCallback`
- Tab / page: `LogicEMR_Admin`
- Permission: `LogicEMR_Manage_Settings` on LogicEMR Admin
