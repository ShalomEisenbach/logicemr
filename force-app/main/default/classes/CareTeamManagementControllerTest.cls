@IsTest
private class CareTeamManagementControllerTest {
    private static final String MEMBER_ALIAS = 'ctmmgr1';

    @TestSetup
    static void setup() {
        User admin = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(admin) {
            insert newUser(MEMBER_ALIAS);
        }
    }

    @IsTest
    static void addMemberCreatesMemberAndPatientShare() {
        User memberUser = getUser(MEMBER_ALIAS);
        Practitioner__c practitioner = insertPractitioner(memberUser.Id, 'Alex', 'Kim');
        Patient__c patient = insertPatient('MRN-CTM-ADD');

        Test.startTest();
        CareTeamManagementController.CareTeamView team = CareTeamManagementController.getOrCreateCareTeam(
            patient.Id
        );
        CareTeamMember__c member = CareTeamManagementController.addMember(
            team.careTeamId,
            practitioner.Id,
            'Attending',
            'Read'
        );
        Test.stopTest();

        System.assertNotEquals(null, member.Id, 'addMember should insert a CareTeamMember__c');
        List<CareTeamMember__c> members = [
            SELECT Id, Care_Team__c, Practitioner__c, Role__c, Access_Level__c, Active__c
            FROM CareTeamMember__c
            WHERE Id = :member.Id
        ];
        System.assertEquals(1, members.size(), 'The inserted member should be queryable');
        System.assertEquals(team.careTeamId, members[0].Care_Team__c, 'Member should belong to the patient care team');
        System.assertEquals(practitioner.Id, members[0].Practitioner__c, 'Practitioner should be stored');
        System.assertEquals('Attending', members[0].Role__c, 'Role should be stored');
        System.assertEquals('Read', members[0].Access_Level__c, 'Access level should be stored');
        System.assertEquals(true, members[0].Active__c, 'New member should be active');

        List<Patient__Share> shares = queryCareTeamShares(patient.Id);
        System.assertEquals(1, shares.size(), 'Adding a member should create a Patient__Share');
        System.assertEquals(memberUser.Id, shares[0].UserOrGroupId, 'Share should target the Practitioner user');
        System.assertEquals('Read', shares[0].AccessLevel, 'Share access should match the member');
        System.assertEquals(
            Schema.Patient__Share.RowCause.Care_Team_Access__c,
            shares[0].RowCause,
            'Share must use the Care_Team_Access__c row cause'
        );
    }

    @IsTest
    static void getOrCreateCreatesOnceAndReturnsMembers() {
        Patient__c patient = insertPatient('MRN-CTM-GET');
        Practitioner__c practitioner = insertPractitioner(null, 'Sam', 'Ortiz');

        Test.startTest();
        CareTeamManagementController.CareTeamView created = CareTeamManagementController.getOrCreateCareTeam(
            patient.Id
        );
        CareTeamManagementController.addMember(created.careTeamId, practitioner.Id, 'Nurse', 'Edit');
        CareTeamManagementController.CareTeamView loaded = CareTeamManagementController.getOrCreateCareTeam(
            patient.Id
        );
        Test.stopTest();

        List<CareTeam__c> teams = [SELECT Id FROM CareTeam__c WHERE Patient__c = :patient.Id];
        System.assertEquals(1, teams.size(), 'getOrCreate should insert only one CareTeam__c');
        System.assertEquals(created.careTeamId, loaded.careTeamId, 'A second call should reuse the existing team');
        System.assertEquals('Active', loaded.status, 'Auto-created team should be Active');
        System.assertEquals(1, loaded.members.size(), 'Loaded view should include members');
        System.assertEquals('Sam Ortiz', loaded.members[0].practitionerName, 'Practitioner name should be First + Last');
        System.assertEquals('Nurse', loaded.members[0].role, 'Role should be returned on the member view');
        System.assertEquals('Edit', loaded.members[0].accessLevel, 'Access level should be returned on the member view');
        System.assertEquals(true, loaded.members[0].active, 'Active should be returned on the member view');
    }

    @IsTest
    static void deactivateAndRemoveRevokePatientShare() {
        User memberUser = getUser(MEMBER_ALIAS);
        Practitioner__c practitioner = insertPractitioner(memberUser.Id, 'Jordan', 'Lee');
        Patient__c patient = insertPatient('MRN-CTM-REV');
        CareTeamManagementController.CareTeamView team = CareTeamManagementController.getOrCreateCareTeam(
            patient.Id
        );
        CareTeamMember__c member = CareTeamManagementController.addMember(
            team.careTeamId,
            practitioner.Id,
            'Consulting',
            'Edit'
        );
        System.assertEquals(1, queryCareTeamShares(patient.Id).size(), 'Precondition: share exists after add');

        Test.startTest();
        CareTeamManagementController.deactivateMembers(new List<Id>{ member.Id });
        List<Patient__Share> afterDeactivate = queryCareTeamShares(patient.Id);
        CareTeamManagementController.removeMembers(new List<Id>{ member.Id });
        Test.stopTest();

        CareTeamMember__c deactivated = [
            SELECT Id, Active__c
            FROM CareTeamMember__c
            WHERE Id = :member.Id
            ALL ROWS
        ];
        System.assertEquals(false, deactivated.Active__c, 'Deactivate should set Active__c to false');
        System.assertEquals(0, afterDeactivate.size(), 'Deactivate should revoke the Patient__Share');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM CareTeamMember__c WHERE Id = :member.Id],
            'Remove should delete the member'
        );
        System.assertEquals(0, queryCareTeamShares(patient.Id).size(), 'Remove should leave no Care Team Access share');
    }

    @IsTest
    static void blankInputsAreNoOpsOrErrors() {
        Boolean getThrew = false;
        Boolean addThrew = false;

        Test.startTest();
        try {
            CareTeamManagementController.getOrCreateCareTeam(null);
        } catch (AuraHandledException e) {
            getThrew = true;
        }
        try {
            CareTeamManagementController.addMember(null, null, null, null);
        } catch (AuraHandledException e) {
            addThrew = true;
        }
        CareTeamManagementController.deactivateMembers(null);
        CareTeamManagementController.deactivateMembers(new List<Id>());
        CareTeamManagementController.removeMembers(null);
        CareTeamManagementController.removeMembers(new List<Id>());
        Test.stopTest();

        System.assertEquals(true, getThrew, 'Null patient Id should throw');
        System.assertEquals(true, addThrew, 'Null care team and practitioner should throw');
    }

    private static User newUser(String alias) {
        return new User(
            Alias = alias,
            Email = alias + '@logicemr.test',
            EmailEncodingKey = 'UTF-8',
            LastName = alias,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/New_York',
            ProfileId = getLowPrivilegeProfileId(),
            Username = alias + '.' + String.valueOf(Crypto.getRandomInteger()) + '@logicemr.test'
        );
    }

    private static Id getLowPrivilegeProfileId() {
        List<Profile> profiles = [
            SELECT Id
            FROM Profile
            WHERE Name IN ('Minimum Access - Salesforce', 'Standard User')
            ORDER BY Name
            LIMIT 1
        ];
        System.assertEquals(false, profiles.isEmpty(), 'A standard low-privilege profile must exist');
        return profiles[0].Id;
    }

    private static User getUser(String alias) {
        return [
            SELECT Id
            FROM User
            WHERE Alias = :alias
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }

    private static Patient__c insertPatient(String mrn) {
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'CareTeam');
        insert patient;
        return patient;
    }

    private static Practitioner__c insertPractitioner(Id userId, String firstName, String lastName) {
        Practitioner__c practitioner = new Practitioner__c(
            First_Name__c = firstName,
            Last_Name__c = lastName,
            User__c = userId
        );
        insert practitioner;
        return practitioner;
    }

    private static List<Patient__Share> queryCareTeamShares(Id patientId) {
        return [
            SELECT Id, ParentId, UserOrGroupId, AccessLevel, RowCause
            FROM Patient__Share
            WHERE
                ParentId = :patientId
                AND RowCause = :Schema.Patient__Share.RowCause.Care_Team_Access__c
        ];
    }
}
