# Clinical workflows

This document describes the implemented chart workflow and the remaining integration roadmap. Metadata and Apex enforce the clinical invariants; the chart components expose the corresponding actions according to the user's permissions.

## Notes and addenda

Create a note from the encounter workspace, save a draft while documenting, and sign when the content is complete. Signing records the actual Salesforce user in `ClinicalNote__c.Signed_By__c` and the signing time in `Signed_Date__c`. A note's practitioner author and its signing user are separate pieces of provenance.

`ClinicalNoteIntegrity`, called by `ClinicalNoteTrigger`, prevents changes to signed clinical content, patient/encounter association, author, type, signature, and addendum association. It also prevents deleting signed notes. These checks apply to standard record editing and Apex/API changes as well as the note editor. Empty or formatting-only notes cannot be signed. Administrative fields such as external identifiers remain outside the clinical content lock.

Use **Add addendum** on a signed note to record a correction or additional information. The addendum is a separate draft or signed note linked through `Addendum_To__c`; the original remains intact. The server requires the parent to be signed and to belong to the same patient and encounter. The note list displays the signing user and links each addendum to its original note. Existing signed notes retain their historical provenance; the application does not invent a signer for earlier records.

## Allergy reconciliation

An empty allergy list starts as **Unknown**, rather than establishing that the patient has no allergies. The review action records one of these explicit states:

| State              | Required chart state                                                            |
| ------------------ | ------------------------------------------------------------------------------- |
| Unknown            | Review is outstanding; review provenance is cleared.                            |
| No known allergies | No active allergy records exist and the reviewer explicitly confirms the state. |
| Allergies recorded | At least one active allergy exists and the reviewer confirms the list.          |

`AllergyReviewService` checks consistency and stamps the actual reviewer/time. Creating, updating, inactivating, or deleting allergy records invalidates the affected patient's review, requiring another confirmation. The alert bar uses **No known allergies** only for the explicitly reconciled state; an empty unreconciled list displays **Allergy status unknown**.

The allergy panel shows Add, Inactivate, Delete, and Review actions according to object and relevant field permissions. Review requires Patient update permission and edit access to `Allergy_Review_Status__c`; the reviewer/time fields are server-derived. Apex remains the authority if permissions change after the page loads.

## Prescriptions and medication planning

The medication form captures medication coding, SIG/dosage, dose and unit, frequency, route, prescriber, dispense quantity, refills, pharmacy, and start/end dates. Save an incomplete prescription as **Draft**, use its standard **Edit** action to complete it, and then **Activate** it. The new prescription API defaults an omitted status to Draft; the form also allows a complete Order to be saved directly as Active.

Activation requires **Order** intent, a prescriber, dosage instructions, and a positive dispense quantity. Plans and proposals remain medication planning records and are excluded from prescription printing. The trigger also checks reactivation and changes to prescribing details on existing Active Orders. Unchanged historical Active records remain compatible with the earlier medication workflow.

Dispense quantity must be positive, refills cannot be negative, and the end date cannot precede the start date. The prescription API limits refills to 999. Creation checks object create permission and access to populated fields; activation checks object update permission and edit access to status/authored time.

Print or email selected Active Orders through the existing prescription document workflow. The document includes the new dispensing and pharmacy information. PDF generation/emailing does not transmit an electronic prescription to a pharmacy, verify prescriber licensing, or perform drug interaction screening. Those services require a separate integration and clinical policy.

## Vitals and result review

Vitals capture displays the recorded measurement and its source unit. Recognized Celsius/Fahrenheit, metric/imperial height, and metric/imperial weight units are handled explicitly; valid source units are retained on edits. Unknown or missing source units remain visible but cannot be overwritten by autosave. Only changed measurements are saved, and unchanged quantities do not acquire a new measurement time. The earlier numeric Apex load API retains its Fahrenheit/inches/pounds contract through conversion.

Cancelled observations are excluded from current vitals and alerts. The banner gives each metric its own measurement time. A combined BP requires systolic and diastolic components with the same recorded timestamp and compatible units; otherwise the newer component is identified as SBP or DBP.

The abnormal alert summary first chooses the latest observation for each code/system, then applies abnormal interpretation filtering. A newer normal or unclassified observation suppresses the earlier abnormal alert. Changing a measurement without changing its classification clears the old interpretation; supplying a changed interpretation preserves that new classification.

Add a diagnostic report with an optional related service order and encounter. The server validates that those links belong to the same patient and compatible encounter. A linked Final or Amended report completes an Active/On Hold service order. Amended reports remain in the provider review queue. Changes to report content or linked observations clear review provenance and reopen review; corrections to a final report become Amended. Review records the actual user/time rather than accepting caller-supplied provenance.

## Encounter completion and billing handoff

The workspace completion checklist shows whether an attending is assigned, allergies are reviewed, an encounter diagnosis exists, and a clinical note is signed. These items remain visible when a visit is Finished. The checklist supports completing the documentation after the physical visit; billing readiness separately requires a signed note.

Every transition into Finished, including standard record updates and direct creation, records a missing encounter end time and validates that the end is not before the start. `EncounterTrigger` delegates to `EncounterCompletionService`, which queues a handoff after the visit transaction commits.

`EncounterCompletionQueueable` processes at most two encounters per transaction and chains bounded batches. It fulfills linked appointments unless they are already Fulfilled, Cancelled, or No Show. It initializes a superbill only if none exists, preserving an existing billing snapshot. A billing failure does not undo the completed visit, appointment fulfillment, or another encounter's handoff.

The encounter exposes Pending, Completed, or Failed handoff status and a generic error. Use **Refresh checklist** to inspect the latest status and **Retry completion handoff** after addressing a failure. A recently queued Pending handoff cannot be retried for 15 minutes; stale Pending work becomes retryable. Exhausted queue capacity produces an explicit retryable failure. See [claim readiness](claim-readiness.md) for billing rules and [scheduling](scheduling.md) for appointment transitions.

## Remaining roadmap

1. Validate these workflows with clinician, billing, scheduler, and administrator roles in the target org, including standard record actions and a complete appointment-to-claim walkthrough.
2. Add result follow-up tracking: patient notification, responsible clinician, due dates, escalation, and acknowledgment distinct from merely marking a result reviewed.
3. Add medication reconciliation provenance and an encounter review step for imported/home medications; connect validated drug-allergy and interaction screening before introducing electronic prescribing.
4. Integrate pharmacy transmission and order/result interfaces with idempotent identifiers, delivery acknowledgments, amendment handling, and retry monitoring.
5. Extend clinical operations monitoring for unsigned notes, stale reviews, outstanding orders, and failed completion handoffs without duplicating patient information in generic errors.

Focused Apex coverage lives in `NoteEditorControllerTest`, `AllergyReviewServiceTest`, `MedicationPanelControllerTest`, `VitalsCaptureControllerTest`, `AlertBarControllerTest`, `PatientBannerControllerTest`, `ClinicalResultIntegrityTest`, and `EncounterCompletionServiceTest`. LWC regression suites cover vitals autosave/units, addenda, result linkage, completion retries, and allergy permission states.
