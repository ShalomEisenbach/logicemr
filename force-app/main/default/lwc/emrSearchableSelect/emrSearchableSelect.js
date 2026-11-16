import { LightningElement, api } from "lwc";

/**
 * A dropdown that lists every option and narrows as you type.
 *
 * Opening it shows the whole list, with an "all" row first when allLabel is set. Typing filters by the
 * option's label and meta. Arrow keys move, Enter picks, Escape closes; a pick fires change.
 *
 * @api label        Field label.
 * @api placeholder  Shown when nothing is picked.
 * @api allLabel     Label of the row that clears the pick ("All providers"). Leave blank for no such row.
 * @api options      [{ value, label, meta? }]
 * @api value        The picked option's value; blank for none.
 * @api disabled
 * Events: change, detail { value, label } (value is null for the "all" row).
 */
const ALL = "";

export default class EmrSearchableSelect extends LightningElement {
  @api label;
  @api placeholder;
  @api allLabel;
  @api disabled = false;

  _options = [];
  _value = ALL;
  query = "";
  isOpen = false;
  isTyping = false;
  activeIndex = -1;

  @api
  get options() {
    return this._options;
  }
  set options(value) {
    this._options = Array.isArray(value) ? value : [];
  }

  @api
  get value() {
    return this._value || null;
  }
  set value(value) {
    this._value = value || ALL;
  }

  get selected() {
    return this._options.find((option) => option.value === this._value);
  }

  /** While typing the box shows the search text; otherwise the pick. */
  get inputValue() {
    if (this.isTyping) {
      return this.query;
    }
    return this.selected ? this.selected.label : "";
  }

  get inputPlaceholder() {
    return this.placeholder || this.allLabel || "";
  }

  get showClear() {
    return !this.disabled && !!this.selected && !!this.allLabel;
  }

  get comboboxClass() {
    return this.isOpen
      ? "slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click slds-is-open"
      : "slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click";
  }

  get expanded() {
    return this.isOpen ? "true" : "false";
  }

  /** The rows to show: the "all" row, then the options that match what was typed. */
  get rows() {
    const needle = this.isTyping ? this.query.trim().toLowerCase() : "";
    const matches = (text) =>
      !needle ||
      String(text || "")
        .toLowerCase()
        .includes(needle);
    const rows = [];
    if (this.allLabel && matches(this.allLabel)) {
      rows.push({ value: ALL, label: this.allLabel, meta: "" });
    }
    this._options.forEach((option) => {
      if (matches(option.label) || matches(option.meta)) {
        rows.push({
          value: option.value,
          label: option.label,
          meta: option.meta || ""
        });
      }
    });
    return rows.map((row, index) => ({
      ...row,
      key: row.value || "all",
      domId: `option-${index}`,
      selected: row.value === this._value ? "true" : "false",
      className: [
        "slds-media slds-listbox__option slds-listbox__option_plain slds-media_small",
        index === this.activeIndex ? "slds-has-focus" : "",
        row.value === this._value ? "slds-is-selected" : ""
      ]
        .filter(Boolean)
        .join(" ")
    }));
  }

  get noRows() {
    return this.rows.length === 0;
  }

  get activeDomId() {
    const row = this.rows[this.activeIndex];
    return row ? row.domId : null;
  }

  open() {
    if (this.disabled || this.isOpen) {
      return;
    }
    this.isOpen = true;
    this.activeIndex = Math.max(
      0,
      this.rows.findIndex((row) => row.value === this._value)
    );
  }

  close() {
    this.isOpen = false;
    this.isTyping = false;
    this.query = "";
    this.activeIndex = -1;
  }

  handleFocus(event) {
    this.open();
    // The pick is selected so that typing replaces it instead of adding to it.
    if (event.target && typeof event.target.select === "function") {
      event.target.select();
    }
  }

  handleClick() {
    this.open();
  }

  handleInput(event) {
    this.query = event.target.value || "";
    this.isTyping = true;
    this.isOpen = true;
    this.activeIndex = this.rows.length ? 0 : -1;
  }

  handleKeyDown(event) {
    const rows = this.rows;
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      if (!this.isOpen) {
        this.open();
        return;
      }
      if (!rows.length) {
        return;
      }
      const step = event.key === "ArrowDown" ? 1 : -1;
      this.activeIndex =
        (this.activeIndex + step + rows.length) % rows.length;
    } else if (event.key === "Enter") {
      if (this.isOpen && rows[this.activeIndex]) {
        event.preventDefault();
        this.pick(rows[this.activeIndex]);
      }
    } else if (event.key === "Escape") {
      if (this.isOpen) {
        event.stopPropagation();
        this.close();
      }
    }
  }

  handleBlur() {
    this.close();
  }

  /** mousedown, not click: the pick has to land before the input's blur closes the list. */
  handleOptionMouseDown(event) {
    event.preventDefault();
    const value = event.currentTarget.dataset.value || ALL;
    const row = this.rows.find((item) => item.value === value);
    if (row) {
      this.pick(row);
    }
  }

  handleClear(event) {
    event.preventDefault();
    this.pick({ value: ALL, label: this.allLabel });
    const input = this.template.querySelector("input");
    if (input) {
      input.focus();
    }
  }

  pick(row) {
    const changed = row.value !== this._value;
    this._value = row.value;
    this.close();
    if (changed) {
      this.dispatchEvent(
        new CustomEvent("change", {
          detail: { value: row.value || null, label: row.label }
        })
      );
    }
  }
}
