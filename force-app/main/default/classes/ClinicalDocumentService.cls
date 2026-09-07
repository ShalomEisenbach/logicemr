public with sharing class ClinicalDocumentService {
    private static final Integer MAX_CLINICAL = 50;
    private static final Integer MAX_LABS = 20;
    private static final Integer MAX_NOTES = 10;
    private static final String STATUS_ACTIVE = 'Active';
    private static final String STATUS_SIGNED = 'Signed';
    private static final String CATEGORY_VITALS = 'Vital Signs';
    private static final String CATEGORY_LAB = 'Laboratory';

    public class ChartSummary {
        public PatientHeader patient { get; set; }
        public Datetime generatedAt { get; set; }
        public List<ProblemRow> problems { get; set; }
        public List<AllergyRow> allergies { get; set; }
        public List<MedicationRow> activeOrders { get; set; }
        public List<MedicationRow> reportedMedications { get; set; }
        public List<ObservationRow> vitals { get; set; }
        public List<ObservationRow> labs { get; set; }
        public List<ProcedureRow> procedures { get; set; }
        public List<NoteRow> signedNotes { get; set; }
    }

    public class PrescriptionPad {
        public PatientHeader patient { get; set; }
        public Datetime generatedAt { get; set; }
        public List<PrescriptionRow> prescriptions { get; set; }
    }

    public class PatientHeader {
        public String fullName { get; set; }
        public String mrn { get; set; }
        public Date dateOfBirth { get; set; }
        public String sexAtBirth { get; set; }
        public String phone { get; set; }
        public String email { get; set; }
    }

    public class ProblemRow {
        public String display { get; set; }
        public String code { get; set; }
        public String codeSystem { get; set; }
        public String clinicalStatus { get; set; }
        public Date onsetDate { get; set; }
    }

    public class AllergyRow {
        public String display { get; set; }
        public String code { get; set; }
        public String reaction { get; set; }
        public String criticality { get; set; }
        public String clinicalStatus { get; set; }
    }

    public class MedicationRow {
        public String display { get; set; }
        public String code { get; set; }
        public String dosageText { get; set; }
        public String frequency { get; set; }
        public String route { get; set; }
        public String status { get; set; }
        public String source { get; set; }
    }

    public class ObservationRow {
        public String display { get; set; }
        public String value { get; set; }
        public String unit { get; set; }
        public Datetime effectiveDateTime { get; set; }
        public String interpretation { get; set; }
    }

    public class ProcedureRow {
        public String display { get; set; }
        public String code { get; set; }
        public String status { get; set; }
        public Datetime performedDateTime { get; set; }
    }

    public class NoteRow {
        public String noteType { get; set; }
        public String body { get; set; }
        public Datetime signedDate { get; set; }
        public String authorName { get; set; }
    }

    public class PrescriptionRow {
        public String display { get; set; }
        public String code { get; set; }
        public String codeSystem { get; set; }
        public String dosageText { get; set; }
        public Decimal doseQuantity { get; set; }
        public String doseUnit { get; set; }
        public String frequency { get; set; }
        public String route { get; set; }
        public String status { get; set; }
        public Datetime authoredOn { get; set; }
        public String requesterName { get; set; }
        public String requesterNpi { get; set; }
        // TODO: Quantity, Refills, DEA, patient address — not in data model yet
    }

    public static ChartSummary getChartSummary(Id patientId) {
        ChartSummary summary = new ChartSummary();
        summary.problems = new List<ProblemRow>();
        summary.allergies = new List<AllergyRow>();
        summary.activeOrders = new List<MedicationRow>();
        summary.reportedMedications = new List<MedicationRow>();
        summary.vitals = new List<ObservationRow>();
        summary.labs = new List<ObservationRow>();
        summary.procedures = new List<ProcedureRow>();
        summary.signedNotes = new List<NoteRow>();
        summary.generatedAt = Datetime.now();

        if (patientId == null) {
            return summary;
        }

        Patient__c patient = queryPatient(patientId);
        if (patient == null) {
            return summary;
        }
        summary.patient = toHeader(patient);

        for (Condition__c row : [
            SELECT
                Diagnosis_Display__c,
                Diagnosis_Code__c,
                Diagnosis_Code_System__c,
                Clinical_Status__c,
                Onset_Date__c
            FROM Condition__c
            WHERE Patient__c = :patientId AND Clinical_Status__c = :STATUS_ACTIVE
            ORDER BY Diagnosis_Display__c ASC NULLS LAST
            LIMIT :MAX_CLINICAL
        ]) {
            ProblemRow item = new ProblemRow();
            item.display = row.Diagnosis_Display__c;
            item.code = row.Diagnosis_Code__c;
            item.codeSystem = row.Diagnosis_Code_System__c;
            item.clinicalStatus = row.Clinical_Status__c;
            item.onsetDate = row.Onset_Date__c;
            summary.problems.add(item);
        }

        for (AllergyIntolerance__c row : [
            SELECT
                Allergen_Display__c,
                Allergen_Code__c,
                Reaction__c,
                Criticality__c,
                Clinical_Status__c
            FROM AllergyIntolerance__c
            WHERE Patient__c = :patientId AND Clinical_Status__c = :STATUS_ACTIVE
            ORDER BY Allergen_Display__c ASC NULLS LAST
            LIMIT :MAX_CLINICAL
        ]) {
            AllergyRow item = new AllergyRow();
            item.display = row.Allergen_Display__c;
            item.code = row.Allergen_Code__c;
            item.reaction = row.Reaction__c;
            item.criticality = row.Criticality__c;
            item.clinicalStatus = row.Clinical_Status__c;
            summary.allergies.add(item);
        }

        for (MedicationRequest__c row : [
            SELECT
                Medication_Display__c,
                Medication_Code__c,
                Dosage_Text__c,
                Frequency__c,
                Route__c,
                Status__c
            FROM MedicationRequest__c
            WHERE Patient__c = :patientId AND Status__c = :STATUS_ACTIVE
            ORDER BY Medication_Display__c ASC NULLS LAST
            LIMIT :MAX_CLINICAL
        ]) {
            MedicationRow item = new MedicationRow();
            item.display = row.Medication_Display__c;
            item.code = row.Medication_Code__c;
            item.dosageText = row.Dosage_Text__c;
            item.frequency = row.Frequency__c;
            item.route = row.Route__c;
            item.status = row.Status__c;
            summary.activeOrders.add(item);
        }

        for (MedicationStatement__c row : [
            SELECT
                Medication_Display__c,
                Medication_Code__c,
                Dosage_Text__c,
                Status__c,
                Source__c
            FROM MedicationStatement__c
            WHERE Patient__c = :patientId AND Status__c = :STATUS_ACTIVE
            ORDER BY Medication_Display__c ASC NULLS LAST
            LIMIT :MAX_CLINICAL
        ]) {
            MedicationRow item = new MedicationRow();
            item.display = row.Medication_Display__c;
            item.code = row.Medication_Code__c;
            item.dosageText = row.Dosage_Text__c;
            item.status = row.Status__c;
            item.source = row.Source__c;
            summary.reportedMedications.add(item);
        }

        for (Observation__c row : [
            SELECT
                Observation_Display__c,
                Value_Quantity__c,
                Value_String__c,
                Value_Unit__c,
                Effective_DateTime__c,
                Interpretation__c
            FROM Observation__c
            WHERE Patient__c = :patientId AND Category__c = :CATEGORY_VITALS
            ORDER BY Effective_DateTime__c DESC NULLS LAST
            LIMIT :MAX_CLINICAL
        ]) {
            summary.vitals.add(toObservationRow(row));
        }

        for (Observation__c row : [
            SELECT
                Observation_Display__c,
                Value_Quantity__c,
                Value_String__c,
                Value_Unit__c,
                Effective_DateTime__c,
                Interpretation__c
            FROM Observation__c
            WHERE Patient__c = :patientId AND Category__c = :CATEGORY_LAB
            ORDER BY Effective_DateTime__c DESC NULLS LAST
            LIMIT :MAX_LABS
        ]) {
            summary.labs.add(toObservationRow(row));
        }

        for (Procedure__c row : [
            SELECT
                Procedure_Display__c,
                Procedure_Code__c,
                Status__c,
                Performed_DateTime__c
            FROM Procedure__c
            WHERE Patient__c = :patientId
            ORDER BY Performed_DateTime__c DESC NULLS LAST
            LIMIT :MAX_CLINICAL
        ]) {
            ProcedureRow item = new ProcedureRow();
            item.display = row.Procedure_Display__c;
            item.code = row.Procedure_Code__c;
            item.status = row.Status__c;
            item.performedDateTime = row.Performed_DateTime__c;
            summary.procedures.add(item);
        }

        for (ClinicalNote__c row : [
            SELECT
                Note_Type__c,
                Body__c,
                Signed_Date__c,
                Author__r.First_Name__c,
                Author__r.Last_Name__c
            FROM ClinicalNote__c
            WHERE Patient__c = :patientId AND Status__c = :STATUS_SIGNED
            ORDER BY Signed_Date__c DESC NULLS LAST
            LIMIT :MAX_NOTES
        ]) {
            NoteRow item = new NoteRow();
            item.noteType = row.Note_Type__c;
            item.body = row.Body__c;
            item.signedDate = row.Signed_Date__c;
            item.authorName = formatName(
                row.Author__r == null ? null : row.Author__r.First_Name__c,
                row.Author__r == null ? null : row.Author__r.Last_Name__c
            );
            summary.signedNotes.add(item);
        }

        return summary;
    }

    public static PrescriptionPad getPrescriptionPad(Id patientId, List<Id> requestIds) {
        PrescriptionPad pad = new PrescriptionPad();
        pad.prescriptions = new List<PrescriptionRow>();
        pad.generatedAt = Datetime.now();

        if (patientId == null || requestIds == null || requestIds.isEmpty()) {
            return pad;
        }

        Patient__c patient = queryPatient(patientId);
        if (patient == null) {
            return pad;
        }
        pad.patient = toHeader(patient);

        Set<Id> ids = new Set<Id>();
        for (Id requestId : requestIds) {
            if (requestId != null) {
                ids.add(requestId);
            }
        }
        if (ids.isEmpty()) {
            return pad;
        }

        for (MedicationRequest__c row : [
            SELECT
                Medication_Display__c,
                Medication_Code__c,
                Medication_Code_System__c,
                Dosage_Text__c,
                Dose_Quantity__c,
                Dose_Unit__c,
                Frequency__c,
                Route__c,
                Status__c,
                Authored_On__c,
                Requester__r.First_Name__c,
                Requester__r.Last_Name__c,
                Requester__r.NPI__c
            FROM MedicationRequest__c
            WHERE Id IN :ids AND Patient__c = :patientId
            ORDER BY Medication_Display__c ASC NULLS LAST
            LIMIT :MAX_CLINICAL
        ]) {
            PrescriptionRow item = new PrescriptionRow();
            item.display = row.Medication_Display__c;
            item.code = row.Medication_Code__c;
            item.codeSystem = row.Medication_Code_System__c;
            item.dosageText = row.Dosage_Text__c;
            item.doseQuantity = row.Dose_Quantity__c;
            item.doseUnit = row.Dose_Unit__c;
            item.frequency = row.Frequency__c;
            item.route = row.Route__c;
            item.status = row.Status__c;
            item.authoredOn = row.Authored_On__c;
            item.requesterName = formatName(
                row.Requester__r == null ? null : row.Requester__r.First_Name__c,
                row.Requester__r == null ? null : row.Requester__r.Last_Name__c
            );
            item.requesterNpi = row.Requester__r == null ? null : row.Requester__r.NPI__c;
            pad.prescriptions.add(item);
        }

        return pad;
    }

    public static Patient__c queryPatient(Id patientId) {
        List<Patient__c> rows = [
            SELECT
                Id,
                First_Name__c,
                Last_Name__c,
                MRN__c,
                Date_of_Birth__c,
                Sex_at_Birth__c,
                Phone__c,
                Email__c
            FROM Patient__c
            WHERE Id = :patientId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static PatientHeader toHeader(Patient__c patient) {
        PatientHeader header = new PatientHeader();
        header.fullName = formatName(patient.First_Name__c, patient.Last_Name__c);
        if (String.isBlank(header.fullName)) {
            header.fullName = 'Patient';
        }
        header.mrn = patient.MRN__c;
        header.dateOfBirth = patient.Date_of_Birth__c;
        header.sexAtBirth = patient.Sex_at_Birth__c;
        header.phone = patient.Phone__c;
        header.email = patient.Email__c;
        return header;
    }

    private static ObservationRow toObservationRow(Observation__c row) {
        ObservationRow item = new ObservationRow();
        item.display = row.Observation_Display__c;
        if (row.Value_Quantity__c != null) {
            item.value = row.Value_Quantity__c.stripTrailingZeros().toPlainString();
        } else {
            item.value = row.Value_String__c;
        }
        item.unit = row.Value_Unit__c;
        item.effectiveDateTime = row.Effective_DateTime__c;
        item.interpretation = row.Interpretation__c;
        return item;
    }

    private static String formatName(String firstName, String lastName) {
        String first = firstName == null ? '' : firstName.trim();
        String last = lastName == null ? '' : lastName.trim();
        return (first + ' ' + last).trim();
    }
}
