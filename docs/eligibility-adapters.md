# Eligibility adapters

LogicEMR talks to a clearinghouse through `EligibilityProvider`. The packaged adapter is `StediEligibilityProvider`. The Coverage panel, `emrEligibilityCheck`, `emrPayerSearch`, `EligibilityCheckController`, `EligibilityService`, and `EligibilityBatch` never call Stedi (or any vendor) directly. They call `EligibilityProviderFactory.getProvider()`.

To add another clearinghouse later, implement the interface and point Custom Metadata at it. Do **not** change the UI, the batch, or `Eligibility_Check__c`.

## What stays unchanged

| Layer | Why it stays put |
| --- | --- |
| `Eligibility_Check__c` | Status, benefits, `Request_Payload__c`, and `Raw_Response__c` are vendor-neutral. |
| `EligibilityService.runCheck` | Builds an `EligibilityRequest`, calls `provider.check`, returns the persisted row. |
| `EligibilityBatch` | Re-verifies active coverages by calling `EligibilityService.runCheck`. |
| `emrCoveragePanel` / `emrEligibilityCheck` / `emrPayerSearch` | Call `EligibilityCheckController` / `PayerSearchController`, which use the factory. |
| `Payer__c.Payer_Identifier__c` | Stores the clearinghouse payer id selected in `emrPayerSearch`. |

## Contract

`EligibilityProvider` has two methods:

```apex
public interface EligibilityProvider {
    EligibilityResult check(EligibilityRequest req);
    List<EligibilityPayerMatch> searchPayers(String query);
}
```

`EligibilityRequest` carries `patient`, `coverage`, optional `serviceType`, and optional provider NPI / organization. The adapter loads Patient, Coverage, and Payer from those Ids.

`EligibilityResult` must set `eligibilityCheckId` after insert (or `error` if persist failed). `EligibilityService` re-queries that Id. Persist an `Eligibility_Check__c` on every attempt, including errors (`Status__c = Error`, `Error_Message__c` set).

Callouts must use `callout:{Named_Credential__c}` from the active `Eligibility_Setting__mdt` row. **Never** put an endpoint URL or API key in Apex, Custom Metadata, or Custom Settings.

## Add a clearinghouse

### 1. Implement `EligibilityProvider`

Create a `with sharing` Apex class, for example `ChangeHealthcareEligibilityProvider`, that implements `EligibilityProvider`.

- `check`: build the vendor 270 (or equivalent), POST through the Named Credential, parse the 271, insert `Eligibility_Check__c`, put the new Id on `EligibilityResult.eligibilityCheckId`.
- `searchPayers`: GET/POST the vendor payer directory through the same Named Credential and return `EligibilityPayerMatch` rows (`payerId`, `name`). `emrPayerSearch` writes `payerId` to `Payer__c.Payer_Identifier__c`.
- Do not set `Authorization` in Apex if the External Credential injects it.
- Add a matching test class with HTTP mocks and meaningful `System.assert` checks (>90% coverage).

`EligibilityProviderFactory.forName` maps:

- blank or `Stedi` → `StediEligibilityProvider`
- any other `Provider_Name__c` → `Type.forName(providerName)` (the Apex class name)

### 2. Named Credential and External Credential

In the subscriber org (or package them if you are shipping a second vendor):

1. Create an External Credential (Custom auth or the vendor's protocol). Store the API key on a Named Principal. Apex never stores the key.
2. Create a Named Credential whose developer name you will put in Custom Metadata (for example `ChangeHealthcare_Eligibility`). Point it at the External Credential. Enable callouts. Do not generate an Authorization header if Custom auth supplies it.
3. Grant **Named Credential Access** and **External Credential Principal Access** on the permission sets that run checks (`LogicEMR_Clinician`, `LogicEMR_Billing`, `LogicEMR_Admin`).

### 3. `Eligibility_Setting__mdt` row

Setup → **Custom Metadata Types** → **Eligibility Setting** → **New**.

| Field | Example | Notes |
| --- | --- | --- |
| Label / Developer name | `Change_Healthcare` | Subscriber-controlled. |
| `Provider_Name__c` | `ChangeHealthcareEligibilityProvider` | Must be the Apex class name (unless the name is `Stedi`). |
| `Named_Credential__c` | `ChangeHealthcare_Eligibility` | Developer name only. Not a URL. |
| `Default_Service_Type__c` | `30` | Used when the request does not pass a service type. |
| `Active__c` | `true` | Factory uses the first active row, ordered by `Provider_Name__c`. |

Deactivate the Stedi row (or leave only one row active). The factory does not load inactive rows.

No UI, batch, or object change is required. The next Check Eligibility click, payer search, or `EligibilityBatch` run uses the new adapter.

## Checklist

- [ ] Class implements `EligibilityProvider` and persists `Eligibility_Check__c` on success and error.
- [ ] Callouts use `callout:{Named_Credential__c}` from the setting row.
- [ ] API key lives only on the External Credential principal.
- [ ] Permission sets grant the new Named Credential / principal.
- [ ] One active `Eligibility_Setting__mdt` row points at the new class and credential.
- [ ] Tests mock HTTP and assert parsed status, stored payload, and error paths.
- [ ] `emrCoveragePanel`, `emrEligibilityCheck`, `emrPayerSearch`, and `EligibilityBatch` are untouched.

## Related

See [eligibility-setup.md](eligibility-setup.md) for Stedi install steps, BAA, and PHI-at-rest handling.
