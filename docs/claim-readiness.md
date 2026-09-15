# Claim readiness and superbills

LogicEMR creates a claim-ready billing snapshot from a finished encounter. This first release stops at a validated superbill; it does not submit an 837P, receive a 277CA/835, post payments, or manage denials.

## Workflow

1. The clinician advances an encounter to **Finished**.
2. `EncounterWorkspaceController` calls `ClaimReadinessController.prepareForFinishedEncounter`.
3. One `Superbill__c` is created for the encounter. `Encounter_Key__c` is a unique idempotency key.
4. Encounter diagnoses are copied to ordered `Superbill_Diagnosis__c` snapshots.
5. Completed encounter procedures are copied to `Charge_Line__c` and priced from the fee schedule effective on the service date. Billing can also add CPT or HCPCS lines manually; those lines use the same pricing service.
6. Claim-level patient, subscriber, payer, rendering-provider, and billing-provider values are copied onto the superbill with a refresh timestamp and revision number.
7. Billing resolves the validation list and marks the superbill **Ready**.

The **Claim Readiness** panel is on the Encounter Workspace sidebar. The **Superbills** tab opens the claim-readiness work queue.

## Readiness checks

A superbill can move to `Ready` only when:

- the encounter is `Finished`;
- the patient snapshot has name, date of birth, sex at birth, and a complete mailing address;
- the rendering provider snapshot has a name, 10-digit NPI, and 10-character taxonomy code;
- the billing provider snapshot has a name, 10-digit NPI, 9-digit EIN, taxonomy code, and complete address;
- the subscriber snapshot has structured name, date of birth, sex, address, relationship, and member ID, and its payer snapshot has a name and clearinghouse payer identifier;
- at least one signed encounter note exists;
- at least one coded diagnosis exists;
- at least one CPT/HCPCS charge has a service date, positive units and amount, a current payer/self-pay rate source (or an authorized override with a reason), and valid diagnosis pointers.

Validation messages are stored on `Superbill__c.Validation_Messages__c` so the standard list and record page expose the reason a bill is held.

## Sync behavior

**Sync from encounter** refreshes patient, coverage, rendering practitioner, billing organization, date of service, claim-party snapshots, diagnosis snapshots, and procedure-derived charges. Non-overridden procedure charges are repriced from the currently applicable effective-dated rate. Authorized overrides are preserved.

**Refresh snapshots** replaces only the claim-level patient, subscriber, payer, and provider values with the current source-record values after an explicit confirmation. For self coverage, subscriber demographics come from the patient. For spouse, child, or other coverage, structured subscriber demographics come from the coverage record; the legacy Subscriber Name is used only as a name fallback. Each refresh advances `Snapshot_Version__c` and records `Snapshot_Refreshed_At__c`.

`Ready`, `Exported`, and `Voided` snapshots are frozen. A Ready claim must be explicitly reopened before source values, charges, or snapshots can be resynchronized. Reopening does not itself change the captured values.

## Fee schedules

`Fee_Schedule__c` is either payer-specific or self-pay. Active schedules are evaluated by ascending priority, then by the most recent rate effective date. `Fee_Schedule_Rate__c` stores an active, effective-dated CPT/HCPCS unit rate. A coverage payer whose type is `Self-Pay` (or a pricing context with no payer) uses the active self-pay schedule; other coverage uses schedules for its payer.

The selected rate, applied unit rate, effective-period label, and calculated line amount are snapshotted on `Charge_Line__c`. Line amount is `unit rate × units`. If a matching code only has a past effective period, Claim Readiness reports an expired rate; if no matching rate exists, it reports a missing rate.

Overrides require `LogicEMR_Override_Charge_Rates` and a nonblank reason. The supplemental **LogicEMR Charge Rate Override** permission set grants that permission to approved billing users; LogicEMR Admin includes it. The Apex service and charge-line trigger both enforce the control.

Demo fee schedules, effective-dated rates, and superbills can be loaded after the other clinical seeds with:

```text
sf apex run --file scripts/apex/seedFeeSchedulesAndSuperbills.apex
```

The script is safe to rerun. It refreshes four representative unlocked superbills through the production claim-preparation service so diagnosis and charge-rate snapshots stay representative of application behavior.

`Exported` and `Voided` superbills are permanently locked by the Apex service.

## Canonical claim export

`ClaimExportService` maps a frozen `Ready` or `Exported` superbill into the versioned `VendorNeutralClaim` contract. Schema version 1.0 contains:

- frozen patient, subscriber, payer, rendering-provider, and billing-provider parties;
- ordered diagnosis snapshots;
- ordered professional service lines with modifiers and numeric diagnosis pointers;
- snapshotted unit rate, rate source, override indicator, and override reason;
- claim identifiers, dates, currency, total charge, and snapshot revision metadata.

The export queries claim snapshot fields and billing child snapshots only; it does not read current patient demographics, coverage details, payer identifiers, or provider records. It also performs a final structural validation and refuses claims still in review or malformed frozen lines.

Ready claims expose **Preview canonical export** in Claim Readiness. `ClaimExportController.getCanonicalJson` returns pretty-printed canonical JSON behind `LogicEMR_Manage_Claims`. It does not change claim status or create a submission; the future clearinghouse adapter owns those side effects.

## Access

`LogicEMR_Manage_Claims` gates the panel and Apex entry points. It is assigned to **LogicEMR Billing** and **LogicEMR Admin**. Billing receives read access to encounters and broad patient visibility so the controlled-by-parent superbill work queue is usable across the practice.

## Next billing increments

- Add an 837P adapter that consumes `VendorNeutralClaim` and owns transmission lifecycle records.
- Add acknowledgement, rejection, denial, remittance, and payment posting objects after outbound claim data is stable.
