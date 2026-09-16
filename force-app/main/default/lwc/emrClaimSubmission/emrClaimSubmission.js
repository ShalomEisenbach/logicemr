import { LightningElement, api, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";
import getSubmissions from "@salesforce/apex/ClaimSubmissionController.getSubmissions";
import queueSubmission from "@salesforce/apex/ClaimSubmissionController.queueSubmission";
import retrySubmission from "@salesforce/apex/ClaimSubmissionController.retrySubmission";
import getAcknowledgments from "@salesforce/apex/ClaimSubmissionController.getAcknowledgments";
import reopenRejectedClaim from "@salesforce/apex/ClaimSubmissionController.reopenRejectedClaim";
import { refreshApex } from "@salesforce/apex";

export default class EmrClaimSubmission extends LightningElement {
  static STALE_QUEUE_MS = 15 * 60 * 1000;

  @api superbillId;
  @api claimStatus;

  submissions = [];
  rawSubmissions = [];
  acknowledgments = [];
  errorMessage;
  isWorking = false;
  wiredResult;
  pollTimer;

  @wire(getSubmissions, { superbillId: "$superbillId" })
  wiredSubmissions(result) {
    this.wiredResult = result;
    if (result.data) {
      this.rawSubmissions = result.data;
      this.rebuildSubmissions();
      this.errorMessage = undefined;
      this.schedulePoll();
    } else if (result.error) {
      this.submissions = [];
      this.errorMessage = this.reduceError(result.error);
    }
  }

  @wire(getAcknowledgments, { superbillId: "$superbillId" })
  wiredAcknowledgments(result) {
    this.wiredAcknowledgmentsResult = result;
    if (result.data) {
      this.acknowledgments = result.data;
      this.rebuildSubmissions();
    } else if (result.error) {
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

  get hasPendingAcknowledgment() {
    const latest = this.submissions[0];
    return (
      latest?.Status__c === "Submitted" &&
      (!latest.Acknowledgment_Status__c ||
        latest.Acknowledgment_Status__c === "Pending")
    );
  }

  get canSubmit() {
    return this.claimStatus === "Ready" && !this.hasPending;
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

  async handleReopenRejected(event) {
    if (this.isWorking) return;
    const submissionId = event.currentTarget.dataset.id;
    const confirmed = await LightningConfirm.open({
      label: "Reopen rejected claim",
      message:
        "Reopen this exported claim for correction? You must mark it Ready and submit a new 837P after making changes.",
      variant: "header"
    });
    if (!confirmed) return;
    this.isWorking = true;
    this.errorMessage = undefined;
    try {
      await reopenRejectedClaim({
        submissionId
      });
      await this.refreshData();
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Success",
          message: "Rejected claim reopened for correction.",
          variant: "success"
        })
      );
      this.dispatchEvent(
        new CustomEvent("claimreopened", {
          detail: { status: "Needs Review" }
        })
      );
    } catch (error) {
      this.errorMessage = this.reduceError(error);
    } finally {
      this.isWorking = false;
    }
  }

  async handleRefresh() {
    await this.refreshData();
  }

  async run(operation, successMessage) {
    if (this.isWorking) return false;
    this.isWorking = true;
    this.errorMessage = undefined;
    try {
      await operation();
      await this.refreshData();
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Success",
          message: successMessage,
          variant: "success"
        })
      );
      return true;
    } catch (error) {
      this.errorMessage = this.reduceError(error);
      return false;
    } finally {
      this.isWorking = false;
    }
  }

  schedulePoll() {
    clearTimeout(this.pollTimer);
    if (
      (!this.hasPending && !this.hasPendingAcknowledgment) ||
      !this.wiredResult
    )
      return;
    // Polling is intentional while the asynchronous Apex job owns the submission.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.pollTimer = setTimeout(
      async () => {
        await this.refreshData();
      },
      this.hasPending ? 3000 : 30000
    );
  }

  async refreshData() {
    const refreshes = [];
    if (this.wiredResult) refreshes.push(refreshApex(this.wiredResult));
    if (this.wiredAcknowledgmentsResult)
      refreshes.push(refreshApex(this.wiredAcknowledgmentsResult));
    await Promise.all(refreshes);
  }

  rebuildSubmissions() {
    const bySubmission = new Map();
    (this.acknowledgments || []).forEach((acknowledgment) => {
      const submissionId = acknowledgment.Claim_Submission__c;
      if (!bySubmission.has(submissionId)) bySubmission.set(submissionId, []);
      bySubmission.get(submissionId).push({
        ...acknowledgment,
        statusClass: `ack-status ack-${(
          acknowledgment.Status__c || "unknown"
        ).toLowerCase()}`,
        senderLabel: [
          acknowledgment.Sender_Type__c,
          acknowledgment.Sender_Name__c
        ]
          .filter(Boolean)
          .join(" · ")
      });
    });
    this.submissions = (this.rawSubmissions || []).map((row, index) => {
      const acknowledgments = bySubmission.get(row.Id) || [];
      const acknowledgmentStatus = row.Acknowledgment_Status__c || "Pending";
      return {
        ...row,
        statusClass: `status status-${(row.Status__c || "").toLowerCase()}`,
        acknowledgmentStatus,
        acknowledgmentStatusClass: `ack-status ack-${acknowledgmentStatus.toLowerCase()}`,
        acknowledgments,
        hasAcknowledgments: acknowledgments.length > 0,
        canRetry: this.canRetryRow(row),
        retryLabel: row.Status__c === "Queued" ? "Recover" : "Retry",
        canReopenRejected:
          index === 0 &&
          row.Status__c === "Submitted" &&
          acknowledgmentStatus === "Rejected" &&
          this.claimStatus === "Exported"
      };
    });
    this.schedulePoll();
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
