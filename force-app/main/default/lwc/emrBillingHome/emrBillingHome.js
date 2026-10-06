import { LightningElement, wire } from "lwc";
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
const SUPERBILL_LIST_VIEW = qualifiedListViewName(
  SUPERBILL_OBJECT.objectApiName,
  "Claim_Readiness_Work_Queue"
);
const SUBMISSION_LIST_VIEW = qualifiedListViewName(
  SUBMISSION_OBJECT.objectApiName,
  "Recent_Submissions"
);
const ACKNOWLEDGMENT_LIST_VIEW = qualifiedListViewName(
  ACKNOWLEDGMENT_OBJECT.objectApiName,
  "Recent_Acknowledgments"
);
const SUPERBILL_REQUIRED_FIELDS = [
  listFieldPath(SUPERBILL_OBJECT.objectApiName, SUPERBILL_NAME)
];
const SUPERBILL_OPTIONAL_FIELDS = [
  SUPERBILL_STATUS,
  SUPERBILL_DATE,
  SUPERBILL_PATIENT
].map((field) => listFieldPath(SUPERBILL_OBJECT.objectApiName, field));
SUPERBILL_OPTIONAL_FIELDS.push(
  `${listFieldPath(SUPERBILL_OBJECT.objectApiName, SUPERBILL_PATIENT).replace(/__c$/, "__r")}.Name`
);
const SUBMISSION_REQUIRED_FIELDS = [
  listFieldPath(SUBMISSION_OBJECT.objectApiName, SUBMISSION_NAME)
];
const SUBMISSION_OPTIONAL_FIELDS = [
  SUBMISSION_STATUS,
  SUBMISSION_PROVIDER,
  SUBMISSION_DATE
].map((field) => listFieldPath(SUBMISSION_OBJECT.objectApiName, field));
const ACKNOWLEDGMENT_REQUIRED_FIELDS = [
  listFieldPath(ACKNOWLEDGMENT_OBJECT.objectApiName, ACKNOWLEDGMENT_NAME)
];
const ACKNOWLEDGMENT_OPTIONAL_FIELDS = [
  ACKNOWLEDGMENT_STATUS,
  ACKNOWLEDGMENT_MATCH_STATUS,
  ACKNOWLEDGMENT_PATIENT_CONTROL,
  ACKNOWLEDGMENT_PROCESSED_AT
].map((field) => listFieldPath(ACKNOWLEDGMENT_OBJECT.objectApiName, field));

function qualifiedListViewName(objectApiName, developerName) {
  // Schema imports resolve package namespaces; literal list-view names do not.
  const namespace = objectNamespace(objectApiName);
  return namespace ? `${namespace}__${developerName}` : developerName;
}

function objectNamespace(objectApiName) {
  return objectApiName?.match(
    /^([A-Za-z][A-Za-z0-9]*)__[A-Za-z][A-Za-z0-9_]*__c$/
  )?.[1];
}

function leafFieldName(field) {
  // Schema references may expose the field as a leaf name or a qualified path.
  return (typeof field === "string" ? field : field.fieldApiName)
    .split(".")
    .pop();
}

function listFieldPath(objectApiName, field) {
  const fieldName = leafFieldName(field);
  const namespace = objectNamespace(objectApiName);
  const prefix = namespace ? `${namespace}__` : "";
  const qualifiedName =
    prefix && /__(c|r)$/.test(fieldName) && !fieldName.startsWith(prefix)
      ? `${prefix}${fieldName}`
      : fieldName;
  return `${objectApiName}.${qualifiedName}`;
}

function listField(record, field) {
  // List API records carry qualified keys even when schema references are local.
  const namespace = objectNamespace(record.apiName || field.objectApiName);
  const prefix = namespace ? `${namespace}__` : "";
  const fieldName = leafFieldName(field);
  const localName =
    prefix && fieldName.startsWith(prefix)
      ? fieldName.slice(prefix.length)
      : fieldName;
  const qualifiedName =
    prefix && /__(c|r)$/.test(localName) ? `${prefix}${localName}` : localName;
  return (
    record.fields?.[fieldName] ??
    record.fields?.[qualifiedName] ??
    record.fields?.[localName]
  );
}

function listValue(record, field) {
  return listField(record, field)?.value;
}

function patientLabel(record) {
  const patient = listField(record, SUPERBILL_PATIENT);
  const relationship = listField(record, {
    objectApiName: SUPERBILL_PATIENT.objectApiName,
    fieldApiName: leafFieldName(SUPERBILL_PATIENT).replace(/__c$/, "__r")
  })?.value;
  return (
    patient?.displayValue ||
    relationship?.fields?.Name?.displayValue ||
    relationship?.fields?.Name?.value ||
    patient?.value
  );
}

export default class EmrBillingHome extends LightningElement {
  superbills = [];
  submissions = [];
  acknowledgments = [];
  superbillError;
  submissionError;
  acknowledgmentError;

  @wire(getListRecordsByName, {
    objectApiName: SUPERBILL_OBJECT.objectApiName,
    listViewApiName: SUPERBILL_LIST_VIEW,
    fields: SUPERBILL_REQUIRED_FIELDS,
    optionalFields: SUPERBILL_OPTIONAL_FIELDS,
    pageSize: PAGE_SIZE
  })
  wiredSuperbills({ data, error }) {
    this.superbills = (data?.records || []).map((record) => ({
      id: record.id,
      name: listValue(record, SUPERBILL_NAME),
      status: listValue(record, SUPERBILL_STATUS),
      dateOfService: listValue(record, SUPERBILL_DATE),
      patient: patientLabel(record)
    }));
    this.superbillError = error ? this.reduceError(error) : undefined;
  }

  @wire(getListRecordsByName, {
    objectApiName: SUBMISSION_OBJECT.objectApiName,
    listViewApiName: SUBMISSION_LIST_VIEW,
    fields: SUBMISSION_REQUIRED_FIELDS,
    optionalFields: SUBMISSION_OPTIONAL_FIELDS,
    pageSize: PAGE_SIZE
  })
  wiredSubmissions({ data, error }) {
    this.submissions = (data?.records || []).map((record) => ({
      id: record.id,
      name: listValue(record, SUBMISSION_NAME),
      status: listValue(record, SUBMISSION_STATUS),
      provider: listValue(record, SUBMISSION_PROVIDER),
      submittedAt: listValue(record, SUBMISSION_DATE)
    }));
    this.submissionError = error ? this.reduceError(error) : undefined;
  }

  @wire(getListRecordsByName, {
    objectApiName: ACKNOWLEDGMENT_OBJECT.objectApiName,
    listViewApiName: ACKNOWLEDGMENT_LIST_VIEW,
    fields: ACKNOWLEDGMENT_REQUIRED_FIELDS,
    optionalFields: ACKNOWLEDGMENT_OPTIONAL_FIELDS,
    pageSize: PAGE_SIZE
  })
  wiredAcknowledgments({ data, error }) {
    this.acknowledgments = (data?.records || []).map((record) => ({
      id: record.id,
      name: listValue(record, ACKNOWLEDGMENT_NAME),
      status: listValue(record, ACKNOWLEDGMENT_STATUS),
      matchStatus: listValue(record, ACKNOWLEDGMENT_MATCH_STATUS),
      patientControlNumber: listValue(record, ACKNOWLEDGMENT_PATIENT_CONTROL),
      processedAt: listValue(record, ACKNOWLEDGMENT_PROCESSED_AT)
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
    if (Array.isArray(error?.body)) {
      return (
        error.body
          .map((item) => item.message)
          .filter(Boolean)
          .join("; ") || "Unable to load billing work."
      );
    }
    return (
      error?.body?.message || error?.message || "Unable to load billing work."
    );
  }
}
