@IsTest
private class DuplicatePatientControllerTest {
    @IsTest
    static void findDuplicatesReturnsMatchingPairAndOmitsUnique() {
        Date dob = Date.newInstance(1984, 3, 12);
        Patient__c first = insertPatient('Rivera', 'Ana', 'MRN-DUP-001', dob, 'Active');
        Patient__c second = insertPatient('Rivera', 'Ana', 'MRN-DUP-002', dob, 'Inactive');
        Patient__c uniquePatient = insertPatient('Chen', 'Li', 'MRN-DUP-UNIQ', Date.newInstance(1978, 1, 9), 'Active');

        Test.startTest();
        DuplicatePatientController.DuplicateFindResult result = DuplicatePatientController.findDuplicates();
        Test.stopTest();

        System.assertEquals(1, result.groups.size(), 'Identical name+DOB patients should form one group');
        System.assertEquals(false, result.truncated, 'A single group should not be truncated');
        System.assertEquals(50, result.groupLimit, 'Default group cap should be 50');

        DuplicatePatientController.DuplicateGroup duplicateGroup = result.groups[0];
        System.assertEquals('Rivera', duplicateGroup.lastName, 'Group last name should match the pair');
        System.assertEquals('Ana', duplicateGroup.firstName, 'Group first name should match the pair');
        System.assertEquals(dob, duplicateGroup.dateOfBirth, 'Group DOB should match the pair');
        System.assertEquals(2, duplicateGroup.memberCount, 'Group should contain both matching patients');
        System.assertEquals(2, duplicateGroup.members.size(), 'Members list should contain both matching patients');

        Set<Id> memberIds = new Set<Id>();
        for (Patient__c member : duplicateGroup.members) {
            memberIds.add(member.Id);
            System.assertNotEquals(null, member.Name, 'Member Name should be populated');
            System.assertNotEquals(null, member.MRN__c, 'Member MRN__c should be populated');
            System.assertEquals(dob, member.Date_of_Birth__c, 'Member Date_of_Birth__c should match the group');
            System.assertNotEquals(null, member.Status__c, 'Member Status__c should be populated');
            System.assertNotEquals(null, member.CreatedDate, 'Member CreatedDate should be populated');
        }
        System.assertEquals(true, memberIds.contains(first.Id), 'Group should include the first matching patient');
        System.assertEquals(true, memberIds.contains(second.Id), 'Group should include the second matching patient');
        System.assertEquals(false, memberIds.contains(uniquePatient.Id), 'Unique name+DOB patient should not be in the group');
    }

    @IsTest
    static void findDuplicatesReturnsEmptyWhenNoDuplicates() {
        insertPatient('Ortiz', 'Maya', 'MRN-DUP-NONE', Date.newInstance(1991, 7, 4), 'Active');

        Test.startTest();
        DuplicatePatientController.DuplicateFindResult result = DuplicatePatientController.findDuplicates();
        Test.stopTest();

        System.assertEquals(0, result.groups.size(), 'A unique patient should not produce a duplicate group');
        System.assertEquals(false, result.truncated, 'Empty results should not be truncated');
    }

    @IsTest
    static void findDuplicatesGroupsPatientsWithBlankDob() {
        Patient__c first = insertPatient('Hale', 'Nora', 'MRN-DUP-DOB-1', null, 'Active');
        Patient__c second = insertPatient('Hale', 'Nora', 'MRN-DUP-DOB-2', null, 'Active');

        Test.startTest();
        DuplicatePatientController.DuplicateFindResult result = DuplicatePatientController.findDuplicates();
        Test.stopTest();

        System.assertEquals(1, result.groups.size(), 'Patients that share name and a blank DOB should form a group');
        System.assertEquals(null, result.groups[0].dateOfBirth, 'Group DOB should be blank');
        Set<Id> memberIds = new Set<Id>{ result.groups[0].members[0].Id, result.groups[0].members[1].Id };
        System.assertEquals(true, memberIds.contains(first.Id), 'Blank-DOB group should include the first patient');
        System.assertEquals(true, memberIds.contains(second.Id), 'Blank-DOB group should include the second patient');
    }

    @IsTest
    static void findDuplicatesGroupsPatientsWithBlankNames() {
        Date dob = Date.newInstance(1960, 6, 15);
        Patient__c first = insertPatient(null, null, 'MRN-DUP-NAME-1', dob, 'Active');
        Patient__c second = insertPatient(null, null, 'MRN-DUP-NAME-2', dob, 'Inactive');

        Test.startTest();
        DuplicatePatientController.DuplicateFindResult result = DuplicatePatientController.findDuplicates();
        Test.stopTest();

        System.assertEquals(1, result.groups.size(), 'Patients that share a blank name and the same DOB should form a group');
        System.assertEquals(null, result.groups[0].lastName, 'Group last name should be blank');
        System.assertEquals(null, result.groups[0].firstName, 'Group first name should be blank');
        Set<Id> memberIds = new Set<Id>{ result.groups[0].members[0].Id, result.groups[0].members[1].Id };
        System.assertEquals(true, memberIds.contains(first.Id), 'Blank-name group should include the first patient');
        System.assertEquals(true, memberIds.contains(second.Id), 'Blank-name group should include the second patient');
    }

    @IsTest
    static void findDuplicatesCapsGroupsAndFlagsTruncation() {
        DuplicatePatientController.groupLimitOverride = 1;
        insertPatient('Hale', 'Nora', 'MRN-DUP-CAP-A1', Date.newInstance(1973, 2, 28), 'Active');
        insertPatient('Hale', 'Nora', 'MRN-DUP-CAP-A2', Date.newInstance(1973, 2, 28), 'Inactive');
        insertPatient('Baker', 'Pat', 'MRN-DUP-CAP-B1', Date.newInstance(1973, 2, 1), 'Active');
        insertPatient('Baker', 'Pat', 'MRN-DUP-CAP-B2', Date.newInstance(1973, 2, 1), 'Active');

        Test.startTest();
        DuplicatePatientController.DuplicateFindResult result = DuplicatePatientController.findDuplicates();
        Test.stopTest();

        System.assertEquals(1, result.groups.size(), 'Only the first N groups should be returned');
        System.assertEquals(true, result.truncated, 'Extra groups should set the showing-first-N indicator');
        System.assertEquals(1, result.groupLimit, 'Returned cap should match the override');
        System.assertEquals(2, result.groups[0].members.size(), 'The returned group should still include its members');
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
}
