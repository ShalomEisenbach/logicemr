/**
 * Idempotent seed for NoteTemplate__c (config / dot phrases).
 * Does not require demo patients. Match on Template Name.
 * NoteTemplate Name is a Text Template Name — set it explicitly.
 *
 *   sf apex run --file scripts/apex/seedNoteTemplates.apex
 */
List<lfemr__NoteTemplate__c> desiredTemplates = new List<lfemr__NoteTemplate__c>{
    // Progress Note
    tpl(
        'SOAP Note',
        '.soap',
        'Progress Note',
        '<p><strong>Subjective</strong></p><p>Chief complaint and history of present illness.</p>' +
            '<p><strong>Objective</strong></p><p>Vitals, exam, and pertinent results.</p>' +
            '<p><strong>Assessment</strong></p><p>Working diagnoses.</p>' +
            '<p><strong>Plan</strong></p><p>Medications, orders, counseling, and follow-up.</p>'
    ),
    tpl(
        'Hypertension Follow-up',
        '.htn',
        'Progress Note',
        '<p>Follow-up essential hypertension. Home blood pressure log reviewed. Discussed adherence, sodium restriction, and lifestyle measures. No chest pain, dyspnea, or edema.</p>'
    ),
    tpl(
        'Diabetes Follow-up',
        '.dm',
        'Progress Note',
        '<p>Follow-up type 2 diabetes. Reviewed home glucose readings, hypoglycemia symptoms, diet, and activity. Foot exam and medication adherence discussed. Screening labs pending or reviewed.</p>'
    ),
    tpl(
        'Telehealth Visit',
        '.tele',
        'Progress Note',
        '<p>Synchronous video visit. Patient identity confirmed. Location and privacy adequate. Limitations of virtual exam reviewed. Consent obtained for telehealth.</p>'
    ),
    tpl(
        'Well Child Visit',
        '.wcc',
        'Progress Note',
        '<p>Well-child visit. Growth plotted. Development discussed with caregiver. Anticipatory guidance: nutrition, safety, sleep, and screen time. Immunizations reviewed and given as indicated.</p>'
    ),
    // ROS
    tpl(
        'ROS Negative',
        '.ros',
        'ROS',
        '<p><strong>Review of systems:</strong> Constitutional, eyes, ENT, cardiovascular, respiratory, GI, GU, musculoskeletal, skin, neurologic, psychiatric, endocrine, and hematologic/lymphatic systems reviewed and are negative except as noted in the HPI.</p>'
    ),
    tpl(
        'Cardiovascular ROS',
        '.ros-cv',
        'ROS',
        '<p>Cardiovascular: Denies chest pain, orthopnea, PND, and syncope. Reports palpitations. No known edema.</p>'
    ),
    tpl(
        'Respiratory ROS',
        '.ros-pulm',
        'ROS',
        '<p>Respiratory: Denies dyspnea at rest, wheeze, hemoptysis, and orthopnea. Reports occasional cough. No recent fever.</p>'
    ),
    tpl(
        'GI ROS',
        '.ros-gi',
        'ROS',
        '<p>Gastrointestinal: Denies abdominal pain, nausea, vomiting, diarrhea, constipation, melena, and hematochezia. Appetite stable.</p>'
    ),
    tpl(
        'Neurologic ROS',
        '.ros-neuro',
        'ROS',
        '<p>Neurologic: Denies headache, weakness, numbness, vision change, seizure, and syncope. Gait steady.</p>'
    ),
    // Physical Exam
    tpl(
        'General Physical Exam',
        '.pe',
        'Physical Exam',
        '<p>General: NAD. HEENT: NCAT, PERRL, oropharynx clear. Neck: no lymphadenopathy. Lungs: CTAB. Heart: RRR, no m/r/g. Abd: soft, NT, no rebound. Ext: no edema. Skin: no rash. Neuro: alert, grossly intact.</p>'
    ),
    tpl(
        'Cardiac Exam',
        '.pe-cv',
        'Physical Exam',
        '<p>Cardiovascular: Regular rate and rhythm. Normal S1/S2. No murmur, rub, or gallop. Pulses 2+ and symmetric. No carotid bruits. No JVD. Extremities without edema or calf tenderness.</p>'
    ),
    tpl(
        'Pulmonary Exam',
        '.pe-pulm',
        'Physical Exam',
        '<p>Respiratory: Comfortable, speaking in full sentences. Lungs clear to auscultation bilaterally. No wheeze, rales, or rhonchi. No accessory muscle use. Percussion resonant.</p>'
    ),
    tpl(
        'Neurologic Exam',
        '.pe-neuro',
        'Physical Exam',
        '<p>Neurologic: Alert and oriented x3. Cranial nerves II–XII intact. Strength 5/5 throughout. Sensation intact to light touch. Reflexes 2+ and symmetric. Finger-to-nose and gait normal. No pronator drift.</p>'
    ),
    // Assessment/Plan
    tpl(
        'Diabetes Assessment/Plan',
        '.dm-ap',
        'Assessment/Plan',
        '<p><strong>Type 2 diabetes mellitus</strong></p><ul><li>Continue metformin if tolerated.</li><li>Review A1c and home glucose; titrate therapy toward individualized goal.</li><li>Counsel on diet, activity, and hypoglycemia recognition.</li><li>Screening: eyes, feet, urine albumin, lipids as indicated.</li><li>Recheck A1c in 3 months.</li></ul>'
    ),
    tpl(
        'Hypertension Assessment/Plan',
        '.htn-ap',
        'Assessment/Plan',
        '<p><strong>Essential hypertension</strong></p><ul><li>Continue current antihypertensive therapy if at goal; otherwise titrate or add agent.</li><li>Home BP log; target discussed.</li><li>Counsel on sodium restriction, weight, and activity.</li><li>Labs: BMP if on ACE/ARB or diuretic.</li><li>Follow-up in 4–12 weeks.</li></ul>'
    ),
    tpl(
        'Return Precautions',
        '.rtp',
        'Assessment/Plan',
        '<p>Return sooner for chest pain, shortness of breath, fever, syncope, severe headache, uncontrolled bleeding, or any rapidly worsening symptom. Call emergency services for life-threatening symptoms.</p>'
    ),
    // Other
    tpl(
        'Counseling / Shared Decision',
        '.sdm',
        'Other',
        '<p>Risks, benefits, and alternatives discussed. Patient questions answered. Shared decision documented. Patient verbalized understanding and agrees with the plan.</p>'
    ),
    tpl(
        'Procedure Note',
        '.proc',
        'Other',
        '<p><strong>Procedure:</strong> </p><p><strong>Indication:</strong> </p><p><strong>Consent:</strong> Risks, benefits, and alternatives reviewed; consent obtained.</p><p><strong>Technique:</strong> Timeout performed. Procedure completed without immediate complication.</p><p><strong>Findings:</strong> </p><p><strong>Plan:</strong> Post-procedure precautions reviewed.</p>'
    ),
    tpl(
        'Discharge Instructions',
        '.dc',
        'Other',
        '<p>Activity as tolerated unless otherwise specified. Resume home medications with the changes discussed today. Take new prescriptions as written. Follow up with the listed clinician. Return precautions reviewed.</p>'
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

System.debug('Seeded ' + desiredTemplates.size() + ' note templates.');

lfemr__NoteTemplate__c tpl(String name, String shortcut, String category, String body) {
    return new lfemr__NoteTemplate__c(
        Name = name,
        lfemr__Shortcut__c = shortcut,
        lfemr__Category__c = category,
        lfemr__Active__c = true,
        lfemr__Body__c = body
    );
}
