# Appointment confirmations, reminders, and printouts

LogicEMR sends one-way appointment notifications to patients by email and optional SMS, and supports staff print slips. There is no patient self-confirm / cancel link.

## Patient contact fields

| Field                      | Purpose                                           |
| -------------------------- | ------------------------------------------------- |
| `Patient__c.Email__c`      | Email destination for confirmations and reminders |
| `Patient__c.Phone__c`      | SMS destination                                   |
| `Patient__c.SMS_Opt_In__c` | Required (checked) before SMS is sent (TCPA)      |

Do not rely on the optional `Contact__c` lookup for messaging.

## Configuration (`Appointment_Comm_Config__mdt`)

Ship record **Default**:

| Field                        | Default           | Notes                                                     |
| ---------------------------- | ----------------- | --------------------------------------------------------- |
| `Email_Enabled__c`           | true              | Salesforce `Messaging.sendEmail`                          |
| `SMS_Enabled__c`             | false             | Enable after Twilio Named Credential is set up            |
| `Auto_Send_Confirmation__c`  | true              | On Booked insert and reschedule                           |
| `Auto_Send_Reminder__c`      | true              | Hourly batch                                              |
| `Reminder_Hours_Before__c`   | 24                | Booked appointments with `Start__c` in `(now, now+hours]` |
| `Twilio_Named_Credential__c` | `LogicEMR_Twilio` | Subscriber creates this Named Credential                  |
| `Twilio_Account_Sid__c`      | (blank)           | Twilio Account SID                                        |
| `Twilio_From_Number__c`      | (blank)           | E.164 Twilio number                                       |
| `Org_Wide_Email_Address__c`  | (blank)           | Optional From address; otherwise running user             |

## Message templates (`Appointment_Message_Template__mdt`)

Four packaged templates: Confirmation/Reminder × Email/SMS. Merge tokens:

`{Patient_Name}`, `{First_Name}`, `{Start}`, `{End}`, `{Location}`, `{Practitioner}`, `{Appointment_Type}`, `{Reason}`

## Twilio Named Credential (subscriber setup)

1. In Setup, create a **Named Credential** named `LogicEMR_Twilio` (or match `Twilio_Named_Credential__c`).
2. URL: `https://api.twilio.com`
3. Identity Type: Named Principal; Authentication Protocol: Password Authentication
4. Username = Twilio Account SID; Password = Twilio Auth Token
5. Generate Authorization Header = enabled
6. Set `Appointment_Comm_Config.Default` fields: `SMS_Enabled__c = true`, `Twilio_Account_Sid__c`, `Twilio_From_Number__c`
7. Ensure patients have `Phone__c` and `SMS_Opt_In__c = true`

Callout path used by the package:

`POST callout:{NamedCredential}/2010-04-01/Accounts/{Sid}/Messages.json`

## Scheduling the reminder job

Use the invocable **Schedule Appointment Reminders** (category LogicEMR) from a Flow, or Apex:

```apex
AppointmentReminderInvocable.scheduleReminders(
    new List<AppointmentReminderInvocable.Request>{ new AppointmentReminderInvocable.Request() }
);
```

Default cron is hourly at minute 0: `0 0 * * * ?`. Job name: `LogicEMR Appointment Reminders`.

## Automation behavior

- **Book / become Booked:** `AppointmentTrigger` → `AppointmentConfirmationQueueable` → email (+ SMS if configured)
- **Reschedule (Start change):** clears `Confirmation_Sent_At__c` and `Reminder_Sent_At__c`, then re-sends confirmation
- **Reminder batch:** Booked appointments starting inside the configured window. Channel history decides which channels still need an attempt; a successful email does not suppress a failed SMS retry.
- **Manual:** calendar popover and patient chart appointment panel → Send Confirmation / Send Reminder / Print
- Logs land on `Appointment_Communication__c` (Email / SMS / Print; Queued / Sent / Failed / Skipped). `Appointment_Start__c` snapshots the appointment occurrence so old notifications cannot suppress a rescheduled visit.

SMS is initially **Queued**, with no sent timestamp. After Twilio accepts the request, the worker marks the log Sent and stamps the appointment only if its start time still matches. Sent means accepted by the configured messaging provider; it does not assert delivery to the patient's device. Failed and Skipped attempts have no sent timestamp. The worker checks current SMS consent, phone, appointment status, and start time immediately before the callout; revoked consent or stale jobs are skipped.

Each automatic channel stops after success or three failed attempts for the current appointment occurrence. Pending SMS blocks duplicate automatic and manual enqueues. The hourly reminder batch retries failures within its reminder window, including appointments already stamped by another successful channel. Manual sends can explicitly retry after the automatic limit or resend a successful channel. Worker batches contain at most 50 callouts and chain the remainder.

Legacy notification stamps without usable channel history remain deduplicated. Legacy logs written around a premature appointment stamp are recognized so an old failed SMS can recover without resending its successful email. Manual send and print logging require communication creation permission; sends also require appointment update permission. Automated workers use their internal processing context.

## Print

LWC `emrAppointmentPrint` renders a slip and calls `window.print()`, then logs a Print channel communication. Exposed on Appointment record pages and via calendar/panel modals.

## Related

See also [scheduling.md](scheduling.md) for the Schedule → Slot → Appointment model and permission sets.
