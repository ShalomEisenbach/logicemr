export function calculateAgeLabel(dateOnly, today = new Date()) {
  const birth = parseCivilDate(dateOnly);
  if (!birth || !(today instanceof Date) || Number.isNaN(today.getTime())) {
    return "";
  }

  let years = today.getFullYear() - birth.year;
  let months = today.getMonth() + 1 - birth.month;
  if (today.getDate() < birth.day) {
    months -= 1;
  }
  if (months < 0) {
    years -= 1;
    months += 12;
  }
  if (years < 0) {
    return "";
  }
  if (years === 0) {
    return months === 1 ? "1 month" : `${months} months`;
  }
  return years === 1 ? "1 year" : `${years} years`;
}

export function parseCivilDate(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value || "");
  if (!match) {
    return undefined;
  }
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const candidate = new Date(year, month - 1, day);
  if (
    candidate.getFullYear() !== year ||
    candidate.getMonth() + 1 !== month ||
    candidate.getDate() !== day
  ) {
    return undefined;
  }
  return { year, month, day };
}

// Date-only Salesforce fields represent a calendar day, not a UTC instant.
export function formatCivilDate(value, options = {}, locales) {
  if (typeof value !== "string" || !value) {
    return "";
  }
  const civil = parseCivilDate(value);
  if (!civil) {
    return value;
  }
  const date = new Date(0);
  date.setUTCFullYear(civil.year, civil.month - 1, civil.day);
  return date.toLocaleDateString(locales, { ...options, timeZone: "UTC" });
}
