public with sharing class ClaimSnapshotService {
    private static final Set<String> FROZEN_STATUSES = new Set<String>{ 'Ready', 'Exported', 'Voided' };
    private static final List<String> CLAIM_CONTEXT_FIELDS = new List<String>{
        'Encounter__c', 'Encounter_Key__c', 'Patient__c', 'Coverage__c',
        'Rendering_Practitioner__c', 'Billing_Organization__c', 'Date_of_Service__c',
        'Place_of_Service_Code__c'
    };
    private static final List<String> SNAPSHOT_FIELDS = new List<String>{
        'Snapshot_Refreshed_At__c', 'Snapshot_Version__c',
        'Patient_First_Name__c', 'Patient_Last_Name__c', 'Patient_Date_of_Birth__c',
        'Patient_Sex__c', 'Patient_Street__c', 'Patient_City__c', 'Patient_State__c',
        'Patient_Postal_Code__c', 'Patient_Country__c',
        'Subscriber_First_Name__c', 'Subscriber_Last_Name__c', 'Subscriber_Date_of_Birth__c',
        'Subscriber_Sex__c', 'Subscriber_Relationship__c', 'Subscriber_Member_Id__c',
        'Subscriber_Group_Number__c', 'Subscriber_Street__c', 'Subscriber_City__c',
        'Subscriber_State__c', 'Subscriber_Postal_Code__c', 'Subscriber_Country__c',
        'Payer_Name__c', 'Payer_Identifier__c', 'Claim_Filing_Code__c', 'Coverage_Effective_Start__c',
        'Coverage_Effective_End__c', 'Rendering_Provider_Name__c',
        'Rendering_Provider_First_Name__c', 'Rendering_Provider_Last_Name__c', 'Rendering_Provider_NPI__c',
        'Rendering_Provider_Taxonomy__c', 'Billing_Provider_Name__c', 'Billing_Provider_NPI__c',
        'Billing_Provider_EIN__c', 'Billing_Provider_Taxonomy__c', 'Billing_Provider_Street__c',
        'Billing_Provider_City__c', 'Billing_Provider_State__c', 'Billing_Provider_Postal_Code__c',
        'Billing_Provider_Country__c'
    };

    public static void populate(Superbill__c superbill) {
        if (superbill == null) return;
        clearSnapshot(superbill);

        Patient__c patient;
        if (superbill.Patient__c != null) {
            patient = [
                SELECT First_Name__c, Last_Name__c, Date_of_Birth__c, Sex_at_Birth__c,
                       Street__c, City__c, State__c, Postal_Code__c, Country__c
                FROM Patient__c
                WHERE Id = :superbill.Patient__c
                LIMIT 1
            ];
            superbill.Patient_First_Name__c = patient.First_Name__c;
            superbill.Patient_Last_Name__c = patient.Last_Name__c;
            superbill.Patient_Date_of_Birth__c = patient.Date_of_Birth__c;
            superbill.Patient_Sex__c = patient.Sex_at_Birth__c;
            superbill.Patient_Street__c = patient.Street__c;
            superbill.Patient_City__c = patient.City__c;
            superbill.Patient_State__c = patient.State__c;
            superbill.Patient_Postal_Code__c = patient.Postal_Code__c;
            superbill.Patient_Country__c = patient.Country__c;
        }

        Coverage__c coverage;
        if (superbill.Coverage__c != null) {
            coverage = [
                SELECT Member_Id__c, Group_Number__c, Relationship_to_Subscriber__c,
                       Subscriber_Name__c, Subscriber_First_Name__c, Subscriber_Last_Name__c,
                       Subscriber_Date_of_Birth__c, Subscriber_Sex__c, Subscriber_Street__c,
                       Subscriber_City__c, Subscriber_State__c, Subscriber_Postal_Code__c,
                       Subscriber_Country__c, Effective_Start__c, Effective_End__c,
                       Payer__c, Payer__r.Name, Payer__r.Payer_Identifier__c,
                       Payer__r.Claim_Filing_Code__c, Payer__r.Type__c
                FROM Coverage__c
                WHERE Id = :superbill.Coverage__c
                LIMIT 1
            ];
        }

        if (coverage != null) {
            superbill.Subscriber_Relationship__c = coverage.Relationship_to_Subscriber__c;
            superbill.Subscriber_Member_Id__c = coverage.Member_Id__c;
            superbill.Subscriber_Group_Number__c = coverage.Group_Number__c;
            superbill.Coverage_Effective_Start__c = coverage.Effective_Start__c;
            superbill.Coverage_Effective_End__c = coverage.Effective_End__c;
            if (coverage.Payer__c != null) {
                superbill.Payer_Name__c = coverage.Payer__r.Name;
                superbill.Payer_Identifier__c = coverage.Payer__r.Payer_Identifier__c;
                superbill.Claim_Filing_Code__c = claimFilingCode(
                    coverage.Payer__r.Claim_Filing_Code__c,
                    coverage.Payer__r.Type__c
                );
            }

            if (coverage.Relationship_to_Subscriber__c == 'Self' && patient != null) {
                copyPatientToSubscriber(superbill, patient);
            } else {
                superbill.Subscriber_First_Name__c = coverage.Subscriber_First_Name__c;
                superbill.Subscriber_Last_Name__c = coverage.Subscriber_Last_Name__c;
                applyLegacySubscriberName(superbill, coverage.Subscriber_Name__c);
                superbill.Subscriber_Date_of_Birth__c = coverage.Subscriber_Date_of_Birth__c;
                superbill.Subscriber_Sex__c = coverage.Subscriber_Sex__c;
                superbill.Subscriber_Street__c = coverage.Subscriber_Street__c;
                superbill.Subscriber_City__c = coverage.Subscriber_City__c;
                superbill.Subscriber_State__c = coverage.Subscriber_State__c;
                superbill.Subscriber_Postal_Code__c = coverage.Subscriber_Postal_Code__c;
                superbill.Subscriber_Country__c = coverage.Subscriber_Country__c;
            }
        }

        if (superbill.Rendering_Practitioner__c != null) {
            Practitioner__c practitioner = [
                SELECT First_Name__c, Last_Name__c, NPI__c, Taxonomy_Code__c
                FROM Practitioner__c
                WHERE Id = :superbill.Rendering_Practitioner__c
                LIMIT 1
            ];
            superbill.Rendering_Provider_Name__c = joinName(practitioner.First_Name__c, practitioner.Last_Name__c);
            superbill.Rendering_Provider_First_Name__c = practitioner.First_Name__c;
            superbill.Rendering_Provider_Last_Name__c = practitioner.Last_Name__c;
            superbill.Rendering_Provider_NPI__c = practitioner.NPI__c;
            superbill.Rendering_Provider_Taxonomy__c = practitioner.Taxonomy_Code__c;
        }

        if (superbill.Billing_Organization__c != null) {
            Organization__c organization = [
                SELECT Name, NPI__c, EIN__c, Taxonomy_Code__c, Street__c, City__c,
                       State__c, Postal_Code__c, Country__c
                FROM Organization__c
                WHERE Id = :superbill.Billing_Organization__c
                LIMIT 1
            ];
            superbill.Billing_Provider_Name__c = organization.Name;
            superbill.Billing_Provider_NPI__c = organization.NPI__c;
            superbill.Billing_Provider_EIN__c = organization.EIN__c;
            superbill.Billing_Provider_Taxonomy__c = organization.Taxonomy_Code__c;
            superbill.Billing_Provider_Street__c = organization.Street__c;
            superbill.Billing_Provider_City__c = organization.City__c;
            superbill.Billing_Provider_State__c = organization.State__c;
            superbill.Billing_Provider_Postal_Code__c = organization.Postal_Code__c;
            superbill.Billing_Provider_Country__c = organization.Country__c;
        }

        superbill.Snapshot_Refreshed_At__c = Datetime.now();
        superbill.Snapshot_Version__c = superbill.Snapshot_Version__c == null
            ? 1
            : superbill.Snapshot_Version__c + 1;
    }

    public static List<String> validate(Superbill__c superbill) {
        List<String> issues = new List<String>();
        if (superbill.Snapshot_Refreshed_At__c == null || superbill.Snapshot_Version__c == null) {
            issues.add('Patient, subscriber, and provider snapshots must be refreshed.');
            return issues;
        }
        if (superbill.Patient__c != null) {
            if (String.isBlank(superbill.Patient_First_Name__c)) issues.add('Patient first name snapshot is required.');
            if (String.isBlank(superbill.Patient_Last_Name__c)) issues.add('Patient last name snapshot is required.');
            if (superbill.Patient_Date_of_Birth__c == null) issues.add('Patient date of birth snapshot is required.');
            if (String.isBlank(superbill.Patient_Sex__c)) issues.add('Patient sex snapshot is required.');
            if (isAddressIncomplete(
                superbill.Patient_Street__c,
                superbill.Patient_City__c,
                superbill.Patient_State__c,
                superbill.Patient_Postal_Code__c
            )) {
                issues.add('Patient address snapshot is incomplete.');
            }
        }
        if (superbill.Coverage__c != null) {
            if (String.isBlank(superbill.Subscriber_Relationship__c)) {
                issues.add('Subscriber relationship snapshot is required.');
            }
            if (String.isBlank(superbill.Subscriber_Member_Id__c)) {
                issues.add('Subscriber member ID snapshot is required.');
            }
            if (String.isBlank(superbill.Subscriber_First_Name__c)) issues.add('Subscriber first name snapshot is required.');
            if (String.isBlank(superbill.Subscriber_Last_Name__c)) issues.add('Subscriber last name snapshot is required.');
            if (superbill.Subscriber_Date_of_Birth__c == null) issues.add('Subscriber date of birth snapshot is required.');
            if (String.isBlank(superbill.Subscriber_Sex__c)) issues.add('Subscriber sex snapshot is required.');
            if (isAddressIncomplete(
                superbill.Subscriber_Street__c,
                superbill.Subscriber_City__c,
                superbill.Subscriber_State__c,
                superbill.Subscriber_Postal_Code__c
            )) {
                issues.add('Subscriber address snapshot is incomplete.');
            }
            if (String.isBlank(superbill.Payer_Name__c)) issues.add('Payer name snapshot is required.');
            if (String.isBlank(superbill.Payer_Identifier__c)) issues.add('Payer identifier snapshot is required.');
            if (String.isBlank(superbill.Claim_Filing_Code__c) ||
                !Pattern.matches('^[A-Za-z0-9]{1,2}$', superbill.Claim_Filing_Code__c)) {
                issues.add('Payer claim filing code snapshot is required.');
            }
            if (superbill.Date_of_Service__c != null &&
                ((superbill.Coverage_Effective_Start__c != null && superbill.Coverage_Effective_Start__c > superbill.Date_of_Service__c) ||
                 (superbill.Coverage_Effective_End__c != null && superbill.Coverage_Effective_End__c < superbill.Date_of_Service__c))) {
                issues.add('Coverage snapshot is not effective on the date of service.');
            }
        }

        if (superbill.Rendering_Practitioner__c != null) {
            if (String.isBlank(superbill.Rendering_Provider_Name__c)) issues.add('Rendering provider name snapshot is required.');
            if (String.isBlank(superbill.Rendering_Provider_First_Name__c)) issues.add('Rendering provider first name snapshot is required.');
            if (String.isBlank(superbill.Rendering_Provider_Last_Name__c)) issues.add('Rendering provider last name snapshot is required.');
            if (!isTenCharacterIdentifier(superbill.Rendering_Provider_NPI__c)) {
                issues.add('Rendering provider snapshot requires a 10-digit NPI.');
            }
            if (!isTaxonomy(superbill.Rendering_Provider_Taxonomy__c)) {
                issues.add('Rendering provider snapshot requires a 10-character taxonomy code.');
            }
        }
        if (superbill.Billing_Organization__c != null) {
            if (String.isBlank(superbill.Billing_Provider_Name__c)) issues.add('Billing provider name snapshot is required.');
            if (!isTenCharacterIdentifier(superbill.Billing_Provider_NPI__c)) {
                issues.add('Billing provider snapshot requires a 10-digit NPI.');
            }
            if (String.isBlank(superbill.Billing_Provider_EIN__c) ||
                !Pattern.matches('^[0-9]{9}$', superbill.Billing_Provider_EIN__c.replaceAll('[^0-9]', ''))) {
                issues.add('Billing provider snapshot requires a 9-digit EIN.');
            }
            if (!isTaxonomy(superbill.Billing_Provider_Taxonomy__c)) {
                issues.add('Billing provider snapshot requires a 10-character taxonomy code.');
            }
            if (isAddressIncomplete(
                superbill.Billing_Provider_Street__c,
                superbill.Billing_Provider_City__c,
                superbill.Billing_Provider_State__c,
                superbill.Billing_Provider_Postal_Code__c
            )) {
                issues.add('Billing provider address snapshot is incomplete.');
            }
        }
        return issues;
    }

    public static void enforceFrozenSnapshots(List<Superbill__c> currentRows, Map<Id, Superbill__c> oldMap) {
        for (Superbill__c current : currentRows) {
            Superbill__c previous = oldMap.get(current.Id);
            if (previous == null || !FROZEN_STATUSES.contains(previous.Status__c)) continue;
            List<String> protectedFields = new List<String>();
            protectedFields.addAll(CLAIM_CONTEXT_FIELDS);
            protectedFields.addAll(SNAPSHOT_FIELDS);
            for (String fieldName : protectedFields) {
                if (current.get(fieldName) != previous.get(fieldName)) {
                    current.addError('Ready, exported, or voided claim snapshots are frozen. Reopen a Ready claim before refreshing snapshots.');
                    break;
                }
            }
        }
    }

    private static void clearSnapshot(Superbill__c superbill) {
        Decimal currentVersion = superbill.Snapshot_Version__c;
        for (String fieldName : SNAPSHOT_FIELDS) superbill.put(fieldName, null);
        superbill.Snapshot_Version__c = currentVersion;
    }

    private static void copyPatientToSubscriber(Superbill__c superbill, Patient__c patient) {
        superbill.Subscriber_First_Name__c = patient.First_Name__c;
        superbill.Subscriber_Last_Name__c = patient.Last_Name__c;
        superbill.Subscriber_Date_of_Birth__c = patient.Date_of_Birth__c;
        superbill.Subscriber_Sex__c = patient.Sex_at_Birth__c;
        superbill.Subscriber_Street__c = patient.Street__c;
        superbill.Subscriber_City__c = patient.City__c;
        superbill.Subscriber_State__c = patient.State__c;
        superbill.Subscriber_Postal_Code__c = patient.Postal_Code__c;
        superbill.Subscriber_Country__c = patient.Country__c;
    }

    private static void applyLegacySubscriberName(Superbill__c superbill, String legacyName) {
        if (!String.isBlank(superbill.Subscriber_First_Name__c) ||
            !String.isBlank(superbill.Subscriber_Last_Name__c) || String.isBlank(legacyName)) return;
        List<String> parts = legacyName.trim().split('\\s+');
        if (parts.size() == 1) {
            superbill.Subscriber_Last_Name__c = parts[0];
            return;
        }
        superbill.Subscriber_Last_Name__c = parts.remove(parts.size() - 1);
        superbill.Subscriber_First_Name__c = String.join(parts, ' ');
    }

    private static String joinName(String firstName, String lastName) {
        List<String> parts = new List<String>();
        if (!String.isBlank(firstName)) parts.add(firstName.trim());
        if (!String.isBlank(lastName)) parts.add(lastName.trim());
        return parts.isEmpty() ? null : String.join(parts, ' ');
    }

    private static String claimFilingCode(String configuredCode, String payerType) {
        if (String.isNotBlank(configuredCode)) return configuredCode.trim().toUpperCase();
        if (payerType == 'Commercial') return 'CI';
        if (payerType == 'Medicare') return 'MB';
        if (payerType == 'Medicaid') return 'MC';
        if (payerType == 'Other') return 'ZZ';
        return null;
    }

    private static Boolean isAddressIncomplete(String street, String city, String state, String postalCode) {
        return String.isBlank(street) || String.isBlank(city) || String.isBlank(state) || String.isBlank(postalCode);
    }

    private static Boolean isTenCharacterIdentifier(String value) {
        return !String.isBlank(value) && Pattern.matches('^[0-9]{10}$', value);
    }

    private static Boolean isTaxonomy(String value) {
        return !String.isBlank(value) && Pattern.matches('^[A-Za-z0-9]{10}$', value);
    }
}
