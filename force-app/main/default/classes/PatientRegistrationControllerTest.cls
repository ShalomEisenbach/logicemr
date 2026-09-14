@IsTest
private class PatientRegistrationControllerTest {
    @IsTest
    static void registerPatientPersistsDemographicsAddressAndDefaultsStatus() {
        PatientRegistrationController.PatientDemographics input = newDemographics(
            'MRN-REG-1',
            ' Ada ',
            ' Lovelace ',
            Date.newInstance(1985, 12, 10),
            'Female',
            '555-0100',
            'ada@example.test',
            true,
            ''
        );
        input.street = ' 123 Main St ';
        input.city = ' Boston ';
        input.state = ' MA ';
        input.postalCode = ' 02108 ';
        input.country = '';

        Test.startTest();
        PatientRegistrationController.RegistrationResult result =
            PatientRegistrationController.registerPatient(input);
        Test.stopTest();

        System.assertNotEquals(null, result.patient, 'A patient should be created');
        System.assertEquals(0, result.duplicates.size(), 'A new person should have no duplicates');
        Patient__c stored = [
            SELECT
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
            WHERE Id = :result.patient.Id
        ];
        System.assertEquals('MRN-REG-1', stored.MRN__c, 'MRN should persist');
        System.assertEquals('Ada', stored.First_Name__c, 'First name should be trimmed');
        System.assertEquals('Lovelace', stored.Last_Name__c, 'Last name should be trimmed');
        System.assertEquals(Date.newInstance(1985, 12, 10), stored.Date_of_Birth__c, 'DOB should persist');
        System.assertEquals('Female', stored.Sex_at_Birth__c, 'Sex at birth should persist');
        System.assertEquals('555-0100', stored.Phone__c, 'Phone should persist');
        System.assertEquals('ada@example.test', stored.Email__c, 'Email should persist');
        System.assertEquals(true, stored.SMS_Opt_In__c, 'SMS opt-in should persist');
        System.assertEquals('Active', stored.Status__c, 'Blank status should default to Active');
        System.assertEquals('123 Main St', stored.Street__c, 'Street should be trimmed');
        System.assertEquals('Boston', stored.City__c, 'City should be trimmed');
        System.assertEquals('MA', stored.State__c, 'State should be trimmed');
        System.assertEquals('02108', stored.Postal_Code__c, 'Postal code should be trimmed');
        System.assertEquals('US', stored.Country__c, 'Blank country should default to US');
    }

    @IsTest
    static void registerPatientReturnsPotentialDuplicatesWithoutInsert() {
        Patient__c existing = new Patient__c(
            MRN__c = 'MRN-REG-2',
            First_Name__c = 'Grace',
            Last_Name__c = 'Hopper',
            Date_of_Birth__c = Date.newInstance(1906, 12, 9)
        );
        insert existing;

        Test.startTest();
        PatientRegistrationController.RegistrationResult result =
            PatientRegistrationController.registerPatient(
                newDemographics(
                    'MRN-REG-3',
                    'Grace',
                    'Hopper',
                    Date.newInstance(1906, 12, 9),
                    'Female',
                    null,
                    null,
                    false,
                    'Active'
                )
            );
        Test.stopTest();

        System.assertEquals(null, result.patient, 'Duplicate match should block insert');
        System.assertEquals(1, result.duplicates.size(), 'Existing match should be returned');
        System.assertEquals(existing.Id, result.duplicates[0].Id, 'Returned duplicate should be the existing patient');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Patient__c WHERE Last_Name__c = 'Hopper'],
            'Duplicate attempt must not insert'
        );
    }

    @IsTest
    static void registerPatientValidatesRequiredInputs() {
        Boolean missingInput = false;
        Boolean missingMrn = false;
        Boolean missingLastName = false;

        Test.startTest();
        try {
            PatientRegistrationController.registerPatient(null);
        } catch (AuraHandledException e) {
            missingInput = true;
        }
        try {
            PatientRegistrationController.registerPatient(
                newDemographics(null, 'Test', 'Patient', null, null, null, null, false, null)
            );
        } catch (AuraHandledException e) {
            missingMrn = true;
        }
        try {
            PatientRegistrationController.registerPatient(
                newDemographics('MRN-REG-4', 'Test', ' ', null, null, null, null, false, null)
            );
        } catch (AuraHandledException e) {
            missingLastName = true;
        }
        Test.stopTest();

        System.assertEquals(true, missingInput, 'Null input should be rejected');
        System.assertEquals(true, missingMrn, 'Missing MRN should be rejected');
        System.assertEquals(true, missingLastName, 'Missing last name should be rejected');
        System.assertEquals(0, [SELECT COUNT() FROM Patient__c], 'Invalid requests must not insert');
    }

    @IsTest
    static void getPatientDemographicsReturnsStoredFields() {
        Patient__c patient = new Patient__c(
            MRN__c = 'MRN-REG-GET',
            First_Name__c = 'Get',
            Last_Name__c = 'Demo',
            Date_of_Birth__c = Date.newInstance(1991, 4, 5),
            Sex_at_Birth__c = 'Male',
            Phone__c = '555-0300',
            Email__c = 'get@example.test',
            SMS_Opt_In__c = true,
            Status__c = 'Active',
            Street__c = '9 Beacon St',
            City__c = 'Boston',
            State__c = 'MA',
            Postal_Code__c = '02108',
            Country__c = 'US'
        );
        insert patient;

        Test.startTest();
        Patient__c loaded = PatientRegistrationController.getPatientDemographics(patient.Id);
        Test.stopTest();

        System.assertEquals(patient.Id, loaded.Id, 'Loaded patient should match');
        System.assertEquals('MRN-REG-GET', loaded.MRN__c, 'MRN should load');
        System.assertEquals('Get', loaded.First_Name__c, 'First name should load');
        System.assertEquals('Demo', loaded.Last_Name__c, 'Last name should load');
        System.assertEquals(Date.newInstance(1991, 4, 5), loaded.Date_of_Birth__c, 'DOB should load');
        System.assertEquals('Male', loaded.Sex_at_Birth__c, 'Sex at birth should load');
        System.assertEquals('555-0300', loaded.Phone__c, 'Phone should load');
        System.assertEquals('get@example.test', loaded.Email__c, 'Email should load');
        System.assertEquals(true, loaded.SMS_Opt_In__c, 'SMS opt-in should load');
        System.assertEquals('Active', loaded.Status__c, 'Status should load');
        System.assertEquals('9 Beacon St', loaded.Street__c, 'Street should load');
        System.assertEquals('Boston', loaded.City__c, 'City should load');
        System.assertEquals('MA', loaded.State__c, 'State should load');
        System.assertEquals('02108', loaded.Postal_Code__c, 'Postal code should load');
        System.assertEquals('US', loaded.Country__c, 'Country should load');
    }

    @IsTest
    static void updatePatientDemographicsUpdatesAllowedFields() {
        Patient__c patient = new Patient__c(
            MRN__c = 'MRN-REG-5',
            First_Name__c = 'Old',
            Last_Name__c = 'Name',
            Status__c = 'Active'
        );
        insert patient;

        PatientRegistrationController.PatientDemographics input = newDemographics(
            null,
            'New',
            'Person',
            Date.newInstance(2000, 1, 2),
            'Unknown',
            '555-0200',
            'new@example.test',
            true,
            'Inactive'
        );
        input.patientId = patient.Id;
        input.street = '50 Federal St';
        input.city = 'Boston';
        input.state = 'MA';
        input.postalCode = '02110';
        input.country = 'US';

        Test.startTest();
        PatientRegistrationController.updatePatientDemographics(input);
        Test.stopTest();

        Patient__c stored = [
            SELECT
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
            WHERE Id = :patient.Id
        ];
        System.assertEquals('MRN-REG-5', stored.MRN__c, 'Update should not change MRN');
        System.assertEquals('New', stored.First_Name__c, 'First name should update');
        System.assertEquals('Person', stored.Last_Name__c, 'Last name should update');
        System.assertEquals(Date.newInstance(2000, 1, 2), stored.Date_of_Birth__c, 'DOB should update');
        System.assertEquals('Unknown', stored.Sex_at_Birth__c, 'Sex at birth should update');
        System.assertEquals('555-0200', stored.Phone__c, 'Phone should update');
        System.assertEquals('new@example.test', stored.Email__c, 'Email should update');
        System.assertEquals(true, stored.SMS_Opt_In__c, 'SMS opt-in should update');
        System.assertEquals('Inactive', stored.Status__c, 'Status should update');
        System.assertEquals('50 Federal St', stored.Street__c, 'Street should update');
        System.assertEquals('Boston', stored.City__c, 'City should update');
        System.assertEquals('MA', stored.State__c, 'State should update');
        System.assertEquals('02110', stored.Postal_Code__c, 'Postal code should update');
        System.assertEquals('US', stored.Country__c, 'Country should update');
    }

    @IsTest
    static void updatePatientDemographicsValidatesInputs() {
        Boolean missingPatient = false;
        Boolean missingLastName = false;
        Patient__c patient = new Patient__c(MRN__c = 'MRN-REG-6', Last_Name__c = 'Valid');
        insert patient;

        PatientRegistrationController.PatientDemographics noId = newDemographics(
            null, null, 'Patient', null, null, null, null, false, null
        );
        PatientRegistrationController.PatientDemographics noLast = newDemographics(
            null, null, '', null, null, null, null, false, null
        );
        noLast.patientId = patient.Id;

        Test.startTest();
        try {
            PatientRegistrationController.updatePatientDemographics(noId);
        } catch (AuraHandledException e) {
            missingPatient = true;
        }
        try {
            PatientRegistrationController.updatePatientDemographics(noLast);
        } catch (AuraHandledException e) {
            missingLastName = true;
        }
        Test.stopTest();

        System.assertEquals(true, missingPatient, 'Missing patient Id should be rejected');
        System.assertEquals(true, missingLastName, 'Missing last name should be rejected');
    }

    private static PatientRegistrationController.PatientDemographics newDemographics(
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
        PatientRegistrationController.PatientDemographics input =
            new PatientRegistrationController.PatientDemographics();
        input.mrn = mrn;
        input.firstName = firstName;
        input.lastName = lastName;
        input.dateOfBirth = dateOfBirth;
        input.sexAtBirth = sexAtBirth;
        input.phone = phone;
        input.email = email;
        input.smsOptIn = smsOptIn;
        input.status = status;
        return input;
    }
}
