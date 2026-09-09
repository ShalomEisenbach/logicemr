public with sharing class PatientRegistrationController {
    private static final String STATUS_ACTIVE = 'Active';
    private static final Integer DUPLICATE_LIMIT = 10;

    public class RegistrationResult {
        @AuraEnabled
        public Patient__c patient;
        @AuraEnabled
        public List<Patient__c> duplicates;

        public RegistrationResult() {
            duplicates = new List<Patient__c>();
        }
    }

    @AuraEnabled
    public static RegistrationResult registerPatient(
        String mrn,
        String firstName,
        String lastName,
        Date dateOfBirth,
        String sexAtBirth,
        String phone,
        String email,
        Boolean smsOptIn,
        String status
    ) {
        if (String.isBlank(mrn)) {
            throw new AuraHandledException('MRN is required.');
        }
        if (String.isBlank(lastName)) {
            throw new AuraHandledException('Last name is required.');
        }

        RegistrationResult result = new RegistrationResult();
        result.duplicates = findDuplicates(firstName, lastName, dateOfBirth);
        if (!result.duplicates.isEmpty()) {
            return result;
        }

        result.patient = new Patient__c(
            MRN__c = mrn.trim(),
            First_Name__c = trimToNull(firstName),
            Last_Name__c = lastName.trim(),
            Date_of_Birth__c = dateOfBirth,
            Sex_at_Birth__c = trimToNull(sexAtBirth),
            Phone__c = trimToNull(phone),
            Email__c = trimToNull(email),
            SMS_Opt_In__c = smsOptIn == true,
            Status__c = String.isBlank(status) ? STATUS_ACTIVE : status
        );
        insert result.patient;
        return result;
    }

    @AuraEnabled
    public static Patient__c updatePatientDemographics(
        Id patientId,
        String firstName,
        String lastName,
        Date dateOfBirth,
        String sexAtBirth,
        String phone,
        String email,
        Boolean smsOptIn,
        String status
    ) {
        if (patientId == null) {
            throw new AuraHandledException('Patient Id is required.');
        }
        if (String.isBlank(lastName)) {
            throw new AuraHandledException('Last name is required.');
        }

        Patient__c patient = [
            SELECT Id
            FROM Patient__c
            WHERE Id = :patientId
            LIMIT 1
        ];
        patient.First_Name__c = trimToNull(firstName);
        patient.Last_Name__c = lastName.trim();
        patient.Date_of_Birth__c = dateOfBirth;
        patient.Sex_at_Birth__c = trimToNull(sexAtBirth);
        patient.Phone__c = trimToNull(phone);
        patient.Email__c = trimToNull(email);
        patient.SMS_Opt_In__c = smsOptIn == true;
        patient.Status__c = String.isBlank(status) ? STATUS_ACTIVE : status;
        update patient;
        return patient;
    }

    private static List<Patient__c> findDuplicates(
        String firstName,
        String lastName,
        Date dateOfBirth
    ) {
        String normalizedFirst = trimToNull(firstName);
        String normalizedLast = lastName.trim();
        if (dateOfBirth == null) {
            return [
                SELECT Id, Name, MRN__c, First_Name__c, Last_Name__c, Date_of_Birth__c
                FROM Patient__c
                WHERE
                    Last_Name__c = :normalizedLast
                    AND First_Name__c = :normalizedFirst
                    AND Date_of_Birth__c = NULL
                ORDER BY Last_Name__c, First_Name__c
                LIMIT :DUPLICATE_LIMIT
            ];
        }
        return [
            SELECT Id, Name, MRN__c, First_Name__c, Last_Name__c, Date_of_Birth__c
            FROM Patient__c
            WHERE
                Last_Name__c = :normalizedLast
                AND First_Name__c = :normalizedFirst
                AND Date_of_Birth__c = :dateOfBirth
            ORDER BY Last_Name__c, First_Name__c
            LIMIT :DUPLICATE_LIMIT
        ];
    }

    private static String trimToNull(String value) {
        return String.isBlank(value) ? null : value.trim();
    }
}
