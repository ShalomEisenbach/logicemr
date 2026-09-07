@IsTest
private class ClinicalDocumentServiceTest {
    @IsTest
    static void getChartSummaryReturnsSectionsForPatientOnly() {
        Patient__c patient = insertPatient('MRN-DOC-1', 'patient1@example.com');
        Patient__c other = insertPatient('MRN-DOC-2', 'other@example.com');
        Practitioner__c author = insertPractitioner('Ada', 'Author', '1234567890');

        insertCondition(patient.Id, 'Active', 'Hypertension');
        insertCondition(patient.Id, 'Resolved', 'Resolved cold');
        insertCondition(other.Id, 'Active', 'Other problem');

        insertAllergy(patient.Id, 'Active', 'Penicillin', 'Rash');
        insertAllergy(other.Id, 'Active', 'Latex', 'Hives');

        insertRequest(patient.Id, 'Active', 'Lisinopril 10 MG', author.Id);
        insertRequest(patient.Id, 'Stopped', 'Stopped med', author.Id);
        insertRequest(other.Id, 'Active', 'Other med', author.Id);

        insertStatement(patient.Id, 'Active', 'Acetaminophen 325 MG');
        insertStatement(other.Id, 'Active', 'Other reported');

        insertObservation(patient.Id, 'Vital Signs', 'Heart rate', 72, 'beats/min');
        insertObservation(patient.Id, 'Laboratory', 'Glucose', 98, 'mg/dL');
        insertObservation(other.Id, 'Vital Signs', 'Other HR', 80, 'beats/min');

        insertProcedure(patient.Id, 'Colonoscopy');
        insertProcedure(other.Id, 'Other procedure');

        Encounter__c encounter = insertEncounter(patient.Id);
        insertNote(patient.Id, encounter.Id, author.Id, 'Signed', 'Progress Note', '<p>Signed note</p>');
        insertNote(patient.Id, encounter.Id, author.Id, 'Draft', 'Progress Note', '<p>Draft note</p>');

        Test.startTest();
        ClinicalDocumentService.ChartSummary summary = ClinicalDocumentService.getChartSummary(
            patient.Id
        );
        ClinicalDocumentService.ChartSummary blank = ClinicalDocumentService.getChartSummary(null);
        Test.stopTest();

        System.assertNotEquals(null, summary.patient, 'Patient header should load');
        System.assertEquals('Ada Patient', summary.patient.fullName, 'Patient name should format');
        System.assertEquals('patient1@example.com', summary.patient.email, 'Email should load');
        System.assertEquals(1, summary.problems.size(), 'Only active problems for this patient');
        System.assertEquals('Hypertension', summary.problems[0].display, 'Problem display should match');
        System.assertEquals(1, summary.allergies.size(), 'Only active allergies for this patient');
        System.assertEquals('Penicillin', summary.allergies[0].display, 'Allergy display should match');
        System.assertEquals(1, summary.activeOrders.size(), 'Only active orders for this patient');
        System.assertEquals(
            'Lisinopril 10 MG',
            summary.activeOrders[0].display,
            'Active order display should match'
        );
        System.assertEquals(1, summary.reportedMedications.size(), 'Only reported meds for this patient');
        System.assertEquals(1, summary.vitals.size(), 'Only vitals for this patient');
        System.assertEquals(1, summary.labs.size(), 'Only labs for this patient');
        System.assertEquals('98', summary.labs[0].value, 'Lab quantity should stringify');
        System.assertEquals(1, summary.procedures.size(), 'Only procedures for this patient');
        System.assertEquals(1, summary.signedNotes.size(), 'Only signed notes for this patient');
        System.assertEquals(
            'Progress Note',
            summary.signedNotes[0].noteType,
            'Signed note type should match'
        );
        System.assertEquals('Ada Author', summary.signedNotes[0].authorName, 'Author name should format');
        System.assertEquals(null, blank.patient, 'Null patient should return empty summary');
        System.assertEquals(0, blank.problems.size(), 'Null patient has no problems');
    }

    @IsTest
    static void getPrescriptionPadScopesRequestsToPatient() {
        Patient__c patient = insertPatient('MRN-DOC-RX-1', 'rx@example.com');
        Patient__c other = insertPatient('MRN-DOC-RX-2', null);
        Practitioner__c requester = insertPractitioner('Pat', 'Prescriber', '9988776655');

        MedicationRequest__c own = insertRequest(patient.Id, 'Active', 'Atorvastatin 40 MG', requester.Id);
        MedicationRequest__c otherRx = insertRequest(other.Id, 'Active', 'Other Rx', requester.Id);

        Test.startTest();
        ClinicalDocumentService.PrescriptionPad pad = ClinicalDocumentService.getPrescriptionPad(
            patient.Id,
            new List<Id>{ own.Id, otherRx.Id }
        );
        ClinicalDocumentService.PrescriptionPad empty = ClinicalDocumentService.getPrescriptionPad(
            patient.Id,
            new List<Id>()
        );
        Test.stopTest();

        System.assertEquals('Ada Patient', pad.patient.fullName, 'Patient header should load');
        System.assertEquals(1, pad.prescriptions.size(), 'Only this patient\'s Rx should be included');
        System.assertEquals('Atorvastatin 40 MG', pad.prescriptions[0].display, 'Rx display should match');
        System.assertEquals('Pat Prescriber', pad.prescriptions[0].requesterName, 'Requester name');
        System.assertEquals('9988776655', pad.prescriptions[0].requesterNpi, 'Requester NPI');
        System.assertEquals(0, empty.prescriptions.size(), 'Empty ids should return no prescriptions');
    }

    @IsTest
    static void vfControllersLoadDocumentModels() {
        Patient__c patient = insertPatient('MRN-DOC-VF', 'vf@example.com');
        MedicationRequest__c rx = insertRequest(patient.Id, 'Active', 'Metformin 500 MG', null);

        PageReference chartPage = Page.PatientChartSummary;
        chartPage.getParameters().put('id', String.valueOf(patient.Id));
        Test.setCurrentPage(chartPage);
        PatientChartSummaryController chartController = new PatientChartSummaryController();
        System.assertEquals(true, chartController.getHasPatient(), 'Chart VF should resolve patient');
        System.assertEquals(
            'Metformin 500 MG',
            ClinicalDocumentService.getPrescriptionPad(patient.Id, new List<Id>{ rx.Id })
                .prescriptions[0]
                .display,
            'Pad service should still resolve Rx for VF coverage setup'
        );

        PageReference rxPage = Page.PrescriptionPad;
        rxPage.getParameters().put('id', String.valueOf(patient.Id));
        rxPage.getParameters().put('ids', String.valueOf(rx.Id) + ',not-an-id');
        Test.setCurrentPage(rxPage);
        PrescriptionPadController padController = new PrescriptionPadController();
        System.assertEquals(true, padController.getHasPatient(), 'Rx VF should resolve patient');
        System.assertEquals(true, padController.getHasPrescriptions(), 'Rx VF should include selected Rx');
        System.assertEquals(
            1,
            padController.pad.prescriptions.size(),
            'Malformed id tokens should be ignored'
        );
    }

    private static Patient__c insertPatient(String mrn, String email) {
        Patient__c patient = new Patient__c(
            MRN__c = mrn,
            First_Name__c = 'Ada',
            Last_Name__c = 'Patient',
            Email__c = email,
            Phone__c = '555-0100',
            Date_of_Birth__c = Date.newInstance(1980, 5, 1),
            Sex_at_Birth__c = 'Female'
        );
        insert patient;
        return patient;
    }

    private static Practitioner__c insertPractitioner(String firstName, String lastName, String npi) {
        Practitioner__c practitioner = new Practitioner__c(
            First_Name__c = firstName,
            Last_Name__c = lastName,
            NPI__c = npi,
            Active__c = true
        );
        insert practitioner;
        return practitioner;
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

    private static Condition__c insertCondition(Id patientId, String status, String display) {
        Condition__c condition = new Condition__c(
            Patient__c = patientId,
            Category__c = 'Problem List Item',
            Clinical_Status__c = status,
            Diagnosis_Code_System__c = 'ICD-10',
            Diagnosis_Code__c = 'I10',
            Diagnosis_Display__c = display
        );
        insert condition;
        return condition;
    }

    private static AllergyIntolerance__c insertAllergy(
        Id patientId,
        String status,
        String display,
        String reaction
    ) {
        AllergyIntolerance__c allergy = new AllergyIntolerance__c(
            Patient__c = patientId,
            Clinical_Status__c = status,
            Allergen_Code_System__c = 'RxNorm',
            Allergen_Code__c = '7980',
            Allergen_Display__c = display,
            Type__c = 'Allergy',
            Category__c = 'Medication',
            Criticality__c = 'High',
            Reaction__c = reaction
        );
        insert allergy;
        return allergy;
    }

    private static MedicationRequest__c insertRequest(
        Id patientId,
        String status,
        String display,
        Id requesterId
    ) {
        MedicationRequest__c request = new MedicationRequest__c(
            Patient__c = patientId,
            Status__c = status,
            Intent__c = 'Order',
            Medication_Code_System__c = 'RxNorm',
            Medication_Code__c = '197361',
            Medication_Display__c = display,
            Dosage_Text__c = 'Take as directed',
            Dose_Quantity__c = 10,
            Dose_Unit__c = 'mg',
            Frequency__c = 'Once daily',
            Route__c = 'Oral',
            Authored_On__c = Datetime.now(),
            Requester__c = requesterId
        );
        insert request;
        return request;
    }

    private static MedicationStatement__c insertStatement(Id patientId, String status, String display) {
        MedicationStatement__c statement = new MedicationStatement__c(
            Patient__c = patientId,
            Status__c = status,
            Source__c = 'Patient Reported',
            Medication_Code_System__c = 'RxNorm',
            Medication_Code__c = '198440',
            Medication_Display__c = display,
            Dosage_Text__c = 'As needed'
        );
        insert statement;
        return statement;
    }

    private static Observation__c insertObservation(
        Id patientId,
        String category,
        String display,
        Decimal quantity,
        String unit
    ) {
        Observation__c observation = new Observation__c(
            Patient__c = patientId,
            Category__c = category,
            Status__c = 'Final',
            Observation_Code_System__c = 'LOINC',
            Observation_Code__c = '8867-4',
            Observation_Display__c = display,
            Value_Quantity__c = quantity,
            Value_Unit__c = unit,
            Effective_DateTime__c = Datetime.now()
        );
        insert observation;
        return observation;
    }

    private static Procedure__c insertProcedure(Id patientId, String display) {
        Procedure__c procedure = new Procedure__c(
            Patient__c = patientId,
            Status__c = 'Completed',
            Category__c = 'Surgical',
            Procedure_Code_System__c = 'CPT',
            Procedure_Code__c = '45378',
            Procedure_Display__c = display,
            Performed_DateTime__c = Datetime.now()
        );
        insert procedure;
        return procedure;
    }

    private static ClinicalNote__c insertNote(
        Id patientId,
        Id encounterId,
        Id authorId,
        String status,
        String noteType,
        String body
    ) {
        ClinicalNote__c note = new ClinicalNote__c(
            Patient__c = patientId,
            Encounter__c = encounterId,
            Author__c = authorId,
            Note_Type__c = noteType,
            Body__c = body,
            Status__c = status,
            Signed_Date__c = status == 'Signed' ? Datetime.now() : null
        );
        insert note;
        return note;
    }
}
