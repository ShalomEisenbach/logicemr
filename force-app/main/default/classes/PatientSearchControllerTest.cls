@IsTest
private class PatientSearchControllerTest {
    @IsTest
    static void searchByLastNameReturnsExpectedShape() {
        Date dob = Date.newInstance(1984, 3, 12);
        Patient__c patient = insertPatient('Rivera', 'Ana', 'MRN-SRCH-001', dob, 'Active');

        Test.startTest();
        List<Patient__c> results = PatientSearchController.search('Rivera');
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Last name search should return one match');
        assertResultShape(results[0], patient.Id, 'Rivera', 'Ana', 'MRN-SRCH-001', dob, 'Active');
    }

    @IsTest
    static void searchByFirstNameAndMrn() {
        Date dob = Date.newInstance(1991, 7, 4);
        Patient__c patient = insertPatient('Ortiz', 'Maya', 'MRN-SRCH-002', dob, 'Inactive');

        Test.startTest();
        List<Patient__c> byFirst = PatientSearchController.search('Maya');
        List<Patient__c> byMrn = PatientSearchController.search('MRN-SRCH-002');
        Test.stopTest();

        System.assertEquals(1, byFirst.size(), 'First name search should return one match');
        assertResultShape(byFirst[0], patient.Id, 'Ortiz', 'Maya', 'MRN-SRCH-002', dob, 'Inactive');
        System.assertEquals(1, byMrn.size(), 'MRN search should return one match');
        System.assertEquals(patient.Id, byMrn[0].Id, 'MRN search should return the same patient');
    }

    @IsTest
    static void searchReturnsMultipleMatchesInOneCall() {
        List<Patient__c> patients = new List<Patient__c>{
            new Patient__c(
                Last_Name__c = 'Chen',
                First_Name__c = 'Li',
                MRN__c = 'MRN-CHEN-1',
                Date_of_Birth__c = Date.newInstance(1978, 1, 9),
                Status__c = 'Active'
            ),
            new Patient__c(
                Last_Name__c = 'Chen',
                First_Name__c = 'Wei',
                MRN__c = 'MRN-CHEN-2',
                Date_of_Birth__c = Date.newInstance(1982, 11, 30),
                Status__c = 'Inactive'
            ),
            new Patient__c(
                Last_Name__c = 'Nguyen',
                First_Name__c = 'Kim',
                MRN__c = 'MRN-NGUY-1',
                Date_of_Birth__c = Date.newInstance(1990, 5, 21),
                Status__c = 'Active'
            )
        };
        insert patients;

        Test.startTest();
        List<Patient__c> results = PatientSearchController.search('Chen');
        Test.stopTest();

        System.assertEquals(2, results.size(), 'A single search call should return both matching patients');
        System.assertEquals('Chen', results[0].Last_Name__c, 'Results should include Last_Name__c');
        System.assertEquals('Chen', results[1].Last_Name__c, 'Results should include Last_Name__c');
        System.assertNotEquals(null, results[0].First_Name__c, 'Results should include First_Name__c');
        System.assertNotEquals(null, results[0].MRN__c, 'Results should include MRN__c');
        System.assertNotEquals(null, results[0].Date_of_Birth__c, 'Results should include Date_of_Birth__c');
        System.assertNotEquals(null, results[0].Status__c, 'Results should include Status__c');
    }

    @IsTest
    static void blankOrUnmatchedSearchReturnsEmpty() {
        insertPatient('Rivera', 'Ana', 'MRN-SRCH-003', Date.newInstance(1984, 3, 12), 'Active');

        Test.startTest();
        List<Patient__c> blank = PatientSearchController.search('   ');
        List<Patient__c> nullTerm = PatientSearchController.search(null);
        List<Patient__c> unmatched = PatientSearchController.search('NoSuchPatient');
        Test.stopTest();

        System.assertEquals(0, blank.size(), 'Whitespace-only search should return no rows');
        System.assertEquals(0, nullTerm.size(), 'Null search should return no rows');
        System.assertEquals(0, unmatched.size(), 'Unmatched search should return no rows');
    }

    private static Patient__c insertPatient(
        String lastName,
        String firstName,
        String mrn,
        Date dob,
        String status
    ) {
        Patient__c patient = new Patient__c(
            Last_Name__c = lastName,
            First_Name__c = firstName,
            MRN__c = mrn,
            Date_of_Birth__c = dob,
            Status__c = status
        );
        insert patient;
        return patient;
    }

    private static void assertResultShape(
        Patient__c row,
        Id expectedId,
        String lastName,
        String firstName,
        String mrn,
        Date dob,
        String status
    ) {
        System.assertEquals(expectedId, row.Id, 'Result Id should match the inserted patient');
        System.assertEquals(lastName, row.Last_Name__c, 'Last_Name__c should be populated');
        System.assertEquals(firstName, row.First_Name__c, 'First_Name__c should be populated');
        System.assertEquals(mrn, row.MRN__c, 'MRN__c should be populated');
        System.assertEquals(dob, row.Date_of_Birth__c, 'Date_of_Birth__c should be populated');
        System.assertEquals(status, row.Status__c, 'Status__c should be populated');
    }
}
