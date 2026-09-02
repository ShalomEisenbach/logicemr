/**
 * Idempotent clinical seed for the objects added after the core demo.
 * Requires seedDemoData.apex patients/encounters/practitioners.
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
List<lfemr__Condition__c> conditions = new List<lfemr__Condition__c>{
    new lfemr__Condition__c(
        lfemr__Source_System_Id__c = 'seed-cond-maya-dm',
        lfemr__FHIR_Id__c = 'seed-cond-maya-dm',
        lfemr__Patient__c = maya,
        lfemr__Category__c = 'Problem List Item',
        lfemr__Clinical_Status__c = 'Active',
        lfemr__Severity__c = 'Moderate',
        lfemr__Diagnosis_Code_System__c = 'ICD-10',
        lfemr__Diagnosis_Code__c = 'E11.9',
        lfemr__Diagnosis_Display__c = 'Type 2 diabetes mellitus',
        lfemr__Onset_Date__c = Date.newInstance(2019, 3, 1),
        lfemr__Notes__c = 'On metformin; last A1c elevated.'
    ),
    new lfemr__Condition__c(
        lfemr__Source_System_Id__c = 'seed-cond-maya-htn',
        lfemr__FHIR_Id__c = 'seed-cond-maya-htn',
        lfemr__Patient__c = maya,
        lfemr__Category__c = 'Problem List Item',
        lfemr__Clinical_Status__c = 'Active',
        lfemr__Severity__c = 'Moderate',
        lfemr__Diagnosis_Code_System__c = 'ICD-10',
        lfemr__Diagnosis_Code__c = 'I10',
        lfemr__Diagnosis_Display__c = 'Essential hypertension',
        lfemr__Onset_Date__c = Date.newInstance(2020, 6, 15)
    ),
    new lfemr__Condition__c(
        lfemr__Source_System_Id__c = 'seed-cond-maya-lipid',
        lfemr__FHIR_Id__c = 'seed-cond-maya-lipid',
        lfemr__Patient__c = maya,
        lfemr__Category__c = 'Problem List Item',
        lfemr__Clinical_Status__c = 'Active',
        lfemr__Severity__c = 'Mild',
        lfemr__Diagnosis_Code_System__c = 'ICD-10',
        lfemr__Diagnosis_Code__c = 'E78.5',
        lfemr__Diagnosis_Display__c = 'Hyperlipidemia',
        lfemr__Onset_Date__c = Date.newInstance(2021, 1, 10)
    ),
    new lfemr__Condition__c(
        lfemr__Source_System_Id__c = 'seed-cond-maya-chest',
        lfemr__FHIR_Id__c = 'seed-cond-maya-chest',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaEd,
        lfemr__Category__c = 'Problem List Item',
        lfemr__Clinical_Status__c = 'Resolved',
        lfemr__Severity__c = 'Moderate',
        lfemr__Diagnosis_Code_System__c = 'ICD-10',
        lfemr__Diagnosis_Code__c = 'R07.9',
        lfemr__Diagnosis_Display__c = 'Chest pain, unspecified',
        lfemr__Onset_Date__c = Date.newInstance(2026, 6, 3),
        lfemr__Abatement_Date__c = Date.newInstance(2026, 6, 4)
    ),
    new lfemr__Condition__c(
        lfemr__Source_System_Id__c = 'seed-cond-maya-ed-chest',
        lfemr__FHIR_Id__c = 'seed-cond-maya-ed-chest',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaEd,
        lfemr__Category__c = 'Encounter Diagnosis',
        lfemr__Clinical_Status__c = 'Active',
        lfemr__Diagnosis_Code_System__c = 'ICD-10',
        lfemr__Diagnosis_Code__c = 'R07.9',
        lfemr__Diagnosis_Display__c = 'Chest tightness'
    ),
    new lfemr__Condition__c(
        lfemr__Source_System_Id__c = 'seed-cond-maya-ed-dm',
        lfemr__FHIR_Id__c = 'seed-cond-maya-ed-dm',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaEd,
        lfemr__Category__c = 'Encounter Diagnosis',
        lfemr__Clinical_Status__c = 'Active',
        lfemr__Diagnosis_Code_System__c = 'ICD-10',
        lfemr__Diagnosis_Code__c = 'E11.9',
        lfemr__Diagnosis_Display__c = 'Type 2 diabetes mellitus'
    ),
    new lfemr__Condition__c(
        lfemr__Source_System_Id__c = 'seed-cond-maya-ip-dm',
        lfemr__FHIR_Id__c = 'seed-cond-maya-ip-dm',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaIp,
        lfemr__Category__c = 'Encounter Diagnosis',
        lfemr__Clinical_Status__c = 'Active',
        lfemr__Diagnosis_Code_System__c = 'ICD-10',
        lfemr__Diagnosis_Code__c = 'E11.65',
        lfemr__Diagnosis_Display__c = 'Type 2 diabetes with hyperglycemia'
    ),
    new lfemr__Condition__c(
        lfemr__Source_System_Id__c = 'seed-cond-liam-asthma',
        lfemr__FHIR_Id__c = 'seed-cond-liam-asthma',
        lfemr__Patient__c = liam,
        lfemr__Category__c = 'Problem List Item',
        lfemr__Clinical_Status__c = 'Active',
        lfemr__Severity__c = 'Mild',
        lfemr__Diagnosis_Code_System__c = 'ICD-10',
        lfemr__Diagnosis_Code__c = 'J45.20',
        lfemr__Diagnosis_Display__c = 'Mild intermittent asthma',
        lfemr__Onset_Date__c = Date.newInstance(2023, 4, 12)
    ),
    new lfemr__Condition__c(
        lfemr__Source_System_Id__c = 'seed-cond-liam-om',
        lfemr__FHIR_Id__c = 'seed-cond-liam-om',
        lfemr__Patient__c = liam,
        lfemr__Category__c = 'Problem List Item',
        lfemr__Clinical_Status__c = 'Resolved',
        lfemr__Severity__c = 'Mild',
        lfemr__Diagnosis_Code_System__c = 'ICD-10',
        lfemr__Diagnosis_Code__c = 'H66.90',
        lfemr__Diagnosis_Display__c = 'Otitis media, unspecified',
        lfemr__Onset_Date__c = Date.newInstance(2026, 3, 8),
        lfemr__Abatement_Date__c = Date.newInstance(2026, 3, 20)
    ),
    new lfemr__Condition__c(
        lfemr__Source_System_Id__c = 'seed-cond-sofia-afib',
        lfemr__FHIR_Id__c = 'seed-cond-sofia-afib',
        lfemr__Patient__c = sofia,
        lfemr__Category__c = 'Problem List Item',
        lfemr__Clinical_Status__c = 'Active',
        lfemr__Severity__c = 'Moderate',
        lfemr__Diagnosis_Code_System__c = 'ICD-10',
        lfemr__Diagnosis_Code__c = 'I48.91',
        lfemr__Diagnosis_Display__c = 'Unspecified atrial fibrillation',
        lfemr__Onset_Date__c = Date.newInstance(2024, 9, 2)
    ),
    new lfemr__Condition__c(
        lfemr__Source_System_Id__c = 'seed-cond-sofia-gall',
        lfemr__FHIR_Id__c = 'seed-cond-sofia-gall',
        lfemr__Patient__c = sofia,
        lfemr__Category__c = 'Problem List Item',
        lfemr__Clinical_Status__c = 'Active',
        lfemr__Severity__c = 'Moderate',
        lfemr__Diagnosis_Code_System__c = 'ICD-10',
        lfemr__Diagnosis_Code__c = 'K80.20',
        lfemr__Diagnosis_Display__c = 'Calculus of gallbladder without cholecystitis',
        lfemr__Onset_Date__c = Date.newInstance(2026, 5, 1)
    ),
    new lfemr__Condition__c(
        lfemr__Source_System_Id__c = 'seed-cond-sofia-enc-palp',
        lfemr__FHIR_Id__c = 'seed-cond-sofia-enc-palp',
        lfemr__Patient__c = sofia,
        lfemr__Encounter__c = sofiaProgress,
        lfemr__Category__c = 'Encounter Diagnosis',
        lfemr__Clinical_Status__c = 'Active',
        lfemr__Diagnosis_Code_System__c = 'ICD-10',
        lfemr__Diagnosis_Code__c = 'R00.2',
        lfemr__Diagnosis_Display__c = 'Palpitations'
    ),
    new lfemr__Condition__c(
        lfemr__Source_System_Id__c = 'seed-cond-james-hip',
        lfemr__FHIR_Id__c = 'seed-cond-james-hip',
        lfemr__Patient__c = james,
        lfemr__Encounter__c = jamesIp,
        lfemr__Category__c = 'Problem List Item',
        lfemr__Clinical_Status__c = 'Active',
        lfemr__Severity__c = 'Severe',
        lfemr__Diagnosis_Code_System__c = 'ICD-10',
        lfemr__Diagnosis_Code__c = 'S72.001A',
        lfemr__Diagnosis_Display__c = 'Fracture of unspecified part of neck of right femur, initial',
        lfemr__Onset_Date__c = Date.newInstance(2026, 8, 2)
    ),
    new lfemr__Condition__c(
        lfemr__Source_System_Id__c = 'seed-cond-james-osteo',
        lfemr__FHIR_Id__c = 'seed-cond-james-osteo',
        lfemr__Patient__c = james,
        lfemr__Category__c = 'Problem List Item',
        lfemr__Clinical_Status__c = 'Active',
        lfemr__Severity__c = 'Moderate',
        lfemr__Diagnosis_Code_System__c = 'ICD-10',
        lfemr__Diagnosis_Code__c = 'M81.0',
        lfemr__Diagnosis_Display__c = 'Age-related osteoporosis without current pathological fracture',
        lfemr__Onset_Date__c = Date.newInstance(2018, 11, 1)
    ),
    new lfemr__Condition__c(
        lfemr__Source_System_Id__c = 'seed-cond-james-htn',
        lfemr__FHIR_Id__c = 'seed-cond-james-htn',
        lfemr__Patient__c = james,
        lfemr__Category__c = 'Problem List Item',
        lfemr__Clinical_Status__c = 'Active',
        lfemr__Diagnosis_Code_System__c = 'ICD-10',
        lfemr__Diagnosis_Code__c = 'I10',
        lfemr__Diagnosis_Display__c = 'Essential hypertension',
        lfemr__Onset_Date__c = Date.newInstance(2008, 2, 14)
    ),
    new lfemr__Condition__c(
        lfemr__Source_System_Id__c = 'seed-cond-james-ip-hip',
        lfemr__FHIR_Id__c = 'seed-cond-james-ip-hip',
        lfemr__Patient__c = james,
        lfemr__Encounter__c = jamesIp,
        lfemr__Category__c = 'Encounter Diagnosis',
        lfemr__Clinical_Status__c = 'Active',
        lfemr__Diagnosis_Code_System__c = 'ICD-10',
        lfemr__Diagnosis_Code__c = 'S72.001A',
        lfemr__Diagnosis_Display__c = 'Right femoral neck fracture'
    ),
    new lfemr__Condition__c(
        lfemr__Source_System_Id__c = 'seed-cond-olivia-anx',
        lfemr__FHIR_Id__c = 'seed-cond-olivia-anx',
        lfemr__Patient__c = olivia,
        lfemr__Category__c = 'Problem List Item',
        lfemr__Clinical_Status__c = 'Active',
        lfemr__Severity__c = 'Mild',
        lfemr__Diagnosis_Code_System__c = 'ICD-10',
        lfemr__Diagnosis_Code__c = 'F41.1',
        lfemr__Diagnosis_Display__c = 'Generalized anxiety disorder',
        lfemr__Onset_Date__c = Date.newInstance(2024, 1, 20)
    ),
    new lfemr__Condition__c(
        lfemr__Source_System_Id__c = 'seed-cond-ben-lipid',
        lfemr__FHIR_Id__c = 'seed-cond-ben-lipid',
        lfemr__Patient__c = benjamin,
        lfemr__Category__c = 'Problem List Item',
        lfemr__Clinical_Status__c = 'Active',
        lfemr__Severity__c = 'Mild',
        lfemr__Diagnosis_Code_System__c = 'ICD-10',
        lfemr__Diagnosis_Code__c = 'E78.5',
        lfemr__Diagnosis_Display__c = 'Hyperlipidemia',
        lfemr__Onset_Date__c = Date.newInstance(2019, 5, 6)
    )
};
upsert conditions lfemr__Source_System_Id__c;
Map<String, Id> condIds = new Map<String, Id>();
for (lfemr__Condition__c row : conditions) {
    condIds.put(row.lfemr__Source_System_Id__c, row.Id);
}

List<lfemr__EncounterDiagnosis__c> diagnoses = new List<lfemr__EncounterDiagnosis__c>{
    new lfemr__EncounterDiagnosis__c(
        lfemr__Source_System_Id__c = 'seed-edx-maya-ed-1',
        lfemr__FHIR_Id__c = 'seed-edx-maya-ed-1',
        lfemr__Encounter__c = mayaEd,
        lfemr__Condition__c = condIds.get('seed-cond-maya-ed-chest'),
        lfemr__Type__c = 'Principal',
        lfemr__Rank__c = 1
    ),
    new lfemr__EncounterDiagnosis__c(
        lfemr__Source_System_Id__c = 'seed-edx-maya-ed-2',
        lfemr__FHIR_Id__c = 'seed-edx-maya-ed-2',
        lfemr__Encounter__c = mayaEd,
        lfemr__Condition__c = condIds.get('seed-cond-maya-ed-dm'),
        lfemr__Type__c = 'Secondary',
        lfemr__Rank__c = 2
    ),
    new lfemr__EncounterDiagnosis__c(
        lfemr__Source_System_Id__c = 'seed-edx-maya-ip-1',
        lfemr__FHIR_Id__c = 'seed-edx-maya-ip-1',
        lfemr__Encounter__c = mayaIp,
        lfemr__Condition__c = condIds.get('seed-cond-maya-ip-dm'),
        lfemr__Type__c = 'Principal',
        lfemr__Rank__c = 1
    ),
    new lfemr__EncounterDiagnosis__c(
        lfemr__Source_System_Id__c = 'seed-edx-maya-ip-2',
        lfemr__FHIR_Id__c = 'seed-edx-maya-ip-2',
        lfemr__Encounter__c = mayaIp,
        lfemr__Condition__c = condIds.get('seed-cond-maya-htn'),
        lfemr__Type__c = 'Secondary',
        lfemr__Rank__c = 2
    ),
    new lfemr__EncounterDiagnosis__c(
        lfemr__Source_System_Id__c = 'seed-edx-sofia-1',
        lfemr__FHIR_Id__c = 'seed-edx-sofia-1',
        lfemr__Encounter__c = sofiaProgress,
        lfemr__Condition__c = condIds.get('seed-cond-sofia-enc-palp'),
        lfemr__Type__c = 'Principal',
        lfemr__Rank__c = 1
    ),
    new lfemr__EncounterDiagnosis__c(
        lfemr__Source_System_Id__c = 'seed-edx-sofia-2',
        lfemr__FHIR_Id__c = 'seed-edx-sofia-2',
        lfemr__Encounter__c = sofiaProgress,
        lfemr__Condition__c = condIds.get('seed-cond-sofia-afib'),
        lfemr__Type__c = 'Secondary',
        lfemr__Rank__c = 2
    ),
    new lfemr__EncounterDiagnosis__c(
        lfemr__Source_System_Id__c = 'seed-edx-james-ip-1',
        lfemr__FHIR_Id__c = 'seed-edx-james-ip-1',
        lfemr__Encounter__c = jamesIp,
        lfemr__Condition__c = condIds.get('seed-cond-james-ip-hip'),
        lfemr__Type__c = 'Admitting',
        lfemr__Rank__c = 1
    ),
    new lfemr__EncounterDiagnosis__c(
        lfemr__Source_System_Id__c = 'seed-edx-james-ip-2',
        lfemr__FHIR_Id__c = 'seed-edx-james-ip-2',
        lfemr__Encounter__c = jamesIp,
        lfemr__Condition__c = condIds.get('seed-cond-james-osteo'),
        lfemr__Type__c = 'Secondary',
        lfemr__Rank__c = 2
    ),
    new lfemr__EncounterDiagnosis__c(
        lfemr__Source_System_Id__c = 'seed-edx-james-ed-1',
        lfemr__FHIR_Id__c = 'seed-edx-james-ed-1',
        lfemr__Encounter__c = jamesEd,
        lfemr__Condition__c = condIds.get('seed-cond-james-hip'),
        lfemr__Type__c = 'Principal',
        lfemr__Rank__c = 1
    )
};
upsert diagnoses lfemr__Source_System_Id__c;
