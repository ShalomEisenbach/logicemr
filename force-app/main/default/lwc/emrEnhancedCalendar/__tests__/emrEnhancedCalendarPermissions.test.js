import { createElement } from "lwc";
import EmrEnhancedCalendar from "c/emrEnhancedCalendar";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import getGrid from "@salesforce/apex/AppointmentCalendarController.getGrid";
import getLocations from "@salesforce/apex/AppointmentCalendarController.getLocations";
import getActiveSchedules from "@salesforce/apex/AppointmentCalendarController.getActiveSchedules";
import getNextAvailability from "@salesforce/apex/AppointmentCalendarController.getNextAvailability";

jest.mock(
  "@salesforce/schema/Slot__c",
  () => ({ default: { objectApiName: "lfemr__Slot__c" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/Slot__c.Status__c",
  () => ({
    default: {
      objectApiName: "lfemr__Slot__c",
      fieldApiName: "lfemr__Status__c"
    }
  }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/AppointmentCalendarController.getGrid",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AppointmentCalendarController.getLocations",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AppointmentCalendarController.getActiveSchedules",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AppointmentCalendarController.getNextAvailability",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
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

describe("calendar permissions", () => {
  afterEach(() => {
    document.body.replaceChildren();
    jest.clearAllMocks();
    jest.useRealTimers();
  });

  it("preserves clinician arrival/no-show while suppressing slot mutations", async () => {
    jest.useFakeTimers().setSystemTime(new Date("2026-10-06T16:00:00Z"));
    getLocations.mockResolvedValue([]);
    getActiveSchedules.mockResolvedValue([]);
    getNextAvailability.mockResolvedValue([]);
    getGrid.mockResolvedValue({
      slots: [
        {
          id: "booked-slot",
          startTime: "2026-10-06T14:00:00Z",
          endTime: "2026-10-06T14:20:00Z",
          status: "Busy",
          appointment: {
            id: "appointment1",
            status: "Booked",
            patientName: "Maya",
            patientId: "patient1"
          }
        },
        {
          id: "free-slot",
          startTime: "2026-10-06T14:20:00Z",
          endTime: "2026-10-06T14:40:00Z",
          status: "Free"
        }
      ]
    });
    const element = createElement("c-emr-enhanced-calendar", {
      is: EmrEnhancedCalendar
    });
    element.practitionerId = "provider1";
    document.body.appendChild(element);
    permission("Appointment__c", { createable: true, updateable: true });
    permission("Encounter__c", { createable: true });
    permission("lfemr__Slot__c", {
      createable: false,
      updateable: false,
      fields: { lfemr__Status__c: { updateable: false } }
    });
    await flush();
    const free = element.shadowRoot.querySelector('[data-slot-id="free-slot"]');
    expect(free.disabled).toBe(true);
    const block = element.shadowRoot.querySelector(".block");
    expect(block.classList.contains("block_draggable")).toBe(false);
    block.dispatchEvent(
      new MouseEvent("pointerdown", { bubbles: true, button: 0 })
    );
    await flush();
    let labels = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].map((item) => item.label);
    expect(labels).toContain("Arrive");
    expect(labels).toContain("No Show");
    expect(labels).not.toContain("Cancel");
    expect(
      element.shadowRoot.querySelector('lightning-input[type="toggle"]')
    ).toBeNull();
    permission("lfemr__Slot__c", {
      createable: true,
      updateable: true,
      fields: {
        lfemr__Status__c: { updateable: false },
        Status__c: { updateable: true }
      }
    });
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-slot-id="free-slot"]').disabled
    ).toBe(true);
    expect(
      [...element.shadowRoot.querySelectorAll("lightning-button")].map(
        (item) => item.label
      )
    ).not.toContain("Cancel");
    expect(
      element.shadowRoot
        .querySelector(".block")
        .classList.contains("block_draggable")
    ).toBe(false);
    permission("lfemr__Slot__c", {
      createable: true,
      updateable: true,
      fields: {
        lfemr__Status__c: { updateable: true },
        Status__c: { updateable: false }
      }
    });
    await flush();
    labels = [...element.shadowRoot.querySelectorAll("lightning-button")].map(
      (item) => item.label
    );
    expect(labels).toContain("Cancel");
    expect(
      element.shadowRoot
        .querySelector(".block")
        .classList.contains("block_draggable")
    ).toBe(true);
    expect(
      element.shadowRoot.querySelector('[data-slot-id="free-slot"]').disabled
    ).toBe(false);
  });
});
