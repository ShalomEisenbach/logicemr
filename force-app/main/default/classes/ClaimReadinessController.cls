public with sharing class ClaimReadinessController {
    private static final String MANAGE_CLAIMS_PERMISSION = 'LogicEMR_Manage_Claims';
    @TestVisible
    private static Boolean manageClaimsOverride;
    private static final String STATUS_NEEDS_REVIEW = 'Needs Review';
    private static final String STATUS_READY = 'Ready';
    private static final String STATUS_EXPORTED = 'Exported';
    private static final String STATUS_VOIDED = 'Voided';
    private static final Set<String> LOCKED_STATUSES = new Set<String>{ STATUS_EXPORTED, STATUS_VOIDED };
    private static final Set<String> ALLOWED_CODE_SYSTEMS = new Set<String>{ 'CPT', 'HCPCS' };

    public class Workspace {
        @AuraEnabled
        public String encounterStatus;
        @AuraEnabled
        public Superbill__c superbill;
        @AuraEnabled
        public List<Superbill_Diagnosis__c> diagnoses;
        @AuraEnabled
        public List<Charge_Line__c> charges;
        @AuraEnabled
        public List<String> issues;
        @AuraEnabled
        public Decimal totalCharges;
        @AuraEnabled
        public Boolean ready;

        public Workspace() {
            diagnoses = new List<Superbill_Diagnosis__c>();
            charges = new List<Charge_Line__c>();
            issues = new List<String>();
            totalCharges = 0;
            ready = false;
        }
    }

    public class ChargeInput {
        @AuraEnabled
        public Id chargeLineId { get; set; }
        @AuraEnabled
        public Id superbillId { get; set; }
        @AuraEnabled
        public Id codeReferenceId { get; set; }
        @AuraEnabled
        public String codeSystem { get; set; }
        @AuraEnabled
        public String code { get; set; }
        @AuraEnabled
        public String display { get; set; }
        @AuraEnabled
        public Date serviceDate { get; set; }
        @AuraEnabled
        public Decimal units { get; set; }
        @AuraEnabled
        public Decimal chargeAmount { get; set; }
        @AuraEnabled
        public String modifiers { get; set; }
        @AuraEnabled
        public String diagnosisPointers { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static Workspace getWorkspace(Id encounterId) {
        requireManageClaims();
        if (encounterId == null) {
            throw new AuraHandledException('Encounter Id is required.');
        }
        List<Encounter__c> encounters = [SELECT Id, Status__c FROM Encounter__c WHERE Id = :encounterId LIMIT 1];
        if (encounters.isEmpty()) {
            throw new AuraHandledException('Encounter was not found.');
        }
        List<Superbill__c> superbills = querySuperbills(encounterId);
        return buildWorkspace(encounters[0].Status__c, superbills.isEmpty() ? null : superbills[0]);
    }

    @AuraEnabled
    public static Workspace initializeSuperbill(Id encounterId) {
        requireManageClaims();
        return initializeSuperbillInternal(encounterId);
    }

    private static Workspace initializeSuperbillInternal(Id encounterId) {
        if (encounterId == null) {
            throw new AuraHandledException('Encounter Id is required.');
        }
        Encounter__c encounter = [
            SELECT Id, Status__c, Patient__c, Practitioner__c, Start__c
            FROM Encounter__c
            WHERE Id = :encounterId
            LIMIT 1
            FOR UPDATE
        ];
        Date serviceDate = encounter.Start__c == null ? Date.today() : encounter.Start__c.date();
        List<Superbill__c> existing = querySuperbills(encounterId);
        Superbill__c superbill = existing.isEmpty() ? new Superbill__c() : existing[0];
        if (LOCKED_STATUSES.contains(superbill.Status__c)) {
            return buildWorkspace(encounter.Status__c, superbill);
        }

        if (superbill.Id == null) {
            superbill.Encounter__c = encounter.Id;
        }
        superbill.Encounter_Key__c = String.valueOf(encounter.Id);
        superbill.Patient__c = encounter.Patient__c;
        superbill.Rendering_Practitioner__c = encounter.Practitioner__c;
        superbill.Date_of_Service__c = serviceDate;
        superbill.Coverage__c = findCoverage(encounter.Patient__c, serviceDate);
        superbill.Billing_Organization__c = findBillingOrganization();
        if (superbill.Id == null) {
            superbill.Status__c = STATUS_NEEDS_REVIEW;
            insert superbill;
        } else {
            superbill.Status__c = STATUS_NEEDS_REVIEW;
            superbill.Ready_Date__c = null;
            update superbill;
        }

        syncDiagnoses(superbill.Id, encounter.Id);
        syncProcedureCharges(superbill.Id, encounter.Id, serviceDate);
        Workspace workspace = buildWorkspace(encounter.Status__c, querySuperbills(encounterId)[0]);
        persistValidation(workspace);
        return buildWorkspace(encounter.Status__c, querySuperbills(encounterId)[0]);
    }

    @AuraEnabled
    public static Workspace saveCharge(ChargeInput input) {
        requireManageClaims();
        if (input == null || input.superbillId == null) {
            throw new AuraHandledException('Superbill is required.');
        }
        if (String.isBlank(input.codeSystem) || !ALLOWED_CODE_SYSTEMS.contains(input.codeSystem)) {
            throw new AuraHandledException('Code system must be CPT or HCPCS.');
        }
        if (String.isBlank(input.code) || String.isBlank(input.display)) {
            throw new AuraHandledException('Procedure code and display are required.');
        }
        if (input.units == null || input.units <= 0) {
            throw new AuraHandledException('Units must be greater than zero.');
        }
        requireEditableSuperbill(input.superbillId);

        Charge_Line__c charge = input.chargeLineId == null
            ? new Charge_Line__c(Superbill__c = input.superbillId)
            : requireCharge(input.chargeLineId, input.superbillId);
        charge.Procedure_Ref__c = input.codeReferenceId;
        charge.Procedure_Code_System__c = input.codeSystem;
        charge.Procedure_Code__c = input.code.trim();
        charge.Procedure_Display__c = input.display.trim();
        charge.Service_Date__c = input.serviceDate;
        charge.Units__c = input.units;
        charge.Charge_Amount__c = input.chargeAmount;
        charge.Modifiers__c = trimToNull(input.modifiers);
        charge.Diagnosis_Pointers__c = trimToNull(input.diagnosisPointers);
        upsert charge;
        return moveToReviewAndBuild(input.superbillId);
    }

    @AuraEnabled
    public static Workspace deleteCharge(Id chargeLineId) {
        requireManageClaims();
        if (chargeLineId == null) {
            throw new AuraHandledException('Charge line Id is required.');
        }
        Charge_Line__c charge = [SELECT Id, Superbill__c FROM Charge_Line__c WHERE Id = :chargeLineId LIMIT 1];
        requireEditableSuperbill(charge.Superbill__c);
        Id superbillId = charge.Superbill__c;
        delete charge;
        return moveToReviewAndBuild(superbillId);
    }

    @AuraEnabled
    public static Workspace markReady(Id superbillId) {
        requireManageClaims();
        Superbill__c superbill = requireEditableSuperbill(superbillId);
        Workspace workspace = buildWorkspaceForSuperbill(superbill);
        if (!workspace.issues.isEmpty()) {
            superbill.Status__c = STATUS_NEEDS_REVIEW;
            superbill.Ready_Date__c = null;
            superbill.Validation_Messages__c = String.join(workspace.issues, '\n');
            update superbill;
            throw new AuraHandledException('Resolve all claim-readiness issues before marking this superbill ready.');
        }
        superbill.Status__c = STATUS_READY;
        superbill.Ready_Date__c = Datetime.now();
        superbill.Validation_Messages__c = null;
        update superbill;
        return buildWorkspaceForSuperbill(requerySuperbill(superbill.Id));
    }

    @AuraEnabled
    public static Workspace reopen(Id superbillId) {
        requireManageClaims();
        Superbill__c superbill = requireEditableSuperbill(superbillId);
        superbill.Status__c = STATUS_NEEDS_REVIEW;
        superbill.Ready_Date__c = null;
        update superbill;
        Workspace workspace = buildWorkspaceForSuperbill(requerySuperbill(superbill.Id));
        persistValidation(workspace);
        return buildWorkspaceForSuperbill(requerySuperbill(superbill.Id));
    }

    public static void prepareForFinishedEncounter(Id encounterId) {
        initializeSuperbillInternal(encounterId);
    }

    private static Workspace moveToReviewAndBuild(Id superbillId) {
        Superbill__c superbill = requireEditableSuperbill(superbillId);
        superbill.Status__c = STATUS_NEEDS_REVIEW;
        superbill.Ready_Date__c = null;
        update superbill;
        Workspace workspace = buildWorkspaceForSuperbill(requerySuperbill(superbillId));
        persistValidation(workspace);
        return buildWorkspaceForSuperbill(requerySuperbill(superbillId));
    }

    private static void syncDiagnoses(Id superbillId, Id encounterId) {
        Map<Id, Superbill_Diagnosis__c> existingBySource = new Map<Id, Superbill_Diagnosis__c>();
        for (Superbill_Diagnosis__c row : [
            SELECT Id, Encounter_Diagnosis__c
            FROM Superbill_Diagnosis__c
            WHERE Superbill__c = :superbillId
        ]) {
            if (row.Encounter_Diagnosis__c != null) {
                existingBySource.put(row.Encounter_Diagnosis__c, row);
            }
        }
        List<Superbill_Diagnosis__c> toSave = new List<Superbill_Diagnosis__c>();
        Integer sequence = 1;
        for (EncounterDiagnosis__c source : [
            SELECT Id, Type__c, Rank__c,
                   Condition__r.Diagnosis_Code_System__c,
                   Condition__r.Diagnosis_Code__c,
                   Condition__r.Diagnosis_Display__c
            FROM EncounterDiagnosis__c
            WHERE Encounter__c = :encounterId
            ORDER BY Type__c ASC NULLS LAST, Rank__c ASC NULLS LAST, CreatedDate ASC
        ]) {
            Superbill_Diagnosis__c snapshot = existingBySource.remove(source.Id);
            if (snapshot == null) {
                snapshot = new Superbill_Diagnosis__c(
                    Superbill__c = superbillId,
                    Encounter_Diagnosis__c = source.Id
                );
            }
            snapshot.Sequence__c = sequence++;
            snapshot.Diagnosis_Type__c = source.Type__c;
            snapshot.Diagnosis_Code_System__c = source.Condition__r.Diagnosis_Code_System__c;
            snapshot.Diagnosis_Code__c = source.Condition__r.Diagnosis_Code__c;
            snapshot.Diagnosis_Display__c = source.Condition__r.Diagnosis_Display__c;
            toSave.add(snapshot);
        }
        if (!toSave.isEmpty()) {
            upsert toSave;
        }
        if (!existingBySource.isEmpty()) {
            delete existingBySource.values();
        }
    }

    private static void syncProcedureCharges(Id superbillId, Id encounterId, Date serviceDate) {
        Set<Id> alreadyLinked = new Set<Id>();
        for (Charge_Line__c charge : [
            SELECT Procedure__c FROM Charge_Line__c WHERE Superbill__c = :superbillId AND Procedure__c != NULL
        ]) {
            alreadyLinked.add(charge.Procedure__c);
        }
        List<Charge_Line__c> toInsert = new List<Charge_Line__c>();
        for (Procedure__c source : [
            SELECT Id, Procedure_Ref__c, Procedure_Code_System__c, Procedure_Code__c,
                   Procedure_Display__c, Performed_DateTime__c
            FROM Procedure__c
            WHERE Encounter__c = :encounterId AND Status__c = 'Completed'
            ORDER BY Performed_DateTime__c ASC NULLS LAST, CreatedDate ASC
        ]) {
            if (alreadyLinked.contains(source.Id)) {
                continue;
            }
            toInsert.add(
                new Charge_Line__c(
                    Superbill__c = superbillId,
                    Procedure__c = source.Id,
                    Procedure_Ref__c = source.Procedure_Ref__c,
                    Procedure_Code_System__c = source.Procedure_Code_System__c,
                    Procedure_Code__c = source.Procedure_Code__c,
                    Procedure_Display__c = source.Procedure_Display__c,
                    Service_Date__c = source.Performed_DateTime__c == null
                        ? serviceDate
                        : source.Performed_DateTime__c.date(),
                    Units__c = 1,
                    Diagnosis_Pointers__c = '1'
                )
            );
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    private static Workspace buildWorkspaceForSuperbill(Superbill__c superbill) {
        return buildWorkspace(superbill.Encounter__r.Status__c, superbill);
    }

    private static Workspace buildWorkspace(String encounterStatus, Superbill__c superbill) {
        Workspace workspace = new Workspace();
        workspace.encounterStatus = encounterStatus;
        workspace.superbill = superbill;
        if (superbill == null) {
            workspace.issues.add('Initialize a superbill for this encounter.');
            return workspace;
        }
        workspace.diagnoses = [
            SELECT Id, Name, Sequence__c, Diagnosis_Type__c, Diagnosis_Code_System__c,
                   Diagnosis_Code__c, Diagnosis_Display__c, Encounter_Diagnosis__c
            FROM Superbill_Diagnosis__c
            WHERE Superbill__c = :superbill.Id
            ORDER BY Sequence__c ASC
        ];
        workspace.charges = [
            SELECT Id, Name, Procedure__c, Procedure_Ref__c, Procedure_Code_System__c,
                   Procedure_Code__c, Procedure_Display__c, Service_Date__c, Units__c,
                   Charge_Amount__c, Modifiers__c, Diagnosis_Pointers__c
            FROM Charge_Line__c
            WHERE Superbill__c = :superbill.Id
            ORDER BY Service_Date__c ASC NULLS LAST, CreatedDate ASC
        ];
        workspace.issues = validate(superbill, encounterStatus, workspace.diagnoses, workspace.charges);
        for (Charge_Line__c charge : workspace.charges) {
            if (charge.Charge_Amount__c != null) {
                workspace.totalCharges += charge.Charge_Amount__c;
            }
        }
        workspace.ready = superbill.Status__c == STATUS_READY && workspace.issues.isEmpty();
        return workspace;
    }

    private static List<String> validate(
        Superbill__c superbill,
        String encounterStatus,
        List<Superbill_Diagnosis__c> diagnoses,
        List<Charge_Line__c> charges
    ) {
        List<String> issues = new List<String>();
        if (encounterStatus != 'Finished') {
            issues.add('Encounter must be Finished.');
        }
        if (superbill.Date_of_Service__c == null) {
            issues.add('Date of service is required.');
        }
        if (superbill.Rendering_Practitioner__c == null) {
            issues.add('Rendering practitioner is required.');
        } else if (String.isBlank(superbill.Rendering_Practitioner__r.NPI__c)) {
            issues.add('Rendering practitioner NPI is required.');
        }
        if (superbill.Billing_Organization__c == null) {
            issues.add('Default billing organization is required.');
        } else if (String.isBlank(superbill.Billing_Organization__r.NPI__c)) {
            issues.add('Billing organization NPI is required.');
        } else {
            if (String.isBlank(superbill.Billing_Organization__r.EIN__c)) {
                issues.add('Billing organization EIN is required.');
            }
            if (String.isBlank(superbill.Billing_Organization__r.Street__c) ||
                String.isBlank(superbill.Billing_Organization__r.City__c) ||
                String.isBlank(superbill.Billing_Organization__r.State__c) ||
                String.isBlank(superbill.Billing_Organization__r.Postal_Code__c)) {
                issues.add('Billing organization mailing address is incomplete.');
            }
        }
        if (superbill.Patient__c == null) {
            issues.add('Patient is required.');
        } else {
            if (String.isBlank(superbill.Patient__r.First_Name__c)) issues.add('Patient first name is required.');
            if (String.isBlank(superbill.Patient__r.Last_Name__c)) issues.add('Patient last name is required.');
            if (superbill.Patient__r.Date_of_Birth__c == null) issues.add('Patient date of birth is required.');
            if (String.isBlank(superbill.Patient__r.Sex_at_Birth__c)) issues.add('Patient sex at birth is required.');
            if (String.isBlank(superbill.Patient__r.Street__c) || String.isBlank(superbill.Patient__r.City__c) ||
                String.isBlank(superbill.Patient__r.State__c) || String.isBlank(superbill.Patient__r.Postal_Code__c)) {
                issues.add('Patient mailing address is incomplete.');
            }
        }
        if (superbill.Coverage__c == null) {
            issues.add('Active primary coverage is required.');
        } else {
            if (String.isBlank(superbill.Coverage__r.Member_Id__c)) issues.add('Coverage member ID is required.');
            if (String.isBlank(superbill.Coverage__r.Relationship_to_Subscriber__c)) {
                issues.add('Relationship to subscriber is required.');
            } else if (superbill.Coverage__r.Relationship_to_Subscriber__c != 'Self' &&
                String.isBlank(superbill.Coverage__r.Subscriber_Name__c)) {
                issues.add('Subscriber name is required when the patient is not the subscriber.');
            }
            if (superbill.Coverage__r.Payer__c == null ||
                String.isBlank(superbill.Coverage__r.Payer__r.Payer_Identifier__c)) {
                issues.add('Payer identifier is required.');
            }
        }
        if ([SELECT COUNT() FROM ClinicalNote__c WHERE Encounter__c = :superbill.Encounter__c AND Status__c = 'Signed'] == 0) {
            issues.add('At least one signed clinical note is required.');
        }
        if (diagnoses.isEmpty()) {
            issues.add('At least one encounter diagnosis is required.');
        }
        Superbill_Diagnosis__c principalDiagnosis;
        for (Superbill_Diagnosis__c diagnosis : diagnoses) {
            if (diagnosis.Diagnosis_Type__c == 'Principal' && principalDiagnosis == null) {
                principalDiagnosis = diagnosis;
            }
        }
        if (!diagnoses.isEmpty() && principalDiagnosis == null) {
            issues.add('One diagnosis must be marked Principal.');
        } else if (principalDiagnosis != null && String.isBlank(principalDiagnosis.Diagnosis_Code__c)) {
            issues.add('Primary diagnosis code is required.');
        }
        if (diagnoses.size() > 12) {
            issues.add('A professional claim can reference no more than 12 diagnoses.');
        }
        if (charges.isEmpty()) {
            issues.add('At least one charge line is required.');
        }
        Set<Integer> validPointers = new Set<Integer>();
        for (Superbill_Diagnosis__c diagnosis : diagnoses) {
            validPointers.add(diagnosis.Sequence__c.intValue());
        }
        Integer lineNumber = 0;
        for (Charge_Line__c charge : charges) {
            lineNumber++;
            String prefix = 'Charge ' + lineNumber + ': ';
            if (String.isBlank(charge.Procedure_Code__c)) issues.add(prefix + 'procedure code is required.');
            if (!ALLOWED_CODE_SYSTEMS.contains(charge.Procedure_Code_System__c)) {
                issues.add(prefix + 'code system must be CPT or HCPCS.');
            }
            if (charge.Service_Date__c == null) issues.add(prefix + 'service date is required.');
            if (charge.Units__c == null || charge.Units__c <= 0) issues.add(prefix + 'units must be greater than zero.');
            if (charge.Charge_Amount__c == null || charge.Charge_Amount__c <= 0) {
                issues.add(prefix + 'charge amount must be greater than zero.');
            }
            if (!hasValidPointers(charge.Diagnosis_Pointers__c, validPointers)) {
                issues.add(prefix + 'diagnosis pointers must reference listed diagnoses.');
            }
            if (!hasValidModifiers(charge.Modifiers__c)) {
                issues.add(prefix + 'modifiers must contain up to four two-character values.');
            }
        }
        return issues;
    }

    private static Boolean hasValidPointers(String value, Set<Integer> validPointers) {
        if (String.isBlank(value)) {
            return false;
        }
        for (String token : value.split(',')) {
            String trimmed = token.trim();
            if (!Pattern.matches('^[0-9]+$', trimmed) || !validPointers.contains(Integer.valueOf(trimmed))) {
                return false;
            }
        }
        return true;
    }

    private static Boolean hasValidModifiers(String value) {
        if (String.isBlank(value)) return true;
        List<String> tokens = value.split(',');
        if (tokens.size() > 4) return false;
        for (String token : tokens) {
            if (!Pattern.matches('^[A-Za-z0-9]{2}$', token.trim())) return false;
        }
        return true;
    }

    private static void persistValidation(Workspace workspace) {
        if (workspace.superbill == null || LOCKED_STATUSES.contains(workspace.superbill.Status__c)) {
            return;
        }
        Superbill__c superbill = workspace.superbill;
        superbill.Validation_Messages__c = workspace.issues.isEmpty()
            ? null
            : String.join(workspace.issues, '\n');
        update superbill;
    }

    private static Id findCoverage(Id patientId, Date serviceDate) {
        if (patientId == null) return null;
        List<Coverage__c> rows = [
            SELECT Id
            FROM Coverage__c
            WHERE Patient__c = :patientId AND Status__c = 'Active'
              AND (Effective_Start__c = NULL OR Effective_Start__c <= :serviceDate)
              AND (Effective_End__c = NULL OR Effective_End__c >= :serviceDate)
            ORDER BY Priority__c ASC NULLS LAST, Effective_Start__c DESC NULLS LAST
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Id;
    }

    private static Id findBillingOrganization() {
        List<Organization__c> rows = [
            SELECT Id FROM Organization__c
            WHERE Active__c = TRUE AND Is_Default_Billing__c = TRUE
            ORDER BY LastModifiedDate DESC LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Id;
    }

    private static List<Superbill__c> querySuperbills(Id encounterId) {
        return [
            SELECT Id, Name, Encounter__c, Encounter__r.Status__c, Encounter_Key__c, Patient__c,
                   Patient__r.Name, Patient__r.First_Name__c, Patient__r.Last_Name__c,
                   Patient__r.Date_of_Birth__c, Patient__r.Sex_at_Birth__c,
                   Patient__r.Street__c, Patient__r.City__c, Patient__r.State__c,
                   Patient__r.Postal_Code__c, Coverage__c, Coverage__r.Member_Id__c,
                   Coverage__r.Relationship_to_Subscriber__c, Coverage__r.Subscriber_Name__c,
                   Coverage__r.Payer__c, Coverage__r.Payer__r.Name,
                   Coverage__r.Payer__r.Payer_Identifier__c, Billing_Organization__c,
                   Billing_Organization__r.Name, Billing_Organization__r.NPI__c,
                   Billing_Organization__r.EIN__c, Billing_Organization__r.Street__c,
                   Billing_Organization__r.City__c, Billing_Organization__r.State__c,
                   Billing_Organization__r.Postal_Code__c,
                   Rendering_Practitioner__c, Rendering_Practitioner__r.Name,
                   Rendering_Practitioner__r.NPI__c, Date_of_Service__c, Status__c,
                   Ready_Date__c, Validation_Messages__c
            FROM Superbill__c
            WHERE Encounter__c = :encounterId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }

    private static Superbill__c requerySuperbill(Id superbillId) {
        Superbill__c seed = [SELECT Encounter__c FROM Superbill__c WHERE Id = :superbillId LIMIT 1];
        return querySuperbills(seed.Encounter__c)[0];
    }

    private static Superbill__c requireEditableSuperbill(Id superbillId) {
        if (superbillId == null) throw new AuraHandledException('Superbill Id is required.');
        Superbill__c superbill = requerySuperbill(superbillId);
        if (LOCKED_STATUSES.contains(superbill.Status__c)) {
            throw new AuraHandledException('Exported or voided superbills cannot be changed.');
        }
        return superbill;
    }

    private static Charge_Line__c requireCharge(Id chargeLineId, Id superbillId) {
        List<Charge_Line__c> rows = [
            SELECT Id, Superbill__c FROM Charge_Line__c
            WHERE Id = :chargeLineId AND Superbill__c = :superbillId LIMIT 1
        ];
        if (rows.isEmpty()) throw new AuraHandledException('Charge line was not found on this superbill.');
        return rows[0];
    }

    private static String trimToNull(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static void requireManageClaims() {
        Boolean allowed = manageClaimsOverride != null
            ? manageClaimsOverride
            : FeatureManagement.checkPermission(MANAGE_CLAIMS_PERMISSION);
        if (!allowed) {
            throw new AuraHandledException('You do not have permission to manage LogicEMR claims.');
        }
    }
}
