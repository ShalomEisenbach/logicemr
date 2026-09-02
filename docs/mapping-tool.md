# Data Mapping Tool

Admin-configured field mapping from any queryable source object into `lfemr__Patient__c`. No Apex is required to add or change a mapping. The package namespace is `lfemr`.

Assign **LogicEMR Mapping Admin** to the people who configure and run mappings. That permission set grants the LogicEMR app, the Data Mapping tabs, CRUD on the three mapping objects, and Apex access to the engine, invocable, batch, and LWC controllers.

To preview or commit Patients, the running user also needs object and field access on the source object (for example Contact) and on `Patient__c`. Assign **LogicEMR Admin** (or another Patient-capable permission set) in addition to Mapping Admin when the same user will execute mappings.

## Model

Three custom objects store configuration. Runtime reads them; it does not generate metadata.

### `Mapping_Definition__c`

One definition is one source object → Patient pipeline.

| Field | Purpose |
|---|---|
| Name | Label shown in the builder, runner, and Flow. |
| `Source_Object__c` | API name to map FROM (for example `Contact`). Resolved at runtime. |
| `Target_Object__c` | Always `lfemr__Patient__c`. |
| `Match_Target_Field__c` | Patient field used to find an existing row for upsert. Default `lfemr__Source_System_Id__c`. |
| `Active__c` | Inactive definitions are skipped by every run mode. |
| `Description__c` | Optional notes for other admins. |

### `Field_Mapping__c`

One source-to-target field under a definition. `Source_Field__c` is a single API name, or a comma-separated list when the transformation is Concatenate.

| Transformation | Extra input |
|---|---|
| Direct | Source field only. |
| Default Value | `Default_Value__c` (source field optional). |
| Trim / Uppercase / Lowercase | Source field. |
| Date Format | `Format_Pattern__c` (for example `yyyy-MM-dd`). |
| Concatenate | Multiple source fields plus `Concat_Separator__c`. |
| Picklist Value Map | Child `Value_Map__c` rows. |

`Sort_Order__c` controls display and apply order.

### `Value_Map__c`

Source value → target value pairs used only by **Picklist Value Map**. Unmapped source values pass through unchanged.

## Run modes

All three modes call `MappingEngine.run`. The definition must be **Active**.

### On-demand (Mapping Runner)

Open **Mapping Runner** in the LogicEMR app.

1. Choose an active mapping.
2. **Preview** a single source record Id. The table shows source value → mapped Patient value. This is a dry run (`dryRun=true`): no Patient DML.
3. **Run** one or more source Ids to commit creates and updates. The page reports created / updated / skipped and row errors.

Use preview before the first commit and after any field-mapping change.

### Batch backfill

**Queue full backfill** on Mapping Runner (confirmation required) enqueues `MappingBatch` for every row of the source object and returns the AsyncApex job Id. The batch is stateful and emails the running user a created/updated/skipped/error summary when it finishes.

Use this for an initial load or a full replay. Prefer on-demand or Flow when only a subset of records changed.

### Flow-invocable

The invocable action **Map Records to Patient** (category LogicEMR) is `MappingInvocable`. Each request supplies:

- **Source Record Id** (required)
- **Mapping Definition Id** and/or **Mapping Name**

Requests that share a mapping are grouped into one engine call. Typical uses: record-triggered Flow on Contact create/update, or a scheduled Flow that queries a work queue.

## Idempotency key

Default match field is `lfemr__Source_System_Id__c` on Patient (External ID, unique).

If the mapping does not write that field, the engine sets:

```text
Source_System_Id__c = SourceObjectApiName + ':' + SourceRecordId
```

Example: `Contact:003xxxxxxxxxxxx`.

A second run with the same definition and source record finds that Patient and **updates** it. It does not insert a duplicate. You can point `Match_Target_Field__c` at another unique Patient field (for example MRN) when the subscriber already has a natural key; the composed `SourceObject:RecordId` key is the default that needs no extra mapping row.

## Security posture (AppExchange review)

The mapping stack is written for subscriber-org FLS and sharing. It does not use `without sharing`.

| Control | Where |
|---|---|
| Sharing | `MappingEngine`, `MappingBatch`, `MappingInvocable`, `MappingBuilderController`, and `MappingRunnerController` are `with sharing`. Source rows the user cannot see are not mapped. |
| Source FLS | Source SOQL includes only fields that are describe-accessible. `Security.stripInaccessible(AccessType.READABLE, …)` is applied to queried source records before transforms. |
| Target FLS | Before DML, insert rows are stripped with `AccessType.CREATABLE` and update rows with `AccessType.UPDATABLE`. Fields the user cannot create or edit are dropped, not written in system mode. |
| Configuration access | Ships as **permission sets only**. LogicEMR Mapping Admin is CRUD on the three mapping objects plus the mapping Apex classes and tabs. Profiles are not edited. |
| Describe in the builder | `getSourceObjectOptions` / `getFields` return objects and fields the running user can query and access. System objects (History, Share, Apex, setup types) are filtered out. |

A reviewer should see: user-mode visibility on source data, FLS-safe DML on Patient, and no hidden profile changes.

## Worked example: Contact → Patient

This is the mapping the package tests use. A subscriber admin can recreate it in a scratch or sandbox org.

### 1. Access

1. Assign **LogicEMR Mapping Admin** and **LogicEMR Admin** (or equivalent Patient + Contact access) to your user.
2. Open the **LogicEMR** app. The Data Mapping items in the nav are **Mapping Definitions**, **Mapping Builder**, and **Mapping Runner**.

### 2. Build the definition

Open **Mapping Builder**.

1. Mapping name: `Contact to Patient`.
2. Source object: `Contact`. Target stays Patient.
3. Add field mappings:

| Source field | Target field | Transformation | Extra |
|---|---|---|---|
| FirstName | `First_Name__c` | Direct | |
| LastName | `Last_Name__c` | Direct | |
| *(none)* | `Status__c` | Default Value | `Active` |
| FirstName, LastName | `MRN__c` | Concatenate | separator `-` |

4. Match target field: `lfemr__Source_System_Id__c` (the default).
5. Leave **Active** on. Save.

Optional Picklist Value Map example: Contact `Salutation` → Patient `Sex_at_Birth__c` with value maps `Mr.` → `Male` and `Ms.` → `Female`.

### 3. Preview

1. Create or open a Contact with First Name `Ada` and Last Name `Lovelace`. Copy its Id.
2. Open **Mapping Runner**, choose `Contact to Patient`, paste the Contact Id, and click **Preview**.

Expected dry-run rows (no Patient inserted):

| Source value | → | Mapped value |
|---|---|---|
| Ada | `First_Name__c` | Ada |
| Lovelace | `Last_Name__c` | Lovelace |
| | `Status__c` | Active |
| Ada, Lovelace | `MRN__c` | Ada-Lovelace |
| `{ContactId}` | `lfemr__Source_System_Id__c` | `Contact:{ContactId}` |

### 4. Run on demand

On Mapping Runner, run the same Contact Id. One Patient is created. Run it again: created stays 0, updated is 1, still one Patient. `Source_System_Id__c` remains `Contact:{ContactId}`.

### 5. Flow (optional)

Record-triggered Flow on Contact, after save, action **Map Records to Patient**:

- Mapping Name = `Contact to Patient` (or the Mapping Definition Id)
- Source Record Id = `$Record.Id`

Each Contact insert or update upserts the same Patient.

### 6. Backfill (optional)

On Mapping Runner, **Queue full backfill** → confirm. Every Contact the user can see is mapped. Copy the job Id if you need to monitor it under Apex Jobs.
