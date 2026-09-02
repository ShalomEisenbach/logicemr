/**
 * Clinical seed is split because anonymous Apex has a size limit.
 * Name on clinical objects is Text composed by NameFormatterHandler from
 * Name_Format__mdt — seed token fields, never set Name.
 *
 *   sf apex run --file scripts/apex/seedCatalog.apex
 *   sf apex run --file scripts/apex/seedDemoData.apex
 *   sf apex run --file scripts/apex/seedClinicalConditions.apex
 *   sf apex run --file scripts/apex/seedClinicalAllergiesImmunizations.apex
 *   sf apex run --file scripts/apex/seedClinicalMedications.apex
 *   sf apex run --file scripts/apex/seedClinicalOrdersAndResults.apex
 *   sf apex run --file scripts/apex/seedClinicalNotesAndProcedures.apex
 *
 * Re-running upserts on Source_System_Id__c refreshes composed Names.
 */
System.debug('See comment above for clinical seed files.');
