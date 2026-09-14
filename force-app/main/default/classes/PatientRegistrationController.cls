public with sharing class PatientRegistrationController {
	private static final String STATUS_ACTIVE = 'Active';
	private static final Integer DUPLICATE_LIMIT = 10;

	public class PatientDemographics {
		@AuraEnabled
		public Id patientId { get; set; }
		@AuraEnabled
		public String mrn { get; set; }
		@AuraEnabled
		public String firstName { get; set; }
		@AuraEnabled
		public String lastName { get; set; }
		@AuraEnabled
		public Date dateOfBirth { get; set; }
		@AuraEnabled
		public String sexAtBirth { get; set; }
		@AuraEnabled
		public String phone { get; set; }
		@AuraEnabled
		public String email { get; set; }
		@AuraEnabled
		public Boolean smsOptIn { get; set; }
		@AuraEnabled
		public String status { get; set; }
		@AuraEnabled
		public String street { get; set; }
		@AuraEnabled
		public String city { get; set; }
		@AuraEnabled
		public String state { get; set; }
		@AuraEnabled
		public String postalCode { get; set; }
		@AuraEnabled
		public String country { get; set; }
	}

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
	public static RegistrationResult registerPatient(PatientDemographics input) {
		if (input == null) {
			throw new AuraHandledException('Patient details are required.');
		}
		if (String.isBlank(input.mrn)) {
			throw new AuraHandledException('MRN is required.');
		}
		if (String.isBlank(input.lastName)) {
			throw new AuraHandledException('Last name is required.');
		}

		RegistrationResult result = new RegistrationResult();
		result.duplicates = findDuplicates(input.firstName, input.lastName, input.dateOfBirth);

		if (!result.duplicates.isEmpty()) {
			return result;
		}

		Patient__c patient = new Patient__c(
			MRN__c = input.mrn.trim(),
			First_Name__c = trimToNull(input.firstName),
			Last_Name__c = input.lastName.trim(),
			Date_of_Birth__c = input.dateOfBirth,
			Sex_at_Birth__c = trimToNull(input.sexAtBirth),
			Phone__c = trimToNull(input.phone),
			Email__c = trimToNull(input.email),
			SMS_Opt_In__c = input.smsOptIn == true,
			Status__c = String.isBlank(input.status) ? STATUS_ACTIVE : input.status
		);
		applyAddress(patient, input);
		insert patient;
		result.patient = patient;
		return result;
	}

	@AuraEnabled(cacheable=true)
	public static Patient__c getPatientDemographics(Id patientId) {
		if (patientId == null) {
			throw new AuraHandledException('Patient Id is required.');
		}

		List<Patient__c> rows = [
			SELECT
				Id,
				MRN__c,
				First_Name__c,
				Last_Name__c,
				Date_of_Birth__c,
				Sex_at_Birth__c,
				Phone__c,
				Email__c,
				SMS_Opt_In__c,
				Status__c,
				Street__c,
				City__c,
				State__c,
				Postal_Code__c,
				Country__c
			FROM Patient__c
			WHERE Id = :patientId
			LIMIT 1
		];

		if (rows.isEmpty()) {
			throw new AuraHandledException('Patient was not found.');
		}

		return rows[0];
	}

	@AuraEnabled
	public static Patient__c updatePatientDemographics(PatientDemographics input) {
		if (input == null || input.patientId == null) {
			throw new AuraHandledException('Patient Id is required.');
		}
		if (String.isBlank(input.lastName)) {
			throw new AuraHandledException('Last name is required.');
		}

		Patient__c patient = [
			SELECT Id
			FROM Patient__c
			WHERE Id = :input.patientId
			LIMIT 1
		];
		patient.First_Name__c = trimToNull(input.firstName);
		patient.Last_Name__c = input.lastName.trim();
		patient.Date_of_Birth__c = input.dateOfBirth;
		patient.Sex_at_Birth__c = trimToNull(input.sexAtBirth);
		patient.Phone__c = trimToNull(input.phone);
		patient.Email__c = trimToNull(input.email);
		patient.SMS_Opt_In__c = input.smsOptIn == true;
		patient.Status__c = String.isBlank(input.status) ? STATUS_ACTIVE : input.status;
		applyAddress(patient, input);
		update patient;
		return patient;
	}

	private static void applyAddress(Patient__c patient, PatientDemographics input) {
		patient.Street__c = trimToNull(input.street);
		patient.City__c = trimToNull(input.city);
		patient.State__c = trimToNull(input.state);
		patient.Postal_Code__c = trimToNull(input.postalCode);
		patient.Country__c = String.isBlank(input.country) ? 'US' : input.country.trim();
	}

	private static List<Patient__c> findDuplicates(String firstName, String lastName, Date dateOfBirth) {
		String normalizedFirst = trimToNull(firstName);
		String normalizedLast = lastName.trim();

		if (dateOfBirth == null) {
			return [
				SELECT Id, Name, MRN__c, First_Name__c, Last_Name__c, Date_of_Birth__c
				FROM Patient__c
				WHERE Last_Name__c = :normalizedLast AND First_Name__c = :normalizedFirst AND Date_of_Birth__c = NULL
				ORDER BY Last_Name__c, First_Name__c
				LIMIT :DUPLICATE_LIMIT
			];
		}

		return [
			SELECT Id, Name, MRN__c, First_Name__c, Last_Name__c, Date_of_Birth__c
			FROM Patient__c
			WHERE Last_Name__c = :normalizedLast AND First_Name__c = :normalizedFirst AND Date_of_Birth__c = :dateOfBirth
			ORDER BY Last_Name__c, First_Name__c
			LIMIT :DUPLICATE_LIMIT
		];
	}

	private static String trimToNull(String value) {
		return String.isBlank(value) ? null : value.trim();
	}
}
