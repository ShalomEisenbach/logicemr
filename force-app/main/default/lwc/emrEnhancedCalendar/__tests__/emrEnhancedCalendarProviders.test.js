import { createElement } from "lwc";
import EmrEnhancedCalendar from "c/emrEnhancedCalendar";
import getGrid from "@salesforce/apex/AppointmentCalendarController.getGrid";
import getLocations from "@salesforce/apex/AppointmentCalendarController.getLocations";
import getActiveSchedules from "@salesforce/apex/AppointmentCalendarController.getActiveSchedules";
import getNextAvailability from "@salesforce/apex/AppointmentCalendarController.getNextAvailability";
import {
  ROW_HEIGHT,
  assignProviderLanes
} from "../emrEnhancedCalendarLogic";

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

// Synthetic providers and patients only.
function slot(id, practitionerId, practitionerName, start, end, extra = {}) {
  return {
    id,
    startTime: `2026-10-06T${start}:00Z`,
    endTime: `2026-10-06T${end}:00Z`,
    status: "Free",
    practitionerId,
    practitionerName,
    locationName: `${practitionerName} Clinic`,
    ...extra
  };
}

function booked(id, practitionerId, practitionerName, start, end, patient) {
  return slot(id, practitionerId, practitionerName, start, end, {
    status: "Busy",
    appointment: {
      id: `appt-${id}`,
      status: "Booked",
      patientName: patient,
      patientId: `pt-${id}`
    }
  });
}

async function mount(slots, props = {}) {
  getLocations.mockResolvedValue([]);
  getActiveSchedules.mockResolvedValue([]);
  getNextAvailability.mockResolvedValue([]);
  getGrid.mockResolvedValue({ slots });
  const element = createElement("c-emr-enhanced-calendar", {
    is: EmrEnhancedCalendar
  });
  Object.assign(element, props);
  document.body.appendChild(element);
  await flush();
  return element;
}

describe("provider lanes", () => {
  it("gives each provider a run of lanes in name order", () => {
    const packing = assignProviderLanes([
      slot("p1", "patel", "Patel, Priya", "14:00", "14:30"),
      slot("l1", "lee", "Lee, Jordan", "14:00", "14:20"),
      slot("l2", "lee", "Lee, Jordan", "14:20", "14:40"),
      // The same provider in two places at once still sits side by side.
      slot("p2", "patel", "Patel, Priya", "14:00", "14:20", {
        locationName: "Telehealth"
      })
    ]);

    expect(packing.providers.map((p) => p.name)).toEqual([
      "Lee, Jordan",
      "Patel, Priya"
    ]);
    expect(packing.providers[0]).toMatchObject({ startLane: 0, span: 1 });
    expect(packing.providers[1]).toMatchObject({ startLane: 1, span: 2 });
    expect(packing.providers[1].locations).toEqual([
      "Patel, Priya Clinic",
      "Telehealth"
    ]);
    expect(packing.laneCount).toBe(3);
    expect(packing.lanes.get("l1")).toBe(0);
    expect(packing.lanes.get("l2")).toBe(0);
    expect(packing.lanes.get("p1")).not.toBe(packing.lanes.get("p2"));
    expect(packing.lanes.get("p1")).toBeGreaterThanOrEqual(1);
    expect(packing.lanes.get("p2")).toBeGreaterThanOrEqual(1);
  });

  it("handles nothing and slots with no provider", () => {
    expect(assignProviderLanes([])).toMatchObject({
      laneCount: 1,
      providers: []
    });
    const packing = assignProviderLanes([
      { id: "x", startTime: "2026-10-06T14:00:00Z", endTime: "2026-10-06T14:20:00Z" }
    ]);
    expect(packing.providers[0].name).toBe("Unassigned");
  });

  it("makes a slot row tall enough for an appointment's two lines", () => {
    expect(ROW_HEIGHT).toBeGreaterThanOrEqual(34);
  });
});

describe("calendar day grouped by provider", () => {
  afterEach(() => {
    document.body.replaceChildren();
    jest.clearAllMocks();
    jest.useRealTimers();
  });

  it("heads each provider's column and drops the provider's name from the cards under it", async () => {
    jest.useFakeTimers().setSystemTime(new Date("2026-10-06T16:00:00Z"));
    const element = await mount([
      booked("b1", "patel", "Patel, Priya", "14:00", "14:30", "Synthetic Ada"),
      slot("f1", "lee", "Lee, Jordan", "14:00", "14:20"),
      slot("f2", "lee", "Lee, Jordan", "14:20", "14:40")
    ]);

    const heads = [
      ...element.shadowRoot.querySelectorAll('[data-id="provider-head"]')
    ];
    expect(heads.map((h) => h.querySelector(".provider-name").textContent)).toEqual(
      ["Lee, Jordan", "Patel, Priya"]
    );
    expect(heads[0].style.left).toBe("0%");
    expect(heads[0].style.width).toBe("50%");
    expect(heads[1].style.left).toBe("50%");
    expect(heads[0].querySelector(".provider-meta").textContent).toBe(
      "Lee, Jordan Clinic"
    );

    // Lee's openings sit in Lee's half, Patel's appointment in Patel's.
    const free = element.shadowRoot.querySelector('[data-slot-id="f1"]');
    expect(free.style.left).toContain("0%");
    expect(free.querySelector(".slot-time").textContent).not.toBe("");
    const block = element.shadowRoot.querySelector(".block");
    expect(block.style.left).toContain("50%");
    expect(block.querySelector(".block-label").textContent).toBe("Synthetic Ada");
    const meta = block.querySelector(".block-meta").textContent;
    expect(meta).toContain("Booked");
    expect(meta).toContain("Patel, Priya Clinic");
    expect(meta).not.toContain("Patel, Priya ·");
    // The full context is still on the card for hover and screen readers.
    expect(block.title).toContain("Patel, Priya");
  });

  it("shows no provider headings for one provider, or in week view", async () => {
    jest.useFakeTimers().setSystemTime(new Date("2026-10-06T16:00:00Z"));
    const element = await mount([
      slot("f1", "lee", "Lee, Jordan", "14:00", "14:20"),
      booked("b1", "lee", "Lee, Jordan", "14:20", "14:40", "Synthetic Bram")
    ]);
    expect(element.shadowRoot.querySelector('[data-id="provider-row"]')).toBeNull();
    // With no heading above it, the card names the provider itself.
    expect(
      element.shadowRoot.querySelector(".block .block-meta").textContent
    ).toContain("Lee, Jordan");
    document.body.replaceChildren();

    const two = await mount([
      slot("f1", "lee", "Lee, Jordan", "14:00", "14:20"),
      slot("p1", "patel", "Patel, Priya", "14:00", "14:30")
    ]);
    expect(two.shadowRoot.querySelector('[data-id="provider-row"]')).not.toBeNull();
    const view = two.shadowRoot.querySelector("lightning-radio-group");
    view.dispatchEvent(new CustomEvent("change", { detail: { value: "week" } }));
    await flush();
    expect(two.shadowRoot.querySelector('[data-id="provider-row"]')).toBeNull();
  });
});
