import { createElement } from "lwc";
import EmrBillingHome from "c/emrBillingHome";
import { getListRecordsByName } from "lightning/uiListsApi";

jest.mock("lightning/uiListsApi", () => {
  const { createLdsTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
  return { getListRecordsByName: createLdsTestWireAdapter(jest.fn()) };
});
jest.mock(
  "@salesforce/schema/Superbill__c",
  () => ({
    default: { objectApiName: "lfemr__Superbill__c" }
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/Claim_Submission__c",
  () => ({
    default: { objectApiName: "lfemr__Claim_Submission__c" }
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/Claim_Acknowledgment__c",
  () => ({
    default: { objectApiName: "lfemr__Claim_Acknowledgment__c" }
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/Superbill__c.Status__c",
  () => ({
    default: {
      objectApiName: "lfemr__Superbill__c",
      fieldApiName: "lfemr__Status__c"
    }
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/Superbill__c.Name",
  () => ({
    default: {
      objectApiName: "lfemr__Superbill__c",
      fieldApiName: "lfemr__Superbill__c.Name"
    }
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/Claim_Submission__c.Name",
  () => ({ default: "lfemr__Claim_Submission__c.Name" }),
  { virtual: true }
);

const field = (value, displayValue = null) => ({ value, displayValue });
const record = (apiName, id, fields) => ({
  apiName,
  id,
  fields,
  childRelationships: {},
  recordTypeId: "012000000000000AAA",
  recordTypeInfo: null,
  weakEtag: 1
});

describe("Billing Home in a namespaced org", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("qualifies all three list-view names from schema imports", async () => {
    const element = createElement("c-emr-billing-home", { is: EmrBillingHome });
    document.body.appendChild(element);
    await Promise.resolve();
    const configs = [];
    getListRecordsByName.emit({ records: [] }, (config) => {
      configs.push(config);
      return false;
    });
    expect(configs).toEqual([
      {
        objectApiName: "lfemr__Superbill__c",
        listViewApiName: "lfemr__Claim_Readiness_Work_Queue",
        fields: ["lfemr__Superbill__c.Name"],
        optionalFields: [
          "lfemr__Superbill__c.lfemr__Status__c",
          "lfemr__Superbill__c.lfemr__Date_of_Service__c",
          "lfemr__Superbill__c.lfemr__Patient__c",
          "lfemr__Superbill__c.lfemr__Patient__r.Name"
        ],
        pageSize: 20
      },
      {
        objectApiName: "lfemr__Claim_Submission__c",
        listViewApiName: "lfemr__Recent_Submissions",
        fields: ["lfemr__Claim_Submission__c.Name"],
        optionalFields: [
          "lfemr__Claim_Submission__c.lfemr__Status__c",
          "lfemr__Claim_Submission__c.lfemr__Provider_Used__c",
          "lfemr__Claim_Submission__c.lfemr__Submitted_At__c"
        ],
        pageSize: 20
      },
      {
        objectApiName: "lfemr__Claim_Acknowledgment__c",
        listViewApiName: "lfemr__Recent_Acknowledgments",
        fields: ["lfemr__Claim_Acknowledgment__c.Name"],
        optionalFields: [
          "lfemr__Claim_Acknowledgment__c.lfemr__Status__c",
          "lfemr__Claim_Acknowledgment__c.lfemr__Match_Status__c",
          "lfemr__Claim_Acknowledgment__c.lfemr__Patient_Control_Number__c",
          "lfemr__Claim_Acknowledgment__c.lfemr__Processed_At__c"
        ],
        pageSize: 20
      }
    ]);
  });

  it("renders namespaced List API field envelopes and lookup relationship names", async () => {
    const element = createElement("c-emr-billing-home", { is: EmrBillingHome });
    document.body.appendChild(element);
    await Promise.resolve();
    const rows = [
      record("lfemr__Superbill__c", "a01000000000001AAA", {
        Name: field("SB-00000001"),
        lfemr__Status__c: field("Ready"),
        lfemr__Date_of_Service__c: field("2026-10-06"),
        lfemr__Patient__c: field("a02000000000001AAA"),
        lfemr__Patient__r: field(
          record("lfemr__Patient__c", "a02000000000001AAA", {
            Name: field("Test Patient")
          })
        )
      }),
      record("lfemr__Claim_Submission__c", "a03000000000001AAA", {
        Name: field("CLMSUB-00000001"),
        lfemr__Status__c: field("Submitted"),
        lfemr__Provider_Used__c: field("Stedi"),
        lfemr__Submitted_At__c: field("2026-10-06T12:00:00.000Z")
      }),
      record("lfemr__Claim_Acknowledgment__c", "a04000000000001AAA", {
        Name: field("CLMACK-00000001"),
        lfemr__Status__c: field("Accepted"),
        lfemr__Match_Status__c: field("Matched"),
        lfemr__Patient_Control_Number__c: field("CONTROL123"),
        lfemr__Processed_At__c: field("2026-10-06T13:00:00.000Z")
      })
    ];
    rows.forEach((row) => {
      getListRecordsByName.emit(
        { count: 1, records: [row], currentPageToken: "0", pageSize: 20 },
        (config) => config.objectApiName === row.apiName
      );
    });
    await Promise.resolve();
    const cards = element.shadowRoot.querySelectorAll("lightning-card");
    const labels = ["SB-00000001", "CLMSUB-00000001", "CLMACK-00000001"];
    const texts = [
      ["Test Patient", "Ready"],
      ["Submitted", "Stedi"],
      ["Accepted", "Matched", "CONTROL123"]
    ];
    const dates = [
      "2026-10-06",
      "2026-10-06T12:00:00.000Z",
      "2026-10-06T13:00:00.000Z"
    ];
    cards.forEach((card, index) => {
      const link = card.querySelector("c-emr-record-link");
      expect(link.label).toBe(labels[index]);
      expect(link.recordId).toBe(rows[index].id);
      expect(link.objectApiName).toBe(rows[index].apiName);
      texts[index].forEach((text) => expect(card.textContent).toContain(text));
      expect(card.querySelector("lightning-formatted-date-time").value).toBe(
        dates[index]
      );
      expect(card.querySelector('[role="alert"]')).toBeNull();
    });
    expect(cards[0].textContent).not.toContain("a02000000000001AAA");
  });

  it("prefers a lookup display value and handles omitted optional fields", async () => {
    const element = createElement("c-emr-billing-home", { is: EmrBillingHome });
    document.body.appendChild(element);
    await Promise.resolve();
    getListRecordsByName.emit(
      {
        records: [
          record("lfemr__Superbill__c", "a01000000000001AAA", {
            Name: field("SB-00000001"),
            lfemr__Status__c: field("Needs Review"),
            lfemr__Patient__c: field("a02000000000001AAA", "Display Patient"),
            lfemr__Patient__r: field(
              record("lfemr__Patient__c", "a02000000000001AAA", {
                Name: field("Relationship Patient")
              })
            )
          })
        ]
      },
      (config) => config.objectApiName === "lfemr__Superbill__c"
    );
    await Promise.resolve();
    const card = element.shadowRoot.querySelector("lightning-card");
    expect(card.textContent).toContain("Display Patient");
    expect(card.textContent).not.toContain("Relationship Patient");
    expect(card.textContent).toContain("Needs Review");
    expect(
      card.querySelector("lightning-formatted-date-time").value
    ).toBeUndefined();
    expect(card.querySelector('[role="alert"]')).toBeNull();
  });
});
