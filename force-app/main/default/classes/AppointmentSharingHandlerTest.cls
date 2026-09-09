@IsTest
private class AppointmentSharingHandlerTest {
    private static final String CLINICIAN_ALIAS = 'apcln1';
    private static final String ALT_ALIAS = 'apcln2';

    @TestSetup
    static void setupUsers() {
        User admin = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(admin) {
            PermissionSet permissionSet = new PermissionSet(
                Name = 'LogicEMR_Appointment_Share_Test',
                Label = 'LogicEMR Appointment Share Test'
            );
            insert permissionSet;
            insert new List<ObjectPermissions>{
                new ObjectPermissions(
                    ParentId = permissionSet.Id,
                    SobjectType = Appointment__c.SObjectType.getDescribe().getName(),
                    PermissionsRead = true,
                    PermissionsEdit = true
                ),
                new ObjectPermissions(
                    ParentId = permissionSet.Id,
                    SobjectType = Patient__c.SObjectType.getDescribe().getName(),
                    PermissionsRead = true,
                    PermissionsEdit = true
                ),
                new ObjectPermissions(
                    ParentId = permissionSet.Id,
                    SobjectType = Encounter__c.SObjectType.getDescribe().getName(),
                    PermissionsRead = true,
                    PermissionsCreate = true,
                    PermissionsEdit = true
                )
            };

            List<User> users = new List<User>{
                newUser(CLINICIAN_ALIAS),
                newUser(ALT_ALIAS)
            };
            insert users;
            insert new List<PermissionSetAssignment>{
                new PermissionSetAssignment(
                    AssigneeId = users[0].Id,
                    PermissionSetId = permissionSet.Id
                ),
                new PermissionSetAssignment(
                    AssigneeId = users[1].Id,
                    PermissionSetId = permissionSet.Id
                )
            };
        }
    }

    @IsTest
    static void shareFollowsAssignedPractitioner() {
        User clinician = getUser(CLINICIAN_ALIAS);
        User alternate = getUser(ALT_ALIAS);
        Practitioner__c first = insertPractitioner('First', clinician.Id);
        Practitioner__c second = insertPractitioner('Second', alternate.Id);
        Patient__c patient = insertPatient('MRN-APSHARE-1');

        Test.startTest();
        Appointment__c appointment = insertAppointment(patient.Id, first.Id);
        Test.stopTest();

        List<Appointment__Share> firstShares = queryShares(appointment.Id);
        System.assertEquals(1, firstShares.size(), 'Assigned practitioner should receive one share');
        System.assertEquals(clinician.Id, firstShares[0].UserOrGroupId, 'Share should target Practitioner.User');
        System.assertEquals('Edit', firstShares[0].AccessLevel, 'Practitioner needs Edit for appointment actions');

        appointment.Practitioner__c = second.Id;
        update appointment;

        List<Appointment__Share> secondShares = queryShares(appointment.Id);
        System.assertEquals(1, secondShares.size(), 'Practitioner change should retain one current share');
        System.assertEquals(alternate.Id, secondShares[0].UserOrGroupId, 'Stale practitioner share should be replaced');
    }

    @IsTest
    static void noShareCreatedWhenPractitionerHasNoUser() {
        Practitioner__c practitioner = insertPractitioner('Unlinked', null);
        Patient__c patient = insertPatient('MRN-APSHARE-2');

        Test.startTest();
        Appointment__c appointment = insertAppointment(patient.Id, practitioner.Id);
        Test.stopTest();

        System.assertEquals(0, queryShares(appointment.Id).size(), 'Unlinked practitioner should not create a share');
    }

    @IsTest
    static void assignedClinicianCanArriveSchedulerOwnedAppointment() {
        User clinician = getUser(CLINICIAN_ALIAS);
        Practitioner__c practitioner = insertPractitioner('Arriver', clinician.Id);
        Patient__c patient = insertPatient('MRN-APSHARE-3');
        CareTeam__c careTeam = new CareTeam__c(Patient__c = patient.Id, Status__c = 'Active');
        insert careTeam;
        insert new CareTeamMember__c(
            Care_Team__c = careTeam.Id,
            Practitioner__c = practitioner.Id,
            Access_Level__c = 'Edit',
            Active__c = true
        );
        Appointment__c appointment = insertAppointment(patient.Id, practitioner.Id);

        Test.startTest();
        System.runAs(clinician) {
            AppointmentCalendarController.ActionResult result =
                AppointmentCalendarController.arriveAppointment(appointment.Id);
            System.assertNotEquals(null, result.encounterId, 'Arrive should create an encounter');
        }
        Test.stopTest();

        Appointment__c stored = [
            SELECT Status__c, Encounter__c
            FROM Appointment__c
            WHERE Id = :appointment.Id
        ];
        System.assertEquals('Arrived', stored.Status__c, 'Clinician should update appointment status');
        System.assertNotEquals(null, stored.Encounter__c, 'Appointment should link to the created encounter');
    }

    @IsTest
    static void assignedClinicianCanCancelSchedulerOwnedAppointment() {
        User clinician = getUser(CLINICIAN_ALIAS);
        Practitioner__c practitioner = insertPractitioner('Canceller', clinician.Id);
        Patient__c patient = insertPatient('MRN-APSHARE-4');
        Appointment__c appointment = insertAppointment(patient.Id, practitioner.Id);

        Test.startTest();
        System.runAs(clinician) {
            AppointmentCalendarController.ActionResult result =
                AppointmentCalendarController.cancelAppointment(appointment.Id);
            System.assertEquals(
                'Cancelled',
                result.appointmentStatus,
                'Action result should report cancellation'
            );
        }
        Test.stopTest();

        Appointment__c stored = [
            SELECT Status__c
            FROM Appointment__c
            WHERE Id = :appointment.Id
        ];
        System.assertEquals('Cancelled', stored.Status__c, 'Clinician should be able to cancel the shared appointment');
    }

    private static Appointment__c insertAppointment(Id patientId, Id practitionerId) {
        Appointment__c appointment = new Appointment__c(
            Patient__c = patientId,
            Practitioner__c = practitionerId,
            Start__c = Datetime.newInstance(2026, 9, 10, 9, 0, 0),
            End__c = Datetime.newInstance(2026, 9, 10, 9, 30, 0),
            Appointment_Type__c = 'Routine',
            Status__c = 'Booked'
        );
        insert appointment;
        return appointment;
    }

    private static Patient__c insertPatient(String mrn) {
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'Share Test');
        insert patient;
        return patient;
    }

    private static Practitioner__c insertPractitioner(String lastName, Id userId) {
        Practitioner__c practitioner = new Practitioner__c(
            First_Name__c = 'Pat',
            Last_Name__c = lastName,
            User__c = userId,
            Active__c = true
        );
        insert practitioner;
        return practitioner;
    }

    private static List<Appointment__Share> queryShares(Id appointmentId) {
        return [
            SELECT Id, UserOrGroupId, AccessLevel, RowCause
            FROM Appointment__Share
            WHERE
                ParentId = :appointmentId
                AND RowCause = :Schema.Appointment__Share.RowCause.Practitioner_Access__c
        ];
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
            ProfileId = lowPrivilegeProfileId(),
            Username = alias + '.' + String.valueOf(Crypto.getRandomInteger()) + '@logicemr.test'
        );
    }

    private static Id lowPrivilegeProfileId() {
        return [
            SELECT Id
            FROM Profile
            WHERE Name IN ('Minimum Access - Salesforce', 'Standard User')
            ORDER BY Name
            LIMIT 1
        ].Id;
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
}
