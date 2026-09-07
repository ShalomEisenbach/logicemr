# Eligibility setup (Stedi)

LogicEMR stores eligibility results on `Eligibility_Check__c` (PHI; sharing follows the parent `Patient__c`). Callouts go through a packaged Named Credential. **Never put a Stedi endpoint or API key in Apex, Custom Metadata, or Custom Settings.**

## What the package ships

| Artifact | Developer name | Role |
| --- | --- | --- |
| Named Credential | `Stedi_Eligibility` | Callout target. Apex uses `callout:Stedi_Eligibility` (or the name in `Eligibility_Setting__mdt.Named_Credential__c`). |
| External Credential | `Stedi_Eligibility` | Custom auth. Injects an `Authorization` header from a stored secret. |
| Principal (structure only) | `Stedi_API` | Named Principal. The API key is **not** packaged. |
| Custom Metadata | `Eligibility_Setting.Stedi` | `Provider_Name__c = Stedi`, `Named_Credential__c = Stedi_Eligibility`, `Default_Service_Type__c = 30`, `Active__c = true`. |

The Named Credential URL is maintained in Setup (packaged default is the Stedi healthcare host). Change it in the Named Credential if Stedi publishes a different host. Do not copy that URL into code.

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
     - Sandbox / test org: Stedi **test** key
     - Production: Stedi **production** key
   - Sequence Number: `1`
5. Save. Do not paste the key anywhere else.

The External Credential adds the `Authorization` header at callout time. Apex does not set that header.

### 2. Confirm Named Credential access

1. Setup → **Named Credentials** → **Stedi Eligibility** (`Stedi_Eligibility`).
2. Confirm it is enabled for callouts and uses External Credential `Stedi_Eligibility`.
3. Leave **Generate Authorization Header** disabled (Custom auth supplies `Authorization`).

### 3. Permission sets

Assign **LogicEMR Admin** and/or **LogicEMR Clinician** for object and field access to `Eligibility_Check__c`.

After the `Stedi_API` principal exists (step 1), grant it on those permission sets:

1. Setup → Permission Set → **LogicEMR Admin** (repeat for **LogicEMR Clinician**)
2. **External Credential Principal Access** → enable `Stedi_Eligibility-Stedi_API`
3. If a callout is denied, also enable **Named Credential Access** for `Stedi_Eligibility`

### 4. Eligibility Setting

Setup → **Custom Metadata Types** → **Eligibility Setting** → **Stedi**.

| Field | Packaged default | Notes |
| --- | --- | --- |
| `Provider_Name__c` | `Stedi` | Factory maps this name to `StediEligibilityProvider`. Another class name can be used for a custom `EligibilityProvider`. |
| `Named_Credential__c` | `Stedi_Eligibility` | Must match the Named Credential developer name. Not a URL and not a key. |
| `Default_Service_Type__c` | `30` | Health benefit plan coverage. Override per request when needed. |
| `Active__c` | true | Factory uses the first active row (by provider name). |

Only one row should be active unless you intend a specific sort order.

## Apex usage

```apex
EligibilityRequest req = new EligibilityRequest();
req.patient = patientId;
req.coverage = coverageId;
req.payerId = stediPayerId;
req.serviceType = null; // uses Default_Service_Type__c

EligibilityResult result = EligibilityProviderFactory.getProvider().check(req);
```

`StediEligibilityProvider` POSTs to `callout:{Named_Credential__c}` and does not set `Authorization`. Persist results to `Eligibility_Check__c` from a later service if needed.

## Related

See [coding-pattern.md](coding-pattern.md) for coded-field conventions. Access ships as permission sets only.
