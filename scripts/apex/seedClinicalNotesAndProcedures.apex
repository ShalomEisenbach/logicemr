/**
 * Idempotent seed for note templates, clinical notes, and procedures.
 * Requires seedDemoData.apex. Run seedCatalog.apex first for Procedure_Ref__c.
 * ClinicalNote Name is composed ({Note_Type__c} - {Author__r.Last_Name__c}).
 * Procedure Name is composed ({Procedure_Display__c} {Performed_DateTime__c}).
 * NoteTemplate Name is a Text Template Name — set it explicitly.
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
Id james = ptIds.get('seed-pt-james-okonkwo');
Id olivia = ptIds.get('seed-pt-olivia-kim');
Id lee = pracIds.get('seed-prac-lee');
Id patel = pracIds.get('seed-prac-patel');
Id chen = pracIds.get('seed-prac-chen');
Id mayaProgress = encIds.get('seed-enc-maya-progress');
Id mayaEd = encIds.get('seed-enc-maya-finished-ed');
Id mayaIp = encIds.get('seed-enc-maya-inpatient');
Id liamWell = encIds.get('seed-enc-liam-well');
Id sofiaProgress = encIds.get('seed-enc-sofia-progress');
Id jamesEd = encIds.get('seed-enc-james-ed');
Id jamesIp = encIds.get('seed-enc-james-ip');
Id oliviaVirtual = encIds.get('seed-enc-olivia-virtual');

List<lfemr__NoteTemplate__c> desiredTemplates = new List<lfemr__NoteTemplate__c>{
    new lfemr__NoteTemplate__c(
        Name = 'Hypertension Follow-up',
        lfemr__Shortcut__c = '.htn',
        lfemr__Category__c = 'Progress Note',
        lfemr__Active__c = true,
        lfemr__Body__c = '<p>BP reviewed. Continue current antihypertensive therapy. Counsel on home readings and sodium restriction.</p>'
    ),
    new lfemr__NoteTemplate__c(
        Name = 'Cardiovascular ROS',
        lfemr__Shortcut__c = '.ros-cv',
        lfemr__Category__c = 'ROS',
        lfemr__Active__c = true,
        lfemr__Body__c = '<p>Denies chest pain, orthopnea, PND. Reports palpitations. No syncope.</p>'
    ),
    new lfemr__NoteTemplate__c(
        Name = 'General Physical Exam',
        lfemr__Shortcut__c = '.pe',
        lfemr__Category__c = 'Physical Exam',
        lfemr__Active__c = true,
        lfemr__Body__c = '<p>General: NAD. HEENT: NCAT. Lungs: CTAB. Heart: RRR, no m/r/g. Abd: soft, NT. Ext: no edema.</p>'
    ),
    new lfemr__NoteTemplate__c(
        Name = 'Diabetes Assessment/Plan',
        lfemr__Shortcut__c = '.dm-ap',
        lfemr__Category__c = 'Assessment/Plan',
        lfemr__Active__c = true,
        lfemr__Body__c = '<p>Type 2 DM: A1c above goal. Continue metformin. Endocrine referral. Recheck A1c in 3 months.</p>'
    )
};

Set<String> templateNames = new Set<String>();
for (lfemr__NoteTemplate__c row : desiredTemplates) {
    templateNames.add(row.Name);
}
Map<String, Id> existingTemplateIds = new Map<String, Id>();
for (lfemr__NoteTemplate__c row : [
    SELECT Id, Name
    FROM lfemr__NoteTemplate__c
    WHERE Name IN :templateNames
]) {
    existingTemplateIds.put(row.Name, row.Id);
}
for (lfemr__NoteTemplate__c row : desiredTemplates) {
    if (existingTemplateIds.containsKey(row.Name)) {
        row.Id = existingTemplateIds.get(row.Name);
    }
}
upsert desiredTemplates;

List<lfemr__ClinicalNote__c> notes = new List<lfemr__ClinicalNote__c>{
    new lfemr__ClinicalNote__c(
        lfemr__Source_System_Id__c = 'seed-note-maya-progress',
        lfemr__FHIR_Id__c = 'seed-note-maya-progress',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaProgress,
        lfemr__Author__c = lee,
        lfemr__Note_Type__c = 'Progress Note',
        lfemr__Status__c = 'Signed',
        lfemr__Signed_Date__c = Datetime.newInstance(2026, 9, 1, 10, 5, 0),
        lfemr__Body__c = '<p>Follow-up hypertension and diabetes. BP 142/88. Continue metformin and lisinopril. Endocrine referral placed.</p>'
    ),
    new lfemr__ClinicalNote__c(
        lfemr__Source_System_Id__c = 'seed-note-maya-ed',
        lfemr__FHIR_Id__c = 'seed-note-maya-ed',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaEd,
        lfemr__Author__c = chen,
        lfemr__Note_Type__c = 'Progress Note',
        lfemr__Status__c = 'Signed',
        lfemr__Signed_Date__c = Datetime.newInstance(2026, 6, 4, 2, 45, 0),
        lfemr__Body__c = '<p>Chest tightness, troponin negative. ECG without acute ischemic changes. Symptoms resolved. Discharge home.</p>'
    ),
    new lfemr__ClinicalNote__c(
        lfemr__Source_System_Id__c = 'seed-note-maya-dc',
        lfemr__FHIR_Id__c = 'seed-note-maya-dc',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaIp,
        lfemr__Author__c = lee,
        lfemr__Note_Type__c = 'Discharge Summary',
        lfemr__Status__c = 'Signed',
        lfemr__Signed_Date__c = Datetime.newInstance(2025, 11, 21, 10, 30, 0),
        lfemr__Body__c = '<p>Admitted for hyperglycemia. Insulin sliding scale while inpatient. Transitioned back to metformin. A1c pending outpatient.</p>'
    ),
    new lfemr__ClinicalNote__c(
        lfemr__Source_System_Id__c = 'seed-note-sofia-consult',
        lfemr__FHIR_Id__c = 'seed-note-sofia-consult',
        lfemr__Patient__c = sofia,
        lfemr__Encounter__c = sofiaProgress,
        lfemr__Author__c = patel,
        lfemr__Note_Type__c = 'Consult',
        lfemr__Status__c = 'Draft',
        lfemr__Body__c = '<p>Palpitations in known atrial fibrillation. HR 112 in clinic. Echo ordered. Continue metoprolol and apixaban.</p>'
    ),
    new lfemr__ClinicalNote__c(
        lfemr__Source_System_Id__c = 'seed-note-james-hp',
        lfemr__FHIR_Id__c = 'seed-note-james-hp',
        lfemr__Patient__c = james,
        lfemr__Encounter__c = jamesIp,
        lfemr__Author__c = lee,
        lfemr__Note_Type__c = 'H&P',
        lfemr__Status__c = 'Signed',
        lfemr__Signed_Date__c = Datetime.newInstance(2026, 8, 3, 6, 30, 0),
        lfemr__Body__c = '<p>78-year-old with fall and right femoral neck fracture. Orthopedics consulted. VTE prophylaxis started. Osteoporosis on problem list.</p>'
    ),
    new lfemr__ClinicalNote__c(
        lfemr__Source_System_Id__c = 'seed-note-olivia-progress',
        lfemr__FHIR_Id__c = 'seed-note-olivia-progress',
        lfemr__Patient__c = olivia,
        lfemr__Encounter__c = oliviaVirtual,
        lfemr__Author__c = patel,
        lfemr__Note_Type__c = 'Progress Note',
        lfemr__Status__c = 'Signed',
        lfemr__Signed_Date__c = Datetime.newInstance(2026, 7, 8, 18, 18, 0),
        lfemr__Body__c = '<p>Anxiety follow-up. Sleep improved on sertraline 50 mg. Continue current dose. Recheck in 6 weeks.</p>'
    ),
    new lfemr__ClinicalNote__c(
        lfemr__Source_System_Id__c = 'seed-note-liam-well',
        lfemr__FHIR_Id__c = 'seed-note-liam-well',
        lfemr__Patient__c = liam,
        lfemr__Encounter__c = liamWell,
        lfemr__Author__c = lee,
        lfemr__Note_Type__c = 'Progress Note',
        lfemr__Status__c = 'Signed',
        lfemr__Signed_Date__c = Datetime.newInstance(2026, 7, 22, 10, 0, 0),
        lfemr__Body__c = '<p>6-year well child. Growth tracking. Mild intermittent asthma, albuterol PRN. DTaP given today.</p>'
    )
};
upsert notes lfemr__Source_System_Id__c;

List<lfemr__Procedure__c> procedures = new List<lfemr__Procedure__c>{
    new lfemr__Procedure__c(
        lfemr__Source_System_Id__c = 'seed-proc-maya-ecg',
        lfemr__FHIR_Id__c = 'seed-proc-maya-ecg',
        lfemr__Patient__c = maya,
        lfemr__Encounter__c = mayaEd,
        lfemr__Performer__c = chen,
        lfemr__Category__c = 'Diagnostic',
        lfemr__Status__c = 'Completed',
        lfemr__Procedure_Code_System__c = 'CPT',
        lfemr__Procedure_Code__c = '93000',
        lfemr__Procedure_Display__c = 'Electrocardiogram, complete',
        lfemr__Procedure_Ref__c = cat.get('CPT::93000'),
        lfemr__Performed_DateTime__c = Datetime.newInstance(2026, 6, 3, 23, 5, 0),
        lfemr__Notes__c = 'No acute ST changes.'
    ),
    new lfemr__Procedure__c(
        lfemr__Source_System_Id__c = 'seed-proc-james-orif',
        lfemr__FHIR_Id__c = 'seed-proc-james-orif',
        lfemr__Patient__c = james,
        lfemr__Encounter__c = jamesIp,
        lfemr__Performer__c = chen,
        lfemr__Category__c = 'Surgical',
        lfemr__Status__c = 'In Progress',
        lfemr__Procedure_Code_System__c = 'CPT',
        lfemr__Procedure_Code__c = '27236',
        lfemr__Procedure_Display__c = 'Open treatment of femoral neck fracture',
        lfemr__Procedure_Ref__c = cat.get('CPT::27236'),
        lfemr__Performed_DateTime__c = Datetime.newInstance(2026, 8, 3, 14, 0, 0),
        lfemr__Notes__c = 'ORIF planned after ED diagnosis of displaced femoral neck fracture.'
    ),
    new lfemr__Procedure__c(
        lfemr__Source_System_Id__c = 'seed-proc-sofia-chole',
        lfemr__FHIR_Id__c = 'seed-proc-sofia-chole',
        lfemr__Patient__c = sofia,
        lfemr__Performer__c = chen,
        lfemr__Category__c = 'Surgical',
        lfemr__Status__c = 'Preparation',
        lfemr__Procedure_Code_System__c = 'CPT',
        lfemr__Procedure_Code__c = '47562',
        lfemr__Procedure_Display__c = 'Laparoscopic cholecystectomy',
        lfemr__Procedure_Ref__c = cat.get('CPT::47562'),
        lfemr__Performed_DateTime__c = Datetime.newInstance(2026, 9, 20, 7, 30, 0),
        lfemr__Notes__c = 'Elective cholecystectomy for symptomatic cholelithiasis.'
    ),
    new lfemr__Procedure__c(
        lfemr__Source_System_Id__c = 'seed-proc-james-xray',
        lfemr__FHIR_Id__c = 'seed-proc-james-xray',
        lfemr__Patient__c = james,
        lfemr__Encounter__c = jamesEd,
        lfemr__Performer__c = chen,
        lfemr__Category__c = 'Diagnostic',
        lfemr__Status__c = 'Completed',
        lfemr__Procedure_Code_System__c = 'CPT',
        lfemr__Procedure_Code__c = '73502',
        lfemr__Procedure_Display__c = 'X-ray hip, 2 or 3 views',
        lfemr__Procedure_Ref__c = cat.get('CPT::73502'),
        lfemr__Performed_DateTime__c = Datetime.newInstance(2026, 8, 2, 19, 35, 0)
    )
};
upsert procedures lfemr__Source_System_Id__c;

System.debug(
    'Seeded ' +
        desiredTemplates.size() +
        ' note templates, ' +
        notes.size() +
        ' clinical notes, ' +
        procedures.size() +
        ' procedures.'
);
