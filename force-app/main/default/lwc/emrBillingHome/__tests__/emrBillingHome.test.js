import { createElement } from "lwc";
import EmrBillingHome from "c/emrBillingHome";
import { getListRecordsByName } from "lightning/uiListsApi";

jest.mock("lightning/uiListsApi", () => {
  const { createLdsTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
  return { getListRecordsByName: createLdsTestWireAdapter(jest.fn()) };
});

const OBJECT_VIEWS = [
  ["Superbill__c", "Claim_Readiness_Work_Queue"],
  ["Claim_Submission__c", "Recent_Submissions"],
  ["Claim_Acknowledgment__c", "Recent_Acknowledgments"]
];
const OPTIONAL_FIELDS = {
  Superbill__c: [
    "Status__c",
    "Date_of_Service__c",
    "Patient__c",
    "Patient__r.Name"
  ],
  Claim_Submission__c: ["Status__c", "Provider_Used__c", "Submitted_At__c"],
  Claim_Acknowledgment__c: [
    "Status__c",
    "Match_Status__c",
    "Patient_Control_Number__c",
    "Processed_At__c"
  ]
};
const flushPromises = () => Promise.resolve();

describe("Billing Home in an unpackaged org", () => {
  const prefix = "";

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  function mount() {
    const element = createElement("c-emr-billing-home", { is: EmrBillingHome });
    document.body.appendChild(element);
    return element;
  }

  it("requests all three views using each object's resolved namespace", async () => {
    mount();
    await flushPromises();
    const configs = [];
    getListRecordsByName.emit({ records: [] }, (config) => {
      configs.push(config);
      return false;
    });
    expect(configs).toHaveLength(3);
    for (const [objectName, viewName] of OBJECT_VIEWS) {
      expect(configs).toContainEqual({
        objectApiName: `${prefix}${objectName}`,
        listViewApiName: `${prefix}${viewName}`,
        fields: [`${objectName}.Name`],
        optionalFields: OPTIONAL_FIELDS[objectName].map(
          (field) => `${objectName}.${field}`
        ),
        pageSize: 20
      });
    }
  });

  it("renders records in the corresponding cards and keeps record links qualified", async () => {
    const element = mount();
    await flushPromises();
    const rows = [
      {
        id: "a01000000000001AAA",
        apiName: "Superbill__c",
        fields: {
          Name: { value: "SB-00000001" },
          Status__c: { value: "Ready" },
          Date_of_Service__c: { value: "2026-10-06" },
          Patient__c: {
            value: "a02000000000001AAA",
            displayValue: "Test Patient"
          }
        }
      },
      {
        id: "a03000000000001AAA",
        apiName: "Claim_Submission__c",
        fields: {
          Name: { value: "CLMSUB-00000001" },
          Status__c: { value: "Submitted" },
          Provider_Used__c: { value: "Stedi" },
          Submitted_At__c: { value: "2026-10-06T12:00:00.000Z" }
        }
      },
      {
        id: "a04000000000001AAA",
        apiName: "Claim_Acknowledgment__c",
        fields: {
          Name: { value: "CLMACK-00000001" },
          Status__c: { value: "Accepted" },
          Match_Status__c: { value: "Matched" },
          Patient_Control_Number__c: { value: "CONTROL123" },
          Processed_At__c: { value: "2026-10-06T13:00:00.000Z" }
        }
      }
    ];
    OBJECT_VIEWS.forEach(([objectName], index) => {
      getListRecordsByName.emit(
        { records: [rows[index]] },
        (config) => config.objectApiName === `${prefix}${objectName}`
      );
    });
    await flushPromises();
    const cards = element.shadowRoot.querySelectorAll("lightning-card");
    const expectedText = ["Test Patient", "Stedi", "CONTROL123"];
    cards.forEach((card, index) => {
      const link = card.querySelector("c-emr-record-link");
      expect(link.recordId).toBe(rows[index].id);
      expect(link.objectApiName).toBe(`${prefix}${OBJECT_VIEWS[index][0]}`);
      expect(link.label).toBe(rows[index].fields.Name.value);
      expect(card.textContent).toContain(expectedText[index]);
      expect(card.querySelector('[role="alert"]')).toBeNull();
    });
  });

  it("shows an actionable error per failed card and clears it when data recovers", async () => {
    const element = mount();
    await flushPromises();
    getListRecordsByName.error(
      [
        {
          errorCode: "NOT_FOUND",
          message: "The requested resource does not exist"
        }
      ],
      404,
      "Not Found"
    );
    await flushPromises();
    const alerts = element.shadowRoot.querySelectorAll('[role="alert"]');
    expect(alerts).toHaveLength(3);
    alerts.forEach((alert) =>
      expect(alert.textContent).toContain(
        "The requested resource does not exist"
      )
    );
    expect(element.shadowRoot.textContent).not.toContain(
      "No superbills need attention."
    );
    getListRecordsByName.emit({ records: [] });
    await flushPromises();
    expect(element.shadowRoot.querySelector('[role="alert"]')).toBeNull();
    expect(element.shadowRoot.textContent).toContain(
      "No superbills need attention."
    );
    expect(element.shadowRoot.textContent).toContain(
      "No claim submissions yet."
    );
    expect(element.shadowRoot.textContent).toContain(
      "No claim acknowledgments yet."
    );
  });
});
