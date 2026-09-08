@IsTest
private class AlertBarControllerTest {
    @IsTest
    static void resolvePatientIdReturnsPatientAndEncounterPatient() {
        Patient__c patient = insertPatient('MRN-AB-1');
        Encounter__c encounter = insertEncounter(patient.Id);
        Patient__c other = insertPatient('MRN-AB-2');
        Encounter__c orphaned = insertEncounter(other.Id);
        Id orphanedId = orphaned.Id;
        delete orphaned;

        Test.startTest();
        Id fromPatient = AlertBarController.resolvePatientId(patient.Id);
        Id fromEncounter = AlertBarController.resolvePatientId(encounter.Id);
        Id fromNull = AlertBarController.resolvePatientId(null);
        Id fromUser = AlertBarController.resolvePatientId(UserInfo.getUserId());
        Id fromMissingEncounter = AlertBarController.resolvePatientId(orphanedId);
        Test.stopTest();

        System.assertEquals(patient.Id, fromPatient, 'Patient Id should resolve to itself');
        System.assertEquals(patient.Id, fromEncounter, 'Encounter should resolve to its Patient__c');
        System.assertEquals(null, fromNull, 'Null record Id should resolve to null');
        System.assertEquals(null, fromUser, 'Non-patient records should not resolve');
        System.assertEquals(null, fromMissingEncounter, 'Missing encounter should resolve to null');
    }

    @IsTest
    static void getActiveAllergiesReturnsActiveRowsForPatientAndEncounter() {
        Patient__c patient = insertPatient('MRN-AB-3');
        Patient__c other = insertPatient('MRN-AB-4');
        Encounter__c encounter = insertEncounter(patient.Id);
        AllergyIntolerance__c high = insertAllergy(patient.Id, 'Active', 'Penicillin', 'High');
        insertAllergy(patient.Id, 'Active', 'Cashew', 'Low');
        insertAllergy(patient.Id, 'Inactive', 'Codeine', 'High');
        insertAllergy(other.Id, 'Active', 'Latex', 'High');

        Test.startTest();
        List<AllergyIntolerance__c> byPatient = AlertBarController.getActiveAllergies(patient.Id);
        List<AllergyIntolerance__c> byEncounter = AlertBarController.getActiveAllergies(encounter.Id);
        List<AllergyIntolerance__c> blank = AlertBarController.getActiveAllergies(null);
        List<AllergyIntolerance__c> unsupported = AlertBarController.getActiveAllergies(UserInfo.getUserId());
        Test.stopTest();

        System.assertEquals(2, byPatient.size(), 'Active allergies for the patient should be returned');
        System.assertEquals(2, byEncounter.size(), 'Encounter context should return the same patient allergies');
        System.assertEquals(0, blank.size(), 'Null record Id should return no allergies');
        System.assertEquals(0, unsupported.size(), 'Unsupported record types should return no allergies');
        System.assertEquals(high.Id, byPatient[0].Id, 'High criticality should sort first');
        System.assertEquals('High', byPatient[0].Criticality__c, 'Criticality should be queried');
        System.assertEquals('Penicillin', byPatient[0].Allergen_Display__c, 'Display should be queried');
        System.assertEquals(byPatient[0].Id, byEncounter[0].Id, 'Patient and encounter queries should match');
        System.assertEquals(byPatient[1].Id, byEncounter[1].Id, 'Both active allergies should match by encounter');
    }

    @IsTest
    static void getActiveAllergiesReturnsEmptyWhenPatientHasNone() {
        Patient__c patient = insertPatient('MRN-AB-5');
        Encounter__c encounter = insertEncounter(patient.Id);

        Test.startTest();
        List<AllergyIntolerance__c> byPatient = AlertBarController.getActiveAllergies(patient.Id);
        List<AllergyIntolerance__c> byEncounter = AlertBarController.getActiveAllergies(encounter.Id);
        Test.stopTest();

        System.assertEquals(0, byPatient.size(), 'Patient with no allergies should return empty');
        System.assertEquals(0, byEncounter.size(), 'Encounter of a patient with no allergies should return empty');
    }

    @IsTest
    static void getClinicalSummaryReturnsEmptySectionsWhenNone() {
        Patient__c patient = insertPatient('MRN-AB-6');
        Encounter__c encounter = insertEncounter(patient.Id);

        Test.startTest();
        AlertBarController.ClinicalSummary byPatient = AlertBarController.getClinicalSummary(patient.Id);
        AlertBarController.ClinicalSummary byEncounter = AlertBarController.getClinicalSummary(encounter.Id);
        AlertBarController.ClinicalSummary blank = AlertBarController.getClinicalSummary(null);
        AlertBarController.ClinicalSummary unsupported = AlertBarController.getClinicalSummary(
            UserInfo.getUserId()
        );
        Test.stopTest();

        System.assertEquals(7, byPatient.sections.size(), 'All clinical tab sections should be present');
        System.assertEquals('problems', byPatient.sections[0].key, 'Problems should be first');
        System.assertEquals('allergies', byPatient.sections[1].key, 'Allergies should be second');
        System.assertEquals('coverage', byPatient.sections[2].key, 'Coverage should be third');
        System.assertEquals('medications', byPatient.sections[3].key, 'Medications should be fourth');
        System.assertEquals('flowsheet', byPatient.sections[4].key, 'Flowsheet should be fifth');
        System.assertEquals('results', byPatient.sections[5].key, 'Results should be sixth');
        System.assertEquals('procedures', byPatient.sections[6].key, 'Procedures should be last');
        for (AlertBarController.SummarySection section : byPatient.sections) {
            System.assertEquals(0, section.totalCount, section.key + ' should be empty');
            System.assertEquals('empty', section.tone, section.key + ' should use the empty tone');
            System.assertEquals(0, section.items.size(), section.key + ' should have no chips');
        }
        System.assertEquals('No known allergies', byPatient.sections[1].emptyLabel, 'NKA copy should remain');
        System.assertEquals('No active coverage', byPatient.sections[2].emptyLabel, 'Coverage empty copy should remain');
        System.assertEquals(7, byEncounter.sections.size(), 'Encounter with no data should still return sections');
        System.assertEquals(7, blank.sections.size(), 'Null record Id should return empty sections');
        System.assertEquals(7, unsupported.sections.size(), 'Unsupported records should return empty sections');
        System.assertEquals(0, blank.sections[0].totalCount, 'Null record Id should have no problems');
    }

    @IsTest
    static void getClinicalSummaryReturnsActiveRowsForEachTab() {
        Patient__c patient = insertPatient('MRN-AB-7');
        Patient__c other = insertPatient('MRN-AB-8');
        Encounter__c encounter = insertEncounter(patient.Id);

        Condition__c hypertension = insertProblem(patient.Id, 'Active', 'I10', 'Essential hypertension');
        insertProblem(patient.Id, 'Resolved', 'E78.5', 'Hyperlipidemia');
        insertProblem(other.Id, 'Active', 'E11.9', 'Type 2 diabetes mellitus');

        AllergyIntolerance__c penicillin = insertAllergy(patient.Id, 'Active', 'Penicillin', 'High');
        insertAllergy(patient.Id, 'Active', 'Latex', 'Low');
        insertAllergy(patient.Id, 'Inactive', 'Codeine', 'High');
        insertAllergy(other.Id, 'Active', 'Peanut', 'High');

        Payer__c aetna = insertPayer('Aetna');
        Payer__c medicaid = insertPayer('State Medicaid');
        Coverage__c primary = insertCoverage(patient.Id, aetna.Id, 'Gold PPO', 'Primary', 'Active');
        Coverage__c secondary = insertCoverage(patient.Id, medicaid.Id, 'Medicaid', 'Secondary', 'Active');
        insertCoverage(patient.Id, aetna.Id, 'Old Plan', 'Primary', 'Inactive');
        insertCoverage(other.Id, aetna.Id, 'Other Plan', 'Primary', 'Active');

        MedicationRequest__c metformin = insertMedicationRequest(
            patient.Id,
            'Active',
            'Metformin 500 mg oral tablet',
            '500 mg twice daily'
        );
        insertMedicationRequest(patient.Id, 'Stopped', 'Lisinopril 10 MG Oral Tablet', null);
        insertMedicationRequest(other.Id, 'Active', 'Atorvastatin 40 MG Oral Tablet', null);
        MedicationStatement__c aspirin = insertMedicationStatement(
            patient.Id,
            'Active',
            'Aspirin 81 MG Oral Tablet'
        );
        insertMedicationStatement(patient.Id, 'Stopped', 'Ibuprofen 200 MG Oral Tablet');

        Observation__c criticalPotassium = insertObservation(
            patient.Id,
            '2823-3',
            'Potassium',
            6.2,
            'mmol/L',
            'Critical',
            Datetime.newInstance(2026, 9, 1, 8, 0, 0)
        );
        insertObservation(
            patient.Id,
            '2085-9',
            'HDL cholesterol',
            38,
            'mg/dL',
            'Low',
            Datetime.newInstance(2026, 9, 1, 7, 0, 0)
        );
        insertObservation(
            patient.Id,
            '2085-9',
            'HDL cholesterol',
            52,
            'mg/dL',
            'Low',
            Datetime.newInstance(2026, 8, 1, 7, 0, 0)
        );
        insertObservation(
            patient.Id,
            '8867-4',
            'Heart rate',
            74,
            '/min',
            'Normal',
            Datetime.newInstance(2026, 9, 1, 9, 0, 0)
        );
        insertObservation(
            other.Id,
            '718-7',
            'Hemoglobin',
            8.1,
            'g/dL',
            'Low',
            Datetime.newInstance(2026, 9, 1, 9, 0, 0)
        );

        DiagnosticReport__c lipidPanel = insertReport(
            patient.Id,
            'Lipid panel',
            '57698-3',
            false,
            Datetime.newInstance(2026, 9, 2, 10, 0, 0)
        );
        insertReport(
            patient.Id,
            'CBC',
            '58410-2',
            true,
            Datetime.newInstance(2026, 8, 15, 10, 0, 0)
        );
        insertReport(
            other.Id,
            'CMP',
            '24323-8',
            false,
            Datetime.newInstance(2026, 9, 2, 10, 0, 0)
        );

        Procedure__c colonoscopy = insertProcedure(
            patient.Id,
            'In Progress',
            'Colonoscopy',
            Datetime.newInstance(2026, 8, 1, 9, 0, 0)
        );
        insertProcedure(
            patient.Id,
            'Completed',
            'Electrocardiogram, complete',
            Datetime.newInstance(2026, 9, 1, 9, 0, 0)
        );
        insertProcedure(
            other.Id,
            'Completed',
            'X-ray hip, 2 or 3 views',
            Datetime.newInstance(2026, 9, 2, 9, 0, 0)
        );

        Test.startTest();
        AlertBarController.ClinicalSummary byPatient = AlertBarController.getClinicalSummary(patient.Id);
        AlertBarController.ClinicalSummary byEncounter = AlertBarController.getClinicalSummary(encounter.Id);
        Test.stopTest();

        Map<String, AlertBarController.SummarySection> sections = byKey(byPatient.sections);
        Map<String, AlertBarController.SummarySection> encounterSections = byKey(byEncounter.sections);

        System.assertEquals(1, sections.get('problems').totalCount, 'Only the active problem should be summarized');
        System.assertEquals(hypertension.Id, sections.get('problems').items[0].id, 'Active problem chip should match');
        System.assertEquals('Essential hypertension', sections.get('problems').items[0].name, 'Problem display should be used');
        System.assertEquals('info', sections.get('problems').tone, 'Active problems should use the info tone');

        System.assertEquals(2, sections.get('allergies').totalCount, 'Only active allergies should be summarized');
        System.assertEquals(penicillin.Id, sections.get('allergies').items[0].id, 'High allergy should sort first');
        System.assertEquals('High', sections.get('allergies').items[0].flag, 'High allergy should be flagged');
        System.assertEquals(true, sections.get('allergies').items[0].emphasize, 'High allergy should be emphasized');
        System.assertEquals('high', sections.get('allergies').tone, 'High allergy should use the high tone');

        System.assertEquals(2, sections.get('coverage').totalCount, 'All active coverages should be summarized');
        System.assertEquals(2, sections.get('coverage').items.size(), 'Coverage chips should not be capped');
        System.assertEquals(primary.Id, sections.get('coverage').items[0].id, 'Primary coverage should sort first');
        System.assertEquals('Gold PPO (AlertBar) - Active', sections.get('coverage').items[0].name, 'Coverage chip should use plan, patient, and status');
        System.assertEquals('Primary', sections.get('coverage').items[0].flag, 'Coverage chip should show priority');
        System.assertEquals(secondary.Id, sections.get('coverage').items[1].id, 'Secondary active coverage should be listed');
        System.assertEquals('Medicaid (AlertBar) - Active', sections.get('coverage').items[1].name, 'Secondary coverage should use plan, patient, and status');
        System.assertEquals('info', sections.get('coverage').tone, 'Active coverage should use the info tone');
        System.assertEquals('chips', sections.get('coverage').variant, 'Coverage should use chips like allergies');

        System.assertEquals(2, sections.get('medications').totalCount, 'Active order and reported med should be summarized');
        System.assertEquals(metformin.Id, sections.get('medications').items[0].id, 'Active order should appear first');
        System.assertEquals(aspirin.Id, sections.get('medications').items[1].id, 'Reported medication should be included');
        System.assertEquals('Reported', sections.get('medications').items[1].flag, 'Reported meds should be flagged');
        System.assertEquals('list', sections.get('medications').variant, 'Medications should use the list layout');
        System.assertEquals(
            '500 mg twice daily',
            sections.get('medications').items[0].detail,
            'Order dosage should be exposed as list detail'
        );
        System.assertEquals('success', sections.get('medications').tone, 'Active meds should use the success tone');

        System.assertEquals(2, sections.get('flowsheet').totalCount, 'Latest abnormal findings should be summarized');
        System.assertEquals(
            criticalPotassium.Id,
            sections.get('flowsheet').items[0].id,
            'Critical finding should sort first'
        );
        System.assertEquals('metrics', sections.get('flowsheet').variant, 'Flowsheet should use the vitals grid layout');
        System.assertEquals('K', sections.get('flowsheet').items[0].name, 'Potassium should use a short metric label');
        System.assertEquals('6.2', sections.get('flowsheet').items[0].value, 'Metric value should be separate from the label');
        System.assertEquals('mmol/L', sections.get('flowsheet').items[0].unit, 'Metric unit should be queried');
        System.assertEquals('Critical', sections.get('flowsheet').items[0].flag, 'Critical finding should be flagged');
        System.assertEquals('high', sections.get('flowsheet').tone, 'Critical findings should use the high tone');
        System.assertEquals('HDL', sections.get('flowsheet').items[1].name, 'Latest HDL should use a short metric label');
        System.assertEquals('38', sections.get('flowsheet').items[1].value, 'Older HDL row should be dropped');
        System.assertEquals('mg/dL', sections.get('flowsheet').items[1].unit, 'HDL unit should be queried');

        System.assertEquals(2, sections.get('results').totalCount, 'Both patient reports should be summarized');
        System.assertEquals(lipidPanel.Id, sections.get('results').items[0].id, 'Unreviewed result should sort first');
        System.assertEquals('New', sections.get('results').items[0].flag, 'Unreviewed result should be flagged');
        System.assertEquals('attention', sections.get('results').tone, 'Unreviewed results should use attention tone');

        System.assertEquals(2, sections.get('procedures').totalCount, 'Both patient procedures should be summarized');
        System.assertEquals(
            colonoscopy.Id,
            sections.get('procedures').items[0].id,
            'In-progress procedure should sort first'
        );
        System.assertEquals('In Progress', sections.get('procedures').items[0].flag, 'Open procedure should be flagged');
        System.assertEquals('attention', sections.get('procedures').tone, 'Open procedures should use attention tone');

        System.assertEquals(
            sections.get('problems').items[0].id,
            encounterSections.get('problems').items[0].id,
            'Encounter context should return the same problem summary'
        );
        System.assertEquals(
            sections.get('allergies').totalCount,
            encounterSections.get('allergies').totalCount,
            'Encounter context should return the same allergy summary'
        );
    }

    @IsTest
    static void getClinicalSummaryCapsVisibleChipsAndKeepsTotalCount() {
        Patient__c patient = insertPatient('MRN-AB-9');
        for (Integer i = 1; i <= 10; i++) {
            insertProblem(patient.Id, 'Active', 'I10.' + String.valueOf(i), 'Problem ' + String.valueOf(i));
        }

        Test.startTest();
        AlertBarController.ClinicalSummary summary = AlertBarController.getClinicalSummary(patient.Id);
        Test.stopTest();

        AlertBarController.SummarySection problems = byKey(summary.sections).get('problems');
        System.assertEquals(10, problems.totalCount, 'Total count should include every active problem');
        System.assertEquals(8, problems.items.size(), 'Visible chips should be capped');
        System.assertEquals('Problem 1', problems.items[0].name, 'Problems should stay in display order');
    }

    private static Map<String, AlertBarController.SummarySection> byKey(
        List<AlertBarController.SummarySection> sections
    ) {
        Map<String, AlertBarController.SummarySection> result = new Map<String, AlertBarController.SummarySection>();
        for (AlertBarController.SummarySection section : sections) {
            result.put(section.key, section);
        }
        return result;
    }

    private static Payer__c insertPayer(String payerName) {
        Payer__c payer = new Payer__c(Name = payerName, Type__c = 'Commercial', Active__c = true);
        insert payer;
        return payer;
    }

    private static Coverage__c insertCoverage(
        Id patientId,
        Id payerId,
        String planName,
        String priority,
        String status
    ) {
        Coverage__c coverage = new Coverage__c(
            Patient__c = patientId,
            Payer__c = payerId,
            Plan_Name__c = planName,
            Type__c = 'Medical',
            Priority__c = priority,
            Status__c = status
        );
        insert coverage;
        return coverage;
    }

    private static Patient__c insertPatient(String mrn) {
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'AlertBar');
        insert patient;
        return patient;
    }

    private static Encounter__c insertEncounter(Id patientId) {
        Encounter__c encounter = new Encounter__c(
            Patient__c = patientId,
            Status__c = 'In Progress',
            Class__c = 'Outpatient',
            Start__c = Datetime.newInstance(2024, 3, 1, 9, 0, 0)
        );
        insert encounter;
        return encounter;
    }

    private static AllergyIntolerance__c insertAllergy(
        Id patientId,
        String status,
        String display,
        String criticality
    ) {
        AllergyIntolerance__c allergy = new AllergyIntolerance__c(
            Patient__c = patientId,
            Clinical_Status__c = status,
            Allergen_Display__c = display,
            Type__c = 'Allergy',
            Category__c = 'Medication',
            Criticality__c = criticality
        );
        insert allergy;
        return allergy;
    }

    private static Condition__c insertProblem(Id patientId, String status, String code, String display) {
        Condition__c condition = new Condition__c(
            Patient__c = patientId,
            Category__c = 'Problem List Item',
            Clinical_Status__c = status,
            Diagnosis_Code_System__c = 'ICD-10',
            Diagnosis_Code__c = code,
            Diagnosis_Display__c = display
        );
        insert condition;
        return condition;
    }

    private static MedicationRequest__c insertMedicationRequest(
        Id patientId,
        String status,
        String display,
        String dosageText
    ) {
        MedicationRequest__c request = new MedicationRequest__c(
            Patient__c = patientId,
            Status__c = status,
            Intent__c = 'Order',
            Medication_Code_System__c = 'RxNorm',
            Medication_Code__c = '197361',
            Medication_Display__c = display,
            Dosage_Text__c = dosageText
        );
        insert request;
        return request;
    }

    private static MedicationStatement__c insertMedicationStatement(Id patientId, String status, String display) {
        MedicationStatement__c statement = new MedicationStatement__c(
            Patient__c = patientId,
            Status__c = status,
            Source__c = 'Patient Reported',
            Medication_Code_System__c = 'RxNorm',
            Medication_Code__c = '308971',
            Medication_Display__c = display
        );
        insert statement;
        return statement;
    }

    private static Observation__c insertObservation(
        Id patientId,
        String code,
        String display,
        Decimal quantity,
        String unit,
        String interpretation,
        Datetime effective
    ) {
        Observation__c observation = new Observation__c(
            Patient__c = patientId,
            Category__c = 'Laboratory',
            Status__c = 'Final',
            Observation_Code__c = code,
            Observation_Display__c = display,
            Value_Quantity__c = quantity,
            Value_Unit__c = unit,
            Interpretation__c = interpretation,
            Effective_DateTime__c = effective
        );
        insert observation;
        return observation;
    }

    private static DiagnosticReport__c insertReport(
        Id patientId,
        String display,
        String code,
        Boolean reviewed,
        Datetime issued
    ) {
        DiagnosticReport__c report = new DiagnosticReport__c(
            Patient__c = patientId,
            Report_Display__c = display,
            Report_Code_System__c = 'LOINC',
            Report_Code__c = code,
            Category__c = 'Laboratory',
            Status__c = 'Final',
            Reviewed__c = reviewed,
            Issued__c = issued
        );
        insert report;
        return report;
    }

    private static Procedure__c insertProcedure(Id patientId, String status, String display, Datetime performed) {
        Procedure__c procedure = new Procedure__c(
            Patient__c = patientId,
            Status__c = status,
            Category__c = 'Diagnostic',
            Procedure_Code_System__c = 'CPT',
            Procedure_Code__c = '45378',
            Procedure_Display__c = display,
            Performed_DateTime__c = performed
        );
        insert procedure;
        return procedure;
    }
}
