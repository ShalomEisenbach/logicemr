/**
 * Idempotent clinical seed for medication requests, statements, and administrations.
 * Requires seedDemoData.apex. Run seedCatalog.apex first for Medication_Ref__c.
 * Do not set Name — composed from medication display, dose, and related request.
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
List<lfemr__MedicationRequest__c> medRequests = new List<lfemr__MedicationRequest__c>{
    new lfemr__MedicationRequest__c(
        lfemr__Source_System_Id__c = 'seed-medreq-maya-metformin',
        lfemr__FHIR_Id__c = 'seed-medreq-maya-metformin',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaProgress,
        lfemr__Requester__c = lee,
        lfemr__Status__c = 'Active',
        lfemr__Intent__c = 'Order',
        lfemr__Medication_Code_System__c = 'RxNorm',
        lfemr__Medication_Code__c = '860975',
        lfemr__Medication_Display__c = 'Metformin 500 mg oral tablet',
        lfemr__Dosage_Text__c = '500 mg by mouth twice daily',
        lfemr__Dose_Quantity__c = 500,
        lfemr__Dose_Unit__c = 'mg',
        lfemr__Frequency__c = 'BID',
        lfemr__Route__c = 'Oral',
        lfemr__Authored_On__c = Datetime.newInstance(2026, 9, 1, 9, 40, 0)
    ),
    new lfemr__MedicationRequest__c(
        lfemr__Source_System_Id__c = 'seed-medreq-maya-lisinopril',
        lfemr__FHIR_Id__c = 'seed-medreq-maya-lisinopril',
        lfemr__Patient__c = maya,
        lfemr__Requester__c = lee,
        lfemr__Status__c = 'Active',
        lfemr__Intent__c = 'Order',
        lfemr__Medication_Code_System__c = 'RxNorm',
        lfemr__Medication_Code__c = '314076',
        lfemr__Medication_Display__c = 'Lisinopril 10 mg oral tablet',
        lfemr__Dosage_Text__c = '10 mg by mouth daily',
        lfemr__Dose_Quantity__c = 10,
        lfemr__Dose_Unit__c = 'mg',
        lfemr__Frequency__c = 'Daily',
        lfemr__Route__c = 'Oral',
        lfemr__Authored_On__c = Datetime.newInstance(2026, 3, 14, 11, 0, 0)
    ),
    new lfemr__MedicationRequest__c(
        lfemr__Source_System_Id__c = 'seed-medreq-maya-atorva',
        lfemr__FHIR_Id__c = 'seed-medreq-maya-atorva',
        lfemr__Patient__c = maya,
        lfemr__Requester__c = patel,
        lfemr__Status__c = 'Active',
        lfemr__Intent__c = 'Order',
        lfemr__Medication_Code_System__c = 'RxNorm',
        lfemr__Medication_Code__c = '617310',
        lfemr__Medication_Display__c = 'Atorvastatin 20 mg oral tablet',
        lfemr__Dosage_Text__c = '20 mg by mouth at bedtime',
        lfemr__Dose_Quantity__c = 20,
        lfemr__Dose_Unit__c = 'mg',
        lfemr__Frequency__c = 'Nightly',
        lfemr__Route__c = 'Oral',
        lfemr__Authored_On__c = Datetime.newInstance(2025, 11, 21, 10, 0, 0)
    ),
    new lfemr__MedicationRequest__c(
        lfemr__Source_System_Id__c = 'seed-medreq-maya-insulin',
        lfemr__FHIR_Id__c = 'seed-medreq-maya-insulin',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaIp,
        lfemr__Requester__c = lee,
        lfemr__Status__c = 'Stopped',
        lfemr__Intent__c = 'Order',
        lfemr__Medication_Code_System__c = 'RxNorm',
        lfemr__Medication_Code__c = '311040',
        lfemr__Medication_Display__c = 'Insulin regular, human',
        lfemr__Dosage_Text__c = 'Sliding scale while inpatient',
        lfemr__Route__c = 'Subcutaneous',
        lfemr__Authored_On__c = Datetime.newInstance(2025, 11, 18, 8, 0, 0)
    ),
    new lfemr__MedicationRequest__c(
        lfemr__Source_System_Id__c = 'seed-medreq-sofia-metop',
        lfemr__FHIR_Id__c = 'seed-medreq-sofia-metop',
        lfemr__Patient__c = sofia,
        lfemr__Encounter__c = sofiaProgress,
        lfemr__Requester__c = patel,
        lfemr__Status__c = 'Active',
        lfemr__Intent__c = 'Order',
        lfemr__Medication_Code_System__c = 'RxNorm',
        lfemr__Medication_Code__c = '866412',
        lfemr__Medication_Display__c = 'Metoprolol tartrate 25 mg oral tablet',
        lfemr__Dosage_Text__c = '25 mg by mouth twice daily',
        lfemr__Dose_Quantity__c = 25,
        lfemr__Dose_Unit__c = 'mg',
        lfemr__Frequency__c = 'BID',
        lfemr__Route__c = 'Oral',
        lfemr__Authored_On__c = Datetime.newInstance(2026, 8, 31, 14, 10, 0)
    ),
    new lfemr__MedicationRequest__c(
        lfemr__Source_System_Id__c = 'seed-medreq-sofia-eliquis',
        lfemr__FHIR_Id__c = 'seed-medreq-sofia-eliquis',
        lfemr__Patient__c = sofia,
        lfemr__Requester__c = patel,
        lfemr__Status__c = 'Active',
        lfemr__Intent__c = 'Order',
        lfemr__Medication_Code_System__c = 'RxNorm',
        lfemr__Medication_Code__c = '1364430',
        lfemr__Medication_Display__c = 'Apixaban 5 mg oral tablet',
        lfemr__Dosage_Text__c = '5 mg by mouth twice daily',
        lfemr__Dose_Quantity__c = 5,
        lfemr__Dose_Unit__c = 'mg',
        lfemr__Frequency__c = 'BID',
        lfemr__Route__c = 'Oral',
        lfemr__Authored_On__c = Datetime.newInstance(2024, 9, 4, 9, 0, 0)
    ),
    new lfemr__MedicationRequest__c(
        lfemr__Source_System_Id__c = 'seed-medreq-james-enox',
        lfemr__FHIR_Id__c = 'seed-medreq-james-enox',
        lfemr__Patient__c = james,
        lfemr__Encounter__c = jamesIp,
        lfemr__Requester__c = chen,
        lfemr__Status__c = 'Active',
        lfemr__Intent__c = 'Order',
        lfemr__Medication_Code_System__c = 'RxNorm',
        lfemr__Medication_Code__c = '854235',
        lfemr__Medication_Display__c = 'Enoxaparin 40 mg/0.4 mL injection',
        lfemr__Dosage_Text__c = '40 mg subcutaneously daily',
        lfemr__Dose_Quantity__c = 40,
        lfemr__Dose_Unit__c = 'mg',
        lfemr__Frequency__c = 'Daily',
        lfemr__Route__c = 'Subcutaneous',
        lfemr__Authored_On__c = Datetime.newInstance(2026, 8, 3, 3, 0, 0)
    ),
    new lfemr__MedicationRequest__c(
        lfemr__Source_System_Id__c = 'seed-medreq-olivia-sert',
        lfemr__FHIR_Id__c = 'seed-medreq-olivia-sert',
        lfemr__Patient__c = olivia,
        lfemr__Encounter__c = oliviaVirtual,
        lfemr__Requester__c = patel,
        lfemr__Status__c = 'Active',
        lfemr__Intent__c = 'Order',
        lfemr__Medication_Code_System__c = 'RxNorm',
        lfemr__Medication_Code__c = '312940',
        lfemr__Medication_Display__c = 'Sertraline 50 mg oral tablet',
        lfemr__Dosage_Text__c = '50 mg by mouth daily',
        lfemr__Dose_Quantity__c = 50,
        lfemr__Dose_Unit__c = 'mg',
        lfemr__Frequency__c = 'Daily',
        lfemr__Route__c = 'Oral',
        lfemr__Authored_On__c = Datetime.newInstance(2026, 7, 8, 18, 10, 0)
    ),
    new lfemr__MedicationRequest__c(
        lfemr__Source_System_Id__c = 'seed-medreq-ben-atorva',
        lfemr__FHIR_Id__c = 'seed-medreq-ben-atorva',
        lfemr__Patient__c = benjamin,
        lfemr__Encounter__c = benFinished,
        lfemr__Requester__c = lee,
        lfemr__Status__c = 'Active',
        lfemr__Intent__c = 'Order',
        lfemr__Medication_Code_System__c = 'RxNorm',
        lfemr__Medication_Code__c = '617310',
        lfemr__Medication_Display__c = 'Atorvastatin 40 mg oral tablet',
        lfemr__Dosage_Text__c = '40 mg by mouth at bedtime',
        lfemr__Dose_Quantity__c = 40,
        lfemr__Dose_Unit__c = 'mg',
        lfemr__Frequency__c = 'Nightly',
        lfemr__Route__c = 'Oral',
        lfemr__Authored_On__c = Datetime.newInstance(2026, 5, 6, 11, 20, 0)
    )
};
for (lfemr__MedicationRequest__c row : medRequests) {
    row.lfemr__Medication_Ref__c = cat.get(
        row.lfemr__Medication_Code_System__c + '::' + row.lfemr__Medication_Code__c
    );
}
upsert medRequests lfemr__Source_System_Id__c;
Map<String, Id> medReqIds = new Map<String, Id>();
for (lfemr__MedicationRequest__c row : medRequests) {
    medReqIds.put(row.lfemr__Source_System_Id__c, row.Id);
}

List<lfemr__MedicationStatement__c> medStatements = new List<lfemr__MedicationStatement__c>{
    new lfemr__MedicationStatement__c(
        lfemr__Source_System_Id__c = 'seed-medstmt-maya-asa',
        lfemr__FHIR_Id__c = 'seed-medstmt-maya-asa',
        lfemr__Patient__c = maya,
        lfemr__Status__c = 'Active',
        lfemr__Source__c = 'Patient Reported',
        lfemr__Medication_Code_System__c = 'RxNorm',
        lfemr__Medication_Code__c = '1191',
        lfemr__Medication_Display__c = 'Aspirin 81 mg oral tablet',
        lfemr__Dosage_Text__c = '81 mg daily',
        lfemr__Effective_Start__c = Date.newInstance(2024, 1, 1)
    ),
    new lfemr__MedicationStatement__c(
        lfemr__Source_System_Id__c = 'seed-medstmt-maya-vitd',
        lfemr__FHIR_Id__c = 'seed-medstmt-maya-vitd',
        lfemr__Patient__c = maya,
        lfemr__Status__c = 'Active',
        lfemr__Source__c = 'Pharmacy',
        lfemr__Medication_Code_System__c = 'RxNorm',
        lfemr__Medication_Code__c = '2418',
        lfemr__Medication_Display__c = 'Cholecalciferol 2000 IU',
        lfemr__Dosage_Text__c = '2000 IU daily',
        lfemr__Effective_Start__c = Date.newInstance(2025, 2, 1)
    ),
    new lfemr__MedicationStatement__c(
        lfemr__Source_System_Id__c = 'seed-medstmt-liam-albut',
        lfemr__FHIR_Id__c = 'seed-medstmt-liam-albut',
        lfemr__Patient__c = liam,
        lfemr__Status__c = 'Active',
        lfemr__Source__c = 'Provider',
        lfemr__Medication_Code_System__c = 'RxNorm',
        lfemr__Medication_Code__c = '745679',
        lfemr__Medication_Display__c = 'Albuterol 90 mcg/actuation inhaler',
        lfemr__Dosage_Text__c = '2 puffs every 4 hours as needed',
        lfemr__Effective_Start__c = Date.newInstance(2023, 4, 12)
    ),
    new lfemr__MedicationStatement__c(
        lfemr__Source_System_Id__c = 'seed-medstmt-james-alend',
        lfemr__FHIR_Id__c = 'seed-medstmt-james-alend',
        lfemr__Patient__c = james,
        lfemr__Status__c = 'Active',
        lfemr__Source__c = 'Provider',
        lfemr__Medication_Code_System__c = 'RxNorm',
        lfemr__Medication_Code__c = '904421',
        lfemr__Medication_Display__c = 'Alendronate 70 mg oral tablet',
        lfemr__Dosage_Text__c = '70 mg weekly',
        lfemr__Effective_Start__c = Date.newInstance(2019, 1, 7)
    )
};
for (lfemr__MedicationStatement__c row : medStatements) {
    row.lfemr__Medication_Ref__c = cat.get(
        row.lfemr__Medication_Code_System__c + '::' + row.lfemr__Medication_Code__c
    );
}
upsert medStatements lfemr__Source_System_Id__c;

List<lfemr__MedicationAdministration__c> medAdmins = new List<lfemr__MedicationAdministration__c>{
    new lfemr__MedicationAdministration__c(
        lfemr__Source_System_Id__c = 'seed-medadm-maya-insulin-1',
        lfemr__FHIR_Id__c = 'seed-medadm-maya-insulin-1',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaIp,
        lfemr__Medication_Request__c = medReqIds.get('seed-medreq-maya-insulin'),
        lfemr__Performer__c = vasquez,
        lfemr__Status__c = 'Completed',
        lfemr__Dose_Quantity__c = 6,
        lfemr__Dose_Unit__c = 'units',
        lfemr__Effective_DateTime__c = Datetime.newInstance(2025, 11, 18, 12, 15, 0)
    ),
    new lfemr__MedicationAdministration__c(
        lfemr__Source_System_Id__c = 'seed-medadm-maya-insulin-2',
        lfemr__FHIR_Id__c = 'seed-medadm-maya-insulin-2',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaIp,
        lfemr__Medication_Request__c = medReqIds.get('seed-medreq-maya-insulin'),
        lfemr__Performer__c = vasquez,
        lfemr__Status__c = 'Completed',
        lfemr__Dose_Quantity__c = 4,
        lfemr__Dose_Unit__c = 'units',
        lfemr__Effective_DateTime__c = Datetime.newInstance(2025, 11, 18, 18, 5, 0)
    ),
    new lfemr__MedicationAdministration__c(
        lfemr__Source_System_Id__c = 'seed-medadm-james-enox-1',
        lfemr__FHIR_Id__c = 'seed-medadm-james-enox-1',
        lfemr__Patient__c = james,
        lfemr__Encounter__c = jamesIp,
        lfemr__Medication_Request__c = medReqIds.get('seed-medreq-james-enox'),
        lfemr__Performer__c = vasquez,
        lfemr__Status__c = 'Completed',
        lfemr__Dose_Quantity__c = 40,
        lfemr__Dose_Unit__c = 'mg',
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 8, 3, 8, 0, 0)
    ),
    new lfemr__MedicationAdministration__c(
        lfemr__Source_System_Id__c = 'seed-medadm-james-enox-2',
        lfemr__FHIR_Id__c = 'seed-medadm-james-enox-2',
        lfemr__Patient__c = james,
        lfemr__Encounter__c = jamesIp,
        lfemr__Medication_Request__c = medReqIds.get('seed-medreq-james-enox'),
        lfemr__Performer__c = vasquez,
        lfemr__Status__c = 'In Progress',
        lfemr__Dose_Quantity__c = 40,
        lfemr__Dose_Unit__c = 'mg',
        lfemr__Effective_DateTime__c = Datetime.newInstance(2026, 9, 1, 8, 0, 0)
    )
};
upsert medAdmins lfemr__Source_System_Id__c;
