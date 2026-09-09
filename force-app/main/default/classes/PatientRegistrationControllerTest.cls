@IsTest
private class PatientRegistrationControllerTest {
    @IsTest
    static void registerPatientPersistsDemographicsAndDefaultsStatus() {
        Test.startTest();
        PatientRegistrationController.RegistrationResult result =
            PatientRegistrationController.registerPatient(
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
                Status__c
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
                'MRN-REG-3',
                'Grace',
                'Hopper',
                Date.newInstance(1906, 12, 9),
                'Female',
                null,
                null,
                false,
                'Active'
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
        Boolean missingMrn = false;
        Boolean missingLastName = false;

        Test.startTest();
        try {
            PatientRegistrationController.registerPatient(
                null, 'Test', 'Patient', null, null, null, null, false, null
            );
        } catch (AuraHandledException e) {
            missingMrn = true;
        }
        try {
            PatientRegistrationController.registerPatient(
                'MRN-REG-4', 'Test', ' ', null, null, null, null, false, null
            );
        } catch (AuraHandledException e) {
            missingLastName = true;
        }
        Test.stopTest();

        System.assertEquals(true, missingMrn, 'Missing MRN should be rejected');
        System.assertEquals(true, missingLastName, 'Missing last name should be rejected');
        System.assertEquals(0, [SELECT COUNT() FROM Patient__c], 'Invalid requests must not insert');
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

        Test.startTest();
        PatientRegistrationController.updatePatientDemographics(
            patient.Id,
            'New',
            'Person',
            Date.newInstance(2000, 1, 2),
            'Unknown',
            '555-0200',
            'new@example.test',
            true,
            'Inactive'
        );
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
                Status__c
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
    }

    @IsTest
    static void updatePatientDemographicsValidatesInputs() {
        Boolean missingPatient = false;
        Boolean missingLastName = false;
        Patient__c patient = new Patient__c(MRN__c = 'MRN-REG-6', Last_Name__c = 'Valid');
        insert patient;

        Test.startTest();
        try {
            PatientRegistrationController.updatePatientDemographics(
                null, null, 'Patient', null, null, null, null, false, null
            );
        } catch (AuraHandledException e) {
            missingPatient = true;
        }
        try {
            PatientRegistrationController.updatePatientDemographics(
                patient.Id, null, '', null, null, null, null, false, null
            );
        } catch (AuraHandledException e) {
            missingLastName = true;
        }
        Test.stopTest();

        System.assertEquals(true, missingPatient, 'Missing patient Id should be rejected');
        System.assertEquals(true, missingLastName, 'Missing last name should be rejected');
    }
}
