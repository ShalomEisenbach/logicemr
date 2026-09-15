# Claim readiness and superbills

LogicEMR creates a claim-ready billing snapshot from a finished encounter. This first release stops at a validated superbill; it does not submit an 837P, receive a 277CA/835, post payments, or manage denials.

## Workflow

1. The clinician advances an encounter to **Finished**.
2. `EncounterWorkspaceController` calls `ClaimReadinessController.prepareForFinishedEncounter`.
3. One `Superbill__c` is created for the encounter. `Encounter_Key__c` is a unique idempotency key.
4. Encounter diagnoses are copied to ordered `Superbill_Diagnosis__c` snapshots.
5. Completed encounter procedures are copied to `Charge_Line__c`. Billing supplies the fee and can add CPT or HCPCS lines manually.
6. Billing resolves the validation list and marks the superbill **Ready**.

The **Claim Readiness** panel is on the Encounter Workspace sidebar. The **Superbills** tab opens the claim-readiness work queue.

## Readiness checks

A superbill can move to `Ready` only when:

- the encounter is `Finished`;
- the patient has name, date of birth, sex at birth, and a complete mailing address;
- the rendering practitioner has an NPI and the default billing organization has an NPI, EIN, and address;
- active coverage has subscriber details and a member ID, and its payer has a clearinghouse payer identifier;
- at least one signed encounter note exists;
- at least one coded diagnosis exists;
- at least one CPT/HCPCS charge has a service date, positive units and amount, and valid diagnosis pointers.

Validation messages are stored on `Superbill__c.Validation_Messages__c` so the standard list and record page expose the reason a bill is held.

## Sync behavior

**Sync from encounter** refreshes patient, coverage, rendering practitioner, billing organization, date of service, diagnosis snapshots, and missing procedure-derived charges. It does not overwrite existing charge edits. Syncing or changing a charge returns a `Ready` superbill to `Needs Review`.

`Exported` and `Voided` superbills are locked by the Apex service.

## Access

`LogicEMR_Manage_Claims` gates the panel and Apex entry points. It is assigned to **LogicEMR Billing** and **LogicEMR Admin**. Billing receives read access to encounters and broad patient visibility so the controlled-by-parent superbill work queue is usable across the practice.

## Next billing increments

- Add self-pay handling and fee schedules.
- Add claim-level subscriber and provider snapshots required for outbound files.
- Add a vendor-neutral claim export interface, then an 837P adapter.
- Add acknowledgement, rejection, denial, remittance, and payment posting objects after outbound claim data is stable.
