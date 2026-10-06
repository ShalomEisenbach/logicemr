// Apex SObject keys include the installed package namespace. DTO keys do not.
export function normalizeBillingRecord(record, objectApiName) {
  const namespace = objectApiName?.match(
    /^([A-Za-z][A-Za-z0-9]*)__[A-Za-z][A-Za-z0-9_]*__c$/
  )?.[1];
  if (!namespace) return record;
  return normalizeValue(record, `${namespace}__`);
}

function normalizeValue(value, prefix) {
  if (Array.isArray(value))
    return value.map((item) => normalizeValue(item, prefix));
  if (value === null || typeof value !== "object") return value;
  return Object.fromEntries(
    Object.entries(value).map(([key, item]) => [
      key.startsWith(prefix) ? key.slice(prefix.length) : key,
      normalizeValue(item, prefix)
    ])
  );
}
