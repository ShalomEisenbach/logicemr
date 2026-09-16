import { LightningElement, wire } from "lwc";
import { getFieldDisplayValue, getFieldValue } from "lightning/uiRecordApi";
import { getListRecordsByName } from "lightning/uiListsApi";
import SUPERBILL_OBJECT from "@salesforce/schema/Superbill__c";
import SUPERBILL_NAME from "@salesforce/schema/Superbill__c.Name";
import SUPERBILL_STATUS from "@salesforce/schema/Superbill__c.Status__c";
import SUPERBILL_DATE from "@salesforce/schema/Superbill__c.Date_of_Service__c";
import SUPERBILL_PATIENT from "@salesforce/schema/Superbill__c.Patient__c";
import SUBMISSION_OBJECT from "@salesforce/schema/Claim_Submission__c";
import SUBMISSION_NAME from "@salesforce/schema/Claim_Submission__c.Name";
import SUBMISSION_STATUS from "@salesforce/schema/Claim_Submission__c.Status__c";
import SUBMISSION_PROVIDER from "@salesforce/schema/Claim_Submission__c.Provider_Used__c";
import SUBMISSION_DATE from "@salesforce/schema/Claim_Submission__c.Submitted_At__c";
import ACKNOWLEDGMENT_OBJECT from "@salesforce/schema/Claim_Acknowledgment__c";
import ACKNOWLEDGMENT_NAME from "@salesforce/schema/Claim_Acknowledgment__c.Name";
import ACKNOWLEDGMENT_STATUS from "@salesforce/schema/Claim_Acknowledgment__c.Status__c";
import ACKNOWLEDGMENT_MATCH_STATUS from "@salesforce/schema/Claim_Acknowledgment__c.Match_Status__c";
import ACKNOWLEDGMENT_PATIENT_CONTROL from "@salesforce/schema/Claim_Acknowledgment__c.Patient_Control_Number__c";
import ACKNOWLEDGMENT_PROCESSED_AT from "@salesforce/schema/Claim_Acknowledgment__c.Processed_At__c";

const PAGE_SIZE = 20;

export default class EmrBillingHome extends LightningElement {
  superbills = [];
  submissions = [];
  acknowledgments = [];
  superbillError;
  submissionError;
  acknowledgmentError;

  @wire(getListRecordsByName, {
    objectApiName: SUPERBILL_OBJECT.objectApiName,
    listViewApiName: "Claim_Readiness_Work_Queue",
    pageSize: PAGE_SIZE
  })
  wiredSuperbills({ data, error }) {
    this.superbills = (data?.records || []).map((record) => ({
      id: record.id,
      name: getFieldValue(record, SUPERBILL_NAME),
      status: getFieldValue(record, SUPERBILL_STATUS),
      dateOfService: getFieldValue(record, SUPERBILL_DATE),
      patient:
        getFieldDisplayValue(record, SUPERBILL_PATIENT) ||
        getFieldValue(record, SUPERBILL_PATIENT)
    }));
    this.superbillError = error ? this.reduceError(error) : undefined;
  }

  @wire(getListRecordsByName, {
    objectApiName: SUBMISSION_OBJECT.objectApiName,
    listViewApiName: "Recent_Submissions",
    pageSize: PAGE_SIZE
  })
  wiredSubmissions({ data, error }) {
    this.submissions = (data?.records || []).map((record) => ({
      id: record.id,
      name: getFieldValue(record, SUBMISSION_NAME),
      status: getFieldValue(record, SUBMISSION_STATUS),
      provider: getFieldValue(record, SUBMISSION_PROVIDER),
      submittedAt: getFieldValue(record, SUBMISSION_DATE)
    }));
    this.submissionError = error ? this.reduceError(error) : undefined;
  }

  @wire(getListRecordsByName, {
    objectApiName: ACKNOWLEDGMENT_OBJECT.objectApiName,
    listViewApiName: "Recent_Acknowledgments",
    pageSize: PAGE_SIZE
  })
  wiredAcknowledgments({ data, error }) {
    this.acknowledgments = (data?.records || []).map((record) => ({
      id: record.id,
      name: getFieldValue(record, ACKNOWLEDGMENT_NAME),
      status: getFieldValue(record, ACKNOWLEDGMENT_STATUS),
      matchStatus: getFieldValue(record, ACKNOWLEDGMENT_MATCH_STATUS),
      patientControlNumber: getFieldValue(
        record,
        ACKNOWLEDGMENT_PATIENT_CONTROL
      ),
      processedAt: getFieldValue(record, ACKNOWLEDGMENT_PROCESSED_AT)
    }));
    this.acknowledgmentError = error ? this.reduceError(error) : undefined;
  }

  get superbillObjectApiName() {
    return SUPERBILL_OBJECT.objectApiName;
  }

  get submissionObjectApiName() {
    return SUBMISSION_OBJECT.objectApiName;
  }

  get acknowledgmentObjectApiName() {
    return ACKNOWLEDGMENT_OBJECT.objectApiName;
  }

  get hasSuperbills() {
    return this.superbills.length > 0;
  }

  get hasSubmissions() {
    return this.submissions.length > 0;
  }

  get hasAcknowledgments() {
    return this.acknowledgments.length > 0;
  }

  reduceError(error) {
    return (
      error?.body?.message || error?.message || "Unable to load billing work."
    );
  }
}
