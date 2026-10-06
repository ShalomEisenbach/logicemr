import { createElement } from "lwc";
import EmrProviderHome from "c/emrProviderHome";
import getHome from "@salesforce/apex/ProviderHomeController.getHome";

jest.mock(
  "@salesforce/apex/ProviderHomeController.getHome",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

describe("c-emr-provider-home dates", () => {
  afterEach(() => {
    document.body.replaceChildren();
    jest.clearAllMocks();
  });

  it("renders the stored birthday while retaining local appointment times", async () => {
    const element = createElement("c-emr-provider-home", {
      is: EmrProviderHome
    });
    document.body.appendChild(element);
    const start = "2026-10-06T14:00:00.000Z";
    getHome.emit({
      recentPatients: [
        {
          Id: "patient1",
          First_Name__c: "Maya",
          Date_of_Birth__c: "1988-03-14"
        }
      ],
      lists: {
        todaysAppointments: [
          {
            Id: "appointment1",
            Status__c: "Booked",
            Start__c: start,
            Patient__r: { First_Name__c: "Maya" }
          }
        ]
      }
    });
    await Promise.resolve();

    const cards = [...element.shadowRoot.querySelectorAll("lightning-card")];
    const recent = cards.find((card) => card.title === "Recent Patients");
    expect(recent.querySelector(".work-meta").textContent).toContain(
      new Date(1988, 2, 14).toLocaleDateString()
    );
    const appointments = cards.find(
      (card) => card.title === "Today's Appointments"
    );
    expect(appointments.querySelector(".work-meta").textContent).toContain(
      new Date(start).toLocaleString(undefined, {
        month: "short",
        day: "numeric",
        hour: "numeric",
        minute: "2-digit"
      })
    );
  });
});
