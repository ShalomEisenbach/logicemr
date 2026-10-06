import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getWorkQueue from "@salesforce/apex/EligibilityCheckController.getWorkQueue";
import retryCheck from "@salesforce/apex/EligibilityCheckController.retryCheck";
import STATUS_FIELD from "@salesforce/schema/Eligibility_Check__c.Status__c";
import hasRunEligibility from "@salesforce/customPermission/LogicEMR_Run_Eligibility";

const REFRESH_MS = 30000;
const COLUMNS = [
  { label: "Check", fieldName: "name" },
  { label: "Patient", fieldName: "patient" },
  { label: "Payer", fieldName: "payer" },
  { label: "Status", fieldName: "status" },
  { label: "Mode", fieldName: "mode" },
  { label: "Stedi trace ID", fieldName: "traceId" },
  {
    label: "Checked",
    fieldName: "checkedAt",
    type: "date",
    typeAttributes: {
      year: "numeric",
      month: "short",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit"
    }
  },
  { label: "Rejection / error", fieldName: "error", wrapText: true },
  {
    type: "button",
    typeAttributes: {
      label: "Retry",
      name: "retry",
      disabled: { fieldName: "retryDisabled" }
    }
  },
  { type: "button", typeAttributes: { label: "Open", name: "open" } }
];

export default class EmrEligibilityQueue extends NavigationMixin(
  LightningElement
) {
  columns = COLUMNS;
  outcomeOptions = ["All", "Success", "Error", "Pending"].map((value) => ({
    label: value,
    value
  }));
  filters = {
    outcome: "All",
    payer: "",
    patient: "",
    startDate: null,
    endDate: null
  };
  appliedFilters = { ...this.filters };
  rows = [];
  hasMore = false;
  loading = false;
  retrying = false;
  autoRefresh = true;
  error;
  lastRefreshed;
  timer;
  connected = false;
  requestVersion = 0;

  connectedCallback() {
    this.connected = true;
    this.loadQueue();
  }

  disconnectedCallback() {
    this.connected = false;
    this.requestVersion++;
    clearTimeout(this.timer);
  }

  get busy() {
    return this.loading || this.retrying;
  }
  get displayRows() {
    return this.rows.map((row) => ({
      ...row,
      retryDisabled: !hasRunEligibility || !row.canRetry || this.busy
    }));
  }
  get hasRows() {
    return this.rows.length > 0;
  }
  get summary() {
    const success = this.rows.filter((row) =>
      ["Active", "Inactive"].includes(row.status)
    ).length;
    const errors = this.rows.filter((row) => row.status === "Error").length;
    return `${this.rows.length} checks shown · ${success} successful · ${errors} errors`;
  }
  get rejectionReasons() {
    const counts = new Map();
    this.rows
      .filter((row) => row.status === "Error")
      .forEach((row) => {
        const reasons = new Set(
          (row.error || "No rejection details returned")
            .split("; ")
            .map((reason) => reason.trim())
            .filter(Boolean)
        );
        reasons.forEach((reason) =>
          counts.set(reason, (counts.get(reason) || 0) + 1)
        );
      });
    return [...counts.entries()]
      .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
      .slice(0, 5)
      .map(([reason, count]) => ({ reason, count }));
  }
  get hasRejections() {
    return this.rejectionReasons.length > 0;
  }

  scheduleRefresh() {
    clearTimeout(this.timer);
    if (this.connected && this.autoRefresh && !this.retrying && !this.loading) {
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      this.timer = setTimeout(() => {
        if (document.visibilityState === "hidden") this.scheduleRefresh();
        else this.loadQueue();
      }, REFRESH_MS);
    }
  }

  async loadQueue() {
    clearTimeout(this.timer);
    const version = ++this.requestVersion;
    this.loading = true;
    try {
      const result = await getWorkQueue(this.appliedFilters);
      if (!this.connected || version !== this.requestVersion) return;
      this.rows = result.rows || [];
      this.hasMore = result.hasMore;
      this.error = undefined;
      this.lastRefreshed = new Date().toISOString();
    } catch (error) {
      if (this.connected && version === this.requestVersion)
        this.error = this.errorMessage(error);
    } finally {
      if (this.connected && version === this.requestVersion) {
        this.loading = false;
        this.scheduleRefresh();
      }
    }
  }

  handleFilter(event) {
    this.filters = {
      ...this.filters,
      [event.target.dataset.field]:
        (event.detail?.value ?? event.target.value) || null
    };
  }

  handleApply() {
    const inputs = [...this.template.querySelectorAll("[data-field]")];
    if (!inputs.every((input) => input.reportValidity())) return;
    if (
      this.filters.startDate &&
      this.filters.endDate &&
      this.filters.startDate > this.filters.endDate
    ) {
      this.error = "Start date must be on or before end date.";
      return;
    }
    this.appliedFilters = { ...this.filters };
    this.loadQueue();
  }

  handleRefresh() {
    this.loadQueue();
  }

  handleAutoRefresh(event) {
    this.autoRefresh = event.target.checked;
    this.scheduleRefresh();
  }

  async handleRowAction(event) {
    const { action, row } = event.detail;
    if (action.name === "open") {
      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: { recordId: row.id, actionName: "view" }
      });
      return;
    }
    if (
      action.name !== "retry" ||
      !row.canRetry ||
      !hasRunEligibility ||
      this.busy
    )
      return;
    this.retrying = true;
    clearTimeout(this.timer);
    try {
      const result = await retryCheck({ checkId: row.id });
      if (!this.connected) return;
      const failed = result[STATUS_FIELD.fieldApiName] === "Error";
      this.dispatchEvent(
        new ShowToastEvent({
          title: failed ? "Retry returned an error" : "Retry completed",
          message:
            "A new eligibility attempt was saved. The original check is retained.",
          variant: failed ? "warning" : "success"
        })
      );
    } catch (error) {
      if (this.connected)
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Retry failed",
            message: this.errorMessage(error),
            variant: "error"
          })
        );
    } finally {
      this.retrying = false;
      if (this.connected) await this.loadQueue();
    }
  }

  errorMessage(error) {
    return (
      error?.body?.message ||
      error?.message ||
      "Unable to load eligibility checks."
    );
  }
}
