# Professional claim submission

LogicEMR submits primary professional claims through a provider-neutral Apex boundary. The packaged Stedi adapter uses the 837P JSON endpoint and stores each attempt as `Claim_Submission__c`, controlled by the parent superbill's sharing.

## Safety defaults

- The packaged `Claim_Submission_Setting.Stedi` row uses usage indicator `T` (test).
- Production transmission requires an explicit admin change to `P` after payer enrollment, testing, and a BAA are complete.
- API keys stay in the existing `Stedi_Eligibility` External Credential. `Stedi_Claims` is a separate Named Credential that reuses that secret and endpoint host.
- The packaged setting intentionally leaves `Contact_Phone__c` blank. Submission is blocked until an admin supplies a real ten-digit billing contact number.
- Every attempt gets a unique 17-character patient control number. Transport retries reuse the original patient control number and idempotency key.
- Raw request and response payloads contain PHI. They inherit the superbill's record sharing, are granted only to billing and admin permission sets, and are not returned to the submission panel. Each organization must apply its approved Salesforce retention policy to these audit fields.

## Setup

1. Complete the Stedi API-key and principal-access steps in [eligibility-setup.md](eligibility-setup.md). LogicEMR Claims reuses `Stedi_Eligibility-Stedi_API`.
2. In Setup, open **Custom Metadata Types → Claim Submission Setting → Manage Records → Stedi**.
3. Set the submitter organization, optional payer-assigned ETIN, billing contact name, and ten-digit contact phone.
4. Keep **Usage Indicator = T** while validating test claims. Change it to `P` only for an approved production connection.
5. Configure each payer's clearinghouse payer ID and optional X12 claim filing code. When the filing code is blank, LogicEMR derives `CI` for Commercial, `MB` for Medicare, `MC` for Medicaid, and `ZZ` for Other. Self-pay claims do not derive a filing code.
6. Confirm the correct place of service in Claim Readiness before marking the superbill Ready.

## Lifecycle

| Status    | Meaning                                                         | Next action                                              |
| --------- | --------------------------------------------------------------- | -------------------------------------------------------- |
| Queued    | Salesforce accepted the request and scheduled the callout       | Wait for the panel to refresh                            |
| Submitted | Stedi returned a successful synchronous handoff                 | Await 277CA in the next increment                        |
| Rejected  | Stedi returned a request/edit rejection                         | Reopen, correct, mark Ready, and create a new submission |
| Failed    | Network, authentication, server, or internal processing failure | Retry the same attempt after resolving the cause         |

Successful handoff does not mean the payer accepted or adjudicated the claim. It only confirms that the clearinghouse received and processed the outbound request synchronously. The later 277CA workflow determines payer acceptance.

HTTP 400 and 422 edit responses, plus a provider edit failure returned with a successful HTTP status, are classified as `Rejected`. Authentication, authorization, rate-limit, timeout, server, and malformed-response failures are classified as `Failed` so they remain retryable.

## Recovery and idempotency

The panel polls while an attempt is `Queued`. After 15 minutes it offers **Recover**, but the server requeues the attempt only when the original Apex job is terminal or no longer exists. An active queued or processing job cannot be duplicated. Recovery and ordinary failure retries preserve the original patient control number and idempotency key so a repeated transport cannot create a second clearinghouse claim.

## Current scope

The adapter sends primary, fee-for-service 837P claims. Billing organization details are also used as the service facility for this first increment. Secondary/tertiary coordination of benefits, attachments, replacement/void frequency codes, acknowledgment ingestion, and remittance posting are intentionally deferred.
