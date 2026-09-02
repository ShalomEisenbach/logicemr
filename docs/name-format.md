# Name formatting and backfill

Clinical record Names are Text values composed by `NameFormatterHandler` from active `Name_Format__mdt` rows. Before-insert and before-update triggers keep new and edited rows current.

## When to backfill

`NameBackfillBatch` recomposes Name on rows created before the Name field changed from Auto Number to Text. **Skip this batch if the org has no real clinical data yet** — empty scratch orgs and fresh installs do not need it.

## Invoke per object

Run as a user who can update the target object. The batch is `global` so subscriber orgs can enqueue it from Execute Anonymous. Default batch size is fine (`200`).

```apex
Database.executeBatch(new NameBackfillBatch('Patient__c'));
Database.executeBatch(new NameBackfillBatch('Encounter__c'));
Database.executeBatch(new NameBackfillBatch('Condition__c'));
Database.executeBatch(new NameBackfillBatch('EncounterDiagnosis__c'));
Database.executeBatch(new NameBackfillBatch('Observation__c'));
Database.executeBatch(new NameBackfillBatch('AllergyIntolerance__c'));
Database.executeBatch(new NameBackfillBatch('Immunization__c'));
Database.executeBatch(new NameBackfillBatch('MedicationRequest__c'));
Database.executeBatch(new NameBackfillBatch('MedicationStatement__c'));
Database.executeBatch(new NameBackfillBatch('MedicationAdministration__c'));
Database.executeBatch(new NameBackfillBatch('ServiceRequest__c'));
Database.executeBatch(new NameBackfillBatch('DiagnosticReport__c'));
Database.executeBatch(new NameBackfillBatch('ClinicalNote__c'));
Database.executeBatch(new NameBackfillBatch('CareTeam__c'));
Database.executeBatch(new NameBackfillBatch('CareTeamMember__c'));
Database.executeBatch(new NameBackfillBatch('Practitioner__c'));
```

Namespaced orgs may pass either `Patient__c` or `lfemr__Patient__c`. Finish logs `LogicEMR name backfill complete for {object}. updated={n}`.
