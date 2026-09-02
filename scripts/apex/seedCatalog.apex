/**
 * Idempotent Code_Reference catalog for demo codes.
 * Run first so clinical seeds can set *_Ref__c lookups.
 * Code_Reference Name is a Text Code Label (no Name_Format trigger) — set it explicitly.
 * Code__c is an External Id but not unique across systems, so match on Code_System + Code.
 */
List<lfemr__Code_Reference__c> desired = new List<lfemr__Code_Reference__c>{
    // ICD-10 — problem list / encounter diagnoses
    ref('ICD-10', 'E11.9', 'Type 2 diabetes mellitus'),
    ref('ICD-10', 'E11.65', 'Type 2 diabetes with hyperglycemia'),
    ref('ICD-10', 'I10', 'Essential hypertension'),
    ref('ICD-10', 'E78.5', 'Hyperlipidemia'),
    ref('ICD-10', 'R07.9', 'Chest pain, unspecified'),
    ref('ICD-10', 'J45.20', 'Mild intermittent asthma'),
    ref('ICD-10', 'J45.909', 'Unspecified asthma, uncomplicated'),
    ref('ICD-10', 'H66.90', 'Otitis media, unspecified'),
    ref('ICD-10', 'I48.91', 'Unspecified atrial fibrillation'),
    ref('ICD-10', 'K80.20', 'Cholelithiasis'),
    ref('ICD-10', 'R00.2', 'Palpitations'),
    ref('ICD-10', 'S72.001A', 'Right femoral neck fracture'),
    ref('ICD-10', 'M81.0', 'Age-related osteoporosis'),
    ref('ICD-10', 'F41.1', 'Generalized anxiety disorder'),
    ref('ICD-10', 'F32.9', 'Major depressive disorder, single episode, unspecified'),
    ref('ICD-10', 'N18.3', 'Chronic kidney disease, stage 3'),
    ref('ICD-10', 'J18.9', 'Pneumonia, unspecified organism'),
    ref('ICD-10', 'G43.909', 'Migraine, unspecified, not intractable'),
    ref('ICD-10', 'M54.5', 'Low back pain'),
    ref('ICD-10', 'E66.9', 'Obesity, unspecified'),
    ref('ICD-10', 'Z79.4', 'Long term (current) use of insulin'),
    // SNOMED — clinical findings for diagnosis search (problem list)
    ref('SNOMED', '44054006', 'Diabetes mellitus type 2'),
    ref('SNOMED', '38341003', 'Hypertensive disorder'),
    ref('SNOMED', '55822004', 'Hyperlipidemia'),
    ref('SNOMED', '29857009', 'Chest pain'),
    ref('SNOMED', '195967001', 'Asthma'),
    ref('SNOMED', '65363002', 'Otitis media'),
    ref('SNOMED', '49436004', 'Atrial fibrillation'),
    ref('SNOMED', '266569009', 'Cholelithiasis'),
    ref('SNOMED', '80313002', 'Palpitations'),
    ref('SNOMED', '5913000', 'Fracture of neck of femur'),
    ref('SNOMED', '64859006', 'Osteoporosis'),
    ref('SNOMED', '21897009', 'Generalized anxiety disorder'),
    ref('SNOMED', '370143000', 'Major depressive disorder'),
    ref('SNOMED', '709044004', 'Chronic kidney disease stage 3'),
    ref('SNOMED', '233604007', 'Pneumonia'),
    ref('SNOMED', '37796009', 'Migraine'),
    ref('SNOMED', '279039007', 'Low back pain'),
    ref('SNOMED', '414916001', 'Obesity'),
    // SNOMED — allergens / referrals
    ref('SNOMED', '91935009', 'Peanut'),
    ref('SNOMED', '111088007', 'Latex'),
    ref('SNOMED', '300913001', 'Shellfish'),
    ref('SNOMED', '91936005', 'Allergy to penicillin'),
    ref('SNOMED', '306118007', 'Referral to endocrinology'),
    // RxNorm — medications / allergens
    ref('RxNorm', '7980', 'Penicillin'),
    ref('RxNorm', '10180', 'Sulfonamide'),
    ref('RxNorm', '723', 'Amoxicillin'),
    ref('RxNorm', '2670', 'Codeine'),
    ref('RxNorm', '860975', 'Metformin 500 mg oral tablet'),
    ref('RxNorm', '314076', 'Lisinopril 10 mg oral tablet'),
    ref('RxNorm', '617310', 'Atorvastatin oral tablet'),
    ref('RxNorm', '311040', 'Insulin regular, human'),
    ref('RxNorm', '866412', 'Metoprolol tartrate 25 mg oral tablet'),
    ref('RxNorm', '1364430', 'Apixaban 5 mg oral tablet'),
    ref('RxNorm', '854235', 'Enoxaparin 40 mg/0.4 mL injection'),
    ref('RxNorm', '312940', 'Sertraline 50 mg oral tablet'),
    ref('RxNorm', '1191', 'Aspirin 81 mg oral tablet'),
    ref('RxNorm', '2418', 'Cholecalciferol 2000 IU'),
    ref('RxNorm', '745679', 'Albuterol 90 mcg/actuation inhaler'),
    ref('RxNorm', '904421', 'Alendronate 70 mg oral tablet'),
    ref('CVX', '141', 'Influenza, seasonal, injectable'),
    ref('CVX', '213', 'SARS-CoV-2 (COVID-19) vaccine'),
    ref('CVX', '20', 'DTaP'),
    ref('CVX', '03', 'MMR'),
    ref('CVX', '08', 'Hep B, adolescent or pediatric'),
    ref('CVX', '119', 'Rotavirus, pentavalent'),
    ref('CVX', '83', 'Hep A, ped/adol, 2 dose'),
    ref('CVX', '115', 'Tdap'),
    ref('LOINC', '4548-4', 'Hemoglobin A1c'),
    ref('LOINC', '57698-3', 'Lipid panel'),
    ref('LOINC', '10839-9', 'Troponin I'),
    ref('LOINC', '30711-8', 'XR Hip Right'),
    ref('LOINC', '34552-0', 'Echocardiogram'),
    ref('LOINC', '8480-6', 'Systolic blood pressure'),
    ref('LOINC', '8462-4', 'Diastolic blood pressure'),
    ref('LOINC', '8867-4', 'Heart rate'),
    ref('LOINC', '9279-1', 'Respiratory rate'),
    ref('LOINC', '8310-5', 'Body temperature'),
    ref('LOINC', '59408-5', 'Oxygen saturation'),
    ref('LOINC', '2345-7', 'Glucose'),
    ref('LOINC', '2089-1', 'LDL cholesterol'),
    ref('LOINC', '2085-9', 'HDL cholesterol'),
    ref('LOINC', '8302-2', 'Body height'),
    ref('LOINC', '29463-7', 'Body weight'),
    ref('CPT', '93306', 'Echocardiogram, complete'),
    ref('CPT', '73502', 'X-ray hip, 2 or 3 views'),
    ref('CPT', '27236', 'Open treatment of femoral neck fracture'),
    ref('CPT', '47562', 'Laparoscopic cholecystectomy'),
    ref('CPT', '93000', 'Electrocardiogram, complete'),
    ref('CPT', '94010', 'Spirometry'),
    ref('CPT', '90834', 'Psychotherapy, 45 minutes')
};

Set<String> codes = new Set<String>();
for (lfemr__Code_Reference__c row : desired) {
    codes.add(row.lfemr__Code__c);
}

Map<String, lfemr__Code_Reference__c> existingByKey = new Map<String, lfemr__Code_Reference__c>();
for (lfemr__Code_Reference__c row : [
    SELECT Id, lfemr__Code_System__c, lfemr__Code__c
    FROM lfemr__Code_Reference__c
    WHERE lfemr__Code__c IN :codes
]) {
    existingByKey.put(catalogKey(row.lfemr__Code_System__c, row.lfemr__Code__c), row);
}

List<lfemr__Code_Reference__c> toUpsert = new List<lfemr__Code_Reference__c>();
for (lfemr__Code_Reference__c row : desired) {
    lfemr__Code_Reference__c existing = existingByKey.get(
        catalogKey(row.lfemr__Code_System__c, row.lfemr__Code__c)
    );
    if (existing != null) {
        row.Id = existing.Id;
    }
    toUpsert.add(row);
}
upsert toUpsert;
System.debug('Seeded ' + toUpsert.size() + ' code references.');

lfemr__Code_Reference__c ref(String codeSystem, String code, String display) {
    return new lfemr__Code_Reference__c(
        Name = display,
        lfemr__Code_System__c = codeSystem,
        lfemr__Code__c = code,
        lfemr__Display__c = display,
        lfemr__Active__c = true
    );
}

String catalogKey(String codeSystem, String code) {
    return String.valueOf(codeSystem) + '::' + String.valueOf(code);
}
