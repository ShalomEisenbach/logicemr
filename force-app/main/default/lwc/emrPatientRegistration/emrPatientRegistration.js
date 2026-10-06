import { LightningElement, api, wire } from "lwc";
import registerPatient from "@salesforce/apex/PatientRegistrationController.registerPatient";
import updatePatientDemographics from "@salesforce/apex/PatientRegistrationController.updatePatientDemographics";
import getPatientDemographics from "@salesforce/apex/PatientRegistrationController.getPatientDemographics";
import getCoverages from "@salesforce/apex/CoveragePanelController.getCoverages";
import saveCoverageDetails from "@salesforce/apex/CoveragePanelController.saveCoverageDetails";
import runCheck from "@salesforce/apex/EligibilityCheckController.runCheck";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import PATIENT_OBJECT from "@salesforce/schema/Patient__c";
import COVERAGE_OBJECT from "@salesforce/schema/Coverage__c";
import PAYER_OBJECT from "@salesforce/schema/Payer__c";
import PAYER_ACTIVE_FIELD from "@salesforce/schema/Payer__c.Active__c";
import hasRunEligibility from "@salesforce/customPermission/LogicEMR_Run_Eligibility";

function readField(record, objectApiName, fieldName) {
  const parts = objectApiName.split("__");
  const prefix = parts.length === 3 ? `${parts[0]}__` : "";
  return record?.[`${prefix}${fieldName}`];
}

export default class EmrPatientRegistration extends LightningElement {
  @api buttonLabel = "New Patient";
  @api buttonVariant = "neutral";

  isOpen = false;
  isSaving = false;
  isLoading = false;
  isEditMode = false;
  patientId;
  errorMessage;
  duplicates = [];
  mrn = "";
  firstName = "";
  lastName = "";
  dateOfBirth;
  sexAtBirth;
  phone = "";
  email = "";
  smsOptIn = false;
  status = "Active";
  street = "";
  city = "";
  state = "";
  postalCode = "";
  country = "US";
  coverageId;
  payerId;
  memberId = "";
  groupNumber = "";
  relationshipToSubscriber = "Self";
  subscriberName = "";
  subscriberDetails = {};
  checkEligibility = false;
  originalInsurance;
  coverageDetails;
  coverageLoadError;

  sexOptions = [
    { label: "Male", value: "Male" },
    { label: "Female", value: "Female" },
    { label: "Unknown", value: "Unknown" },
    { label: "Other", value: "Other" }
  ];

  statusOptions = [
    { label: "Active", value: "Active" },
    { label: "Inactive", value: "Inactive" }
  ];

  relationshipOptions = [
    { label: "Self", value: "Self" },
    { label: "Spouse", value: "Spouse" },
    { label: "Child", value: "Child" },
    { label: "Other", value: "Other" }
  ];

  payerFilter = {
    criteria: [
      {
        fieldPath: PAYER_ACTIVE_FIELD.fieldApiName,
        operator: "eq",
        value: true
      }
    ]
  };

  @wire(getObjectInfo, { objectApiName: PATIENT_OBJECT })
  patientObjectInfo;

  @wire(getObjectInfo, { objectApiName: COVERAGE_OBJECT })
  coverageObjectInfo;

  get canRegister() {
    return this.patientObjectInfo.data?.createable === true;
  }

  get canEdit() {
    return this.patientObjectInfo.data?.updateable === true;
  }

  get showNewButton() {
    return this.canRegister && !this.isEditMode;
  }

  get showCoverageSection() {
    const info = this.coverageObjectInfo.data;
    return (
      !this.coverageLoadError &&
      (info?.createable === true || info?.updateable === true)
    );
  }

  get canRunEligibility() {
    return hasRunEligibility === true;
  }

  get showSubscriberDetails() {
    return this.relationshipToSubscriber !== "Self";
  }

  get requiresSubscriberIdentity() {
    return (
      this.showSubscriberDetails &&
      this.subscriberDetails.memberIdIdentifiesPatient === false
    );
  }

  get payerObjectApiName() {
    return PAYER_OBJECT.objectApiName;
  }

  get modalTitle() {
    return this.isEditMode ? "Edit demographics" : "Register patient";
  }

  get saveLabel() {
    return this.isEditMode ? "Save" : "Register patient";
  }

  get mrnDisabled() {
    return !!this.patientId;
  }

  get hasDuplicates() {
    return this.duplicates.length > 0;
  }

  @api
  open() {
    this.isEditMode = false;
    this.patientId = undefined;
    this.isOpen = true;
    this.errorMessage = undefined;
    this.duplicates = [];
    this.isLoading = false;
    this.resetForm();
    this.checkEligibility = this.canRunEligibility;
  }

  @api
  async openForEdit(patientId) {
    if (!patientId) {
      return;
    }
    this.isEditMode = true;
    this.patientId = patientId;
    this.isOpen = true;
    this.errorMessage = undefined;
    this.duplicates = [];
    this.isLoading = true;
    this.resetForm();
    try {
      const row = await getPatientDemographics({ patientId });
      const value = (field) =>
        readField(row, PATIENT_OBJECT.objectApiName, field);
      this.mrn = value("MRN__c") || "";
      this.firstName = value("First_Name__c") || "";
      this.lastName = value("Last_Name__c") || "";
      this.dateOfBirth = value("Date_of_Birth__c") || undefined;
      this.sexAtBirth = value("Sex_at_Birth__c") || undefined;
      this.phone = value("Phone__c") || "";
      this.email = value("Email__c") || "";
      this.smsOptIn = value("SMS_Opt_In__c") === true;
      this.status = value("Status__c") || "Active";
      this.street = value("Street__c") || "";
      this.city = value("City__c") || "";
      this.state = value("State__c") || "";
      this.postalCode = value("Postal_Code__c") || "";
      this.country = value("Country__c") || "US";
      await this.loadPrimaryCoverage(patientId);
    } catch (error) {
      this.errorMessage = this.reduceError(error);
    } finally {
      this.isLoading = false;
    }
  }

  handleClose() {
    if (this.isSaving) return;
    if (this.patientId && !this.isEditMode) {
      this.dispatchEvent(
        new CustomEvent("patientcreated", {
          bubbles: true,
          composed: true,
          detail: { patientId: this.patientId, registrationIncomplete: true }
        })
      );
    }
    this.isOpen = false;
    this.reset();
  }

  handleInput(event) {
    const { name, value, checked, type } = event.target;
    this[name] = type === "checkbox" ? checked : value;
    this.duplicates = [];
    this.errorMessage = undefined;
  }

  handlePayerChange(event) {
    this.payerId = event.detail.recordId;
    this.duplicates = [];
    this.errorMessage = undefined;
  }

  handleSubscriberDetail(event) {
    const { name, value, checked, type } = event.target;
    this.subscriberDetails = {
      ...this.subscriberDetails,
      [name]: type === "checkbox" ? checked : value
    };
    this.duplicates = [];
    this.errorMessage = undefined;
  }

  async handleSave() {
    if (this.isSaving || this.isLoading) {
      return;
    }
    const inputs = [
      ...this.template.querySelectorAll("lightning-input, lightning-combobox")
    ];
    if (
      !inputs.reduce((valid, input) => input.reportValidity() && valid, true)
    ) {
      return;
    }
    if (
      this.requiresSubscriberIdentity &&
      (!this.subscriberDetails.subscriberFirstName?.trim() ||
        !this.subscriberDetails.subscriberLastName?.trim() ||
        !this.subscriberDetails.subscriberDateOfBirth)
    ) {
      this.errorMessage =
        "Enter the policyholder first name, last name, and date of birth.";
      return;
    }

    this.isSaving = true;
    this.errorMessage = undefined;
    this.duplicates = [];
    try {
      const demographics = this.buildDemographics();
      let savedPatientId = this.patientId;
      if (savedPatientId) {
        await updatePatientDemographics({ input: demographics });
      } else {
        const result = await registerPatient({ input: demographics });
        if (result?.duplicates?.length) {
          this.duplicates = result.duplicates.map((row) => ({
            ...row,
            MRN__c: readField(row, PATIENT_OBJECT.objectApiName, "MRN__c"),
            Date_of_Birth__c: readField(
              row,
              PATIENT_OBJECT.objectApiName,
              "Date_of_Birth__c"
            ),
            displayName:
              [
                readField(row, PATIENT_OBJECT.objectApiName, "Last_Name__c"),
                readField(row, PATIENT_OBJECT.objectApiName, "First_Name__c")
              ]
                .filter((part) => part)
                .join(", ") ||
              row.Name ||
              "Patient"
          }));
          this.errorMessage =
            "Potential duplicate found. Open the existing chart or change the details.";
          return;
        }
        if (!result?.patient?.Id) {
          return;
        }
        savedPatientId = result.patient.Id;
        this.patientId = savedPatientId;
      }

      await this.saveInsurance(savedPatientId);

      this.dispatchEvent(
        new CustomEvent(this.isEditMode ? "patientupdated" : "patientcreated", {
          bubbles: true,
          composed: true,
          detail: { patientId: savedPatientId }
        })
      );
      this.isOpen = false;
      this.reset();
    } catch (error) {
      const savedMessage =
        this.patientId && !this.isEditMode
          ? "The patient was registered. Retry to finish insurance and eligibility without registering again. "
          : "";
      this.errorMessage = savedMessage + this.reduceError(error);
    } finally {
      this.isSaving = false;
    }
  }

  handleUseExisting(event) {
    this.dispatchEvent(
      new CustomEvent("patientcreated", {
        bubbles: true,
        composed: true,
        detail: { patientId: event.currentTarget.dataset.id, existing: true }
      })
    );
    this.isOpen = false;
    this.reset();
  }

  reset() {
    this.isEditMode = false;
    this.patientId = undefined;
    this.isLoading = false;
    this.resetForm();
  }

  resetForm() {
    this.errorMessage = undefined;
    this.duplicates = [];
    this.mrn = "";
    this.firstName = "";
    this.lastName = "";
    this.dateOfBirth = undefined;
    this.sexAtBirth = undefined;
    this.phone = "";
    this.email = "";
    this.smsOptIn = false;
    this.status = "Active";
    this.street = "";
    this.city = "";
    this.state = "";
    this.postalCode = "";
    this.country = "US";
    this.coverageId = undefined;
    this.payerId = undefined;
    this.memberId = "";
    this.groupNumber = "";
    this.relationshipToSubscriber = "Self";
    this.subscriberName = "";
    this.subscriberDetails = {
      memberIdIdentifiesPatient: true,
      subscriberFirstName: "",
      subscriberLastName: "",
      subscriberDateOfBirth: null,
      subscriberSex: null,
      subscriberStreet: null,
      subscriberCity: null,
      subscriberState: null,
      subscriberPostalCode: null,
      subscriberCountry: null
    };
    this.checkEligibility = false;
    this.originalInsurance = undefined;
    this.coverageDetails = undefined;
    this.coverageLoadError = undefined;
  }

  buildDemographics() {
    return {
      patientId: this.patientId,
      mrn: this.mrn,
      firstName: this.firstName,
      lastName: this.lastName,
      dateOfBirth: this.dateOfBirth || null,
      sexAtBirth: this.sexAtBirth || null,
      phone: this.phone,
      email: this.email,
      smsOptIn: this.smsOptIn,
      status: this.status,
      street: this.street,
      city: this.city,
      state: this.state,
      postalCode: this.postalCode,
      country: this.country
    };
  }

  async loadPrimaryCoverage(patientId) {
    try {
      const rows = await getCoverages({ patientId });
      const value = (record, field) =>
        readField(record, COVERAGE_OBJECT.objectApiName, field);
      const first = rows
        ?.map((row) => row.coverage)
        .find(
          (coverage) =>
            value(coverage, "Status__c") === "Active" &&
            value(coverage, "Priority__c") === "Primary" &&
            value(coverage, "Type__c") === "Medical"
        );
      if (!first) {
        return;
      }
      this.coverageId = first.Id;
      this.payerId = value(first, "Payer__c");
      this.memberId = value(first, "Member_Id__c") || "";
      this.groupNumber = value(first, "Group_Number__c") || "";
      this.relationshipToSubscriber =
        value(first, "Relationship_to_Subscriber__c") || "Self";
      this.subscriberName = value(first, "Subscriber_Name__c") || "";
      this.subscriberDetails = {
        memberIdIdentifiesPatient:
          value(first, "Member_ID_Identifies_Patient__c") !== false,
        subscriberFirstName: value(first, "Subscriber_First_Name__c") ?? "",
        subscriberLastName: value(first, "Subscriber_Last_Name__c") ?? "",
        subscriberDateOfBirth:
          value(first, "Subscriber_Date_of_Birth__c") ?? null,
        subscriberSex: value(first, "Subscriber_Sex__c") ?? null,
        subscriberStreet: value(first, "Subscriber_Street__c") ?? null,
        subscriberCity: value(first, "Subscriber_City__c") ?? null,
        subscriberState: value(first, "Subscriber_State__c") ?? null,
        subscriberPostalCode: value(first, "Subscriber_Postal_Code__c") ?? null,
        subscriberCountry: value(first, "Subscriber_Country__c") ?? null
      };
      this.coverageDetails = {
        planName: value(first, "Plan_Name__c") ?? null,
        coverageType: value(first, "Type__c"),
        status: value(first, "Status__c"),
        effectiveStart: value(first, "Effective_Start__c") ?? null,
        effectiveEnd: value(first, "Effective_End__c") ?? null,
        priority: value(first, "Priority__c")
      };
      this.originalInsurance = this.insuranceValues();
    } catch {
      this.coverageLoadError =
        "Insurance could not be loaded. Demographics can still be saved; manage coverage from the patient chart.";
    }
  }

  async saveInsurance(patientId) {
    if (!this.showCoverageSection || !this.payerId || !patientId) {
      return;
    }
    const values = this.insuranceValues();
    if (
      !this.coverageId ||
      JSON.stringify(values) !== JSON.stringify(this.originalInsurance)
    ) {
      const coverage = await saveCoverageDetails({
        input: {
          coverageId: this.coverageId || null,
          patientId,
          ...values,
          ...(this.coverageDetails || {
            planName: null,
            coverageType: "Medical",
            status: "Active",
            effectiveStart: null,
            effectiveEnd: null,
            priority: "Primary"
          })
        }
      });
      if (!coverage?.Id) {
        throw new Error("Coverage could not be saved.");
      }
      this.coverageId = coverage.Id;
      this.originalInsurance = values;
    }
    if (this.checkEligibility && this.canRunEligibility && this.coverageId) {
      await runCheck({ coverageId: this.coverageId });
      this.checkEligibility = false;
    }
  }

  insuranceValues() {
    return {
      payerId: this.payerId,
      memberId: this.memberId,
      groupNumber: this.groupNumber,
      relationshipToSubscriber: this.relationshipToSubscriber || "Self",
      subscriberName: this.subscriberName,
      ...this.subscriberDetails
    };
  }

  reduceError(error) {
    if (error?.body?.message) {
      return error.body.message;
    }
    if (Array.isArray(error?.body)) {
      return error.body.map((item) => item.message).join(", ");
    }
    return error?.message || "Unable to save patient.";
  }
}
