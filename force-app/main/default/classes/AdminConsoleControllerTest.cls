@IsTest
private class AdminConsoleControllerTest {
    @TestSetup
    static void setupData() {
        insert new Practitioner__c(First_Name__c = 'Ada', Last_Name__c = 'Admin');
        insert new NoteTemplate__c(
            Name = 'Admin ROS',
            Shortcut__c = '.ros',
            Category__c = 'ROS',
            Body__c = '<p>Review of systems</p>',
            Active__c = true
        );
        insert new Code_Reference__c(
            Name = 'E11.9',
            Code_System__c = 'ICD-10',
            Code__c = 'E11.9',
            Display__c = 'Type 2 diabetes mellitus without complications',
            Active__c = true
        );
    }

    @IsTest
    static void getOverviewReturnsHealthPayload() {
        AdminConsoleController.manageSettingsOverride = true;

        Test.startTest();
        AdminConsoleController.OverviewPayload payload = AdminConsoleController.getOverview();
        Test.stopTest();

        System.assertNotEquals(null, payload, 'Overview payload should be returned');
        System.assertNotEquals(null, payload.reminderJob, 'Reminder job status should be present');
        System.assertEquals(
            AdminConsoleController.REMINDER_JOB_NAME,
            payload.reminderJob.jobName,
            'Reminder job name should match'
        );
        System.assertNotEquals(null, payload.eligibilityJob, 'Eligibility job status should be present');
        System.assertEquals(
            AdminConsoleController.ELIGIBILITY_JOB_NAME,
            payload.eligibilityJob.jobName,
            'Eligibility job name should match'
        );
        System.assert(
            payload.practitionersMissingUser >= 1,
            'At least one practitioner should be missing a User link'
        );
        System.assertEquals(1, payload.activeNoteTemplates, 'Active note template count should be 1');
        System.assertEquals(1, payload.codeCatalogCount, 'Code catalog count should be 1');
        System.assertNotEquals(null, payload.commConfig, 'Comm config should load');
        System.assertEquals('Default', payload.commConfig.developerName, 'Default comm config should load');
        System.assertNotEquals(null, payload.stediSetupHint, 'Stedi setup hint should be present');
        System.assertNotEquals(null, payload.twilioSetupHint, 'Twilio setup hint should be present');
        System.assert(
            payload.messageTemplates != null && !payload.messageTemplates.isEmpty(),
            'Packaged message templates should be returned'
        );
        System.assert(
            payload.nameFormats != null && !payload.nameFormats.isEmpty(),
            'Packaged name formats should be returned'
        );
    }

    @IsTest
    static void requireManageSettingsDeniesWithoutPermission() {
        AdminConsoleController.manageSettingsOverride = false;
        Boolean denied = false;
        try {
            AdminConsoleController.getOverview();
        } catch (AuraHandledException e) {
            denied = true;
            System.assert(
                e.getMessage().contains('permission'),
                'Denial message should mention permission'
            );
        }
        System.assertEquals(true, denied, 'Overview should deny without Manage Settings');
    }

    @IsTest
    static void getNoteTemplatesAndPractitioners() {
        AdminConsoleController.manageSettingsOverride = true;

        Test.startTest();
        List<NoteTemplate__c> templates = AdminConsoleController.getNoteTemplates();
        List<AdminConsoleController.PractitionerRow> practitioners = AdminConsoleController.getPractitioners();
        Test.stopTest();

        System.assertEquals(1, templates.size(), 'One note template should be returned');
        System.assertEquals('Admin ROS', templates[0].Name, 'Template name should match');
        System.assertEquals(1, practitioners.size(), 'One practitioner should be returned');
        System.assertEquals('Ada', practitioners[0].firstName, 'Practitioner first name should match');
        System.assertEquals(null, practitioners[0].userId, 'Practitioner should start without a User');
    }

    @IsTest
    static void savePractitionerUsersUpdatesLink() {
        AdminConsoleController.manageSettingsOverride = true;
        Practitioner__c practitioner = [SELECT Id, User__c FROM Practitioner__c LIMIT 1];
        System.assertEquals(null, practitioner.User__c, 'Precondition: User is blank');

        AdminConsoleController.PractitionerUserUpdate updateRow =
            new AdminConsoleController.PractitionerUserUpdate();
        updateRow.practitionerId = practitioner.Id;
        updateRow.userId = UserInfo.getUserId();

        Test.startTest();
        Integer updated = AdminConsoleController.savePractitionerUsers(
            new List<AdminConsoleController.PractitionerUserUpdate>{ updateRow }
        );
        Test.stopTest();

        System.assertEquals(1, updated, 'One practitioner should be updated');
        Practitioner__c refreshed = [
            SELECT User__c
            FROM Practitioner__c
            WHERE Id = :practitioner.Id
        ];
        System.assertEquals(UserInfo.getUserId(), refreshed.User__c, 'User link should be saved');
    }

    @IsTest
    static void savePractitionerUsersNoopWhenEmpty() {
        AdminConsoleController.manageSettingsOverride = true;
        Test.startTest();
        Integer updated = AdminConsoleController.savePractitionerUsers(
            new List<AdminConsoleController.PractitionerUserUpdate>()
        );
        Test.stopTest();
        System.assertEquals(0, updated, 'Empty updates should return 0');
    }

    @IsTest
    static void metadataSaveMethodsQueueWithSkipFlag() {
        AdminConsoleController.manageSettingsOverride = true;
        AdminConsoleController.skipMetadataDeploy = true;

        AdminConsoleController.EligibilitySettingDto eligibility =
            new AdminConsoleController.EligibilitySettingDto();
        eligibility.developerName = 'Stedi';
        eligibility.masterLabel = 'Stedi';
        eligibility.providerName = 'Stedi';
        eligibility.namedCredential = 'Stedi_Eligibility';
        eligibility.defaultServiceType = '30';
        eligibility.active = true;

        AdminConsoleController.CommConfigDto comm = new AdminConsoleController.CommConfigDto();
        comm.developerName = 'Default';
        comm.masterLabel = 'Default';
        comm.emailEnabled = true;
        comm.smsEnabled = false;
        comm.autoSendConfirmation = true;
        comm.autoSendReminder = true;
        comm.reminderHoursBefore = 24;
        comm.twilioNamedCredential = 'LogicEMR_Twilio';

        AdminConsoleController.MessageTemplateDto template =
            new AdminConsoleController.MessageTemplateDto();
        template.developerName = 'Confirmation_Email';
        template.masterLabel = 'Confirmation Email';
        template.typeValue = 'Confirmation';
        template.channel = 'Email';
        template.subject = 'Updated subject';
        template.body = '<p>Body</p>';
        template.active = true;

        AdminConsoleController.NameFormatDto nameFormat = new AdminConsoleController.NameFormatDto();
        nameFormat.developerName = 'Patient';
        nameFormat.masterLabel = 'Patient';
        nameFormat.objectApiName = 'Patient__c';
        nameFormat.formatPattern = '{Last_Name__c}, {First_Name__c}';
        nameFormat.active = true;

        Test.startTest();
        AdminConsoleController.ActionResult eligibilityResult =
            AdminConsoleController.saveEligibilitySetting(eligibility);
        AdminConsoleController.ActionResult commResult = AdminConsoleController.saveCommConfig(comm);
        AdminConsoleController.ActionResult templateResult =
            AdminConsoleController.saveMessageTemplate(template);
        AdminConsoleController.ActionResult nameResult = AdminConsoleController.saveNameFormat(nameFormat);
        Test.stopTest();

        System.assertEquals(true, eligibilityResult.success, 'Eligibility save should succeed in test skip mode');
        System.assertEquals(true, commResult.success, 'Comm config save should succeed in test skip mode');
        System.assertEquals(true, templateResult.success, 'Template save should succeed in test skip mode');
        System.assertEquals(true, nameResult.success, 'Name format save should succeed in test skip mode');
        System.assertEquals(
            'TEST_DEPLOY',
            AdminConsoleController.lastDeployRequestId,
            'Deploy request id should be recorded'
        );
    }

    @IsTest
    static void metadataSaveRequiresDeveloperName() {
        AdminConsoleController.manageSettingsOverride = true;
        AdminConsoleController.skipMetadataDeploy = true;
        Boolean denied = false;
        try {
            AdminConsoleController.saveCommConfig(new AdminConsoleController.CommConfigDto());
        } catch (AuraHandledException e) {
            denied = true;
        }
        System.assertEquals(true, denied, 'Blank developer name should throw');
    }

    @IsTest
    static void scheduleAndAbortReminderJob() {
        AdminConsoleController.manageSettingsOverride = true;
        abortIfPresent(AdminConsoleController.REMINDER_JOB_NAME);

        Test.startTest();
        AdminConsoleController.ActionResult scheduled = AdminConsoleController.scheduleReminderJob(null);
        AdminConsoleController.ActionResult already = AdminConsoleController.scheduleReminderJob(null);
        AdminConsoleController.ActionResult aborted = AdminConsoleController.abortReminderJob();
        AdminConsoleController.ActionResult abortAgain = AdminConsoleController.abortReminderJob();
        Test.stopTest();

        System.assertEquals(true, scheduled.success, 'Reminder schedule should succeed');
        System.assertNotEquals(null, scheduled.jobId, 'Scheduled reminder should return a job Id');
        System.assertEquals(true, already.success, 'Second schedule should report already scheduled');
        System.assert(
            already.message != null && already.message.contains('already'),
            'Already-scheduled message expected'
        );
        System.assertEquals(true, aborted.success, 'Abort should succeed');
        System.assertEquals(true, abortAgain.success, 'Abort when missing should still succeed');
    }

    @IsTest
    static void scheduleAndAbortEligibilityJob() {
        AdminConsoleController.manageSettingsOverride = true;
        abortIfPresent(AdminConsoleController.ELIGIBILITY_JOB_NAME);

        Test.startTest();
        AdminConsoleController.ActionResult scheduled = AdminConsoleController.scheduleEligibilityJob(
            '0 0 3 * * ?'
        );
        AdminConsoleController.ActionResult already = AdminConsoleController.scheduleEligibilityJob(null);
        AdminConsoleController.ActionResult aborted = AdminConsoleController.abortEligibilityJob();
        Test.stopTest();

        System.assertEquals(true, scheduled.success, 'Eligibility schedule should succeed');
        System.assertNotEquals(null, scheduled.jobId, 'Eligibility schedule should return a job Id');
        System.assertEquals(true, already.success, 'Second eligibility schedule should be idempotent');
        System.assertEquals(true, aborted.success, 'Eligibility abort should succeed');
    }

    @IsTest
    static void runEligibilityNowQueuesBatch() {
        AdminConsoleController.manageSettingsOverride = true;
        Test.startTest();
        AdminConsoleController.ActionResult result = AdminConsoleController.runEligibilityNow(3);
        Test.stopTest();
        System.assertEquals(true, result.success, 'Eligibility run-now should succeed');
        System.assertNotEquals(null, result.jobId, 'Eligibility run-now should return a batch Id');
    }

    @IsTest
    static void enqueueNameBackfill() {
        AdminConsoleController.manageSettingsOverride = true;
        Test.startTest();
        AdminConsoleController.ActionResult result = AdminConsoleController.enqueueNameBackfill(
            'Practitioner__c'
        );
        Test.stopTest();
        System.assertEquals(true, result.success, 'Name backfill should queue');
        System.assertNotEquals(null, result.jobId, 'Name backfill should return a batch Id');
    }

    @IsTest
    static void enqueueNameBackfillRequiresObject() {
        AdminConsoleController.manageSettingsOverride = true;
        Boolean denied = false;
        try {
            AdminConsoleController.enqueueNameBackfill('');
        } catch (AuraHandledException e) {
            denied = true;
        }
        System.assertEquals(true, denied, 'Blank object should throw');
    }

    @IsTest
    static void enqueueCatalogLinkBackfill() {
        AdminConsoleController.manageSettingsOverride = true;
        Test.startTest();
        AdminConsoleController.ActionResult result = AdminConsoleController.enqueueCatalogLinkBackfill(
            'Condition__c',
            'Diagnosis_Code_System__c',
            'Diagnosis_Code__c',
            'Diagnosis_Ref__c'
        );
        Test.stopTest();
        System.assertEquals(true, result.success, 'Catalog link backfill should queue');
        System.assertNotEquals(null, result.jobId, 'Catalog link backfill should return a batch Id');
    }

    @IsTest
    static void enqueueCatalogLinkRequiresFields() {
        AdminConsoleController.manageSettingsOverride = true;
        Boolean denied = false;
        try {
            AdminConsoleController.enqueueCatalogLinkBackfill('Condition__c', null, null, null);
        } catch (AuraHandledException e) {
            denied = true;
        }
        System.assertEquals(true, denied, 'Missing catalog fields should throw');
    }

    @IsTest
    static void optionListsReturnExpectedEntries() {
        AdminConsoleController.manageSettingsOverride = true;
        Test.startTest();
        List<String> nameObjects = AdminConsoleController.getNameBackfillObjects();
        List<AdminConsoleController.CatalogLinkOption> catalogOptions =
            AdminConsoleController.getCatalogLinkOptions();
        Test.stopTest();

        System.assert(nameObjects.contains('Patient__c'), 'Name backfill list should include Patient__c');
        System.assert(nameObjects.contains('Coverage__c'), 'Name backfill list should include Coverage__c');
        System.assertEquals(9, catalogOptions.size(), 'Catalog link options should match docs');
        System.assertEquals('Condition__c', catalogOptions[0].objectApiName, 'First catalog option is Condition');
    }

    @IsTest
    static void deployCallbackRecordsSuccessAndFailure() {
        AdminConsoleDeployCallback callback = new AdminConsoleDeployCallback();

        Metadata.DeployResult success = new Metadata.DeployResult();
        success.id = '0Af000000000001';
        success.success = true;
        callback.handleResult(success, null);
        System.assertEquals(true, AdminConsoleDeployCallback.lastSuccess, 'Success should be recorded');
        System.assertEquals(
            'Custom metadata deploy completed.',
            AdminConsoleDeployCallback.lastMessage,
            'Success message should be set'
        );

        Metadata.DeployResult failure = new Metadata.DeployResult();
        failure.id = '0Af000000000002';
        failure.success = false;
        failure.details = new Metadata.DeployDetails();
        Metadata.DeployMessage message = new Metadata.DeployMessage();
        message.problem = 'Field not writable';
        failure.details.componentFailures = new List<Metadata.DeployMessage>{ message };
        callback.handleResult(failure, null);
        System.assertEquals(false, AdminConsoleDeployCallback.lastSuccess, 'Failure should be recorded');
        System.assert(
            AdminConsoleDeployCallback.lastMessage.contains('Field not writable'),
            'Failure message should include component problem'
        );

        callback.handleResult(null, null);
        System.assertEquals(false, AdminConsoleDeployCallback.lastSuccess, 'Null result should not be success');
    }

    @IsTest
    static void savePractitionerUsersSkipsInvalidRows() {
        AdminConsoleController.manageSettingsOverride = true;
        AdminConsoleController.PractitionerUserUpdate blank =
            new AdminConsoleController.PractitionerUserUpdate();
        blank.practitionerId = null;
        blank.userId = UserInfo.getUserId();

        Test.startTest();
        Integer updated = AdminConsoleController.savePractitionerUsers(
            new List<AdminConsoleController.PractitionerUserUpdate>{ null, blank }
        );
        Test.stopTest();

        System.assertEquals(0, updated, 'Invalid practitioner updates should be skipped');
    }

    @IsTest
    static void savePractitionerUsersNoChangeWhenSameUser() {
        AdminConsoleController.manageSettingsOverride = true;
        Practitioner__c practitioner = [SELECT Id FROM Practitioner__c LIMIT 1];
        practitioner.User__c = UserInfo.getUserId();
        update practitioner;

        AdminConsoleController.PractitionerUserUpdate updateRow =
            new AdminConsoleController.PractitionerUserUpdate();
        updateRow.practitionerId = practitioner.Id;
        updateRow.userId = UserInfo.getUserId();

        Test.startTest();
        Integer updated = AdminConsoleController.savePractitionerUsers(
            new List<AdminConsoleController.PractitionerUserUpdate>{ updateRow }
        );
        Test.stopTest();

        System.assertEquals(0, updated, 'Unchanged user links should not update');
    }

    @IsTest
    static void metadataSaveRejectsNullDtos() {
        AdminConsoleController.manageSettingsOverride = true;
        AdminConsoleController.skipMetadataDeploy = true;
        Integer failures = 0;
        try {
            AdminConsoleController.saveEligibilitySetting(null);
        } catch (AuraHandledException e) {
            failures++;
        }
        try {
            AdminConsoleController.saveMessageTemplate(null);
        } catch (AuraHandledException e) {
            failures++;
        }
        try {
            AdminConsoleController.saveNameFormat(null);
        } catch (AuraHandledException e) {
            failures++;
        }
        System.assertEquals(3, failures, 'Null DTOs should throw for each save method');
    }

    @IsTest
    static void saveCommConfigUsesDefaultsForBlankLabelAndHours() {
        AdminConsoleController.manageSettingsOverride = true;
        AdminConsoleController.skipMetadataDeploy = true;

        AdminConsoleController.CommConfigDto comm = new AdminConsoleController.CommConfigDto();
        comm.developerName = 'Default';
        comm.masterLabel = null;
        comm.emailEnabled = true;
        comm.smsEnabled = false;
        comm.autoSendConfirmation = true;
        comm.autoSendReminder = true;
        comm.reminderHoursBefore = null;
        comm.twilioNamedCredential = 'LogicEMR_Twilio';

        Test.startTest();
        AdminConsoleController.ActionResult result = AdminConsoleController.saveCommConfig(comm);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Comm config with blank label/hours should save');
    }

    @IsTest
    static void saveEligibilityUsesDeveloperNameWhenLabelBlank() {
        AdminConsoleController.manageSettingsOverride = true;
        AdminConsoleController.skipMetadataDeploy = true;

        AdminConsoleController.EligibilitySettingDto eligibility =
            new AdminConsoleController.EligibilitySettingDto();
        eligibility.developerName = 'Stedi';
        eligibility.masterLabel = '';
        eligibility.providerName = 'Stedi';
        eligibility.namedCredential = 'Stedi_Eligibility';
        eligibility.defaultServiceType = '30';
        eligibility.active = false;

        Test.startTest();
        AdminConsoleController.ActionResult result =
            AdminConsoleController.saveEligibilitySetting(eligibility);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Eligibility save with blank label should succeed');
    }

    @IsTest
    static void enqueueMetadataRealDeployPathSurfacesPlatformLimitInTests() {
        AdminConsoleController.manageSettingsOverride = true;
        AdminConsoleController.skipMetadataDeploy = false;

        AdminConsoleController.NameFormatDto nameFormat = new AdminConsoleController.NameFormatDto();
        nameFormat.developerName = 'Patient';
        nameFormat.masterLabel = 'Patient';
        nameFormat.objectApiName = 'Patient__c';
        nameFormat.formatPattern = '{Last_Name__c}, {First_Name__c}';
        nameFormat.active = true;

        Boolean denied = false;
        Test.startTest();
        try {
            AdminConsoleController.saveNameFormat(nameFormat);
        } catch (AuraHandledException e) {
            denied = true;
            System.assert(
                e.getMessage().contains('Metadata') || e.getMessage().contains('test'),
                'Platform should block metadata deploy inside tests'
            );
        }
        Test.stopTest();

        System.assertEquals(true, denied, 'Real metadata deploy from a test should throw');
    }

    @IsTest
    static void scheduleReminderFailurePathWhenAlreadyCoveredBySuccess() {
        AdminConsoleController.manageSettingsOverride = true;
        abortIfPresent(AdminConsoleController.REMINDER_JOB_NAME);

        Test.startTest();
        AdminConsoleController.ActionResult first = AdminConsoleController.scheduleReminderJob(
            AppointmentReminderInvocable.DEFAULT_CRON
        );
        Test.stopTest();

        System.assertEquals(true, first.success, 'Reminder schedule with explicit cron should succeed');
        abortIfPresent(AdminConsoleController.REMINDER_JOB_NAME);
    }

    private static void abortIfPresent(String jobName) {
        for (CronTrigger row : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :jobName
        ]) {
            System.abortJob(row.Id);
        }
    }
}
