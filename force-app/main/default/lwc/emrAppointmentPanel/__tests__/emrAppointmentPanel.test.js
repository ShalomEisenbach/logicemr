import { createElement } from "lwc";
import EmrAppointmentPanel from "c/emrAppointmentPanel";
import getAppointments from "@salesforce/apex/AppointmentPanelController.getAppointments";

jest.mock(
  "@salesforce/apex/AppointmentPanelController.getAppointments",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function dateAt(dayOffset, hour = 12) {
  const value = new Date();
  value.setHours(hour, 0, 0, 0);
  value.setDate(value.getDate() + dayOffset);
  return value.toISOString();
}

function appointment(id, start, status) {
  return {
    Id: id,
    Start__c: start,
    Status__c: status,
    Appointment_Type__c: "Follow-up"
  };
}

describe("c-emr-appointment-panel", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("requests and renders the default upcoming-only view", async () => {
    const element = createElement("c-emr-appointment-panel", {
      is: EmrAppointmentPanel
    });
    element.recordId = "001000000000001AAA";
    document.body.appendChild(element);
    await flushPromises();

    expect(getAppointments.getLastConfig()).toEqual({
      patientId: "001000000000001AAA",
      upcomingOnly: true
    });
    getAppointments.emit([
      appointment("a01", dateAt(0), "Proposed"),
      appointment("a02", dateAt(1), "Booked")
    ]);
    await flushPromises();
    await flushPromises();

    const table = element.shadowRoot.querySelector("lightning-datatable");
    const panel = element.shadowRoot.querySelector("c-emr-chart-panel");
    expect(table.data.map((row) => row.Id)).toEqual(["a01", "a02"]);
    expect(panel.count).toBe(2);
  });

  it("requests and renders all appointments when Upcoming only is toggled off", async () => {
    const element = createElement("c-emr-appointment-panel", {
      is: EmrAppointmentPanel
    });
    element.recordId = "001000000000001AAA";
    document.body.appendChild(element);
    await flushPromises();

    getAppointments.emit([appointment("a01", dateAt(1), "Booked")]);
    await flushPromises();
    await flushPromises();

    const toggle = element.shadowRoot.querySelector("lightning-input");
    toggle.checked = false;
    toggle.dispatchEvent(new CustomEvent("change"));
    await flushPromises();

    expect(getAppointments.getLastConfig()).toEqual({
      patientId: "001000000000001AAA",
      upcomingOnly: false
    });
    getAppointments.emit([
      appointment("a01", dateAt(1), "Booked"),
      appointment("a02", dateAt(-1), "Fulfilled"),
      appointment("a03", dateAt(1), "Arrived")
    ]);
    await flushPromises();
    await flushPromises();

    const table = element.shadowRoot.querySelector("lightning-datatable");
    const panel = element.shadowRoot.querySelector("c-emr-chart-panel");
    expect(table.data).toHaveLength(3);
    expect(panel.count).toBe(3);
  });
});
