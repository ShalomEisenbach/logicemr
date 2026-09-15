# Canonical professional claim schema

`VendorNeutralClaim` is the stable boundary between LogicEMR claim preparation and transport-specific adapters. The current `schemaVersion` is `1.1`.

## Contract

```json
{
  "schemaVersion": "1.1",
  "sourceSystem": "LogicEMR",
  "claimType": "professional",
  "sourceRecordId": "Superbill Id",
  "claimIdentifier": "SB-00000001",
  "status": "Ready",
  "dateOfService": "2026-09-15",
  "placeOfServiceCode": "11",
  "claimFilingCode": "CI",
  "readyAt": "2026-09-15T15:00:00.000Z",
  "snapshotVersion": 1,
  "snapshotRefreshedAt": "2026-09-15T14:55:00.000Z",
  "currencyCode": "USD",
  "totalCharge": 175.00,
  "patient": {
    "name": { "first": "Jamie", "last": "Patient" },
    "dateOfBirth": "1985-05-12",
    "sex": "Female",
    "address": { "street": "10 Main St", "city": "Boston", "state": "MA", "postalCode": "02108", "country": "US" }
  },
  "subscriber": {
    "name": { "first": "Jamie", "last": "Patient" },
    "dateOfBirth": "1985-05-12",
    "sex": "Female",
    "patientRelationshipToSubscriber": "Self",
    "memberId": "MEMBER-1",
    "groupNumber": "GROUP-1",
    "coverageStart": "2026-01-01",
    "coverageEnd": null,
    "address": { "street": "10 Main St", "city": "Boston", "state": "MA", "postalCode": "02108", "country": "US" }
  },
  "payer": { "name": "Example Payer", "identifier": "842610001" },
  "renderingProvider": { "name": "Pat Provider", "firstName": "Pat", "lastName": "Provider", "npi": "1999999984", "taxonomyCode": "207Q00000X" },
  "billingProvider": {
    "legalName": "Logic Clinic",
    "npi": "1888888875",
    "taxIdentifier": "123456789",
    "taxonomyCode": "261QP2300X",
    "address": { "street": "100 Clinic Ave", "city": "Boston", "state": "MA", "postalCode": "02108", "country": "US" }
  },
  "diagnoses": [
    { "sequence": 1, "type": "Principal", "codeSystem": "ICD-10", "code": "J06.9", "display": "Acute URI" }
  ],
  "serviceLines": [
    {
      "sourceLineId": "Charge Line Id",
      "codeSystem": "CPT",
      "code": "99213",
      "display": "Office visit",
      "serviceDate": "2026-09-15",
      "units": 1,
      "chargeAmount": 175.00,
      "modifiers": ["25"],
      "diagnosisPointers": [1],
      "rate": { "unitRate": 175.00, "source": "Commercial 2026", "overridden": false, "overrideReason": null }
    }
  ]
}
```

## Invariants

- Only `Ready` or `Exported` superbills can be mapped.
- Party values come from frozen `Superbill__c` snapshot fields, never current source demographics.
- Diagnoses and service lines preserve their claim ordering.
- Diagnosis pointers are emitted as integers and must reference an included diagnosis sequence.
- EIN values are normalized to nine digits; codes, identifiers, and postal codes remain strings.
- Schema 1.1 adds claim filing code, place of service, and structured rendering-provider name fields required by professional-claim adapters.
- Generating canonical JSON is read-only. Submission adapters own persistence, transmission, and status changes.
