import { createElement } from "lwc";
import EmrSearchableSelect from "c/emrSearchableSelect";

// Synthetic providers only.
const OPTIONS = [
  { value: "chen", label: "Chen, Marcus - Emergency Medicine" },
  { value: "lee", label: "Lee, Jordan - Primary Care" },
  { value: "patel", label: "Patel, Priya - Cardiology", meta: "Telehealth" }
];

const flush = () => Promise.resolve().then(() => Promise.resolve());

function mount(props = {}) {
  const element = createElement("c-emr-searchable-select", {
    is: EmrSearchableSelect
  });
  Object.assign(
    element,
    { label: "Provider", allLabel: "All providers", options: OPTIONS },
    props
  );
  document.body.appendChild(element);
  return element;
}

const input = (element) => element.shadowRoot.querySelector("input");
const labels = (element) =>
  [...element.shadowRoot.querySelectorAll('[data-id="option"]')].map(
    (row) => row.querySelector(".option-label").textContent
  );

function type(element, text) {
  const box = input(element);
  box.value = text;
  box.dispatchEvent(new CustomEvent("input"));
}

function key(element, name) {
  input(element).dispatchEvent(
    new KeyboardEvent("keydown", { key: name, bubbles: true, cancelable: true })
  );
}

describe("c-emr-searchable-select", () => {
  afterEach(() => {
    document.body.replaceChildren();
  });

  it("lists every option, with the all row first, as soon as it opens", async () => {
    const element = mount();
    expect(input(element).placeholder).toBe("All providers");
    expect(input(element).getAttribute("aria-expanded")).toBe("false");

    input(element).dispatchEvent(new CustomEvent("focus"));
    await flush();

    expect(input(element).getAttribute("aria-expanded")).toBe("true");
    expect(labels(element)).toEqual([
      "All providers",
      "Chen, Marcus - Emergency Medicine",
      "Lee, Jordan - Primary Care",
      "Patel, Priya - Cardiology"
    ]);
  });

  it("narrows as you type, matching the label or the meta, whatever the case", async () => {
    const element = mount();
    input(element).dispatchEvent(new CustomEvent("focus"));
    type(element, "PRI");
    await flush();
    expect(labels(element)).toEqual([
      "Lee, Jordan - Primary Care",
      "Patel, Priya - Cardiology"
    ]);

    type(element, "tele");
    await flush();
    expect(labels(element)).toEqual(["Patel, Priya - Cardiology"]);

    type(element, "zzz");
    await flush();
    expect(labels(element)).toEqual([]);
    expect(
      element.shadowRoot.querySelector('[data-id="no-match"]').textContent
    ).toContain("No matches");
  });

  it("picks with the mouse, shows the pick, and fires change once", async () => {
    const element = mount();
    const handler = jest.fn();
    element.addEventListener("change", handler);
    input(element).dispatchEvent(new CustomEvent("focus"));
    await flush();

    const lee = [
      ...element.shadowRoot.querySelectorAll('[data-id="option"]')
    ].find((row) => row.dataset.value === "lee");
    lee.dispatchEvent(new MouseEvent("mousedown", { cancelable: true }));
    await flush();

    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toEqual({
      value: "lee",
      label: "Lee, Jordan - Primary Care"
    });
    expect(element.value).toBe("lee");
    expect(input(element).value).toBe("Lee, Jordan - Primary Care");
    expect(input(element).getAttribute("aria-expanded")).toBe("false");

    // Picking the same one again is not a change.
    input(element).dispatchEvent(new CustomEvent("focus"));
    await flush();
    [...element.shadowRoot.querySelectorAll('[data-id="option"]')]
      .find((row) => row.dataset.value === "lee")
      .dispatchEvent(new MouseEvent("mousedown", { cancelable: true }));
    await flush();
    expect(handler).toHaveBeenCalledTimes(1);
  });

  it("works from the keyboard: arrows move, Enter picks, Escape closes", async () => {
    const element = mount();
    const handler = jest.fn();
    element.addEventListener("change", handler);

    key(element, "ArrowDown");
    await flush();
    expect(input(element).getAttribute("aria-expanded")).toBe("true");

    type(element, "p");
    await flush();
    // "All providers", "Lee … Primary Care", "Patel …" all contain a p; the first is active.
    key(element, "ArrowDown");
    key(element, "ArrowDown");
    await flush();
    const active = element.shadowRoot.querySelector(".slds-has-focus");
    expect(active.dataset.value).toBe("patel");
    expect(input(element).getAttribute("aria-activedescendant")).toContain(
      "option-2"
    );

    key(element, "Enter");
    await flush();
    expect(handler.mock.calls[0][0].detail.value).toBe("patel");
    expect(input(element).value).toBe("Patel, Priya - Cardiology");

    key(element, "ArrowDown");
    type(element, "le");
    await flush();
    key(element, "Escape");
    await flush();
    expect(input(element).getAttribute("aria-expanded")).toBe("false");
    // Escape abandons the search and keeps the pick.
    expect(input(element).value).toBe("Patel, Priya - Cardiology");
    expect(handler).toHaveBeenCalledTimes(1);
  });

  it("clears back to all, with the button or the all row", async () => {
    const element = mount({ value: "chen" });
    const handler = jest.fn();
    element.addEventListener("change", handler);
    await flush();
    expect(input(element).value).toBe("Chen, Marcus - Emergency Medicine");

    element.shadowRoot
      .querySelector('[data-id="clear"]')
      .dispatchEvent(new MouseEvent("mousedown", { cancelable: true }));
    await flush();
    expect(handler.mock.calls[0][0].detail).toEqual({
      value: null,
      label: "All providers"
    });
    expect(element.value).toBeNull();
    expect(input(element).value).toBe("");
    expect(element.shadowRoot.querySelector('[data-id="clear"]')).toBeNull();
  });

  it("follows a value set from outside, and closes on blur without picking", async () => {
    const element = mount();
    const handler = jest.fn();
    element.addEventListener("change", handler);
    element.value = "patel";
    await flush();
    expect(input(element).value).toBe("Patel, Priya - Cardiology");

    input(element).dispatchEvent(new CustomEvent("focus"));
    type(element, "chen");
    await flush();
    input(element).dispatchEvent(new CustomEvent("blur"));
    await flush();
    expect(input(element).getAttribute("aria-expanded")).toBe("false");
    expect(input(element).value).toBe("Patel, Priya - Cardiology");
    expect(handler).not.toHaveBeenCalled();
  });

  it("has no all row unless asked for one, and does nothing when disabled", async () => {
    const element = mount({ allLabel: undefined, disabled: true });
    input(element).dispatchEvent(new CustomEvent("focus"));
    await flush();
    expect(input(element).getAttribute("aria-expanded")).toBe("false");
    document.body.replaceChildren();

    const plain = mount({ allLabel: undefined });
    input(plain).dispatchEvent(new CustomEvent("focus"));
    await flush();
    expect(labels(plain)).toHaveLength(3);
  });
});
