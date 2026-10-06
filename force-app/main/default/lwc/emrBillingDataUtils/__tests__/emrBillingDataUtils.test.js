import { normalizeBillingRecord } from "c/emrBillingDataUtils";

describe("billing Apex SObject field names", () => {
  it("normalizes installed-package fields and related records without changing another namespace", () => {
    const result = normalizeBillingRecord(
      [
        {
          Id: "bill",
          lfemr__Status__c: "Ready",
          lfemr__Coverage__r: { lfemr__Payer__r: { Name: "Payer" } },
          other__Reference__c: "external"
        }
      ],
      "lfemr__Superbill__c"
    );
    expect(result).toEqual([
      {
        Id: "bill",
        Status__c: "Ready",
        Coverage__r: { Payer__r: { Name: "Payer" } },
        other__Reference__c: "external"
      }
    ]);
  });

  it("preserves unnamespaced records, DTOs, and empty values", () => {
    const plain = { Id: "bill", Status__c: "Ready" };
    expect(normalizeBillingRecord(plain, "Superbill__c")).toBe(plain);
    expect(
      normalizeBillingRecord({ status: "Ready" }, "lfemr__Superbill__c")
    ).toEqual({ status: "Ready" });
    expect(normalizeBillingRecord(null, "lfemr__Superbill__c")).toBeNull();
  });
});
