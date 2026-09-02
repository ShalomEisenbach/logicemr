@IsTest
private class NameFormatterHandlerTest {
    @IsTest
    static void formatsLocalTokensOnCondition() {
        Patient__c patient = insertPatient('MRN-NF-COND');

        Test.startTest();
        Condition__c condition = new Condition__c(
            Patient__c = patient.Id,
            Diagnosis_Display__c = 'Chest tightness',
            Diagnosis_Code__c = 'R07.9',
            Category__c = 'Problem List Item',
            Clinical_Status__c = 'Active'
        );
        insert condition;
        Test.stopTest();

        Condition__c stored = [SELECT Name FROM Condition__c WHERE Id = :condition.Id];
        System.assertEquals(
            'Chest tightness R07.9',
            stored.Name,
            'Condition Name should compose local display and code tokens'
        );
    }

    @IsTest
    static void formatsParentTokenOnEncounter() {
        Patient__c patient = new Patient__c(
            MRN__c = 'MRN-NF-ENC',
            First_Name__c = 'Jane',
            Last_Name__c = 'Smith',
            Date_of_Birth__c = Date.newInstance(1980, 5, 12)
        );
        insert patient;
        patient = [SELECT Name FROM Patient__c WHERE Id = :patient.Id];

        Test.startTest();
        Encounter__c encounter = new Encounter__c(
            Patient__c = patient.Id,
            Class__c = 'Outpatient',
            Status__c = 'In Progress',
            Start__c = Datetime.newInstance(2026, 9, 2, 10, 0, 0)
        );
        insert encounter;
        Test.stopTest();

        Encounter__c stored = [SELECT Name FROM Encounter__c WHERE Id = :encounter.Id];
        System.assert(
            stored.Name.contains(patient.Name),
            'Encounter Name should include the parent Patient Name. Actual: ' + stored.Name
        );
        System.assert(
            stored.Name.contains('Outpatient'),
            'Encounter Name should include the local Class token. Actual: ' + stored.Name
        );
    }

    @IsTest
    static void truncatesComposedNameToEightyCharacters() {
        Patient__c patient = insertPatient('MRN-NF-TRUNC');
        String longDisplay = 'Chest tightness ' + 'x'.repeat(80);
        String expected = (longDisplay + ' R07.9').normalizeSpace().left(80);

        Test.startTest();
        Condition__c condition = new Condition__c(
            Patient__c = patient.Id,
            Diagnosis_Display__c = longDisplay,
            Diagnosis_Code__c = 'R07.9',
            Category__c = 'Problem List Item',
            Clinical_Status__c = 'Active'
        );
        insert condition;
        Test.stopTest();

        Condition__c stored = [SELECT Name FROM Condition__c WHERE Id = :condition.Id];
        System.assertEquals(80, stored.Name.length(), 'Composed Name must be truncated to 80 characters');
        System.assertEquals(expected, stored.Name, 'Truncated Name should be the first 80 characters of the composed value');
    }

    @IsTest
    static void leavesNameUnchangedWhenFormatIsMissing() {
        NoteTemplate__c template = new NoteTemplate__c(Name = 'Leave This Name', Category__c = 'ROS');

        Test.startTest();
        NameFormatterHandler.format(null);
        NameFormatterHandler.format(new List<SObject>());
        NameFormatterHandler.format(new List<SObject>{ template });
        Test.stopTest();

        System.assertEquals(
            'Leave This Name',
            template.Name,
            'Name should stay as-is when no active Name_Format__mdt exists for the object'
        );
    }

    @IsTest
    static void recomposesNameOnUpdateAndCollapsesNullTokens() {
        Patient__c patient = insertPatient('MRN-NF-UPD');
        Condition__c condition = new Condition__c(
            Patient__c = patient.Id,
            Diagnosis_Display__c = 'Chest tightness',
            Diagnosis_Code__c = 'R07.9',
            Category__c = 'Problem List Item',
            Clinical_Status__c = 'Active'
        );
        insert condition;

        Test.startTest();
        condition.Diagnosis_Display__c = 'Wheeze';
        condition.Diagnosis_Code__c = null;
        update condition;
        Test.stopTest();

        Condition__c stored = [SELECT Name FROM Condition__c WHERE Id = :condition.Id];
        System.assertEquals(
            'Wheeze',
            stored.Name,
            'Update should recompose Name and collapse extra spaces when a token is null'
        );

        Encounter__c orphan = new Encounter__c(Class__c = 'Virtual');
        NameFormatterHandler.format(new List<SObject>{ orphan });
        System.assert(
            orphan.Name.contains('Virtual'),
            'Null parent tokens should render as empty and leave surrounding literals. Actual: ' + orphan.Name
        );
    }

    @IsTest
    static void formatsAllSupportedObjectsOnInsert() {
        Patient__c patient = new Patient__c(
            MRN__c = 'MRN-NF-ALL',
            First_Name__c = 'Ada',
            Last_Name__c = 'Lovelace',
            Date_of_Birth__c = Date.newInstance(1815, 12, 10)
        );
        insert patient;
        patient = [SELECT Name FROM Patient__c WHERE Id = :patient.Id];

        Practitioner__c practitioner = new Practitioner__c(
            First_Name__c = 'John',
            Last_Name__c = 'Watson',
            Specialty__c = 'Other'
        );
        insert practitioner;
        practitioner = [SELECT Name FROM Practitioner__c WHERE Id = :practitioner.Id];

        Encounter__c encounter = new Encounter__c(
            Patient__c = patient.Id,
            Class__c = 'Inpatient',
            Status__c = 'Arrived',
            Start__c = Datetime.newInstance(2026, 1, 15, 8, 30, 0)
        );
        insert encounter;

        Condition__c condition = new Condition__c(
            Patient__c = patient.Id,
            Diagnosis_Display__c = 'Hypertension',
            Diagnosis_Code__c = 'I10',
            Category__c = 'Problem List Item',
            Clinical_Status__c = 'Active'
        );
        insert condition;
        condition = [SELECT Name FROM Condition__c WHERE Id = :condition.Id];

        MedicationRequest__c medRequest = new MedicationRequest__c(
            Patient__c = patient.Id,
            Medication_Display__c = 'Lisinopril',
            Dose_Quantity__c = 10,
            Dose_Unit__c = 'mg',
            Status__c = 'Active',
            Intent__c = 'Order'
        );
        insert medRequest;
        medRequest = [SELECT Name FROM MedicationRequest__c WHERE Id = :medRequest.Id];

        Test.startTest();
        insert new EncounterDiagnosis__c(
            Encounter__c = encounter.Id,
            Condition__c = condition.Id,
            Type__c = 'Principal'
        );
        insert new Observation__c(
            Patient__c = patient.Id,
            Observation_Display__c = 'Heart rate',
            Value_Quantity__c = 72,
            Value_Unit__c = 'bpm',
            Category__c = 'Vital Signs',
            Status__c = 'Final'
        );
        insert new AllergyIntolerance__c(
            Patient__c = patient.Id,
            Allergen_Display__c = 'Penicillin',
            Criticality__c = 'High'
        );
        insert new Immunization__c(
            Patient__c = patient.Id,
            Vaccine_Display__c = 'Influenza',
            Occurrence_Date__c = Date.newInstance(2026, 9, 1)
        );
        insert new MedicationStatement__c(
            Patient__c = patient.Id,
            Medication_Display__c = 'Aspirin',
            Status__c = 'Active'
        );
        insert new MedicationAdministration__c(
            Patient__c = patient.Id,
            Medication_Request__c = medRequest.Id,
            Effective_DateTime__c = Datetime.newInstance(2026, 9, 2, 11, 0, 0)
        );
        insert new ServiceRequest__c(
            Patient__c = patient.Id,
            Category__c = 'Lab',
            Service_Display__c = 'CBC'
        );
        insert new DiagnosticReport__c(
            Patient__c = patient.Id,
            Report_Display__c = 'CBC',
            Effective_DateTime__c = Datetime.newInstance(2026, 9, 2, 12, 0, 0)
        );
        insert new ClinicalNote__c(
            Patient__c = patient.Id,
            Note_Type__c = 'Progress Note',
            Author__c = practitioner.Id,
            Status__c = 'Draft',
            Body__c = 'Note body'
        );
        insert new Procedure__c(
            Patient__c = patient.Id,
            Procedure_Display__c = 'ECG',
            Performed_DateTime__c = Datetime.newInstance(2026, 9, 2, 9, 0, 0),
            Status__c = 'Completed'
        );
        insert new CareTeam__c(Patient__c = patient.Id, Status__c = 'Active');
        insert new Appointment__c(
            Patient__c = patient.Id,
            Start__c = Datetime.newInstance(2026, 9, 2, 14, 0, 0),
            Status__c = 'Booked'
        );
        Test.stopTest();

        CareTeam__c careTeam = [SELECT Name FROM CareTeam__c WHERE Patient__c = :patient.Id LIMIT 1];
        CareTeamMember__c member = new CareTeamMember__c(
            Care_Team__c = careTeam.Id,
            Practitioner__c = practitioner.Id,
            Role__c = 'Attending',
            Access_Level__c = 'Read',
            Active__c = true
        );
        insert member;

        System.assertEquals(
            'Lovelace, Ada (1815-12-10)',
            patient.Name,
            'Patient Name should compose last, first, and date of birth'
        );
        System.assertEquals(
            'Watson, John - Other',
            practitioner.Name,
            'Practitioner Name should compose last, first, and specialty'
        );
        System.assert(
            careTeam.Name.contains(patient.Name),
            'Care Team Name should include the patient name. Actual: ' + careTeam.Name
        );
        System.assertEquals(
            'Watson - Attending',
            [SELECT Name FROM CareTeamMember__c WHERE Id = :member.Id].Name,
            'Care Team Member Name should compose practitioner last name and role'
        );
        System.assertEquals(
            'Hypertension I10 (Principal)',
            [SELECT Name FROM EncounterDiagnosis__c WHERE Encounter__c = :encounter.Id].Name,
            'Encounter Diagnosis Name should use the parent Condition Name'
        );
        System.assertEquals(
            'Penicillin (High)',
            [SELECT Name FROM AllergyIntolerance__c WHERE Patient__c = :patient.Id].Name,
            'Allergy Name should compose allergen and criticality'
        );
        System.assertEquals(
            'Aspirin',
            [SELECT Name FROM MedicationStatement__c WHERE Patient__c = :patient.Id].Name,
            'Medication Statement Name should use the medication display'
        );
        Procedure__c procedureRow = [
            SELECT Name
            FROM Procedure__c
            WHERE Patient__c = :patient.Id
            LIMIT 1
        ];
        System.assert(
            procedureRow.Name.startsWith('ECG'),
            'Procedure Name should compose display and performed datetime. Actual: ' + procedureRow.Name
        );
        Appointment__c appointmentRow = [
            SELECT Name
            FROM Appointment__c
            WHERE Patient__c = :patient.Id
            LIMIT 1
        ];
        System.assert(
            appointmentRow.Name.contains(patient.Name),
            'Appointment Name should include the parent Patient Name. Actual: ' + appointmentRow.Name
        );
    }

    private static Patient__c insertPatient(String mrn) {
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'Formatter');
        insert patient;
        return patient;
    }
}
