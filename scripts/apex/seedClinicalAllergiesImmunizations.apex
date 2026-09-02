/**
 * Idempotent clinical seed for allergies and immunizations.
 * Requires seedDemoData.apex. Run seedCatalog.apex first for catalog lookups.
 * Do not set Name — composed from allergen/vaccine display tokens.
 */
Map<String, Id> ptIds = new Map<String, Id>();
for (lfemr__Patient__c row : [
    SELECT Id, lfemr__Source_System_Id__c
    FROM lfemr__Patient__c
    WHERE lfemr__Source_System_Id__c LIKE 'seed-pt-%'
]) {
    ptIds.put(row.lfemr__Source_System_Id__c, row.Id);
}
Map<String, Id> encIds = new Map<String, Id>();
for (lfemr__Encounter__c row : [
    SELECT Id, lfemr__Source_System_Id__c
    FROM lfemr__Encounter__c
    WHERE lfemr__Source_System_Id__c LIKE 'seed-enc-%'
]) {
    encIds.put(row.lfemr__Source_System_Id__c, row.Id);
}
Map<String, Id> pracIds = new Map<String, Id>();
for (lfemr__Practitioner__c row : [
    SELECT Id, lfemr__Source_System_Id__c
    FROM lfemr__Practitioner__c
    WHERE lfemr__Source_System_Id__c LIKE 'seed-prac-%'
]) {
    pracIds.put(row.lfemr__Source_System_Id__c, row.Id);
}
if (ptIds.size() < 10 || encIds.isEmpty()) {
    throw new AuraHandledException('Run scripts/apex/seedDemoData.apex first.');
}

Map<String, Id> cat = new Map<String, Id>();
for (lfemr__Code_Reference__c row : [
    SELECT Id, lfemr__Code_System__c, lfemr__Code__c
    FROM lfemr__Code_Reference__c
    WHERE lfemr__Active__c = true
]) {
    cat.put(row.lfemr__Code_System__c + '::' + row.lfemr__Code__c, row.Id);
}

Id maya = ptIds.get('seed-pt-maya-chen');
Id liam = ptIds.get('seed-pt-liam-chen');
Id sofia = ptIds.get('seed-pt-sofia-rivera');
Id noah = ptIds.get('seed-pt-noah-rivera');
Id james = ptIds.get('seed-pt-james-okonkwo');
Id ethan = ptIds.get('seed-pt-ethan-brooks');
Id olivia = ptIds.get('seed-pt-olivia-kim');
Id benjamin = ptIds.get('seed-pt-benjamin-alvarez');
Id harper = ptIds.get('seed-pt-harper-nguyen');
Id lee = pracIds.get('seed-prac-lee');
Id patel = pracIds.get('seed-prac-patel');
Id chen = pracIds.get('seed-prac-chen');
Id vasquez = pracIds.get('seed-prac-vasquez');
Id mayaProgress = encIds.get('seed-enc-maya-progress');
Id mayaArrived = encIds.get('seed-enc-maya-arrived');
Id mayaEd = encIds.get('seed-enc-maya-finished-ed');
Id mayaIp = encIds.get('seed-enc-maya-inpatient');
Id liamWell = encIds.get('seed-enc-liam-well');
Id sofiaProgress = encIds.get('seed-enc-sofia-progress');
Id noahWell = encIds.get('seed-enc-noah-well');
Id jamesEd = encIds.get('seed-enc-james-ed');
Id jamesIp = encIds.get('seed-enc-james-ip');
Id ethanWell = encIds.get('seed-enc-ethan-well');
Id oliviaVirtual = encIds.get('seed-enc-olivia-virtual');
Id benFinished = encIds.get('seed-enc-ben-finished');
Id harperSports = encIds.get('seed-enc-harper-sports');
List<lfemr__AllergyIntolerance__c> allergies = new List<lfemr__AllergyIntolerance__c>{
    new lfemr__AllergyIntolerance__c(
        lfemr__Source_System_Id__c = 'seed-alg-maya-pcn',
        lfemr__FHIR_Id__c = 'seed-alg-maya-pcn',
        lfemr__Patient__c = maya,
        lfemr__Allergen_Code_System__c = 'RxNorm',
        lfemr__Allergen_Code__c = '7980',
        lfemr__Allergen_Display__c = 'Penicillin',
        lfemr__Type__c = 'Allergy',
        lfemr__Category__c = 'Medication',
        lfemr__Criticality__c = 'High',
        lfemr__Clinical_Status__c = 'Active',
        lfemr__Reaction__c = 'Hives and facial swelling',
        lfemr__Onset_Date__c = Date.newInstance(2005, 8, 12)
    ),
    new lfemr__AllergyIntolerance__c(
        lfemr__Source_System_Id__c = 'seed-alg-maya-peanut',
        lfemr__FHIR_Id__c = 'seed-alg-maya-peanut',
        lfemr__Patient__c = maya,
        lfemr__Allergen_Code_System__c = 'SNOMED',
        lfemr__Allergen_Code__c = '91935009',
        lfemr__Allergen_Display__c = 'Peanut',
        lfemr__Type__c = 'Allergy',
        lfemr__Category__c = 'Food',
        lfemr__Criticality__c = 'High',
        lfemr__Clinical_Status__c = 'Active',
        lfemr__Reaction__c = 'Anaphylaxis',
        lfemr__Onset_Date__c = Date.newInstance(1992, 4, 1)
    ),
    new lfemr__AllergyIntolerance__c(
        lfemr__Source_System_Id__c = 'seed-alg-maya-latex',
        lfemr__FHIR_Id__c = 'seed-alg-maya-latex',
        lfemr__Patient__c = maya,
        lfemr__Allergen_Code_System__c = 'SNOMED',
        lfemr__Allergen_Code__c = '111088007',
        lfemr__Allergen_Display__c = 'Latex',
        lfemr__Type__c = 'Allergy',
        lfemr__Category__c = 'Environment',
        lfemr__Criticality__c = 'Low',
        lfemr__Clinical_Status__c = 'Active',
        lfemr__Reaction__c = 'Contact dermatitis'
    ),
    new lfemr__AllergyIntolerance__c(
        lfemr__Source_System_Id__c = 'seed-alg-maya-sulfa',
        lfemr__FHIR_Id__c = 'seed-alg-maya-sulfa',
        lfemr__Patient__c = maya,
        lfemr__Allergen_Code_System__c = 'RxNorm',
        lfemr__Allergen_Code__c = '10180',
        lfemr__Allergen_Display__c = 'Sulfonamide',
        lfemr__Type__c = 'Allergy',
        lfemr__Category__c = 'Medication',
        lfemr__Criticality__c = 'High',
        lfemr__Clinical_Status__c = 'Inactive',
        lfemr__Reaction__c = 'Rash'
    ),
    new lfemr__AllergyIntolerance__c(
        lfemr__Source_System_Id__c = 'seed-alg-liam-amox',
        lfemr__FHIR_Id__c = 'seed-alg-liam-amox',
        lfemr__Patient__c = liam,
        lfemr__Allergen_Code_System__c = 'RxNorm',
        lfemr__Allergen_Code__c = '723',
        lfemr__Allergen_Display__c = 'Amoxicillin',
        lfemr__Type__c = 'Allergy',
        lfemr__Category__c = 'Medication',
        lfemr__Criticality__c = 'High',
        lfemr__Clinical_Status__c = 'Active',
        lfemr__Reaction__c = 'Urticaria',
        lfemr__Onset_Date__c = Date.newInstance(2024, 2, 3)
    ),
    new lfemr__AllergyIntolerance__c(
        lfemr__Source_System_Id__c = 'seed-alg-sofia-codeine',
        lfemr__FHIR_Id__c = 'seed-alg-sofia-codeine',
        lfemr__Patient__c = sofia,
        lfemr__Allergen_Code_System__c = 'RxNorm',
        lfemr__Allergen_Code__c = '2670',
        lfemr__Allergen_Display__c = 'Codeine',
        lfemr__Type__c = 'Intolerance',
        lfemr__Category__c = 'Medication',
        lfemr__Criticality__c = 'Low',
        lfemr__Clinical_Status__c = 'Active',
        lfemr__Reaction__c = 'Nausea'
    ),
    new lfemr__AllergyIntolerance__c(
        lfemr__Source_System_Id__c = 'seed-alg-olivia-shellfish',
        lfemr__FHIR_Id__c = 'seed-alg-olivia-shellfish',
        lfemr__Patient__c = olivia,
        lfemr__Allergen_Code_System__c = 'SNOMED',
        lfemr__Allergen_Code__c = '300913001',
        lfemr__Allergen_Display__c = 'Shellfish',
        lfemr__Type__c = 'Allergy',
        lfemr__Category__c = 'Food',
        lfemr__Criticality__c = 'High',
        lfemr__Clinical_Status__c = 'Active',
        lfemr__Reaction__c = 'Itching, self-resolved'
    )
};
for (lfemr__AllergyIntolerance__c row : allergies) {
    if (String.isNotBlank(row.lfemr__Allergen_Code_System__c) && String.isNotBlank(row.lfemr__Allergen_Code__c)) {
        row.lfemr__Allergen_Ref__c = cat.get(
            row.lfemr__Allergen_Code_System__c + '::' + row.lfemr__Allergen_Code__c
        );
    }
}
upsert allergies lfemr__Source_System_Id__c;

List<lfemr__Immunization__c> immunizations = new List<lfemr__Immunization__c>{
    new lfemr__Immunization__c(
        lfemr__Source_System_Id__c = 'seed-imm-maya-flu',
        lfemr__FHIR_Id__c = 'seed-imm-maya-flu',
        lfemr__Patient__c = maya,
        lfemr__Vaccine_Code_System__c = 'CVX',
        lfemr__Vaccine_Code__c = '141',
        lfemr__Vaccine_Display__c = 'Influenza, seasonal, injectable',
        lfemr__Status__c = 'Completed',
        lfemr__Occurrence_Date__c = Date.newInstance(2025, 10, 8),
        lfemr__Lot_Number__c = 'FLU25-441',
        lfemr__Performer__c = vasquez
    ),
    new lfemr__Immunization__c(
        lfemr__Source_System_Id__c = 'seed-imm-maya-covid',
        lfemr__FHIR_Id__c = 'seed-imm-maya-covid',
        lfemr__Patient__c = maya,
        lfemr__Vaccine_Code_System__c = 'CVX',
        lfemr__Vaccine_Code__c = '213',
        lfemr__Vaccine_Display__c = 'SARS-CoV-2 (COVID-19) vaccine',
        lfemr__Status__c = 'Completed',
        lfemr__Occurrence_Date__c = Date.newInstance(2025, 9, 20),
        lfemr__Lot_Number__c = 'CVD-9921',
        lfemr__Performer__c = lee
    ),
    new lfemr__Immunization__c(
        lfemr__Source_System_Id__c = 'seed-imm-liam-dtap',
        lfemr__FHIR_Id__c = 'seed-imm-liam-dtap',
        lfemr__Patient__c = liam,
        lfemr__Encounter__c = liamWell,
        lfemr__Vaccine_Code_System__c = 'CVX',
        lfemr__Vaccine_Code__c = '20',
        lfemr__Vaccine_Display__c = 'DTaP',
        lfemr__Status__c = 'Completed',
        lfemr__Occurrence_Date__c = Date.newInstance(2026, 7, 22),
        lfemr__Lot_Number__c = 'DTAP-118',
        lfemr__Performer__c = lee
    ),
    new lfemr__Immunization__c(
        lfemr__Source_System_Id__c = 'seed-imm-liam-mmr',
        lfemr__FHIR_Id__c = 'seed-imm-liam-mmr',
        lfemr__Patient__c = liam,
        lfemr__Vaccine_Code_System__c = 'CVX',
        lfemr__Vaccine_Code__c = '03',
        lfemr__Vaccine_Display__c = 'MMR',
        lfemr__Status__c = 'Completed',
        lfemr__Occurrence_Date__c = Date.newInstance(2025, 8, 4),
        lfemr__Lot_Number__c = 'MMR-77',
        lfemr__Performer__c = vasquez
    ),
    new lfemr__Immunization__c(
        lfemr__Source_System_Id__c = 'seed-imm-noah-hepb',
        lfemr__FHIR_Id__c = 'seed-imm-noah-hepb',
        lfemr__Patient__c = noah,
        lfemr__Encounter__c = noahWell,
        lfemr__Vaccine_Code_System__c = 'CVX',
        lfemr__Vaccine_Code__c = '08',
        lfemr__Vaccine_Display__c = 'Hep B, adolescent or pediatric',
        lfemr__Status__c = 'Completed',
        lfemr__Occurrence_Date__c = Date.newInstance(2026, 8, 18),
        lfemr__Lot_Number__c = 'HEPB-04',
        lfemr__Performer__c = lee
    ),
    new lfemr__Immunization__c(
        lfemr__Source_System_Id__c = 'seed-imm-noah-rota',
        lfemr__FHIR_Id__c = 'seed-imm-noah-rota',
        lfemr__Patient__c = noah,
        lfemr__Encounter__c = noahWell,
        lfemr__Vaccine_Code_System__c = 'CVX',
        lfemr__Vaccine_Code__c = '119',
        lfemr__Vaccine_Display__c = 'Rotavirus, pentavalent',
        lfemr__Status__c = 'Completed',
        lfemr__Occurrence_Date__c = Date.newInstance(2026, 8, 18),
        lfemr__Lot_Number__c = 'ROTA-22',
        lfemr__Performer__c = lee
    ),
    new lfemr__Immunization__c(
        lfemr__Source_System_Id__c = 'seed-imm-ethan-hepa',
        lfemr__FHIR_Id__c = 'seed-imm-ethan-hepa',
        lfemr__Patient__c = ethan,
        lfemr__Encounter__c = ethanWell,
        lfemr__Vaccine_Code_System__c = 'CVX',
        lfemr__Vaccine_Code__c = '83',
        lfemr__Vaccine_Display__c = 'Hep A, ped/adol, 2 dose',
        lfemr__Status__c = 'Completed',
        lfemr__Occurrence_Date__c = Date.newInstance(2026, 9, 1),
        lfemr__Lot_Number__c = 'HEPA-09',
        lfemr__Performer__c = vasquez
    ),
    new lfemr__Immunization__c(
        lfemr__Source_System_Id__c = 'seed-imm-harper-tdap',
        lfemr__FHIR_Id__c = 'seed-imm-harper-tdap',
        lfemr__Patient__c = harper,
        lfemr__Encounter__c = harperSports,
        lfemr__Vaccine_Code_System__c = 'CVX',
        lfemr__Vaccine_Code__c = '115',
        lfemr__Vaccine_Display__c = 'Tdap',
        lfemr__Status__c = 'Completed',
        lfemr__Occurrence_Date__c = Date.newInstance(2026, 8, 10),
        lfemr__Lot_Number__c = 'TDAP-55',
        lfemr__Performer__c = vasquez
    ),
    new lfemr__Immunization__c(
        lfemr__Source_System_Id__c = 'seed-imm-james-flu-err',
        lfemr__FHIR_Id__c = 'seed-imm-james-flu-err',
        lfemr__Patient__c = james,
        lfemr__Vaccine_Code_System__c = 'CVX',
        lfemr__Vaccine_Code__c = '141',
        lfemr__Vaccine_Display__c = 'Influenza, seasonal, injectable',
        lfemr__Status__c = 'Entered in Error',
        lfemr__Occurrence_Date__c = Date.newInstance(2025, 10, 1)
    )
};
for (lfemr__Immunization__c row : immunizations) {
    row.lfemr__Vaccine_Ref__c = cat.get(
        row.lfemr__Vaccine_Code_System__c + '::' + row.lfemr__Vaccine_Code__c
    );
}
upsert immunizations lfemr__Source_System_Id__c;
