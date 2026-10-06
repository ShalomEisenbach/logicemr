import { createElement } from "lwc";
import EmrAppointmentBooking from "c/emrAppointmentBooking";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import bookAppointment from "@salesforce/apex/AppointmentBookingController.bookAppointment";
import getLocations from "@salesforce/apex/AppointmentBookingController.getLocations";

jest.mock(
  "@salesforce/apex/AppointmentBookingController.bookAppointment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AppointmentBookingController.getLocations",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());
function permission(objectApiName, data) {
  getObjectInfo.emit(
    data,
    (config) =>
      (config.objectApiName?.objectApiName || config.objectApiName) ===
      objectApiName
  );
}

describe("appointment booking permissions", () => {
  afterEach(() => {
    document.body.replaceChildren();
    jest.clearAllMocks();
  });

  it("disables booking for a read-only slot user and enables it for scheduling access", async () => {
    getLocations.mockResolvedValue([]);
    bookAppointment.mockResolvedValue({
      appointmentId: "appointment1",
      appointmentName: "Booked appointment"
    });
    const element = createElement("c-emr-appointment-booking", {
      is: EmrAppointmentBooking
    });
    document.body.appendChild(element);
    element.beginFromSlot({
      id: "slot1",
      startTime: "2026-10-06T14:00:00Z",
      endTime: "2026-10-06T14:20:00Z"
    });
    permission("Appointment__c", { createable: true, updateable: true });
    permission("Slot__c", {
      updateable: false,
      fields: { Status__c: { updateable: false } }
    });
    await flush();
    element.shadowRoot
      .querySelector("lightning-record-picker")
      .dispatchEvent(
        new CustomEvent("change", { detail: { recordId: "patient1" } })
      );
    element.shadowRoot
      .querySelector("lightning-combobox")
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: "Checkup" } })
      );
    await flush();
    let button = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((item) => item.label === "Book");
    expect(button.disabled).toBe(true);
    button.click();
    expect(bookAppointment).not.toHaveBeenCalled();
    expect(
      element.shadowRoot.querySelector('[role="status"]').textContent
    ).toContain("requires scheduling access");
    permission("Slot__c", {
      updateable: true,
      fields: { Status__c: { updateable: true } }
    });
    await flush();
    button = [...element.shadowRoot.querySelectorAll("lightning-button")].find(
      (item) => item.label === "Book"
    );
    expect(button.disabled).toBe(false);
    button.click();
    await flush();
    expect(bookAppointment).toHaveBeenCalledWith({
      patientId: "patient1",
      slotId: "slot1",
      appointmentType: "Checkup",
      reason: ""
    });
  });
});
