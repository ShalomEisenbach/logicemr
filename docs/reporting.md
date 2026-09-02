# Reporting on coded clinical data

Group and count diagnoses, medications, allergies, immunizations, observations, service requests, diagnostic reports, and procedures using the **master catalog Lookup** (for example `Condition__c.Diagnosis_Ref__c` → `Code_Reference__c`). That Id is the stable key for a code. Snapshot fields (`Diagnosis_Code_System__c`, `Diagnosis_Code__c`, `Diagnosis_Display__c`, and the same pattern on other objects) preserve the point-in-time display that was stored when the clinical row was written. They can drift from the catalog if a display label is later corrected, so they are the wrong grain for “how many patients have X”.

## Example: patients grouped by diagnosis

```sql
SELECT Diagnosis_Ref__r.Code_System__c, Diagnosis_Ref__r.Code__c, Diagnosis_Ref__r.Display__c,
       COUNT_DISTINCT(Patient__c) patientCount
FROM Condition__c
WHERE Diagnosis_Ref__c != null
GROUP BY Diagnosis_Ref__r.Code_System__c, Diagnosis_Ref__r.Code__c, Diagnosis_Ref__r.Display__c
```

Same idea for other coded objects: `Observation__c.Observation_Ref__c`, `AllergyIntolerance__c.Allergen_Ref__c`, `Immunization__c.Vaccine_Ref__c`, `MedicationRequest__c.Medication_Ref__c`, `MedicationStatement__c.Medication_Ref__c`, `ServiceRequest__c.Service_Ref__c`, `DiagnosticReport__c.Report_Ref__c`, `Procedure__c.Procedure_Ref__c`.

## Linking older rows to the catalog

`CatalogLinkBackfillBatch` finds coded rows that have a snapshot code and a null Lookup, matches `Code_Reference__c` on Code System + Code, sets the Lookup, and logs unmatched keys. **Skip this batch if the org has no real clinical data yet.**

```apex
Database.executeBatch(new CatalogLinkBackfillBatch(
    'Condition__c', 'Diagnosis_Code_System__c', 'Diagnosis_Code__c', 'Diagnosis_Ref__c'
));
Database.executeBatch(new CatalogLinkBackfillBatch(
    'Observation__c', 'Observation_Code_System__c', 'Observation_Code__c', 'Observation_Ref__c'
));
Database.executeBatch(new CatalogLinkBackfillBatch(
    'AllergyIntolerance__c', 'Allergen_Code_System__c', 'Allergen_Code__c', 'Allergen_Ref__c'
));
Database.executeBatch(new CatalogLinkBackfillBatch(
    'Immunization__c', 'Vaccine_Code_System__c', 'Vaccine_Code__c', 'Vaccine_Ref__c'
));
Database.executeBatch(new CatalogLinkBackfillBatch(
    'MedicationRequest__c', 'Medication_Code_System__c', 'Medication_Code__c', 'Medication_Ref__c'
));
Database.executeBatch(new CatalogLinkBackfillBatch(
    'MedicationStatement__c', 'Medication_Code_System__c', 'Medication_Code__c', 'Medication_Ref__c'
));
Database.executeBatch(new CatalogLinkBackfillBatch(
    'ServiceRequest__c', 'Service_Code_System__c', 'Service_Code__c', 'Service_Ref__c'
));
Database.executeBatch(new CatalogLinkBackfillBatch(
    'DiagnosticReport__c', 'Report_Code_System__c', 'Report_Code__c', 'Report_Ref__c'
));
Database.executeBatch(new CatalogLinkBackfillBatch(
    'Procedure__c', 'Procedure_Code_System__c', 'Procedure_Code__c', 'Procedure_Ref__c'
));
```

Finish logs updated and unmatched counts, including unmatched `System::Code` keys.
