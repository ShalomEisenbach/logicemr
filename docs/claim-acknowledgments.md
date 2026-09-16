# 277CA claim acknowledgments

LogicEMR ingests Stedi 277CA claim acknowledgments asynchronously, correlates each acknowledged claim to its original `Claim_Submission__c`, and gives billing a controlled correction and resubmission workflow for rejected claims.

## Processing flow

1. Stedi sends a `transaction.processed.v2` event after an inbound 277 transaction is available.
2. `StediClaimAcknowledgmentWebhook` validates the request, ignores non-277 events, and immediately queues `ClaimAcknowledgmentQueueable`.
3. The queueable retrieves Stedi's canonical JSON report from `/2024-04-01/change/medicalnetwork/reports/v2/{transactionId}/277` through `Stedi_Claims`.
4. `ClaimAcknowledgmentService` creates one `Claim_Acknowledgment__c` per claim in the transaction and matches it case-insensitively by patient control number. When the acknowledgment omits that number, the Stedi claim transaction batch number is a secondary match to the submission correlation ID.
5. The related submission is summarized as `Received`, `Accepted`, `Rejected`, or `Unknown`. Rejection takes precedence over acceptance, payer responses take precedence over clearinghouse responses, and then the newest response wins.

The acknowledgment key is a deterministic SHA-256 value derived from the Stedi transaction ID and claim position. Webhook retries therefore update existing rows instead of creating duplicates. The retrieval job retries a failed report call up to three times at five-minute intervals before surfacing a failed Apex job. Unmatched claims are retained with `Match Status = Unmatched` for billing investigation.

## Webhook setup

The Apex REST mapping is:

```text
/services/apexrest/logicemr/v1/claim-acknowledgments/stedi
```

For an installed namespaced package, Salesforce may include the namespace before the mapping:

```text
/services/apexrest/lfemr/logicemr/v1/claim-acknowledgments/stedi
```

Use the exact URL exposed by the target org. Configure a Stedi event destination for `transaction.processed.v2`. The receiver returns `202 Accepted` before retrieving the report so it stays within Stedi's webhook response window.

Two authentication models are supported:

- **Authenticated integration endpoint:** The caller supplies a valid Salesforce OAuth bearer token for a user assigned `LogicEMR_Manage_Claims` and External Credential Principal Access to `Stedi_Eligibility-Stedi_API`. Because Stedi credential-set API-key values are static, use an integration gateway if OAuth access-token refresh is required.
- **Salesforce Site shared secret:** Expose only this Apex REST class through a Salesforce Site. Generate a high-entropy secret, store only its 64-character SHA-256 hex digest in `Claim Submission Setting.Webhook Secret Hash`, and configure the raw secret as Stedi API-key header `X-LogicEMR-Webhook-Secret`. Grant the Site guest profile Apex class access to `StediClaimAcknowledgmentWebhook`, `ClaimAcknowledgmentQueueable`, and `ClaimAcknowledgmentService`, plus External Credential Principal Access to `Stedi_Eligibility-Stedi_API` for the report callout.

Never store the raw webhook secret in source control or Custom Metadata. Do not expose a Site endpoint until the hash is configured and a request without the secret has been verified to return HTTP 403.

## Billing workflow

The Claim Submission panel shows the complete acknowledgment timeline, including sender, status codes, message, effective date, and payer claim control number. The Billing Home and **Claim Acknowledgments** tab also expose recent and unmatched acknowledgments.

When the latest submission is rejected and its superbill is still `Exported`:

1. Select **Reopen rejected claim**.
2. LogicEMR moves the superbill to `Needs Review`, clears its ready date, and copies the rejection message into validation messages.
3. Correct the source data or billing lines, refresh the snapshot as appropriate, resolve validation, and mark the claim `Ready` again.
4. Submit a new 837P attempt. The rejected acknowledgment and prior submission remain immutable audit history.

Accepted and received claims cannot be reopened through this action. A new submission is blocked while another attempt is still queued.

## Data handling

The full Stedi report is retained on `Claim_Acknowledgment__c.Raw_Payload__c` for audit and troubleshooting. It can contain PHI, is not returned to the Lightning panel, and is exposed only to the billing and admin permission sets. Apply the organization's approved Salesforce retention, encryption, auditing, and access-review controls.
