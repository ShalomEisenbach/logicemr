@IsTest
private class CareTeamMemberSharingHandlerTest {
    private static final Integer BULK_SIZE = 200;
    private static final String MEMBER_ALIAS = 'ctmembr';
    private static final String OUTSIDER_ALIAS = 'ctoutsid';
    private static final String ALT_ALIAS = 'ctaltusr';

    @TestSetup
    static void setup() {
        User admin = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(admin) {
            PermissionSet permSet = new PermissionSet(
                Name = 'LogicEMR_CareTeam_Test',
                Label = 'LogicEMR Care Team Test'
            );
            insert permSet;
            insert new ObjectPermissions(
                ParentId = permSet.Id,
                SobjectType = Patient__c.SObjectType.getDescribe().getName(),
                PermissionsRead = true,
                PermissionsEdit = true,
                PermissionsCreate = false,
                PermissionsDelete = false,
                PermissionsViewAllRecords = false,
                PermissionsModifyAllRecords = false
            );

            List<User> users = new List<User>{
                newUser(MEMBER_ALIAS),
                newUser(OUTSIDER_ALIAS),
                newUser(ALT_ALIAS)
            };
            insert users;

            List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
            for (User testUser : users) {
                assignments.add(
                    new PermissionSetAssignment(
                        AssigneeId = testUser.Id,
                        PermissionSetId = permSet.Id
                    )
                );
            }
            insert assignments;
        }
    }

    @IsTest
    static void shareCreatedOnInsertFromPractitionerUser() {
        User memberUser = getUser(MEMBER_ALIAS);
        Practitioner__c practitioner = insertPractitioner(memberUser.Id);
        Patient__c patient = insertPatient('MRN-INSERT');
        CareTeam__c careTeam = insertCareTeam(patient.Id);

        Test.startTest();
        CareTeamMember__c member = insertMember(careTeam.Id, practitioner.Id, null, 'Read', true);
        Test.stopTest();

        List<Patient__Share> shares = queryCareTeamShares(new Set<Id>{ patient.Id });
        System.assertEquals(1, shares.size(), 'Insert should create one Care Team Access share');
        System.assertEquals(memberUser.Id, shares[0].UserOrGroupId, 'Share should go to Practitioner.User');
        System.assertEquals('Read', shares[0].AccessLevel, 'Default access level should be Read');
        System.assertEquals(
            Schema.Patient__Share.RowCause.Care_Team_Access__c,
            shares[0].RowCause,
            'Share must use the Care_Team_Access__c row cause'
        );
        System.assertNotEquals(null, member.Id, 'Member should be inserted');
    }

    @IsTest
    static void shareUpdatedOnAccessLevelChange() {
        User memberUser = getUser(MEMBER_ALIAS);
        Practitioner__c practitioner = insertPractitioner(memberUser.Id);
        Patient__c patient = insertPatient('MRN-ACCESS');
        CareTeam__c careTeam = insertCareTeam(patient.Id);
        CareTeamMember__c member = insertMember(careTeam.Id, practitioner.Id, null, 'Read', true);

        Test.startTest();
        member.Access_Level__c = 'Edit';
        update member;
        Test.stopTest();

        List<Patient__Share> shares = queryCareTeamShares(new Set<Id>{ patient.Id });
        System.assertEquals(1, shares.size(), 'Access-level change should keep a single share');
        System.assertEquals('Edit', shares[0].AccessLevel, 'Share access should update to Edit');
    }

    @IsTest
    static void shareRemovedOnDeactivate() {
        User memberUser = getUser(MEMBER_ALIAS);
        Practitioner__c practitioner = insertPractitioner(memberUser.Id);
        Patient__c patient = insertPatient('MRN-DEACT');
        CareTeam__c careTeam = insertCareTeam(patient.Id);
        CareTeamMember__c member = insertMember(careTeam.Id, practitioner.Id, null, 'Read', true);

        Test.startTest();
        member.Active__c = false;
        update member;
        Test.stopTest();

        List<Patient__Share> shares = queryCareTeamShares(new Set<Id>{ patient.Id });
        System.assertEquals(0, shares.size(), 'Deactivating a member should remove its share');
    }

    @IsTest
    static void shareRemovedOnDeleteAndRestoredOnUndelete() {
        User memberUser = getUser(MEMBER_ALIAS);
        Practitioner__c practitioner = insertPractitioner(memberUser.Id);
        Patient__c patient = insertPatient('MRN-DEL');
        CareTeam__c careTeam = insertCareTeam(patient.Id);
        CareTeamMember__c member = insertMember(careTeam.Id, practitioner.Id, null, 'Read', true);

        Test.startTest();
        delete member;
        List<Patient__Share> afterDelete = queryCareTeamShares(new Set<Id>{ patient.Id });
        System.assertEquals(0, afterDelete.size(), 'Deleting a member should remove its share');

        undelete member;
        Test.stopTest();

        List<Patient__Share> afterUndelete = queryCareTeamShares(new Set<Id>{ patient.Id });
        System.assertEquals(1, afterUndelete.size(), 'Undelete should recreate the share');
        System.assertEquals(memberUser.Id, afterUndelete[0].UserOrGroupId, 'Restored share should target the same user');
    }

    @IsTest
    static void shareUsesMemberUserWhenSet() {
        User memberUser = getUser(MEMBER_ALIAS);
        User altUser = getUser(ALT_ALIAS);
        Practitioner__c practitioner = insertPractitioner(memberUser.Id);
        Patient__c patient = insertPatient('MRN-USER');
        CareTeam__c careTeam = insertCareTeam(patient.Id);

        Test.startTest();
        insertMember(careTeam.Id, practitioner.Id, altUser.Id, 'Read', true);
        Test.stopTest();

        List<Patient__Share> shares = queryCareTeamShares(new Set<Id>{ patient.Id });
        System.assertEquals(1, shares.size(), 'A resolvable User__c should create a share');
        System.assertEquals(altUser.Id, shares[0].UserOrGroupId, 'User__c should win over Practitioner.User__c');
    }

    @IsTest
    static void noShareWhenUserCannotBeResolved() {
        Practitioner__c practitioner = insertPractitioner(null);
        Patient__c patient = insertPatient('MRN-NOUSER');
        CareTeam__c careTeam = insertCareTeam(patient.Id);

        Test.startTest();
        insertMember(careTeam.Id, practitioner.Id, null, 'Read', true);
        Test.stopTest();

        List<Patient__Share> shares = queryCareTeamShares(new Set<Id>{ patient.Id });
        System.assertEquals(0, shares.size(), 'No share should be created without a resolvable User');
    }

    @IsTest
    static void runAsNonAdminCanSeeSharedPatientOnly() {
        User memberUser = getUser(MEMBER_ALIAS);
        User outsider = getUser(OUTSIDER_ALIAS);
        Practitioner__c practitioner = insertPractitioner(memberUser.Id);
        Patient__c patient = insertPatient('MRN-RUNAS');
        CareTeam__c careTeam = insertCareTeam(patient.Id);

        System.runAs(memberUser) {
            List<Patient__c> beforeShare = [SELECT Id FROM Patient__c WHERE Id = :patient.Id];
            System.assertEquals(0, beforeShare.size(), 'Non-admin should not see an unshared private patient');
        }

        insertMember(careTeam.Id, practitioner.Id, null, 'Read', true);

        System.runAs(memberUser) {
            List<Patient__c> afterShare = [SELECT Id FROM Patient__c WHERE Id = :patient.Id];
            System.assertEquals(1, afterShare.size(), 'Care team member should see the patient after share');
        }

        System.runAs(outsider) {
            List<Patient__c> outsiderView = [SELECT Id FROM Patient__c WHERE Id = :patient.Id];
            System.assertEquals(0, outsiderView.size(), 'A user without a care-team share should not see the patient');
        }
    }

    @IsTest
    static void bulkRecalculatesTwoHundredShares() {
        User memberUser = getUser(MEMBER_ALIAS);
        Practitioner__c practitioner = insertPractitioner(memberUser.Id);

        List<Patient__c> patients = new List<Patient__c>();
        for (Integer i = 0; i < BULK_SIZE; i++) {
            patients.add(new Patient__c(MRN__c = 'MRN-BULK-' + i, Last_Name__c = 'Bulk' + i));
        }
        insert patients;

        List<CareTeam__c> careTeams = new List<CareTeam__c>();
        for (Patient__c patient : patients) {
            careTeams.add(new CareTeam__c(Patient__c = patient.Id));
        }
        insert careTeams;

        List<CareTeamMember__c> members = new List<CareTeamMember__c>();
        for (CareTeam__c careTeam : careTeams) {
            members.add(
                new CareTeamMember__c(
                    Care_Team__c = careTeam.Id,
                    Practitioner__c = practitioner.Id,
                    Access_Level__c = 'Read',
                    Active__c = true
                )
            );
        }

        Test.startTest();
        insert members;
        Test.stopTest();

        Set<Id> patientIds = new Map<Id, Patient__c>(patients).keySet();
        List<Patient__Share> shares = queryCareTeamShares(patientIds);
        System.assertEquals(BULK_SIZE, shares.size(), 'Bulk insert should create one share per patient');

        for (CareTeamMember__c member : members) {
            member.Access_Level__c = 'Edit';
        }
        update members;
        shares = queryCareTeamShares(patientIds);
        System.assertEquals(BULK_SIZE, shares.size(), 'Bulk access-level update should keep one share per patient');
        for (Patient__Share shareRow : shares) {
            System.assertEquals('Edit', shareRow.AccessLevel, 'Bulk update should set Edit on every share');
        }

        for (CareTeamMember__c member : members) {
            member.Active__c = false;
        }
        update members;
        shares = queryCareTeamShares(patientIds);
        System.assertEquals(0, shares.size(), 'Bulk deactivate should remove every Care Team Access share');

        delete members;
        shares = queryCareTeamShares(patientIds);
        System.assertEquals(0, shares.size(), 'Bulk delete of inactive members should leave no shares');
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
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'Patient');
        insert patient;
        return patient;
    }

    private static Practitioner__c insertPractitioner(Id userId) {
        Practitioner__c practitioner = new Practitioner__c(
            First_Name__c = 'Pat',
            Last_Name__c = 'Practitioner',
            User__c = userId
        );
        insert practitioner;
        return practitioner;
    }

    private static CareTeam__c insertCareTeam(Id patientId) {
        CareTeam__c careTeam = new CareTeam__c(Patient__c = patientId, Status__c = 'Active');
        insert careTeam;
        return careTeam;
    }

    private static CareTeamMember__c insertMember(
        Id careTeamId,
        Id practitionerId,
        Id userId,
        String accessLevel,
        Boolean isActive
    ) {
        CareTeamMember__c member = new CareTeamMember__c(
            Care_Team__c = careTeamId,
            Practitioner__c = practitionerId,
            User__c = userId,
            Access_Level__c = accessLevel,
            Active__c = isActive
        );
        insert member;
        return member;
    }

    private static List<Patient__Share> queryCareTeamShares(Set<Id> patientIds) {
        return [
            SELECT Id, ParentId, UserOrGroupId, AccessLevel, RowCause
            FROM Patient__Share
            WHERE
                ParentId IN :patientIds
                AND RowCause = :Schema.Patient__Share.RowCause.Care_Team_Access__c
        ];
    }
}
