import {
  calculateAgeLabel,
  formatCivilDate,
  parseCivilDate
} from "c/emrDateUtils";

describe("emrDateUtils", () => {
  it("keeps a date-only birthday on its civil day", () => {
    expect(calculateAgeLabel("1988-04-12", new Date(2026, 3, 11, 23, 59))).toBe(
      "37 years"
    );
    expect(calculateAgeLabel("1988-04-12", new Date(2026, 3, 12, 0, 1))).toBe(
      "38 years"
    );
  });

  it("calculates infant ages in completed months", () => {
    expect(calculateAgeLabel("2026-01-20", new Date(2026, 2, 19))).toBe(
      "1 month"
    );
    expect(calculateAgeLabel("2026-01-20", new Date(2026, 2, 20))).toBe(
      "2 months"
    );
  });

  it("rejects invalid civil dates", () => {
    expect(parseCivilDate("2026-02-30")).toBeUndefined();
    expect(calculateAgeLabel("not-a-date", new Date(2026, 0, 1))).toBe("");
  });

  it("preserves birthdays and coverage boundaries in America/New_York", () => {
    // Demonstrate the UTC-midnight conversion that caused the production bug.
    expect(
      new Date("1988-03-14").toLocaleDateString("en-US", {
        timeZone: "America/New_York"
      })
    ).toBe("3/13/1988");
    for (const [value, expected] of [
      ["1988-03-14", "3/14/1988"],
      ["2026-01-01", "1/1/2026"],
      ["2026-12-31", "12/31/2026"],
      ["2024-02-29", "2/29/2024"]
    ]) {
      expect(
        formatCivilDate(value, { timeZone: "America/New_York" }, "en-US")
      ).toBe(expected);
    }
  });

  it("keeps invalid values readable without inventing a different day", () => {
    expect(formatCivilDate("2026-02-30")).toBe("2026-02-30");
    expect(formatCivilDate("not-a-date")).toBe("not-a-date");
    expect(formatCivilDate(null)).toBe("");
    expect(formatCivilDate(undefined)).toBe("");
    expect(formatCivilDate("")).toBe("");
    expect(formatCivilDate(new Date(NaN))).toBe("");
  });
});
