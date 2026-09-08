# Eligibility setup (Stedi)

LogicEMR stores eligibility results on `Eligibility_Check__c` (PHI). Sharing is **Controlled by Parent** on the master-detail to `Patient__c`, so it inherits Patient **Private** OWD. Callouts go through a packaged Named Credential. **Never put a Stedi endpoint or API key in Apex, Custom Metadata, or Custom Settings.**

## What the package ships

| Artifact | Developer name | Role |
| --- | --- | --- |
| Named Credential | `Stedi_Eligibility` | Callout target. Apex uses `callout:Stedi_Eligibility` (or the name in `Eligibility_Setting__mdt.Named_Credential__c`). |
| External Credential | `Stedi_Eligibility` | Custom auth. Injects an `Authorization` header from a stored secret. |
| Principal (structure only) | `Stedi_API` | Named Principal. The API key is **not** packaged. |
| Custom Metadata | `Eligibility_Setting.Stedi` | `Provider_Name__c = Stedi`, `Named_Credential__c = Stedi_Eligibility`, `Default_Service_Type__c = 30`, `Active__c = true`. |
| Custom permission | `LogicEMR_Run_Eligibility` | Gates the Check Eligibility action. |

The Named Credential URL is maintained in Setup (packaged default is the Stedi healthcare host). Change it in the Named Credential if Stedi publishes a different host. Do not copy that URL into code.

## BAA with Stedi

Eligibility requests and responses are PHI (member identifiers, names, dates of birth, plan data). Before enabling live checks in any org that sends real patient data:

1. Execute a **Business Associate Agreement (BAA)** with Stedi.
2. Confirm your Salesforce org already has a BAA with Salesforce (HIPAA-enabled org).
3. Use a **test** Stedi API key in sandboxes. Use a **production** key only in production after the BAA is in place.

Do not send production PHI with a test key, and do not point a production org at a test Stedi environment.

## Admin steps after install

### 1. Create or edit the External Credential principal

1. Setup → **Named Credentials** → **External Credentials** → **Stedi Eligibility** (`Stedi_Eligibility`).
2. Open **Principals**.
3. If **Stedi_API** exists, click **Edit**. Otherwise click **New**:
   - Identity Type: **Named Principal**
   - Principal Name: `Stedi_API` (must match this name so packaged permission sets can grant access)
4. Under **Authentication Parameters**, add one parameter:
   - Name: `ApiKey` (exact — the packaged `Authorization` header formula is `{!$Credential.Stedi_Eligibility.ApiKey}`)
   - Value: your Stedi API key
     - Sandbox / scratch / test org: Stedi **test** key
     - Production: Stedi **production** key
   - Sequence Number: `1`
5. Save. Do not paste the key anywhere else.

The External Credential adds the `Authorization` header at callout time. Apex does not set that header.

### 2. Confirm Named Credential access

1. Setup → **Named Credentials** → **Stedi Eligibility** (`Stedi_Eligibility`).
2. Confirm it is enabled for callouts and uses External Credential `Stedi_Eligibility`.
3. Leave **Generate Authorization Header** disabled (Custom auth supplies `Authorization`).

### 3. Permission sets

Assign permission sets. Do not edit profiles.

| Permission set | `Eligibility_Check__c` | Check Eligibility action | Callout credentials |
| --- | --- | --- | --- |
| **LogicEMR Clinician** | Read (object and fields) | Yes (`LogicEMR_Run_Eligibility`) | `Stedi_Eligibility` Named Credential and `Stedi_Eligibility-Stedi_API` principal |
| **LogicEMR Billing** | Read | Yes (`LogicEMR_Run_Eligibility`) | Same |
| **LogicEMR Admin** | Full CRUD | Yes (`LogicEMR_Run_Eligibility`) | Same |

All three grant Apex access to `EligibilityService`, `StediEligibilityProvider`, `EligibilityProviderFactory`, and `EligibilityBatch`.

The packaged permission sets already include Named Credential and External Credential principal access. After the `Stedi_API` principal exists (step 1), assign the permission set. If a callout is still denied, confirm the principal name is exactly `Stedi_API` and that **External Credential Principal Access** shows `Stedi_Eligibility-Stedi_API`.

`EligibilityCheckController.runCheck` and the Check Eligibility button require `LogicEMR_Run_Eligibility`. Users with only object Read can see the latest status and prior checks. They cannot start a new check. `EligibilityBatch` (scheduled re-verify) does not require the custom permission; schedule it as an admin.

### 4. Resolve a payer's Stedi id (`emrPayerSearch`)

Eligibility cannot run until `Payer__c.Payer_Identifier__c` holds the Stedi payer id.

1. Open the **Payer** record (from the Payer tab or from a coverage's Payer lookup).
2. Use **emrPayerSearch** on the Payer record page.
3. Search the payer name (for example `Aetna`).
4. Select the matching result. The component writes the Stedi id to `Payer_Identifier__c`.

The search uses the active `EligibilityProvider` (`EligibilityProviderFactory.getProvider().searchPayers`). For Stedi that is a GET to `callout:{Named_Credential__c}/2024-04-01/payers/search`. The id you select is what the 270 sends as the trading-partner service id.

If search returns no match, confirm the External Credential key (step 1) and that the Named Credential can call out.

### 5. Eligibility Setting

Setup → **Custom Metadata Types** → **Eligibility Setting** → **Stedi**.

| Field | Packaged default | Notes |
| --- | --- | --- |
| `Provider_Name__c` | `Stedi` | Factory maps this name to `StediEligibilityProvider`. Another class name can be used for a custom `EligibilityProvider`. |
| `Named_Credential__c` | `Stedi_Eligibility` | Must match the Named Credential developer name. Not a URL and not a key. |
| `Default_Service_Type__c` | `30` | Health benefit plan coverage. Override per request when needed. |
| `Active__c` | true | Factory uses the first active row (by provider name). |

Only one row should be active unless you intend a specific sort order. To add another clearinghouse later, see [eligibility-adapters.md](eligibility-adapters.md).

## PHI at rest (`Request_Payload__c` / `Raw_Response__c`)

`Eligibility_Check__c` persists the outbound 270 (`Request_Payload__c`) and the inbound 271 (`Raw_Response__c`). Both are long text and contain PHI.

| Control | Packaged behavior | Subscriber option |
| --- | --- | --- |
| Organization-Wide Default | `Patient__c` is **Private**. `Eligibility_Check__c` is **Controlled by Parent**, so checks inherit Patient sharing. | Leave Private. Do not open OWD. |
| Object access | Clinician and Billing: Read. Admin: CRUD. Access is permission sets only. | Assign the least privilege set that matches the role. |
| Platform Encryption | Not packaged. The package does not enable Shield or mark these fields as encrypted. | If the org has **Salesforce Shield Platform Encryption**, encrypt `Request_Payload__c` and `Raw_Response__c` (and other PHI fields) in Setup. That is a subscriber configuration, not a package change. |

Do not copy request or response bodies into Custom Settings, Platform Cache, debug logs you retain, or email. The Check Eligibility UI shows parsed status and benefits, not the raw payload.

## UI wiring

- **Patient Coverage panel** (`emrCoveragePanel`): Check Eligibility (gated by `LogicEMR_Run_Eligibility`) opens `emrEligibilityCheck` for that coverage. The coverage table and cards show the latest `Eligibility_Check__c.Status__c`.
- **Coverage record page**: `emrEligibilityCheck` runs `EligibilityService.runCheck` for that coverage.
- **Provider home** (`emrProviderHome`, Today's Appointments): shows the patient's latest eligibility status when a check exists.
- **Payer record page**: `emrPayerSearch` sets `Payer_Identifier__c`.

## Apex usage

```apex
Eligibility_Check__c check = EligibilityService.runCheck(patientId, coverageId, null);

List<EligibilityPayerMatch> payers = EligibilityProviderFactory.getProvider().searchPayers('Aetna');
```

`StediEligibilityProvider` POSTs the 270 to `callout:{Named_Credential__c}/change/medicalnetwork/eligibility/v3` and GETs payer search at `/2024-04-01/payers/search`. It does not set `Authorization`. `check` persists `Eligibility_Check__c` (Status, parsed benefits, request payload, raw 271). On any error it stores Status=Error and Error_Message.

`EligibilityBatch` re-verifies active coverages for patients with upcoming appointments (default next 7 days). Schedule it in Execute Anonymous or Setup:

```apex
System.schedule('Eligibility Re-verify', '0 0 2 * * ?', new EligibilityBatch());
```

## Related

See [eligibility-adapters.md](eligibility-adapters.md) to add another clearinghouse without changing the UI, batch, or data model. See [coding-pattern.md](coding-pattern.md) for coded-field conventions. Access ships as permission sets only.
