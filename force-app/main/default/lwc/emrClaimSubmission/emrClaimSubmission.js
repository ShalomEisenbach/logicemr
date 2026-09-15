import { LightningElement, api, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";
import getSubmissions from "@salesforce/apex/ClaimSubmissionController.getSubmissions";
import queueSubmission from "@salesforce/apex/ClaimSubmissionController.queueSubmission";
import retrySubmission from "@salesforce/apex/ClaimSubmissionController.retrySubmission";
import { refreshApex } from "@salesforce/apex";

export default class EmrClaimSubmission extends LightningElement {
  static STALE_QUEUE_MS = 15 * 60 * 1000;

  @api superbillId;
  @api claimStatus;

  submissions = [];
  errorMessage;
  isWorking = false;
  wiredResult;
  pollTimer;

  @wire(getSubmissions, { superbillId: "$superbillId" })
  wiredSubmissions(result) {
    this.wiredResult = result;
    if (result.data) {
      this.submissions = result.data.map((row) => ({
        ...row,
        statusClass: `status status-${(row.Status__c || "").toLowerCase()}`,
        canRetry: this.canRetryRow(row),
        retryLabel: row.Status__c === "Queued" ? "Recover" : "Retry"
      }));
      this.errorMessage = undefined;
      this.schedulePoll();
    } else if (result.error) {
      this.submissions = [];
      this.errorMessage = this.reduceError(result.error);
    }
  }

  disconnectedCallback() {
    clearTimeout(this.pollTimer);
  }

  get hasSubmissions() {
    return this.submissions.length > 0;
  }

  get hasPending() {
    return this.submissions.some((row) => row.Status__c === "Queued");
  }

  get hasSubmitted() {
    return this.submissions.some((row) => row.Status__c === "Submitted");
  }

  get canSubmit() {
    return (
      this.claimStatus === "Ready" && !this.hasPending && !this.hasSubmitted
    );
  }

  get submitDisabled() {
    return this.isWorking || !this.canSubmit;
  }

  async handleSubmit() {
    const confirmed = await LightningConfirm.open({
      label: "Submit professional claim",
      message: "Queue this frozen claim for clearinghouse submission?",
      variant: "header"
    });
    if (!confirmed) return;
    await this.run(
      () => queueSubmission({ superbillId: this.superbillId }),
      "Claim submission queued."
    );
  }

  async handleRetry(event) {
    await this.run(
      () => retrySubmission({ submissionId: event.currentTarget.dataset.id }),
      "Claim submission retry queued."
    );
  }

  async handleRefresh() {
    if (this.wiredResult) await refreshApex(this.wiredResult);
  }

  async run(operation, successMessage) {
    if (this.isWorking) return;
    this.isWorking = true;
    this.errorMessage = undefined;
    try {
      await operation();
      await refreshApex(this.wiredResult);
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Success",
          message: successMessage,
          variant: "success"
        })
      );
    } catch (error) {
      this.errorMessage = this.reduceError(error);
    } finally {
      this.isWorking = false;
    }
  }

  schedulePoll() {
    clearTimeout(this.pollTimer);
    if (!this.hasPending || !this.wiredResult) return;
    // Polling is intentional while the asynchronous Apex job owns the submission.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.pollTimer = setTimeout(async () => {
      await refreshApex(this.wiredResult);
    }, 3000);
  }

  canRetryRow(row) {
    if (row.Status__c === "Failed") return true;
    if (row.Status__c !== "Queued" || !row.Queued_At__c) return false;
    const queuedAt = Date.parse(row.Queued_At__c);
    return (
      Number.isFinite(queuedAt) &&
      Date.now() - queuedAt >= EmrClaimSubmission.STALE_QUEUE_MS
    );
  }

  reduceError(error) {
    if (Array.isArray(error?.body))
      return error.body.map((item) => item.message).join(", ");
    return error?.body?.message || error?.message || "Unexpected error.";
  }
}
