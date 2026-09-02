/**
 * Clinical seed is split because anonymous Apex has a size limit.
 * Run after seedDemoData.apex:
 *
 *   sf apex run --file scripts/apex/seedClinicalConditions.apex
 *   sf apex run --file scripts/apex/seedClinicalAllergiesImmunizations.apex
 *   sf apex run --file scripts/apex/seedClinicalMedications.apex
 *   sf apex run --file scripts/apex/seedClinicalOrdersAndResults.apex
 */
System.debug('See comment above for clinical seed files.');
