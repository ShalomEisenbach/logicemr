/**
 * Idempotent LogicEMR demo seed. Re-run safe via Source_System_Id__c upsert.
 * Covers Patient Search, Patient Banner, Encounter Panel, and Care Team.
 * Do not set Name — Patient, Practitioner, Encounter, CareTeam, and
 * CareTeamMember Names are composed by NameFormatterHandler.
 */
Id runningUserId = UserInfo.getUserId();

List<lfemr__Practitioner__c> practitioners = new List<lfemr__Practitioner__c>{
    new lfemr__Practitioner__c(
        lfemr__Source_System_Id__c = 'seed-prac-lee',
        lfemr__FHIR_Id__c = 'seed-prac-lee',
        lfemr__First_Name__c = 'Jordan',
        lfemr__Last_Name__c = 'Lee',
        lfemr__NPI__c = '1000000001',
        lfemr__Active__c = true,
        lfemr__User__c = runningUserId,
        lfemr__Specialty__c = 'Primary Care'
    ),
    new lfemr__Practitioner__c(
        lfemr__Source_System_Id__c = 'seed-prac-patel',
        lfemr__FHIR_Id__c = 'seed-prac-patel',
        lfemr__First_Name__c = 'Priya',
        lfemr__Last_Name__c = 'Patel',
        lfemr__NPI__c = '1000000002',
        lfemr__Active__c = true,
        lfemr__Specialty__c = 'Cardiology'
    ),
    new lfemr__Practitioner__c(
        lfemr__Source_System_Id__c = 'seed-prac-chen',
        lfemr__FHIR_Id__c = 'seed-prac-chen',
        lfemr__First_Name__c = 'Marcus',
        lfemr__Last_Name__c = 'Chen',
        lfemr__NPI__c = '1000000003',
        lfemr__Active__c = true,
        lfemr__Specialty__c = 'Emergency Medicine'
    ),
    new lfemr__Practitioner__c(
        lfemr__Source_System_Id__c = 'seed-prac-vasquez',
        lfemr__FHIR_Id__c = 'seed-prac-vasquez',
        lfemr__First_Name__c = 'Elena',
        lfemr__Last_Name__c = 'Vasquez',
        lfemr__NPI__c = '1000000004',
        lfemr__Active__c = true,
        lfemr__Specialty__c = 'Nursing'
    ),
    new lfemr__Practitioner__c(
        lfemr__Source_System_Id__c = 'seed-prac-smith',
        lfemr__FHIR_Id__c = 'seed-prac-smith',
        lfemr__First_Name__c = 'Robert',
        lfemr__Last_Name__c = 'Smith',
        lfemr__NPI__c = '1000000005',
        lfemr__Active__c = false,
        lfemr__Specialty__c = 'Other'
    )
};
upsert practitioners lfemr__Source_System_Id__c;

Map<String, Id> pracIds = new Map<String, Id>();
for (lfemr__Practitioner__c row : practitioners) {
    pracIds.put(row.lfemr__Source_System_Id__c, row.Id);
}

List<lfemr__Patient__c> patients = new List<lfemr__Patient__c>{
    new lfemr__Patient__c(
        lfemr__Source_System_Id__c = 'seed-pt-maya-chen',
        lfemr__FHIR_Id__c = 'seed-pt-maya-chen',
        lfemr__First_Name__c = 'Maya',
        lfemr__Last_Name__c = 'Chen',
        lfemr__MRN__c = 'MRN-1001',
        lfemr__Date_of_Birth__c = Date.newInstance(1988, 3, 14),
        lfemr__Phone__c = '555-010-1001',
        lfemr__Sex_at_Birth__c = 'Female',
        lfemr__Status__c = 'Active'
    ),
    new lfemr__Patient__c(
        lfemr__Source_System_Id__c = 'seed-pt-liam-chen',
        lfemr__FHIR_Id__c = 'seed-pt-liam-chen',
        lfemr__First_Name__c = 'Liam',
        lfemr__Last_Name__c = 'Chen',
        lfemr__MRN__c = 'MRN-1002',
        lfemr__Date_of_Birth__c = Date.newInstance(2020, 7, 22),
        lfemr__Phone__c = '555-010-1002',
        lfemr__Sex_at_Birth__c = 'Male',
        lfemr__Status__c = 'Active'
    ),
    new lfemr__Patient__c(
        lfemr__Source_System_Id__c = 'seed-pt-sofia-rivera',
        lfemr__FHIR_Id__c = 'seed-pt-sofia-rivera',
        lfemr__First_Name__c = 'Sofia',
        lfemr__Last_Name__c = 'Rivera',
        lfemr__MRN__c = 'MRN-1003',
        lfemr__Date_of_Birth__c = Date.newInstance(1975, 11, 2),
        lfemr__Phone__c = '555-010-1003',
        lfemr__Sex_at_Birth__c = 'Female',
        lfemr__Status__c = 'Active'
    ),
    new lfemr__Patient__c(
        lfemr__Source_System_Id__c = 'seed-pt-noah-rivera',
        lfemr__FHIR_Id__c = 'seed-pt-noah-rivera',
        lfemr__First_Name__c = 'Noah',
        lfemr__Last_Name__c = 'Rivera',
        lfemr__MRN__c = 'MRN-1004',
        lfemr__Date_of_Birth__c = Date.newInstance(2026, 4, 18),
        lfemr__Phone__c = '555-010-1004',
        lfemr__Sex_at_Birth__c = 'Male',
        lfemr__Status__c = 'Active'
    ),
    new lfemr__Patient__c(
        lfemr__Source_System_Id__c = 'seed-pt-james-okonkwo',
        lfemr__FHIR_Id__c = 'seed-pt-james-okonkwo',
        lfemr__First_Name__c = 'James',
        lfemr__Last_Name__c = 'Okonkwo',
        lfemr__MRN__c = 'MRN-1005',
        lfemr__Date_of_Birth__c = Date.newInstance(1948, 1, 9),
        lfemr__Phone__c = '555-010-1005',
        lfemr__Sex_at_Birth__c = 'Male',
        lfemr__Status__c = 'Active'
    ),
    new lfemr__Patient__c(
        lfemr__Source_System_Id__c = 'seed-pt-ava-thompson',
        lfemr__FHIR_Id__c = 'seed-pt-ava-thompson',
        lfemr__First_Name__c = 'Ava',
        lfemr__Last_Name__c = 'Thompson',
        lfemr__MRN__c = 'MRN-1006',
        lfemr__Date_of_Birth__c = Date.newInstance(1992, 6, 30),
        lfemr__Phone__c = '555-010-1006',
        lfemr__Sex_at_Birth__c = 'Female',
        lfemr__Status__c = 'Inactive'
    ),
    new lfemr__Patient__c(
        lfemr__Source_System_Id__c = 'seed-pt-ethan-brooks',
        lfemr__FHIR_Id__c = 'seed-pt-ethan-brooks',
        lfemr__First_Name__c = 'Ethan',
        lfemr__Last_Name__c = 'Brooks',
        lfemr__MRN__c = 'MRN-1007',
        lfemr__Date_of_Birth__c = Date.newInstance(2025, 8, 15),
        lfemr__Phone__c = '555-010-1007',
        lfemr__Sex_at_Birth__c = 'Male',
        lfemr__Status__c = 'Active'
    ),
    new lfemr__Patient__c(
        lfemr__Source_System_Id__c = 'seed-pt-olivia-kim',
        lfemr__FHIR_Id__c = 'seed-pt-olivia-kim',
        lfemr__First_Name__c = 'Olivia',
        lfemr__Last_Name__c = 'Kim',
        lfemr__MRN__c = 'MRN-1008',
        lfemr__Date_of_Birth__c = Date.newInstance(2001, 12, 1),
        lfemr__Phone__c = '555-010-1008',
        lfemr__Sex_at_Birth__c = 'Female',
        lfemr__Status__c = 'Active'
    ),
    new lfemr__Patient__c(
        lfemr__Source_System_Id__c = 'seed-pt-benjamin-alvarez',
        lfemr__FHIR_Id__c = 'seed-pt-benjamin-alvarez',
        lfemr__First_Name__c = 'Benjamin',
        lfemr__Last_Name__c = 'Alvarez',
        lfemr__MRN__c = 'MRN-1009',
        lfemr__Date_of_Birth__c = Date.newInstance(1963, 5, 18),
        lfemr__Phone__c = '555-010-1009',
        lfemr__Sex_at_Birth__c = 'Male',
        lfemr__Status__c = 'Active'
    ),
    new lfemr__Patient__c(
        lfemr__Source_System_Id__c = 'seed-pt-harper-nguyen',
        lfemr__FHIR_Id__c = 'seed-pt-harper-nguyen',
        lfemr__First_Name__c = 'Harper',
        lfemr__Last_Name__c = 'Nguyen',
        lfemr__MRN__c = 'MRN-1010',
        lfemr__Date_of_Birth__c = Date.newInstance(2010, 9, 8),
        lfemr__Phone__c = '555-010-1010',
        lfemr__Sex_at_Birth__c = 'Unknown',
        lfemr__Status__c = 'Active'
    )
};
upsert patients lfemr__Source_System_Id__c;

Map<String, Id> ptIds = new Map<String, Id>();
for (lfemr__Patient__c row : patients) {
    ptIds.put(row.lfemr__Source_System_Id__c, row.Id);
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

List<lfemr__Encounter__c> encounters = new List<lfemr__Encounter__c>{
    new lfemr__Encounter__c(
        lfemr__Source_System_Id__c = 'seed-enc-maya-progress',
        lfemr__FHIR_Id__c = 'seed-enc-maya-progress',
        lfemr__Patient__c = maya,
        lfemr__Practitioner__c = lee,
        lfemr__Status__c = 'In Progress',
        lfemr__Class__c = 'Outpatient',
        lfemr__Start__c = Datetime.newInstance(2026, 9, 1, 9, 15, 0),
        lfemr__Location_Name__c = 'Primary Care Clinic A',
        lfemr__Reason__c = 'Follow-up hypertension'
    ),
    new lfemr__Encounter__c(
        lfemr__Source_System_Id__c = 'seed-enc-maya-arrived',
        lfemr__FHIR_Id__c = 'seed-enc-maya-arrived',
        lfemr__Patient__c = maya,
        lfemr__Practitioner__c = vasquez,
        lfemr__Status__c = 'Arrived',
        lfemr__Class__c = 'Outpatient',
        lfemr__Start__c = Datetime.newInstance(2026, 8, 28, 14, 0, 0),
        lfemr__Location_Name__c = 'Lab Draw Station',
        lfemr__Reason__c = 'Fasting labs'
    ),
    new lfemr__Encounter__c(
        lfemr__Source_System_Id__c = 'seed-enc-maya-planned',
        lfemr__FHIR_Id__c = 'seed-enc-maya-planned',
        lfemr__Patient__c = maya,
        lfemr__Practitioner__c = patel,
        lfemr__Status__c = 'Planned',
        lfemr__Class__c = 'Virtual',
        lfemr__Start__c = Datetime.newInstance(2026, 9, 12, 11, 0, 0),
        lfemr__Location_Name__c = 'Telehealth',
        lfemr__Reason__c = 'Endocrine consult'
    ),
    new lfemr__Encounter__c(
        lfemr__Source_System_Id__c = 'seed-enc-maya-finished-ed',
        lfemr__FHIR_Id__c = 'seed-enc-maya-finished-ed',
        lfemr__Patient__c = maya,
        lfemr__Practitioner__c = chen,
        lfemr__Status__c = 'Finished',
        lfemr__Class__c = 'Emergency',
        lfemr__Start__c = Datetime.newInstance(2026, 6, 3, 22, 40, 0),
        lfemr__End__c = Datetime.newInstance(2026, 6, 4, 3, 10, 0),
        lfemr__Location_Name__c = 'ED Bay 4',
        lfemr__Reason__c = 'Chest tightness'
    ),
    new lfemr__Encounter__c(
        lfemr__Source_System_Id__c = 'seed-enc-maya-inpatient',
        lfemr__FHIR_Id__c = 'seed-enc-maya-inpatient',
        lfemr__Patient__c = maya,
        lfemr__Practitioner__c = lee,
        lfemr__Status__c = 'Finished',
        lfemr__Class__c = 'Inpatient',
        lfemr__Start__c = Datetime.newInstance(2025, 11, 18, 7, 0, 0),
        lfemr__End__c = Datetime.newInstance(2025, 11, 21, 11, 30, 0),
        lfemr__Location_Name__c = 'Med-Surg 3 West',
        lfemr__Reason__c = 'Uncontrolled diabetes'
    ),
    new lfemr__Encounter__c(
        lfemr__Source_System_Id__c = 'seed-enc-maya-cancelled',
        lfemr__FHIR_Id__c = 'seed-enc-maya-cancelled',
        lfemr__Patient__c = maya,
        lfemr__Status__c = 'Cancelled',
        lfemr__Class__c = 'Outpatient',
        lfemr__Start__c = Datetime.newInstance(2026, 4, 9, 10, 0, 0),
        lfemr__Location_Name__c = 'Primary Care Clinic A',
        lfemr__Reason__c = 'Annual physical'
    ),
    new lfemr__Encounter__c(
        lfemr__Source_System_Id__c = 'seed-enc-liam-well',
        lfemr__FHIR_Id__c = 'seed-enc-liam-well',
        lfemr__Patient__c = liam,
        lfemr__Practitioner__c = lee,
        lfemr__Status__c = 'Finished',
        lfemr__Class__c = 'Outpatient',
        lfemr__Start__c = Datetime.newInstance(2026, 7, 22, 9, 30, 0),
        lfemr__End__c = Datetime.newInstance(2026, 7, 22, 10, 5, 0),
        lfemr__Location_Name__c = 'Pediatrics',
        lfemr__Reason__c = '6-year well child'
    ),
    new lfemr__Encounter__c(
        lfemr__Source_System_Id__c = 'seed-enc-liam-sick',
        lfemr__FHIR_Id__c = 'seed-enc-liam-sick',
        lfemr__Patient__c = liam,
        lfemr__Practitioner__c = vasquez,
        lfemr__Status__c = 'Finished',
        lfemr__Class__c = 'Virtual',
        lfemr__Start__c = Datetime.newInstance(2026, 3, 11, 16, 15, 0),
        lfemr__End__c = Datetime.newInstance(2026, 3, 11, 16, 35, 0),
        lfemr__Location_Name__c = 'Telehealth',
        lfemr__Reason__c = 'Otitis media follow-up'
    ),
    new lfemr__Encounter__c(
        lfemr__Source_System_Id__c = 'seed-enc-sofia-progress',
        lfemr__FHIR_Id__c = 'seed-enc-sofia-progress',
        lfemr__Patient__c = sofia,
        lfemr__Practitioner__c = patel,
        lfemr__Status__c = 'In Progress',
        lfemr__Class__c = 'Outpatient',
        lfemr__Start__c = Datetime.newInstance(2026, 8, 31, 13, 45, 0),
        lfemr__Location_Name__c = 'Cardiology Clinic',
        lfemr__Reason__c = 'Palpitations'
    ),
    new lfemr__Encounter__c(
        lfemr__Source_System_Id__c = 'seed-enc-sofia-finished',
        lfemr__FHIR_Id__c = 'seed-enc-sofia-finished',
        lfemr__Patient__c = sofia,
        lfemr__Practitioner__c = lee,
        lfemr__Status__c = 'Finished',
        lfemr__Class__c = 'Outpatient',
        lfemr__Start__c = Datetime.newInstance(2026, 2, 14, 8, 20, 0),
        lfemr__End__c = Datetime.newInstance(2026, 2, 14, 8, 50, 0),
        lfemr__Location_Name__c = 'Primary Care Clinic B',
        lfemr__Reason__c = 'Medication refill'
    ),
    new lfemr__Encounter__c(
        lfemr__Source_System_Id__c = 'seed-enc-sofia-planned',
        lfemr__FHIR_Id__c = 'seed-enc-sofia-planned',
        lfemr__Patient__c = sofia,
        lfemr__Practitioner__c = chen,
        lfemr__Status__c = 'Planned',
        lfemr__Class__c = 'Inpatient',
        lfemr__Start__c = Datetime.newInstance(2026, 9, 20, 6, 0, 0),
        lfemr__Location_Name__c = 'OR 2',
        lfemr__Reason__c = 'Elective cholecystectomy'
    ),
    new lfemr__Encounter__c(
        lfemr__Source_System_Id__c = 'seed-enc-noah-well',
        lfemr__FHIR_Id__c = 'seed-enc-noah-well',
        lfemr__Patient__c = noah,
        lfemr__Practitioner__c = lee,
        lfemr__Status__c = 'Finished',
        lfemr__Class__c = 'Outpatient',
        lfemr__Start__c = Datetime.newInstance(2026, 8, 18, 10, 0, 0),
        lfemr__End__c = Datetime.newInstance(2026, 8, 18, 10, 25, 0),
        lfemr__Location_Name__c = 'Pediatrics',
        lfemr__Reason__c = '4-month well child'
    ),
    new lfemr__Encounter__c(
        lfemr__Source_System_Id__c = 'seed-enc-james-ed',
        lfemr__FHIR_Id__c = 'seed-enc-james-ed',
        lfemr__Patient__c = james,
        lfemr__Practitioner__c = chen,
        lfemr__Status__c = 'Finished',
        lfemr__Class__c = 'Emergency',
        lfemr__Start__c = Datetime.newInstance(2026, 8, 2, 19, 5, 0),
        lfemr__End__c = Datetime.newInstance(2026, 8, 3, 1, 40, 0),
        lfemr__Location_Name__c = 'ED Bay 1',
        lfemr__Reason__c = 'Fall, hip pain'
    ),
    new lfemr__Encounter__c(
        lfemr__Source_System_Id__c = 'seed-enc-james-ip',
        lfemr__FHIR_Id__c = 'seed-enc-james-ip',
        lfemr__Patient__c = james,
        lfemr__Practitioner__c = lee,
        lfemr__Status__c = 'In Progress',
        lfemr__Class__c = 'Inpatient',
        lfemr__Start__c = Datetime.newInstance(2026, 8, 3, 2, 0, 0),
        lfemr__Location_Name__c = 'Orthopedics 4 East',
        lfemr__Reason__c = 'Hip fracture admission'
    ),
    new lfemr__Encounter__c(
        lfemr__Source_System_Id__c = 'seed-enc-ethan-well',
        lfemr__FHIR_Id__c = 'seed-enc-ethan-well',
        lfemr__Patient__c = ethan,
        lfemr__Practitioner__c = vasquez,
        lfemr__Status__c = 'Arrived',
        lfemr__Class__c = 'Outpatient',
        lfemr__Start__c = Datetime.newInstance(2026, 9, 1, 15, 30, 0),
        lfemr__Location_Name__c = 'Pediatrics',
        lfemr__Reason__c = '12-month well child'
    ),
    new lfemr__Encounter__c(
        lfemr__Source_System_Id__c = 'seed-enc-olivia-virtual',
        lfemr__FHIR_Id__c = 'seed-enc-olivia-virtual',
        lfemr__Patient__c = olivia,
        lfemr__Practitioner__c = patel,
        lfemr__Status__c = 'Finished',
        lfemr__Class__c = 'Virtual',
        lfemr__Start__c = Datetime.newInstance(2026, 7, 8, 18, 0, 0),
        lfemr__End__c = Datetime.newInstance(2026, 7, 8, 18, 20, 0),
        lfemr__Location_Name__c = 'Telehealth',
        lfemr__Reason__c = 'Anxiety follow-up'
    ),
    new lfemr__Encounter__c(
        lfemr__Source_System_Id__c = 'seed-enc-olivia-planned',
        lfemr__FHIR_Id__c = 'seed-enc-olivia-planned',
        lfemr__Patient__c = olivia,
        lfemr__Practitioner__c = lee,
        lfemr__Status__c = 'Planned',
        lfemr__Class__c = 'Outpatient',
        lfemr__Start__c = Datetime.newInstance(2026, 9, 18, 9, 0, 0),
        lfemr__Location_Name__c = 'Primary Care Clinic A',
        lfemr__Reason__c = 'Annual physical'
    ),
    new lfemr__Encounter__c(
        lfemr__Source_System_Id__c = 'seed-enc-ben-finished',
        lfemr__FHIR_Id__c = 'seed-enc-ben-finished',
        lfemr__Patient__c = benjamin,
        lfemr__Practitioner__c = lee,
        lfemr__Status__c = 'Finished',
        lfemr__Class__c = 'Outpatient',
        lfemr__Start__c = Datetime.newInstance(2026, 5, 6, 11, 10, 0),
        lfemr__End__c = Datetime.newInstance(2026, 5, 6, 11, 40, 0),
        lfemr__Location_Name__c = 'Primary Care Clinic B',
        lfemr__Reason__c = 'Lipid panel review'
    ),
    new lfemr__Encounter__c(
        lfemr__Source_System_Id__c = 'seed-enc-ben-virtual',
        lfemr__FHIR_Id__c = 'seed-enc-ben-virtual',
        lfemr__Patient__c = benjamin,
        lfemr__Status__c = 'Cancelled',
        lfemr__Class__c = 'Virtual',
        lfemr__Start__c = Datetime.newInstance(2026, 6, 20, 15, 0, 0),
        lfemr__Location_Name__c = 'Telehealth',
        lfemr__Reason__c = 'Blood pressure check'
    ),
    new lfemr__Encounter__c(
        lfemr__Source_System_Id__c = 'seed-enc-ben-progress',
        lfemr__FHIR_Id__c = 'seed-enc-ben-progress',
        lfemr__Patient__c = benjamin,
        lfemr__Practitioner__c = patel,
        lfemr__Status__c = 'Arrived',
        lfemr__Class__c = 'Outpatient',
        lfemr__Start__c = Datetime.newInstance(2026, 8, 27, 8, 45, 0),
        lfemr__Location_Name__c = 'Cardiology Clinic',
        lfemr__Reason__c = 'Stress test'
    ),
    new lfemr__Encounter__c(
        lfemr__Source_System_Id__c = 'seed-enc-harper-sports',
        lfemr__FHIR_Id__c = 'seed-enc-harper-sports',
        lfemr__Patient__c = harper,
        lfemr__Practitioner__c = vasquez,
        lfemr__Status__c = 'Finished',
        lfemr__Class__c = 'Outpatient',
        lfemr__Start__c = Datetime.newInstance(2026, 8, 10, 16, 0, 0),
        lfemr__End__c = Datetime.newInstance(2026, 8, 10, 16, 20, 0),
        lfemr__Location_Name__c = 'Pediatrics',
        lfemr__Reason__c = 'Sports physical'
    )
};
upsert encounters lfemr__Source_System_Id__c;

List<lfemr__CareTeam__c> careTeams = new List<lfemr__CareTeam__c>{
    new lfemr__CareTeam__c(
        lfemr__Source_System_Id__c = 'seed-ct-maya',
        lfemr__FHIR_Id__c = 'seed-ct-maya',
        lfemr__Patient__c = maya,
        lfemr__Status__c = 'Active'
    ),
    new lfemr__CareTeam__c(
        lfemr__Source_System_Id__c = 'seed-ct-sofia',
        lfemr__FHIR_Id__c = 'seed-ct-sofia',
        lfemr__Patient__c = sofia,
        lfemr__Status__c = 'Active'
    ),
    new lfemr__CareTeam__c(
        lfemr__Source_System_Id__c = 'seed-ct-james',
        lfemr__FHIR_Id__c = 'seed-ct-james',
        lfemr__Patient__c = james,
        lfemr__Status__c = 'Active'
    ),
    new lfemr__CareTeam__c(
        lfemr__Source_System_Id__c = 'seed-ct-liam',
        lfemr__FHIR_Id__c = 'seed-ct-liam',
        lfemr__Patient__c = liam,
        lfemr__Status__c = 'Active'
    )
};
upsert careTeams lfemr__Source_System_Id__c;

Map<String, Id> ctIds = new Map<String, Id>();
for (lfemr__CareTeam__c row : careTeams) {
    ctIds.put(row.lfemr__Source_System_Id__c, row.Id);
}

List<lfemr__CareTeamMember__c> members = new List<lfemr__CareTeamMember__c>{
    new lfemr__CareTeamMember__c(
        lfemr__Source_System_Id__c = 'seed-ctm-maya-lee',
        lfemr__FHIR_Id__c = 'seed-ctm-maya-lee',
        lfemr__Care_Team__c = ctIds.get('seed-ct-maya'),
        lfemr__Practitioner__c = lee,
        lfemr__User__c = runningUserId,
        lfemr__Role__c = 'Attending',
        lfemr__Access_Level__c = 'Edit',
        lfemr__Active__c = true
    ),
    new lfemr__CareTeamMember__c(
        lfemr__Source_System_Id__c = 'seed-ctm-maya-patel',
        lfemr__FHIR_Id__c = 'seed-ctm-maya-patel',
        lfemr__Care_Team__c = ctIds.get('seed-ct-maya'),
        lfemr__Practitioner__c = patel,
        lfemr__Role__c = 'Consulting',
        lfemr__Access_Level__c = 'Read',
        lfemr__Active__c = true
    ),
    new lfemr__CareTeamMember__c(
        lfemr__Source_System_Id__c = 'seed-ctm-maya-vasquez',
        lfemr__FHIR_Id__c = 'seed-ctm-maya-vasquez',
        lfemr__Care_Team__c = ctIds.get('seed-ct-maya'),
        lfemr__Practitioner__c = vasquez,
        lfemr__Role__c = 'Nurse',
        lfemr__Access_Level__c = 'Edit',
        lfemr__Active__c = true
    ),
    new lfemr__CareTeamMember__c(
        lfemr__Source_System_Id__c = 'seed-ctm-maya-chen',
        lfemr__FHIR_Id__c = 'seed-ctm-maya-chen',
        lfemr__Care_Team__c = ctIds.get('seed-ct-maya'),
        lfemr__Practitioner__c = chen,
        lfemr__Role__c = 'Care Coordinator',
        lfemr__Access_Level__c = 'Read',
        lfemr__Active__c = true
    ),
    new lfemr__CareTeamMember__c(
        lfemr__Source_System_Id__c = 'seed-ctm-maya-smith',
        lfemr__FHIR_Id__c = 'seed-ctm-maya-smith',
        lfemr__Care_Team__c = ctIds.get('seed-ct-maya'),
        lfemr__Practitioner__c = pracIds.get('seed-prac-smith'),
        lfemr__Role__c = 'Other',
        lfemr__Access_Level__c = 'Read',
        lfemr__Active__c = false
    ),
    new lfemr__CareTeamMember__c(
        lfemr__Source_System_Id__c = 'seed-ctm-sofia-lee',
        lfemr__FHIR_Id__c = 'seed-ctm-sofia-lee',
        lfemr__Care_Team__c = ctIds.get('seed-ct-sofia'),
        lfemr__Practitioner__c = lee,
        lfemr__User__c = runningUserId,
        lfemr__Role__c = 'Attending',
        lfemr__Access_Level__c = 'Edit',
        lfemr__Active__c = true
    ),
    new lfemr__CareTeamMember__c(
        lfemr__Source_System_Id__c = 'seed-ctm-sofia-patel',
        lfemr__FHIR_Id__c = 'seed-ctm-sofia-patel',
        lfemr__Care_Team__c = ctIds.get('seed-ct-sofia'),
        lfemr__Practitioner__c = patel,
        lfemr__Role__c = 'Consulting',
        lfemr__Access_Level__c = 'Read',
        lfemr__Active__c = true
    ),
    new lfemr__CareTeamMember__c(
        lfemr__Source_System_Id__c = 'seed-ctm-james-lee',
        lfemr__FHIR_Id__c = 'seed-ctm-james-lee',
        lfemr__Care_Team__c = ctIds.get('seed-ct-james'),
        lfemr__Practitioner__c = lee,
        lfemr__User__c = runningUserId,
        lfemr__Role__c = 'Attending',
        lfemr__Access_Level__c = 'Edit',
        lfemr__Active__c = true
    ),
    new lfemr__CareTeamMember__c(
        lfemr__Source_System_Id__c = 'seed-ctm-james-chen',
        lfemr__FHIR_Id__c = 'seed-ctm-james-chen',
        lfemr__Care_Team__c = ctIds.get('seed-ct-james'),
        lfemr__Practitioner__c = chen,
        lfemr__Role__c = 'Consulting',
        lfemr__Access_Level__c = 'Read',
        lfemr__Active__c = true
    ),
    new lfemr__CareTeamMember__c(
        lfemr__Source_System_Id__c = 'seed-ctm-liam-lee',
        lfemr__FHIR_Id__c = 'seed-ctm-liam-lee',
        lfemr__Care_Team__c = ctIds.get('seed-ct-liam'),
        lfemr__Practitioner__c = lee,
        lfemr__User__c = runningUserId,
        lfemr__Role__c = 'Attending',
        lfemr__Access_Level__c = 'Edit',
        lfemr__Active__c = true
    )
};
upsert members lfemr__Source_System_Id__c;

System.debug(
    'Seeded ' +
        practitioners.size() +
        ' practitioners, ' +
        patients.size() +
        ' patients, ' +
        encounters.size() +
        ' encounters, ' +
        careTeams.size() +
        ' care teams, ' +
        members.size() +
        ' care team members.'
);
