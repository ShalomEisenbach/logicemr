@IsTest
private class ProviderHomeControllerTest {
    private static final String PROVIDER_ALIAS = 'provhome';

    @TestSetup
    static void setup() {
        User admin = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(admin) {
            insert newUser(PROVIDER_ALIAS);
        }
    }

    @IsTest
    static void getHomeReturnsScopedMetricsAndListsThenMarkReviewedRemovesItem() {
        User provider = getUser(PROVIDER_ALIAS);
        Practitioner__c myPractitioner = insertPractitioner(provider.Id, 'Pat', 'Provider');
        Practitioner__c otherPractitioner = insertPractitioner(null, 'Other', 'Clinician');

        Patient__c myPatient = insertPatient('MRN-HOME-MINE', 'Mine');
        Patient__c otherPatient = insertPatient('MRN-HOME-OTH', 'Other');
        Patient__c inactiveMemberPatient = insertPatient('MRN-HOME-INACT', 'Inactive');

        assignCareTeam(myPatient.Id, myPractitioner.Id, provider.Id, true);
        assignCareTeam(inactiveMemberPatient.Id, myPractitioner.Id, provider.Id, false);

        Datetime now = Datetime.now();
        Encounter__c todayMine = new Encounter__c(
            Patient__c = myPatient.Id,
            Practitioner__c = myPractitioner.Id,
            Class__c = 'Outpatient',
            Status__c = 'In Progress',
            Start__c = now,
            Reason__c = 'Follow-up'
        );
        Encounter__c yesterdayMine = new Encounter__c(
            Patient__c = myPatient.Id,
            Practitioner__c = myPractitioner.Id,
            Class__c = 'Outpatient',
            Status__c = 'Arrived',
            Start__c = now.addDays(-1)
        );
        Encounter__c finishedMine = new Encounter__c(
            Patient__c = myPatient.Id,
            Practitioner__c = myPractitioner.Id,
            Class__c = 'Outpatient',
            Status__c = 'Finished',
            Start__c = now.addDays(-1)
        );
        Encounter__c todayOther = new Encounter__c(
            Patient__c = otherPatient.Id,
            Practitioner__c = otherPractitioner.Id,
            Class__c = 'Emergency',
            Status__c = 'In Progress',
            Start__c = now
        );
        insert new List<Encounter__c>{ todayMine, yesterdayMine, finishedMine, todayOther };

        DiagnosticReport__c unreviewedMine = new DiagnosticReport__c(
            Patient__c = myPatient.Id,
            Report_Display__c = 'CBC',
            Status__c = 'Final',
            Issued__c = now
        );
        DiagnosticReport__c registeredMine = new DiagnosticReport__c(
            Patient__c = myPatient.Id,
            Report_Display__c = 'CXR',
            Status__c = 'Registered',
            Issued__c = now
        );
        DiagnosticReport__c unreviewedOther = new DiagnosticReport__c(
            Patient__c = otherPatient.Id,
            Report_Display__c = 'CMP',
            Status__c = 'Preliminary',
            Issued__c = now
        );
        insert new List<DiagnosticReport__c>{ unreviewedMine, registeredMine, unreviewedOther };

        ClinicalNote__c draftMine = new ClinicalNote__c(
            Patient__c = myPatient.Id,
            Author__c = myPractitioner.Id,
            Note_Type__c = 'Progress Note',
            Status__c = 'Draft',
            Body__c = 'Needs signature'
        );
        ClinicalNote__c signedMine = new ClinicalNote__c(
            Patient__c = myPatient.Id,
            Author__c = myPractitioner.Id,
            Note_Type__c = 'Progress Note',
            Status__c = 'Signed',
            Body__c = 'Signed note'
        );
        ClinicalNote__c draftOtherAuthor = new ClinicalNote__c(
            Patient__c = myPatient.Id,
            Author__c = otherPractitioner.Id,
            Note_Type__c = 'Consult',
            Status__c = 'Draft',
            Body__c = 'Other author'
        );
        insert new List<ClinicalNote__c>{ draftMine, signedMine, draftOtherAuthor };

        Datetime todayMorning = Datetime.newInstance(Date.today(), Time.newInstance(9, 0, 0, 0));
        Datetime todayAfternoon = todayMorning.addHours(3);
        Appointment__c bookedMine = new Appointment__c(
            Patient__c = myPatient.Id,
            Practitioner__c = myPractitioner.Id,
            Start__c = todayMorning,
            End__c = todayMorning.addMinutes(20),
            Status__c = 'Booked',
            Appointment_Type__c = 'Checkup',
            OwnerId = provider.Id
        );
        Appointment__c arrivedMine = new Appointment__c(
            Patient__c = myPatient.Id,
            Practitioner__c = myPractitioner.Id,
            Start__c = todayAfternoon,
            End__c = todayAfternoon.addMinutes(20),
            Status__c = 'Arrived',
            Appointment_Type__c = 'Follow-up',
            OwnerId = provider.Id
        );
        Appointment__c cancelledMine = new Appointment__c(
            Patient__c = myPatient.Id,
            Practitioner__c = myPractitioner.Id,
            Start__c = todayMorning.addHours(1),
            End__c = todayMorning.addHours(1).addMinutes(20),
            Status__c = 'Cancelled',
            Appointment_Type__c = 'Routine',
            OwnerId = provider.Id
        );
        Appointment__c yesterdayAppointmentMine = new Appointment__c(
            Patient__c = myPatient.Id,
            Practitioner__c = myPractitioner.Id,
            Start__c = todayMorning.addDays(-1),
            End__c = todayMorning.addDays(-1).addMinutes(20),
            Status__c = 'Booked',
            Appointment_Type__c = 'Checkup',
            OwnerId = provider.Id
        );
        Appointment__c bookedOtherPractitioner = new Appointment__c(
            Patient__c = otherPatient.Id,
            Practitioner__c = otherPractitioner.Id,
            Start__c = todayMorning,
            End__c = todayMorning.addMinutes(20),
            Status__c = 'Booked',
            Appointment_Type__c = 'Walk-in',
            OwnerId = provider.Id
        );
        insert new List<Appointment__c>{
            bookedMine,
            arrivedMine,
            cancelledMine,
            yesterdayAppointmentMine,
            bookedOtherPractitioner
        };

        ProviderHomeController.HomePayload payload;
        Test.startTest();
        System.runAs(provider) {
            payload = ProviderHomeController.getHome();
        }
        Test.stopTest();

        System.assertEquals(1, payload.metrics.myActivePatients, 'Only the active care-team patient should count');
        System.assertEquals(
            2,
            payload.metrics.openEncounters,
            'Open encounters should include today and yesterday In Progress/Arrived for my patient, not Finished or other patients'
        );
        System.assertEquals(1, payload.metrics.resultsToReview, 'Only my unreviewed Preliminary/Final report should count');
        System.assertEquals(1, payload.metrics.unsignedNotes, 'Only draft notes authored by my Practitioner should count');
        System.assertEquals(
            2,
            payload.metrics.todaysAppointments,
            'Today appointments metric should count Booked and Arrived for my Practitioner only'
        );

        System.assertEquals(2, payload.lists.todaysAppointments.size(), 'Today appointments should include Booked and Arrived for my Practitioner');
        System.assertEquals(bookedMine.Id, payload.lists.todaysAppointments[0].Id, 'Earlier Booked appointment should be first');
        System.assertEquals(arrivedMine.Id, payload.lists.todaysAppointments[1].Id, 'Later Arrived appointment should be second');
        System.assertEquals('Booked', payload.lists.todaysAppointments[0].Status__c, 'First appointment should still be Booked');
        System.assertEquals(myPractitioner.Id, payload.lists.todaysAppointments[0].Practitioner__c, 'Listed appointments must belong to the current user Practitioner');
        System.assertEquals(myPractitioner.Id, payload.lists.todaysAppointments[1].Practitioner__c, 'Arrived appointment must belong to the current user Practitioner');
        for (Appointment__c row : payload.lists.todaysAppointments) {
            System.assertNotEquals(cancelledMine.Id, row.Id, 'Cancelled appointments must not appear');
            System.assertNotEquals(yesterdayAppointmentMine.Id, row.Id, 'Yesterday appointments must not appear');
            System.assertNotEquals(bookedOtherPractitioner.Id, row.Id, 'Other practitioners appointments must not appear');
        }

        System.assertEquals(1, payload.lists.todaysEncounters.size(), 'Today list should include only my patient encounter starting today');
        System.assertEquals(todayMine.Id, payload.lists.todaysEncounters[0].Id, 'Today encounter should be the in-progress visit');
        System.assertEquals(1, payload.lists.resultsToReview.size(), 'Results list should include only my unreviewed report');
        System.assertEquals(unreviewedMine.Id, payload.lists.resultsToReview[0].Id, 'Unreviewed CBC should be on the worklist');
        System.assertEquals(1, payload.lists.unsignedNotes.size(), 'Unsigned notes should include only my draft');
        System.assertEquals(draftMine.Id, payload.lists.unsignedNotes[0].Id, 'Draft progress note should be on the worklist');
        System.assertNotEquals(null, payload.recentPatients, 'Recent patients should always be returned');
        System.assert(payload.recentPatients.size() <= 10, 'Recent patients should be capped at 10');
        for (Patient__c recent : payload.recentPatients) {
            System.assertEquals(
                myPatient.Id,
                recent.Id,
                'Recent patients must respect sharing and only include patients the provider can see'
            );
        }

        System.runAs(provider) {
            DiagnosticReportService.markReviewed(new List<Id>{ unreviewedMine.Id });
            payload = ProviderHomeController.getHome();
        }

        System.assertEquals(0, payload.metrics.resultsToReview, 'Mark reviewed should drop the results-to-review count');
        System.assertEquals(0, payload.lists.resultsToReview.size(), 'Mark reviewed should remove the report from the worklist');
        System.assertEquals(1, payload.metrics.unsignedNotes, 'Mark reviewed should not change unsigned notes');
    }

    @IsTest
    static void getHomeIsEmptyWhenUserHasNoPractitionerOrCareTeam() {
        User provider = getUser(PROVIDER_ALIAS);

        Test.startTest();
        ProviderHomeController.HomePayload payload;
        System.runAs(provider) {
            payload = ProviderHomeController.getHome();
        }
        Test.stopTest();

        System.assertEquals(0, payload.metrics.myActivePatients, 'No care-team patients should yield a zero count');
        System.assertEquals(0, payload.metrics.openEncounters, 'No practitioner or patients should yield zero open encounters');
        System.assertEquals(0, payload.metrics.resultsToReview, 'No patients should yield zero results to review');
        System.assertEquals(0, payload.metrics.unsignedNotes, 'No practitioner should yield zero unsigned notes');
        System.assertEquals(0, payload.metrics.todaysAppointments, 'No practitioner should yield zero today appointments');
        System.assertEquals(0, payload.lists.todaysAppointments.size(), 'Today appointments should be empty without a Practitioner');
        System.assertEquals(0, payload.lists.todaysEncounters.size(), 'Today encounters should be empty');
        System.assertEquals(0, payload.lists.resultsToReview.size(), 'Results to review should be empty');
        System.assertEquals(0, payload.lists.unsignedNotes.size(), 'Unsigned notes should be empty');
        System.assertEquals(0, payload.recentPatients.size(), 'A user with no patient access should see no recent patients');
    }

    @IsTest
    static void getHomeIncludesAttendingEncountersWithoutCareTeamPatients() {
        User provider = getUser(PROVIDER_ALIAS);
        Practitioner__c myPractitioner = insertPractitioner(provider.Id, 'Pat', 'Attending');
        Patient__c ownedPatient = insertPatient('MRN-HOME-ATT', 'Owned');
        ownedPatient.OwnerId = provider.Id;
        update ownedPatient;

        insert new Encounter__c(
            Patient__c = ownedPatient.Id,
            Practitioner__c = myPractitioner.Id,
            Class__c = 'Virtual',
            Status__c = 'Planned',
            Start__c = Datetime.now()
        );
        insert new DiagnosticReport__c(
            Patient__c = ownedPatient.Id,
            Report_Display__c = 'MRI',
            Status__c = 'Final'
        );

        Test.startTest();
        ProviderHomeController.HomePayload payload;
        System.runAs(provider) {
            payload = ProviderHomeController.getHome();
        }
        Test.stopTest();

        System.assertEquals(0, payload.metrics.myActivePatients, 'Owned patients without an active care-team membership should not count');
        System.assertEquals(1, payload.metrics.openEncounters, 'Encounters I attend should count even without a care-team patient set');
        System.assertEquals(1, payload.lists.todaysEncounters.size(), 'Today list should include the encounter I attend');
        System.assertEquals(0, payload.metrics.todaysAppointments, 'No appointments were created for this attending-only case');
        System.assertEquals(0, payload.lists.todaysAppointments.size(), 'Today appointments should be empty when none exist for my Practitioner');
        System.assertEquals(0, payload.metrics.resultsToReview, 'Results to review are limited to care-team patients');
    }

    @IsTest
    static void getHomeUsesCareTeamPatientsWhenUserHasNoPractitioner() {
        User provider = getUser(PROVIDER_ALIAS);
        Practitioner__c teamPractitioner = insertPractitioner(null, 'Team', 'Doc');
        Patient__c myPatient = insertPatient('MRN-HOME-NOPRAC', 'Panel');
        assignCareTeam(myPatient.Id, teamPractitioner.Id, provider.Id, true);

        insert new Encounter__c(
            Patient__c = myPatient.Id,
            Class__c = 'Outpatient',
            Status__c = 'Arrived',
            Start__c = Datetime.now()
        );
        insert new DiagnosticReport__c(
            Patient__c = myPatient.Id,
            Report_Display__c = 'Lipid',
            Status__c = 'Preliminary'
        );
        insert new ClinicalNote__c(
            Patient__c = myPatient.Id,
            Author__c = teamPractitioner.Id,
            Note_Type__c = 'Progress Note',
            Status__c = 'Draft',
            Body__c = 'Not mine'
        );
        Datetime todayMorning = Datetime.newInstance(Date.today(), Time.newInstance(10, 0, 0, 0));
        insert new Appointment__c(
            Patient__c = myPatient.Id,
            Practitioner__c = teamPractitioner.Id,
            Start__c = todayMorning,
            End__c = todayMorning.addMinutes(20),
            Status__c = 'Booked',
            Appointment_Type__c = 'Checkup',
            OwnerId = provider.Id
        );

        Test.startTest();
        ProviderHomeController.HomePayload payload;
        System.runAs(provider) {
            payload = ProviderHomeController.getHome();
        }
        Test.stopTest();

        System.assertEquals(1, payload.metrics.myActivePatients, 'Care-team patients should count without a Practitioner for the user');
        System.assertEquals(1, payload.metrics.openEncounters, 'Open encounters on my patients should count');
        System.assertEquals(1, payload.lists.todaysEncounters.size(), 'Today encounters on my patients should be listed');
        System.assertEquals(1, payload.metrics.resultsToReview, 'Unreviewed reports on my patients should count');
        System.assertEquals(0, payload.metrics.unsignedNotes, 'Unsigned notes require the current user Practitioner');
        System.assertEquals(
            0,
            payload.metrics.todaysAppointments,
            'Today appointments must be scoped to the current user Practitioner, not care-team patients alone'
        );
        System.assertEquals(0, payload.lists.todaysAppointments.size(), 'A user without a Practitioner must not see another provider appointments');
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

    private static Patient__c insertPatient(String mrn, String lastName) {
        Patient__c patient = new Patient__c(
            MRN__c = mrn,
            Last_Name__c = lastName,
            First_Name__c = 'Home',
            Status__c = 'Active'
        );
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

    private static void assignCareTeam(Id patientId, Id practitionerId, Id userId, Boolean active) {
        CareTeam__c team = new CareTeam__c(Patient__c = patientId, Status__c = 'Active');
        insert team;
        insert new CareTeamMember__c(
            Care_Team__c = team.Id,
            Practitioner__c = practitionerId,
            User__c = userId,
            Role__c = 'Attending',
            Access_Level__c = 'Edit',
            Active__c = active
        );
    }
}
