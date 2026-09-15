import { calculateAgeLabel, parseCivilDate } from "c/emrDateUtils";

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
});
