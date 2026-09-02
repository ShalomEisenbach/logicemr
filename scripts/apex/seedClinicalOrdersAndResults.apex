/**
 * Idempotent clinical seed for service requests, diagnostic reports, and observations.
 * Requires seedDemoData.apex. Run seedCatalog.apex first for catalog lookups.
 * Do not set Name — composed from display, category, value, and datetime tokens.
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
List<lfemr__ServiceRequest__c> serviceRequests = new List<lfemr__ServiceRequest__c>{
    new lfemr__ServiceRequest__c(
        lfemr__Source_System_Id__c = 'seed-sr-maya-a1c',
        lfemr__FHIR_Id__c = 'seed-sr-maya-a1c',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaArrived,
        lfemr__Requester__c = lee,
        lfemr__Category__c = 'Lab',
        lfemr__Status__c = 'Completed',
        lfemr__Priority__c = 'Routine',
        lfemr__Service_Code_System__c = 'LOINC',
        lfemr__Service_Code__c = '4548-4',
        lfemr__Service_Display__c = 'Hemoglobin A1c',
        lfemr__Reason__c = 'Diabetes monitoring',
        lfemr__Authored_On__c = Datetime.newInstance(2026, 8, 28, 14, 5, 0)
    ),
    new lfemr__ServiceRequest__c(
        lfemr__Source_System_Id__c = 'seed-sr-maya-lipid',
        lfemr__FHIR_Id__c = 'seed-sr-maya-lipid',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaArrived,
        lfemr__Requester__c = lee,
        lfemr__Category__c = 'Lab',
        lfemr__Status__c = 'Completed',
        lfemr__Priority__c = 'Routine',
        lfemr__Service_Code_System__c = 'LOINC',
        lfemr__Service_Code__c = '57698-3',
        lfemr__Service_Display__c = 'Lipid panel',
        lfemr__Reason__c = 'Fasting labs',
        lfemr__Authored_On__c = Datetime.newInstance(2026, 8, 28, 14, 6, 0)
    ),
    new lfemr__ServiceRequest__c(
        lfemr__Source_System_Id__c = 'seed-sr-maya-endo',
        lfemr__FHIR_Id__c = 'seed-sr-maya-endo',
        lfemr__Patient__c = maya,
        lfemr__Requester__c = lee,
        lfemr__Category__c = 'Referral',
        lfemr__Status__c = 'Active',
        lfemr__Priority__c = 'Routine',
        lfemr__Service_Code_System__c = 'SNOMED',
        lfemr__Service_Code__c = '306118007',
        lfemr__Service_Display__c = 'Referral to endocrinology',
        lfemr__Reason__c = 'Uncontrolled diabetes',
        lfemr__Authored_On__c = Datetime.newInstance(2026, 9, 1, 9, 50, 0)
    ),
    new lfemr__ServiceRequest__c(
        lfemr__Source_System_Id__c = 'seed-sr-maya-trop',
        lfemr__FHIR_Id__c = 'seed-sr-maya-trop',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaEd,
        lfemr__Requester__c = chen,
        lfemr__Category__c = 'Lab',
        lfemr__Status__c = 'Completed',
        lfemr__Priority__c = 'STAT',
        lfemr__Service_Code_System__c = 'LOINC',
        lfemr__Service_Code__c = '10839-9',
        lfemr__Service_Display__c = 'Troponin I',
        lfemr__Reason__c = 'Chest tightness',
        lfemr__Authored_On__c = Datetime.newInstance(2026, 6, 3, 22, 50, 0)
    ),
    new lfemr__ServiceRequest__c(
        lfemr__Source_System_Id__c = 'seed-sr-sofia-echo',
        lfemr__FHIR_Id__c = 'seed-sr-sofia-echo',
        lfemr__Patient__c = sofia,
        lfemr__Encounter__c = sofiaProgress,
        lfemr__Requester__c = patel,
        lfemr__Category__c = 'Imaging',
        lfemr__Status__c = 'Active',
        lfemr__Priority__c = 'Urgent',
        lfemr__Service_Code_System__c = 'CPT',
        lfemr__Service_Code__c = '93306',
        lfemr__Service_Display__c = 'Echocardiogram, complete',
        lfemr__Reason__c = 'Palpitations, atrial fibrillation',
        lfemr__Authored_On__c = Datetime.newInstance(2026, 8, 31, 14, 20, 0)
    ),
    new lfemr__ServiceRequest__c(
        lfemr__Source_System_Id__c = 'seed-sr-james-xray',
        lfemr__FHIR_Id__c = 'seed-sr-james-xray',
        lfemr__Patient__c = james,
        lfemr__Encounter__c = jamesEd,
        lfemr__Requester__c = chen,
        lfemr__Category__c = 'Imaging',
        lfemr__Status__c = 'Completed',
        lfemr__Priority__c = 'STAT',
        lfemr__Service_Code_System__c = 'CPT',
        lfemr__Service_Code__c = '73502',
        lfemr__Service_Display__c = 'X-ray hip, 2 or 3 views',
        lfemr__Reason__c = 'Fall, hip pain',
        lfemr__Authored_On__c = Datetime.newInstance(2026, 8, 2, 19, 20, 0)
    ),
    new lfemr__ServiceRequest__c(
        lfemr__Source_System_Id__c = 'seed-sr-ben-lipid',
        lfemr__FHIR_Id__c = 'seed-sr-ben-lipid',
        lfemr__Patient__c = benjamin,
        lfemr__Encounter__c = benFinished,
        lfemr__Requester__c = lee,
        lfemr__Category__c = 'Lab',
        lfemr__Status__c = 'Completed',
        lfemr__Priority__c = 'Routine',
        lfemr__Service_Code_System__c = 'LOINC',
        lfemr__Service_Code__c = '57698-3',
        lfemr__Service_Display__c = 'Lipid panel',
        lfemr__Reason__c = 'Statin monitoring',
        lfemr__Authored_On__c = Datetime.newInstance(2026, 5, 1, 9, 0, 0)
    )
};
for (lfemr__ServiceRequest__c row : serviceRequests) {
    row.lfemr__Service_Ref__c = cat.get(
        row.lfemr__Service_Code_System__c + '::' + row.lfemr__Service_Code__c
    );
}
upsert serviceRequests lfemr__Source_System_Id__c;
Map<String, Id> srIds = new Map<String, Id>();
for (lfemr__ServiceRequest__c row : serviceRequests) {
    srIds.put(row.lfemr__Source_System_Id__c, row.Id);
}

List<lfemr__DiagnosticReport__c> reports = new List<lfemr__DiagnosticReport__c>{
    new lfemr__DiagnosticReport__c(
        lfemr__Source_System_Id__c = 'seed-dr-maya-a1c',
        lfemr__FHIR_Id__c = 'seed-dr-maya-a1c',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaArrived,
        lfemr__ServiceRequest__c = srIds.get('seed-sr-maya-a1c'),
        lfemr__Category__c = 'Laboratory',
        lfemr__Status__c = 'Final',
        lfemr__Report_Code_System__c = 'LOINC',
        lfemr__Report_Code__c = '4548-4',
        lfemr__Report_Display__c = 'Hemoglobin A1c',
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 8, 28, 15, 10, 0),
        lfemr__Issued__c = Datetime.newInstance(2026, 8, 28, 16, 40, 0),
        lfemr__Conclusion__c = 'A1c remains above goal. Continue metformin and endocrinology referral.'
    ),
    new lfemr__DiagnosticReport__c(
        lfemr__Source_System_Id__c = 'seed-dr-maya-lipid',
        lfemr__FHIR_Id__c = 'seed-dr-maya-lipid',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaArrived,
        lfemr__ServiceRequest__c = srIds.get('seed-sr-maya-lipid'),
        lfemr__Category__c = 'Laboratory',
        lfemr__Status__c = 'Final',
        lfemr__Report_Code_System__c = 'LOINC',
        lfemr__Report_Code__c = '57698-3',
        lfemr__Report_Display__c = 'Lipid panel',
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 8, 28, 15, 10, 0),
        lfemr__Issued__c = Datetime.newInstance(2026, 8, 28, 16, 45, 0),
        lfemr__Conclusion__c = 'LDL above target on current statin dose.'
    ),
    new lfemr__DiagnosticReport__c(
        lfemr__Source_System_Id__c = 'seed-dr-maya-trop',
        lfemr__FHIR_Id__c = 'seed-dr-maya-trop',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaEd,
        lfemr__ServiceRequest__c = srIds.get('seed-sr-maya-trop'),
        lfemr__Category__c = 'Laboratory',
        lfemr__Status__c = 'Final',
        lfemr__Report_Code_System__c = 'LOINC',
        lfemr__Report_Code__c = '10839-9',
        lfemr__Report_Display__c = 'Troponin I',
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 6, 3, 23, 20, 0),
        lfemr__Issued__c = Datetime.newInstance(2026, 6, 3, 23, 45, 0),
        lfemr__Conclusion__c = 'Troponin negative. Chest tightness not consistent with ACS.'
    ),
    new lfemr__DiagnosticReport__c(
        lfemr__Source_System_Id__c = 'seed-dr-james-xray',
        lfemr__FHIR_Id__c = 'seed-dr-james-xray',
        lfemr__Patient__c = james,
        lfemr__Encounter__c = jamesEd,
        lfemr__ServiceRequest__c = srIds.get('seed-sr-james-xray'),
        lfemr__Category__c = 'Radiology',
        lfemr__Status__c = 'Final',
        lfemr__Report_Code_System__c = 'LOINC',
        lfemr__Report_Code__c = '30711-8',
        lfemr__Report_Display__c = 'XR Hip Right',
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 8, 2, 19, 40, 0),
        lfemr__Issued__c = Datetime.newInstance(2026, 8, 2, 20, 15, 0),
        lfemr__Conclusion__c = 'Displaced right femoral neck fracture. Orthopedics consulted.'
    ),
    new lfemr__DiagnosticReport__c(
        lfemr__Source_System_Id__c = 'seed-dr-ben-lipid',
        lfemr__FHIR_Id__c = 'seed-dr-ben-lipid',
        lfemr__Patient__c = benjamin,
        lfemr__Encounter__c = benFinished,
        lfemr__ServiceRequest__c = srIds.get('seed-sr-ben-lipid'),
        lfemr__Category__c = 'Laboratory',
        lfemr__Status__c = 'Final',
        lfemr__Report_Code_System__c = 'LOINC',
        lfemr__Report_Code__c = '57698-3',
        lfemr__Report_Display__c = 'Lipid panel',
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 5, 2, 8, 0, 0),
        lfemr__Issued__c = Datetime.newInstance(2026, 5, 2, 12, 0, 0),
        lfemr__Conclusion__c = 'LDL improved; continue atorvastatin 40 mg.'
    ),
    new lfemr__DiagnosticReport__c(
        lfemr__Source_System_Id__c = 'seed-dr-sofia-echo-prelim',
        lfemr__FHIR_Id__c = 'seed-dr-sofia-echo-prelim',
        lfemr__Patient__c = sofia,
        lfemr__Encounter__c = sofiaProgress,
        lfemr__ServiceRequest__c = srIds.get('seed-sr-sofia-echo'),
        lfemr__Category__c = 'Radiology',
        lfemr__Status__c = 'Registered',
        lfemr__Report_Code_System__c = 'LOINC',
        lfemr__Report_Code__c = '34552-0',
        lfemr__Report_Display__c = 'Echocardiogram',
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 9, 2, 10, 0, 0)
    )
};
for (lfemr__DiagnosticReport__c row : reports) {
    row.lfemr__Report_Ref__c = cat.get(
        row.lfemr__Report_Code_System__c + '::' + row.lfemr__Report_Code__c
    );
}
upsert reports lfemr__Source_System_Id__c;
Map<String, Id> drIds = new Map<String, Id>();
for (lfemr__DiagnosticReport__c row : reports) {
    drIds.put(row.lfemr__Source_System_Id__c, row.Id);
}

List<lfemr__Observation__c> observations = new List<lfemr__Observation__c>{
    new lfemr__Observation__c(
        lfemr__Source_System_Id__c = 'seed-obs-maya-sbp',
        lfemr__FHIR_Id__c = 'seed-obs-maya-sbp',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaProgress,
        lfemr__Performer__c = vasquez,
        lfemr__Category__c = 'Vital Signs',
        lfemr__Status__c = 'Final',
        lfemr__Observation_Code_System__c = 'LOINC',
        lfemr__Observation_Code__c = '8480-6',
        lfemr__Observation_Display__c = 'Systolic blood pressure',
        lfemr__Value_Quantity__c = 142,
        lfemr__Value_Unit__c = 'mmHg',
        lfemr__Interpretation__c = 'High',
        lfemr__Reference_Range_Low__c = 90,
        lfemr__Reference_Range_High__c = 120,
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 9, 1, 9, 20, 0)
    ),
    new lfemr__Observation__c(
        lfemr__Source_System_Id__c = 'seed-obs-maya-dbp',
        lfemr__FHIR_Id__c = 'seed-obs-maya-dbp',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaProgress,
        lfemr__Performer__c = vasquez,
        lfemr__Category__c = 'Vital Signs',
        lfemr__Status__c = 'Final',
        lfemr__Observation_Code_System__c = 'LOINC',
        lfemr__Observation_Code__c = '8462-4',
        lfemr__Observation_Display__c = 'Diastolic blood pressure',
        lfemr__Value_Quantity__c = 88,
        lfemr__Value_Unit__c = 'mmHg',
        lfemr__Interpretation__c = 'High',
        lfemr__Reference_Range_Low__c = 60,
        lfemr__Reference_Range_High__c = 80,
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 9, 1, 9, 20, 0)
    ),
    new lfemr__Observation__c(
        lfemr__Source_System_Id__c = 'seed-obs-maya-hr',
        lfemr__FHIR_Id__c = 'seed-obs-maya-hr',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaProgress,
        lfemr__Performer__c = vasquez,
        lfemr__Category__c = 'Vital Signs',
        lfemr__Status__c = 'Final',
        lfemr__Observation_Code_System__c = 'LOINC',
        lfemr__Observation_Code__c = '8867-4',
        lfemr__Observation_Display__c = 'Heart rate',
        lfemr__Value_Quantity__c = 78,
        lfemr__Value_Unit__c = '/min',
        lfemr__Interpretation__c = 'Normal',
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 9, 1, 9, 20, 0)
    ),
    new lfemr__Observation__c(
        lfemr__Source_System_Id__c = 'seed-obs-maya-rr',
        lfemr__FHIR_Id__c = 'seed-obs-maya-rr',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaProgress,
        lfemr__Category__c = 'Vital Signs',
        lfemr__Status__c = 'Final',
        lfemr__Observation_Code_System__c = 'LOINC',
        lfemr__Observation_Code__c = '9279-1',
        lfemr__Observation_Display__c = 'Respiratory rate',
        lfemr__Value_Quantity__c = 16,
        lfemr__Value_Unit__c = '/min',
        lfemr__Interpretation__c = 'Normal',
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 9, 1, 9, 20, 0)
    ),
    new lfemr__Observation__c(
        lfemr__Source_System_Id__c = 'seed-obs-maya-temp',
        lfemr__FHIR_Id__c = 'seed-obs-maya-temp',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaProgress,
        lfemr__Category__c = 'Vital Signs',
        lfemr__Status__c = 'Final',
        lfemr__Observation_Code_System__c = 'LOINC',
        lfemr__Observation_Code__c = '8310-5',
        lfemr__Observation_Display__c = 'Body temperature',
        lfemr__Value_Quantity__c = 36.8,
        lfemr__Value_Unit__c = 'Cel',
        lfemr__Interpretation__c = 'Normal',
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 9, 1, 9, 20, 0)
    ),
    new lfemr__Observation__c(
        lfemr__Source_System_Id__c = 'seed-obs-maya-spo2',
        lfemr__FHIR_Id__c = 'seed-obs-maya-spo2',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaProgress,
        lfemr__Category__c = 'Vital Signs',
        lfemr__Status__c = 'Final',
        lfemr__Observation_Code_System__c = 'LOINC',
        lfemr__Observation_Code__c = '59408-5',
        lfemr__Observation_Display__c = 'Oxygen saturation',
        lfemr__Value_Quantity__c = 98,
        lfemr__Value_Unit__c = '%',
        lfemr__Interpretation__c = 'Normal',
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 9, 1, 9, 20, 0)
    ),
    new lfemr__Observation__c(
        lfemr__Source_System_Id__c = 'seed-obs-maya-a1c',
        lfemr__FHIR_Id__c = 'seed-obs-maya-a1c',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaArrived,
        lfemr__DiagnosticReport__c = drIds.get('seed-dr-maya-a1c'),
        lfemr__Performer__c = lee,
        lfemr__Category__c = 'Laboratory',
        lfemr__Status__c = 'Final',
        lfemr__Observation_Code_System__c = 'LOINC',
        lfemr__Observation_Code__c = '4548-4',
        lfemr__Observation_Display__c = 'Hemoglobin A1c',
        lfemr__Value_Quantity__c = 8.2,
        lfemr__Value_Unit__c = '%',
        lfemr__Interpretation__c = 'High',
        lfemr__Reference_Range_Low__c = 4.0,
        lfemr__Reference_Range_High__c = 5.6,
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 8, 28, 15, 10, 0)
    ),
    new lfemr__Observation__c(
        lfemr__Source_System_Id__c = 'seed-obs-maya-gluc',
        lfemr__FHIR_Id__c = 'seed-obs-maya-gluc',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaArrived,
        lfemr__DiagnosticReport__c = drIds.get('seed-dr-maya-a1c'),
        lfemr__Category__c = 'Laboratory',
        lfemr__Status__c = 'Final',
        lfemr__Observation_Code_System__c = 'LOINC',
        lfemr__Observation_Code__c = '2345-7',
        lfemr__Observation_Display__c = 'Glucose',
        lfemr__Value_Quantity__c = 168,
        lfemr__Value_Unit__c = 'mg/dL',
        lfemr__Interpretation__c = 'High',
        lfemr__Reference_Range_Low__c = 70,
        lfemr__Reference_Range_High__c = 99,
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 8, 28, 15, 10, 0)
    ),
    new lfemr__Observation__c(
        lfemr__Source_System_Id__c = 'seed-obs-maya-ldl',
        lfemr__FHIR_Id__c = 'seed-obs-maya-ldl',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaArrived,
        lfemr__DiagnosticReport__c = drIds.get('seed-dr-maya-lipid'),
        lfemr__Category__c = 'Laboratory',
        lfemr__Status__c = 'Final',
        lfemr__Observation_Code_System__c = 'LOINC',
        lfemr__Observation_Code__c = '2089-1',
        lfemr__Observation_Display__c = 'LDL cholesterol',
        lfemr__Value_Quantity__c = 142,
        lfemr__Value_Unit__c = 'mg/dL',
        lfemr__Interpretation__c = 'High',
        lfemr__Reference_Range_High__c = 100,
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 8, 28, 15, 10, 0)
    ),
    new lfemr__Observation__c(
        lfemr__Source_System_Id__c = 'seed-obs-maya-hdl',
        lfemr__FHIR_Id__c = 'seed-obs-maya-hdl',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaArrived,
        lfemr__DiagnosticReport__c = drIds.get('seed-dr-maya-lipid'),
        lfemr__Category__c = 'Laboratory',
        lfemr__Status__c = 'Final',
        lfemr__Observation_Code_System__c = 'LOINC',
        lfemr__Observation_Code__c = '2085-9',
        lfemr__Observation_Display__c = 'HDL cholesterol',
        lfemr__Value_Quantity__c = 38,
        lfemr__Value_Unit__c = 'mg/dL',
        lfemr__Interpretation__c = 'Low',
        lfemr__Reference_Range_Low__c = 40,
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 8, 28, 15, 10, 0)
    ),
    new lfemr__Observation__c(
        lfemr__Source_System_Id__c = 'seed-obs-maya-trop',
        lfemr__FHIR_Id__c = 'seed-obs-maya-trop',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaEd,
        lfemr__DiagnosticReport__c = drIds.get('seed-dr-maya-trop'),
        lfemr__Category__c = 'Laboratory',
        lfemr__Status__c = 'Final',
        lfemr__Observation_Code_System__c = 'LOINC',
        lfemr__Observation_Code__c = '10839-9',
        lfemr__Observation_Display__c = 'Troponin I',
        lfemr__Value_Quantity__c = 0.01,
        lfemr__Value_Unit__c = 'ng/mL',
        lfemr__Interpretation__c = 'Normal',
        lfemr__Reference_Range_High__c = 0.04,
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 6, 3, 23, 20, 0)
    ),
    new lfemr__Observation__c(
        lfemr__Source_System_Id__c = 'seed-obs-liam-ht',
        lfemr__FHIR_Id__c = 'seed-obs-liam-ht',
        lfemr__Patient__c = liam,
        lfemr__Encounter__c = liamWell,
        lfemr__Performer__c = lee,
        lfemr__Category__c = 'Vital Signs',
        lfemr__Status__c = 'Final',
        lfemr__Observation_Code_System__c = 'LOINC',
        lfemr__Observation_Code__c = '8302-2',
        lfemr__Observation_Display__c = 'Body height',
        lfemr__Value_Quantity__c = 116,
        lfemr__Value_Unit__c = 'cm',
        lfemr__Interpretation__c = 'Normal',
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 7, 22, 9, 35, 0)
    ),
    new lfemr__Observation__c(
        lfemr__Source_System_Id__c = 'seed-obs-liam-wt',
        lfemr__FHIR_Id__c = 'seed-obs-liam-wt',
        lfemr__Patient__c = liam,
        lfemr__Encounter__c = liamWell,
        lfemr__Performer__c = lee,
        lfemr__Category__c = 'Vital Signs',
        lfemr__Status__c = 'Final',
        lfemr__Observation_Code_System__c = 'LOINC',
        lfemr__Observation_Code__c = '29463-7',
        lfemr__Observation_Display__c = 'Body weight',
        lfemr__Value_Quantity__c = 21.4,
        lfemr__Value_Unit__c = 'kg',
        lfemr__Interpretation__c = 'Normal',
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 7, 22, 9, 35, 0)
    ),
    new lfemr__Observation__c(
        lfemr__Source_System_Id__c = 'seed-obs-noah-wt',
        lfemr__FHIR_Id__c = 'seed-obs-noah-wt',
        lfemr__Patient__c = noah,
        lfemr__Encounter__c = noahWell,
        lfemr__Performer__c = lee,
        lfemr__Category__c = 'Vital Signs',
        lfemr__Status__c = 'Final',
        lfemr__Observation_Code_System__c = 'LOINC',
        lfemr__Observation_Code__c = '29463-7',
        lfemr__Observation_Display__c = 'Body weight',
        lfemr__Value_Quantity__c = 6.8,
        lfemr__Value_Unit__c = 'kg',
        lfemr__Interpretation__c = 'Normal',
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 8, 18, 10, 5, 0)
    ),
    new lfemr__Observation__c(
        lfemr__Source_System_Id__c = 'seed-obs-sofia-hr',
        lfemr__FHIR_Id__c = 'seed-obs-sofia-hr',
        lfemr__Patient__c = sofia,
        lfemr__Encounter__c = sofiaProgress,
        lfemr__Performer__c = patel,
        lfemr__Category__c = 'Vital Signs',
        lfemr__Status__c = 'Final',
        lfemr__Observation_Code_System__c = 'LOINC',
        lfemr__Observation_Code__c = '8867-4',
        lfemr__Observation_Display__c = 'Heart rate',
        lfemr__Value_Quantity__c = 112,
        lfemr__Value_Unit__c = '/min',
        lfemr__Interpretation__c = 'High',
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 8, 31, 13, 50, 0)
    ),
    new lfemr__Observation__c(
        lfemr__Source_System_Id__c = 'seed-obs-james-sbp',
        lfemr__FHIR_Id__c = 'seed-obs-james-sbp',
        lfemr__Patient__c = james,
        lfemr__Encounter__c = jamesIp,
        lfemr__Performer__c = vasquez,
        lfemr__Category__c = 'Vital Signs',
        lfemr__Status__c = 'Final',
        lfemr__Observation_Code_System__c = 'LOINC',
        lfemr__Observation_Code__c = '8480-6',
        lfemr__Observation_Display__c = 'Systolic blood pressure',
        lfemr__Value_Quantity__c = 154,
        lfemr__Value_Unit__c = 'mmHg',
        lfemr__Interpretation__c = 'High',
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 8, 3, 6, 0, 0)
    ),
    new lfemr__Observation__c(
        lfemr__Source_System_Id__c = 'seed-obs-ben-ldl',
        lfemr__FHIR_Id__c = 'seed-obs-ben-ldl',
        lfemr__Patient__c = benjamin,
        lfemr__Encounter__c = benFinished,
        lfemr__DiagnosticReport__c = drIds.get('seed-dr-ben-lipid'),
        lfemr__Category__c = 'Laboratory',
        lfemr__Status__c = 'Final',
        lfemr__Observation_Code_System__c = 'LOINC',
        lfemr__Observation_Code__c = '2089-1',
        lfemr__Observation_Display__c = 'LDL cholesterol',
        lfemr__Value_Quantity__c = 96,
        lfemr__Value_Unit__c = 'mg/dL',
        lfemr__Interpretation__c = 'Normal',
        lfemr__Reference_Range_High__c = 100,
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 5, 2, 8, 0, 0)
    ),
    new lfemr__Observation__c(
        lfemr__Source_System_Id__c = 'seed-obs-ethan-wt',
        lfemr__FHIR_Id__c = 'seed-obs-ethan-wt',
        lfemr__Patient__c = ethan,
        lfemr__Encounter__c = ethanWell,
        lfemr__Performer__c = vasquez,
        lfemr__Category__c = 'Vital Signs',
        lfemr__Status__c = 'Final',
        lfemr__Observation_Code_System__c = 'LOINC',
        lfemr__Observation_Code__c = '29463-7',
        lfemr__Observation_Display__c = 'Body weight',
        lfemr__Value_Quantity__c = 9.6,
        lfemr__Value_Unit__c = 'kg',
        lfemr__Interpretation__c = 'Normal',
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 9, 1, 15, 35, 0)
    )
};
for (lfemr__Observation__c row : observations) {
    row.lfemr__Observation_Ref__c = cat.get(
        row.lfemr__Observation_Code_System__c + '::' + row.lfemr__Observation_Code__c
    );
}
upsert observations lfemr__Source_System_Id__c;
System.debug(
    'Seeded ' +
        serviceRequests.size() +
        ' service requests, ' +
        reports.size() +
        ' reports, ' +
        observations.size() +
        ' observations.'
);
