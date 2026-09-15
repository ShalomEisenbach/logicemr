public with sharing class ClaimExportService {
    public static final String SCHEMA_VERSION = '1.1';
    private static final Set<String> EXPORTABLE_STATUSES = new Set<String>{ 'Ready', 'Exported' };

    public static VendorNeutralClaim build(Id superbillId) {
        if (superbillId == null) throw new AuraHandledException('Superbill Id is required.');
        List<Superbill__c> rows = [
            SELECT Id, Name, Status__c, Date_of_Service__c, Ready_Date__c,
                   Encounter__c, Patient__c, Coverage__c, Rendering_Practitioner__c,
                   Billing_Organization__c, Snapshot_Refreshed_At__c, Snapshot_Version__c,
                   Place_of_Service_Code__c, Claim_Filing_Code__c,
                   Patient_First_Name__c, Patient_Last_Name__c, Patient_Date_of_Birth__c,
                   Patient_Sex__c, Patient_Street__c, Patient_City__c, Patient_State__c,
                   Patient_Postal_Code__c, Patient_Country__c,
                   Subscriber_First_Name__c, Subscriber_Last_Name__c,
                   Subscriber_Date_of_Birth__c, Subscriber_Sex__c,
                   Subscriber_Relationship__c, Subscriber_Member_Id__c,
                   Subscriber_Group_Number__c, Subscriber_Street__c, Subscriber_City__c,
                   Subscriber_State__c, Subscriber_Postal_Code__c, Subscriber_Country__c,
                   Coverage_Effective_Start__c, Coverage_Effective_End__c,
                   Payer_Name__c, Payer_Identifier__c,
                   Rendering_Provider_Name__c, Rendering_Provider_First_Name__c,
                   Rendering_Provider_Last_Name__c, Rendering_Provider_NPI__c,
                   Rendering_Provider_Taxonomy__c, Billing_Provider_Name__c,
                   Billing_Provider_NPI__c, Billing_Provider_EIN__c,
                   Billing_Provider_Taxonomy__c, Billing_Provider_Street__c,
                   Billing_Provider_City__c, Billing_Provider_State__c,
                   Billing_Provider_Postal_Code__c, Billing_Provider_Country__c
            FROM Superbill__c
            WHERE Id = :superbillId
            LIMIT 1
        ];
        if (rows.isEmpty()) throw new AuraHandledException('Superbill was not found.');
        Superbill__c superbill = rows[0];
        if (!EXPORTABLE_STATUSES.contains(superbill.Status__c)) {
            throw new AuraHandledException('Only Ready or Exported superbills can produce a canonical claim export.');
        }

        List<Superbill_Diagnosis__c> diagnoses = [
            SELECT Sequence__c, Diagnosis_Type__c, Diagnosis_Code_System__c,
                   Diagnosis_Code__c, Diagnosis_Display__c
            FROM Superbill_Diagnosis__c
            WHERE Superbill__c = :superbillId
            ORDER BY Sequence__c ASC, CreatedDate ASC
        ];
        List<Charge_Line__c> charges = [
            SELECT Id, Procedure_Code_System__c, Procedure_Code__c, Procedure_Display__c,
                   Service_Date__c, Units__c, Charge_Amount__c, Modifiers__c,
                   Diagnosis_Pointers__c, Applied_Unit_Rate__c, Rate_Source__c,
                   Rate_Override__c, Override_Reason__c
            FROM Charge_Line__c
            WHERE Superbill__c = :superbillId
            ORDER BY Service_Date__c ASC NULLS LAST, CreatedDate ASC, Id ASC
        ];
        assertExportable(superbill, diagnoses, charges);
        return mapClaim(superbill, diagnoses, charges);
    }

    public static String serialize(Id superbillId) {
        return JSON.serializePretty(build(superbillId));
    }

    private static VendorNeutralClaim mapClaim(
        Superbill__c superbill,
        List<Superbill_Diagnosis__c> diagnosisRows,
        List<Charge_Line__c> chargeRows
    ) {
        VendorNeutralClaim claim = new VendorNeutralClaim();
        claim.schemaVersion = SCHEMA_VERSION;
        claim.sourceSystem = 'LogicEMR';
        claim.claimType = 'professional';
        claim.sourceRecordId = superbill.Id;
        claim.claimIdentifier = superbill.Name;
        claim.status = superbill.Status__c;
        claim.dateOfService = superbill.Date_of_Service__c;
        claim.placeOfServiceCode = superbill.Place_of_Service_Code__c;
        claim.claimFilingCode = superbill.Claim_Filing_Code__c;
        claim.readyAt = superbill.Ready_Date__c;
        claim.snapshotVersion = superbill.Snapshot_Version__c;
        claim.snapshotRefreshedAt = superbill.Snapshot_Refreshed_At__c;
        claim.currencyCode = 'USD';
        claim.totalCharge = 0;

        claim.patient = new VendorNeutralClaim.Patient();
        claim.patient.name = personName(superbill.Patient_First_Name__c, superbill.Patient_Last_Name__c);
        claim.patient.dateOfBirth = superbill.Patient_Date_of_Birth__c;
        claim.patient.sex = superbill.Patient_Sex__c;
        claim.patient.address = address(
            superbill.Patient_Street__c, superbill.Patient_City__c, superbill.Patient_State__c,
            superbill.Patient_Postal_Code__c, superbill.Patient_Country__c
        );

        claim.subscriber = new VendorNeutralClaim.Subscriber();
        claim.subscriber.name = personName(superbill.Subscriber_First_Name__c, superbill.Subscriber_Last_Name__c);
        claim.subscriber.dateOfBirth = superbill.Subscriber_Date_of_Birth__c;
        claim.subscriber.sex = superbill.Subscriber_Sex__c;
        claim.subscriber.patientRelationshipToSubscriber = superbill.Subscriber_Relationship__c;
        claim.subscriber.memberId = superbill.Subscriber_Member_Id__c;
        claim.subscriber.groupNumber = superbill.Subscriber_Group_Number__c;
        claim.subscriber.coverageStart = superbill.Coverage_Effective_Start__c;
        claim.subscriber.coverageEnd = superbill.Coverage_Effective_End__c;
        claim.subscriber.address = address(
            superbill.Subscriber_Street__c, superbill.Subscriber_City__c, superbill.Subscriber_State__c,
            superbill.Subscriber_Postal_Code__c, superbill.Subscriber_Country__c
        );

        claim.payer = new VendorNeutralClaim.Payer();
        claim.payer.name = superbill.Payer_Name__c;
        claim.payer.identifier = superbill.Payer_Identifier__c;

        claim.renderingProvider = new VendorNeutralClaim.RenderingProvider();
        claim.renderingProvider.name = superbill.Rendering_Provider_Name__c;
        claim.renderingProvider.firstName = superbill.Rendering_Provider_First_Name__c;
        claim.renderingProvider.lastName = superbill.Rendering_Provider_Last_Name__c;
        claim.renderingProvider.npi = superbill.Rendering_Provider_NPI__c;
        claim.renderingProvider.taxonomyCode = superbill.Rendering_Provider_Taxonomy__c;

        claim.billingProvider = new VendorNeutralClaim.BillingProvider();
        claim.billingProvider.legalName = superbill.Billing_Provider_Name__c;
        claim.billingProvider.npi = superbill.Billing_Provider_NPI__c;
        claim.billingProvider.taxIdentifier = normalizeDigits(superbill.Billing_Provider_EIN__c);
        claim.billingProvider.taxonomyCode = superbill.Billing_Provider_Taxonomy__c;
        claim.billingProvider.address = address(
            superbill.Billing_Provider_Street__c, superbill.Billing_Provider_City__c,
            superbill.Billing_Provider_State__c, superbill.Billing_Provider_Postal_Code__c,
            superbill.Billing_Provider_Country__c
        );

        claim.diagnoses = new List<VendorNeutralClaim.Diagnosis>();
        for (Superbill_Diagnosis__c row : diagnosisRows) {
            VendorNeutralClaim.Diagnosis diagnosis = new VendorNeutralClaim.Diagnosis();
            diagnosis.sequence = row.Sequence__c == null ? null : row.Sequence__c.intValue();
            diagnosis.type = row.Diagnosis_Type__c;
            diagnosis.codeSystem = row.Diagnosis_Code_System__c;
            diagnosis.code = row.Diagnosis_Code__c;
            diagnosis.display = row.Diagnosis_Display__c;
            claim.diagnoses.add(diagnosis);
        }

        claim.serviceLines = new List<VendorNeutralClaim.ServiceLine>();
        for (Charge_Line__c row : chargeRows) {
            VendorNeutralClaim.ServiceLine line = new VendorNeutralClaim.ServiceLine();
            line.sourceLineId = row.Id;
            line.codeSystem = row.Procedure_Code_System__c;
            line.code = row.Procedure_Code__c;
            line.display = row.Procedure_Display__c;
            line.serviceDate = row.Service_Date__c;
            line.units = row.Units__c;
            line.chargeAmount = row.Charge_Amount__c;
            line.modifiers = parseStrings(row.Modifiers__c);
            line.diagnosisPointers = parseIntegers(row.Diagnosis_Pointers__c);
            line.rate = new VendorNeutralClaim.Rate();
            line.rate.unitRate = row.Applied_Unit_Rate__c;
            line.rate.source = row.Rate_Source__c;
            line.rate.overridden = row.Rate_Override__c == true;
            line.rate.overrideReason = row.Override_Reason__c;
            claim.totalCharge += row.Charge_Amount__c;
            claim.serviceLines.add(line);
        }
        return claim;
    }

    private static void assertExportable(
        Superbill__c superbill,
        List<Superbill_Diagnosis__c> diagnoses,
        List<Charge_Line__c> charges
    ) {
        List<String> issues = ClaimSnapshotService.validate(superbill);
        if (String.isBlank(superbill.Place_of_Service_Code__c)) issues.add('Place of service code is required.');
        if (String.isBlank(superbill.Claim_Filing_Code__c)) issues.add('Claim filing code snapshot is required.');
        if (superbill.Encounter__c == null) issues.add('Encounter reference is required.');
        if (superbill.Patient__c == null) issues.add('Patient reference is required.');
        if (superbill.Coverage__c == null) issues.add('Coverage reference is required.');
        if (superbill.Rendering_Practitioner__c == null) issues.add('Rendering practitioner reference is required.');
        if (superbill.Billing_Organization__c == null) issues.add('Billing organization reference is required.');
        if (diagnoses.isEmpty()) issues.add('At least one diagnosis snapshot is required.');
        if (charges.isEmpty()) issues.add('At least one service line snapshot is required.');
        for (Superbill_Diagnosis__c diagnosis : diagnoses) {
            if (diagnosis.Sequence__c == null || String.isBlank(diagnosis.Diagnosis_Code__c)) {
                issues.add('Every diagnosis snapshot requires a sequence and code.');
                break;
            }
        }
        for (Charge_Line__c charge : charges) {
            if (String.isBlank(charge.Procedure_Code__c) || charge.Service_Date__c == null ||
                charge.Units__c == null || charge.Units__c <= 0 ||
                charge.Charge_Amount__c == null || charge.Charge_Amount__c <= 0 ||
                !validPointers(charge.Diagnosis_Pointers__c, diagnoses.size())) {
                issues.add('Every service line snapshot requires a code, date, positive units and charge, and valid diagnosis pointers.');
                break;
            }
        }
        if (!issues.isEmpty()) {
            throw new AuraHandledException('Claim cannot be exported: ' + String.join(issues, ' '));
        }
    }

    private static VendorNeutralClaim.PersonName personName(String firstName, String lastName) {
        VendorNeutralClaim.PersonName value = new VendorNeutralClaim.PersonName();
        value.first = firstName;
        value.last = lastName;
        return value;
    }

    private static VendorNeutralClaim.Address address(
        String street,
        String city,
        String state,
        String postalCode,
        String country
    ) {
        VendorNeutralClaim.Address value = new VendorNeutralClaim.Address();
        value.street = street;
        value.city = city;
        value.state = state;
        value.postalCode = postalCode;
        value.country = country;
        return value;
    }

    private static List<String> parseStrings(String value) {
        List<String> parsed = new List<String>();
        if (String.isBlank(value)) return parsed;
        for (String token : value.split(',')) parsed.add(token.trim());
        return parsed;
    }

    private static List<Integer> parseIntegers(String value) {
        List<Integer> parsed = new List<Integer>();
        if (String.isBlank(value)) return parsed;
        for (String token : value.split(',')) parsed.add(Integer.valueOf(token.trim()));
        return parsed;
    }

    private static Boolean validPointers(String value, Integer diagnosisCount) {
        if (String.isBlank(value)) return false;
        for (String token : value.split(',')) {
            String trimmed = token.trim();
            if (!Pattern.matches('^[0-9]+$', trimmed)) return false;
            Integer pointer = Integer.valueOf(trimmed);
            if (pointer < 1 || pointer > diagnosisCount) return false;
        }
        return true;
    }

    private static String normalizeDigits(String value) {
        return String.isBlank(value) ? null : value.replaceAll('[^0-9]', '');
    }
}
