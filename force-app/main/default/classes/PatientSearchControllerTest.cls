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
    static void searchByDobPhoneAndExternalIds() {
        Date dob = Date.newInstance(1973, 2, 28);
        Patient__c patient = new Patient__c(
            Last_Name__c = 'Hale',
            First_Name__c = 'Nora',
            MRN__c = 'MRN-SRCH-DOB',
            Date_of_Birth__c = dob,
            Phone__c = '555-010-4477',
            Email__c = 'nora.hale@example.com',
            FHIR_Id__c = 'fhir-nora-hale',
            Source_System_Id__c = 'src-nora-hale',
            Status__c = 'Active'
        );
        insert patient;

        Test.startTest();
        List<Patient__c> byIso = PatientSearchController.search('1973-02-28');
        List<Patient__c> byUs = PatientSearchController.search('2/28/1973');
        List<Patient__c> byYear = PatientSearchController.search('1973');
        List<Patient__c> byPhone = PatientSearchController.search('555-010-4477');
        List<Patient__c> byDigits = PatientSearchController.search('5550104477');
        List<Patient__c> byEmail = PatientSearchController.search('nora.hale@example.com');
        List<Patient__c> byFhir = PatientSearchController.search('fhir-nora-hale');
        List<Patient__c> bySource = PatientSearchController.search('src-nora-hale');
        List<Patient__c> byFullName = PatientSearchController.search('Nora Hale');
        Test.stopTest();

        System.assertEquals(1, byIso.size(), 'ISO DOB search should return one match');
        System.assertEquals(patient.Id, byIso[0].Id, 'ISO DOB search should return the inserted patient');
        System.assertEquals('555-010-4477', byIso[0].Phone__c, 'Results should include Phone__c');
        System.assertEquals('nora.hale@example.com', byIso[0].Email__c, 'Results should include Email__c');
        System.assertEquals(1, byUs.size(), 'US DOB search should return one match');
        System.assertEquals(patient.Id, byUs[0].Id, 'US DOB search should return the inserted patient');
        System.assertEquals(1, byYear.size(), 'Birth year search should return one match');
        System.assertEquals(patient.Id, byYear[0].Id, 'Birth year search should return the inserted patient');
        System.assertEquals(1, byPhone.size(), 'Formatted phone search should return one match');
        System.assertEquals(patient.Id, byPhone[0].Id, 'Formatted phone search should return the inserted patient');
        System.assertEquals(1, byDigits.size(), 'Digit-only phone search should return one match');
        System.assertEquals(patient.Id, byDigits[0].Id, 'Digit-only phone search should return the inserted patient');
        System.assertEquals(1, byEmail.size(), 'Email search should return one match');
        System.assertEquals(patient.Id, byEmail[0].Id, 'Email search should return the inserted patient');
        System.assertEquals(1, byFhir.size(), 'FHIR Id search should return one match');
        System.assertEquals(patient.Id, byFhir[0].Id, 'FHIR Id search should return the inserted patient');
        System.assertEquals(1, bySource.size(), 'Source system Id search should return one match');
        System.assertEquals(patient.Id, bySource[0].Id, 'Source system Id search should return the inserted patient');
        System.assertEquals(1, byFullName.size(), 'First and last name search should return one match');
        System.assertEquals(patient.Id, byFullName[0].Id, 'First and last name search should return the inserted patient');
    }

    @IsTest
    static void searchByDobAcceptsAnyCommonFormat() {
        Date dob = Date.newInstance(1973, 2, 28);
        Patient__c patient = insertPatient('Hale', 'Nora', 'MRN-SRCH-FMT', dob, 'Active');

        List<String> terms = new List<String>{
            '1973-02-28',
            '1973/2/28',
            '1973.02.28',
            '02/28/1973',
            '2-28-1973',
            '28/02/1973',
            '28-02-1973',
            '28.02.1973',
            '19730228',
            '02281973',
            '28021973',
            '022873',
            '2/28/73',
            '28 Feb 1973',
            'February 28, 1973',
            'Feb. 28 1973',
            '28-Feb-1973',
            'Feb-28-1973',
            'February 28th, 1973',
            '  02 / 28 / 1973  '
        };

        Test.startTest();
        for (String term : terms) {
            List<Patient__c> results = PatientSearchController.search(term);
            System.assertEquals(1, results.size(), 'DOB search should match for "' + term + '"');
            System.assertEquals(patient.Id, results[0].Id, 'DOB search "' + term + '" should return the inserted patient');
        }
        List<Patient__c> byMonthYear = PatientSearchController.search('Feb 1973');
        List<Patient__c> byIsoMonth = PatientSearchController.search('1973-02');
        Test.stopTest();

        System.assertEquals(1, byMonthYear.size(), 'Month and year search should return one match');
        System.assertEquals(patient.Id, byMonthYear[0].Id, 'Month and year search should return the inserted patient');
        System.assertEquals(1, byIsoMonth.size(), 'ISO month search should return one match');
        System.assertEquals(patient.Id, byIsoMonth[0].Id, 'ISO month search should return the inserted patient');
    }

    @IsTest
    static void searchByAmbiguousDobTriesMonthFirstAndDayFirst() {
        Patient__c monthFirst = insertPatient('Able', 'Pat', 'MRN-SRCH-MDY', Date.newInstance(1973, 1, 2), 'Active');
        Patient__c dayFirst = insertPatient('Baker', 'Pat', 'MRN-SRCH-DMY', Date.newInstance(1973, 2, 1), 'Active');
        insertPatient('Chase', 'Pat', 'MRN-SRCH-INV', Date.newInstance(1973, 3, 3), 'Active');

        Test.startTest();
        List<Patient__c> ambiguous = PatientSearchController.search('1/2/1973');
        List<Patient__c> invalid = PatientSearchController.search('2/31/1973');
        Test.stopTest();

        System.assertEquals(2, ambiguous.size(), 'Ambiguous numeric DOB should match both MDY and DMY patients');
        Set<Id> ids = new Set<Id>{ ambiguous[0].Id, ambiguous[1].Id };
        System.assertEquals(true, ids.contains(monthFirst.Id), 'Ambiguous DOB should include January 2');
        System.assertEquals(true, ids.contains(dayFirst.Id), 'Ambiguous DOB should include February 1');
        System.assertEquals(0, invalid.size(), 'Invalid calendar dates should not roll over to another day');
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
