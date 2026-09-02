# Coding Pattern

Reusable field group for coded clinical data. Every coded element on a custom object is **exactly three fields**. Future clinical objects reuse this pattern verbatim.

## Field group

Replace `{Element}` with the PascalCase name of the coded concept (for example `Code`, `Diagnosis`, `Vaccine`).

| Field API name | Type | Notes |
|---|---|---|
| `{Element}_Code_System__c` | Picklist | Restricted. Uses the `LogicEMR_Code_System` global value set. |
| `{Element}_Code__c` | Text (50) | The code value from that system. |
| `{Element}_Display__c` | Text (255) | Human-readable display text for the code. |

Do not add extra coding fields (URI, version, user-selected flag) unless a later prompt specifies them.

### Global value set

`LogicEMR_Code_System` (label: LogicEMR Code System):

- ICD-10
- CPT
- LOINC
- RxNorm
- SNOMED
- CVX

Picklists that use this value set must be restricted and must reference it by name. Do not copy the values into a local value set.

## Worked example

A future `Condition__c` object with one coded element named `Code` (the diagnosis).

Stored values for Type 2 diabetes mellitus without complications:

| Field | Value |
|---|---|
| `Code_Code_System__c` | ICD-10 |
| `Code_Code__c` | E11.9 |
| `Code_Display__c` | Type 2 diabetes mellitus without complications |

### `Code_Code_System__c.field-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Code_Code_System__c</fullName>
    <label>Code System</label>
    <required>false</required>
    <type>Picklist</type>
    <valueSet>
        <restricted>true</restricted>
        <valueSetName>LogicEMR_Code_System</valueSetName>
    </valueSet>
</CustomField>
```

### `Code_Code__c.field-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Code_Code__c</fullName>
    <label>Code</label>
    <length>50</length>
    <required>false</required>
    <type>Text</type>
    <unique>false</unique>
</CustomField>
```

### `Code_Display__c.field-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Code_Display__c</fullName>
    <label>Code Display</label>
    <length>255</length>
    <required>false</required>
    <type>Text</type>
    <unique>false</unique>
</CustomField>
```

Copy these three files onto the target object, substituting `{Element}` in the API names and labels. Keep `valueSetName` as `LogicEMR_Code_System`.
