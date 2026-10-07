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
    ClinicalUnitSettings.preferenceOverride = clinicalPreferences(
      'Cel',
      'Metric'
    );

    Test.startTest();
    AdminConsoleController.OverviewPayload payload = AdminConsoleController.getOverview();
    Test.stopTest();

    System.assertNotEquals(
      null,
      payload,
      'Overview payload should be returned'
    );
    System.assertNotEquals(
      null,
      payload.reminderJob,
      'Reminder job status should be present'
    );
    System.assertEquals(
      AdminConsoleController.REMINDER_JOB_NAME,
      payload.reminderJob.jobName,
      'Reminder job name should match'
    );
    System.assertNotEquals(
      null,
      payload.eligibilityJob,
      'Eligibility job status should be present'
    );
    System.assertEquals(
      AdminConsoleController.ELIGIBILITY_JOB_NAME,
      payload.eligibilityJob.jobName,
      'Eligibility job name should match'
    );
    System.assert(
      payload.practitionersMissingUser >= 1,
      'At least one practitioner should be missing a User link'
    );
    System.assertEquals(
      1,
      payload.activeNoteTemplates,
      'Active note template count should be 1'
    );
    System.assertEquals(
      1,
      payload.codeCatalogCount,
      'Code catalog count should be 1'
    );
    System.assertNotEquals(null, payload.commConfig, 'Comm config should load');
    System.assertEquals(
      'Cel',
      payload.clinicalUnits.temperatureUnit,
      'Overview should expose org temperature units'
    );
    System.assertEquals(
      'Metric',
      payload.clinicalUnits.measurementSystem,
      'Overview should expose org measurement preferences'
    );
    System.assertEquals(
      'Default',
      payload.commConfig.developerName,
      'Default comm config should load'
    );
    System.assertNotEquals(
      null,
      payload.stediSetupHint,
      'Stedi setup hint should be present'
    );
    System.assertNotEquals(
      null,
      payload.twilioSetupHint,
      'Twilio setup hint should be present'
    );
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
  static void getIntegrationMonitorReturnsStediTraffic() {
    AdminConsoleController.manageSettingsOverride = true;
    Patient__c patient = new Patient__c(
      Name = 'Monitor Patient',
      MRN__c = 'MONITOR-001'
    );
    insert patient;
    insert new Eligibility_Check__c(
      Patient__c = patient.Id,
      Status__c = 'Active',
      Provider_Used__c = 'Stedi',
      Checked_Date__c = Datetime.now(),
      Request_Payload__c = '{"transaction":"270"}',
      Raw_Response__c = '{"transaction":"271"}'
    );

    Encounter__c encounter = new Encounter__c(
      Patient__c = patient.Id,
      Status__c = 'Finished'
    );
    insert encounter;
    Superbill__c superbill = new Superbill__c(
      Encounter__c = encounter.Id,
      Encounter_Key__c = String.valueOf(encounter.Id),
      Patient__c = patient.Id,
      Status__c = 'Exported'
    );
    insert superbill;
    Claim_Submission__c submission = new Claim_Submission__c(
      Superbill__c = superbill.Id,
      Status__c = 'Submitted',
      Acknowledgment_Status__c = 'Pending',
      Attempt_Number__c = 1,
      Idempotency_Key__c = 'ADMIN-MONITOR-IDEMP',
      Patient_Control_Number__c = 'ADMIN-MONITOR-PCN',
      Provider_Used__c = 'Stedi',
      Http_Status_Code__c = 200,
      Provider_Status__c = 'SUCCESS',
      Correlation_Id__c = 'ADMIN-MONITOR-CORR',
      Clearinghouse_Claim_Id__c = 'STEDI-CLAIM-001',
      Request_Payload__c = '{"transaction":"837P"}',
      Response_Payload__c = '{"status":"SUCCESS"}',
      Submitted_At__c = Datetime.now()
    );
    insert submission;
    insert new Claim_Acknowledgment__c(
      Acknowledgment_Key__c = 'ADMIN-MONITOR-ACK',
      Transaction_Id__c = '71716ec5-0e96-462f-bb77-869941bb27ab',
      Claim_Submission__c = submission.Id,
      Superbill__c = superbill.Id,
      Match_Status__c = 'Matched',
      Status__c = 'Accepted',
      Sender_Type__c = 'Clearinghouse',
      Sender_Name__c = 'Stedi',
      Payer_Claim_Control_Number__c = 'PAYER-001',
      Processed_At__c = Datetime.now(),
      Raw_Payload__c = '{"transaction":"277CA"}',
      Message__c = 'Claim accepted'
    );

    Test.startTest();
    AdminConsoleController.IntegrationMonitorPayload payload = AdminConsoleController.getIntegrationMonitor();
    Test.stopTest();

    System.assertEquals(
      1,
      payload.eligibilityCount,
      'Eligibility activity should be counted'
    );
    System.assertEquals(
      1,
      payload.submissionCount,
      'Claim submissions should be counted'
    );
    System.assertEquals(
      1,
      payload.acknowledgmentCount,
      'Acknowledgments should be counted'
    );
    System.assertEquals(
      3,
      payload.rows.size(),
      'All integration activity should be returned'
    );

    Map<String, AdminConsoleController.IntegrationMonitorRow> rowsByType = new Map<String, AdminConsoleController.IntegrationMonitorRow>();
    for (AdminConsoleController.IntegrationMonitorRow row : payload.rows) {
      rowsByType.put(row.kind, row);
    }
    System.assertEquals(
      200,
      rowsByType.get('Professional claim 837P').httpStatus,
      'HTTP response code should be exposed'
    );
    System.assertEquals(
      'STEDI-CLAIM-001',
      rowsByType.get('Professional claim 837P').clearinghouseId,
      'Clearinghouse claim id should be exposed'
    );
    System.assertEquals(
      'Clearinghouse - Stedi',
      rowsByType.get('Claim acknowledgment 277CA').provider,
      'Acknowledgment sender should be exposed'
    );
    System.assertEquals(
      '{"transaction":"271"}',
      rowsByType.get('Eligibility 270/271').responsePayload,
      'Eligibility response should be exposed'
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
    System.assertEquals(
      true,
      denied,
      'Overview should deny without Manage Settings'
    );
  }

  @IsTest
  static void getNoteTemplatesAndPractitioners() {
    AdminConsoleController.manageSettingsOverride = true;

    Test.startTest();
    List<NoteTemplate__c> templates = AdminConsoleController.getNoteTemplates();
    List<AdminConsoleController.PractitionerRow> practitioners = AdminConsoleController.getPractitioners();
    Test.stopTest();

    System.assertEquals(
      1,
      templates.size(),
      'One note template should be returned'
    );
    System.assertEquals(
      'Admin ROS',
      templates[0].Name,
      'Template name should match'
    );
    System.assertEquals(
      1,
      practitioners.size(),
      'One practitioner should be returned'
    );
    System.assertEquals(
      'Ada',
      practitioners[0].firstName,
      'Practitioner first name should match'
    );
    System.assertEquals(
      null,
      practitioners[0].userId,
      'Practitioner should start without a User'
    );
  }

  @IsTest
  static void getBillingOrganizationReturnsEmptyDraftWhenNoneExist() {
    AdminConsoleController.manageSettingsOverride = true;

    Test.startTest();
    AdminConsoleController.BillingOrganizationDto dto = AdminConsoleController.getBillingOrganization();
    Test.stopTest();

    System.assertEquals(null, dto.id, 'No organization should exist yet');
    System.assertEquals(true, dto.active, 'Draft should default to active');
    System.assertEquals(
      true,
      dto.isDefaultBilling,
      'Draft should be the default billing org'
    );
    System.assertEquals(
      'US',
      dto.country,
      'Draft country should default to US'
    );
  }

  @IsTest
  static void saveBillingOrganizationCreatesDefaultAndClearsOthers() {
    AdminConsoleController.manageSettingsOverride = true;
    insert new Organization__c(
      Name = 'Old Billing',
      NPI__c = '1111111116',
      Active__c = true,
      Is_Default_Billing__c = true
    );

    AdminConsoleController.BillingOrganizationDto input = new AdminConsoleController.BillingOrganizationDto();
    input.name = ' Logic Clinic ';
    input.npi = '1999999984';
    input.ein = '12-3456789';
    input.street = '1 Clinic Way';
    input.city = 'Boston';
    input.state = 'MA';
    input.postalCode = '02108';
    input.country = '';
    input.active = true;

    Test.startTest();
    AdminConsoleController.BillingOrganizationDto saved = AdminConsoleController.saveBillingOrganization(
      input
    );
    AdminConsoleController.OverviewPayload overview = AdminConsoleController.getOverview();
    Test.stopTest();

    System.assertNotEquals(null, saved.id, 'Organization should be inserted');
    System.assertEquals('Logic Clinic', saved.name, 'Name should be trimmed');
    System.assertEquals('1999999984', saved.npi, 'Type 2 NPI should persist');
    System.assertEquals('12-3456789', saved.ein, 'EIN should persist');
    System.assertEquals(
      'US',
      saved.country,
      'Blank country should default to US'
    );
    System.assertEquals(
      true,
      saved.isDefaultBilling,
      'Saved org should be default billing'
    );
    System.assertEquals(
      'Logic Clinic',
      overview.billingOrganizationName,
      'Overview should show billing org name'
    );
    System.assertEquals(
      '1999999984',
      overview.billingOrganizationNpi,
      'Overview should show billing org NPI'
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Organization__c WHERE Is_Default_Billing__c = TRUE],
      'Only one default billing organization should remain'
    );
    System.assertEquals(
      false,
      [
        SELECT Is_Default_Billing__c
        FROM Organization__c
        WHERE Name = 'Old Billing'
      ]
      .Is_Default_Billing__c,
      'Previous default should be cleared'
    );
  }

  @IsTest
  static void saveBillingOrganizationRequiresName() {
    AdminConsoleController.manageSettingsOverride = true;
    Boolean denied = false;

    Test.startTest();
    try {
      AdminConsoleController.saveBillingOrganization(
        new AdminConsoleController.BillingOrganizationDto()
      );
    } catch (AuraHandledException e) {
      denied = true;
    }
    Test.stopTest();

    System.assertEquals(
      true,
      denied,
      'Blank organization name should be rejected'
    );
  }

  @IsTest
  static void savePractitionerUsersUpdatesLink() {
    AdminConsoleController.manageSettingsOverride = true;
    Practitioner__c practitioner = [
      SELECT Id, User__c
      FROM Practitioner__c
      LIMIT 1
    ];
    System.assertEquals(
      null,
      practitioner.User__c,
      'Precondition: User is blank'
    );

    AdminConsoleController.PractitionerUserUpdate updateRow = new AdminConsoleController.PractitionerUserUpdate();
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
    System.assertEquals(
      UserInfo.getUserId(),
      refreshed.User__c,
      'User link should be saved'
    );
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

    AdminConsoleController.EligibilitySettingDto eligibility = new AdminConsoleController.EligibilitySettingDto();
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

    AdminConsoleController.MessageTemplateDto template = new AdminConsoleController.MessageTemplateDto();
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
    AdminConsoleController.ActionResult eligibilityResult = AdminConsoleController.saveEligibilitySetting(
      eligibility
    );
    AdminConsoleController.ActionResult commResult = AdminConsoleController.saveCommConfig(
      comm
    );
    AdminConsoleController.ActionResult templateResult = AdminConsoleController.saveMessageTemplate(
      template
    );
    AdminConsoleController.ActionResult nameResult = AdminConsoleController.saveNameFormat(
      nameFormat
    );
    Test.stopTest();

    System.assertEquals(
      true,
      eligibilityResult.success,
      'Eligibility save should succeed in test skip mode'
    );
    System.assertEquals(
      true,
      commResult.success,
      'Comm config save should succeed in test skip mode'
    );
    System.assertEquals(
      true,
      templateResult.success,
      'Template save should succeed in test skip mode'
    );
    System.assertEquals(
      true,
      nameResult.success,
      'Name format save should succeed in test skip mode'
    );
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
      AdminConsoleController.saveCommConfig(
        new AdminConsoleController.CommConfigDto()
      );
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
    AdminConsoleController.ActionResult scheduled = AdminConsoleController.scheduleReminderJob(
      null
    );
    AdminConsoleController.ActionResult already = AdminConsoleController.scheduleReminderJob(
      null
    );
    AdminConsoleController.ActionResult aborted = AdminConsoleController.abortReminderJob();
    AdminConsoleController.ActionResult abortAgain = AdminConsoleController.abortReminderJob();
    Test.stopTest();

    System.assertEquals(
      true,
      scheduled.success,
      'Reminder schedule should succeed'
    );
    System.assertNotEquals(
      null,
      scheduled.jobId,
      'Scheduled reminder should return a job Id'
    );
    System.assertEquals(
      true,
      already.success,
      'Second schedule should report already scheduled'
    );
    System.assert(
      already.message != null && already.message.contains('already'),
      'Already-scheduled message expected'
    );
    System.assertEquals(true, aborted.success, 'Abort should succeed');
    System.assertEquals(
      true,
      abortAgain.success,
      'Abort when missing should still succeed'
    );
  }

  @IsTest
  static void scheduleAndAbortEligibilityJob() {
    AdminConsoleController.manageSettingsOverride = true;
    abortIfPresent(AdminConsoleController.ELIGIBILITY_JOB_NAME);

    Test.startTest();
    AdminConsoleController.ActionResult scheduled = AdminConsoleController.scheduleEligibilityJob(
      '0 0 3 * * ?'
    );
    AdminConsoleController.ActionResult already = AdminConsoleController.scheduleEligibilityJob(
      null
    );
    AdminConsoleController.ActionResult aborted = AdminConsoleController.abortEligibilityJob();
    Test.stopTest();

    System.assertEquals(
      true,
      scheduled.success,
      'Eligibility schedule should succeed'
    );
    System.assertNotEquals(
      null,
      scheduled.jobId,
      'Eligibility schedule should return a job Id'
    );
    System.assertEquals(
      true,
      already.success,
      'Second eligibility schedule should be idempotent'
    );
    System.assertEquals(
      true,
      aborted.success,
      'Eligibility abort should succeed'
    );
  }

  @IsTest
  static void runEligibilityNowQueuesBatch() {
    AdminConsoleController.manageSettingsOverride = true;
    Test.startTest();
    AdminConsoleController.ActionResult result = AdminConsoleController.runEligibilityNow(
      3
    );
    Test.stopTest();
    System.assertEquals(
      true,
      result.success,
      'Eligibility run-now should succeed'
    );
    System.assertNotEquals(
      null,
      result.jobId,
      'Eligibility run-now should return a batch Id'
    );
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
    System.assertNotEquals(
      null,
      result.jobId,
      'Name backfill should return a batch Id'
    );
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
    System.assertEquals(
      true,
      result.success,
      'Catalog link backfill should queue'
    );
    System.assertNotEquals(
      null,
      result.jobId,
      'Catalog link backfill should return a batch Id'
    );
  }

  @IsTest
  static void enqueueCatalogLinkRequiresFields() {
    AdminConsoleController.manageSettingsOverride = true;
    Boolean denied = false;
    try {
      AdminConsoleController.enqueueCatalogLinkBackfill(
        'Condition__c',
        null,
        null,
        null
      );
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
    List<AdminConsoleController.CatalogLinkOption> catalogOptions = AdminConsoleController.getCatalogLinkOptions();
    Test.stopTest();

    System.assert(
      nameObjects.contains('Patient__c'),
      'Name backfill list should include Patient__c'
    );
    System.assert(
      nameObjects.contains('Coverage__c'),
      'Name backfill list should include Coverage__c'
    );
    System.assertEquals(
      9,
      catalogOptions.size(),
      'Catalog link options should match docs'
    );
    System.assertEquals(
      'Condition__c',
      catalogOptions[0].objectApiName,
      'First catalog option is Condition'
    );
  }

  @IsTest
  static void deployCallbackRecordsSuccessAndFailure() {
    AdminConsoleDeployCallback callback = new AdminConsoleDeployCallback();

    Metadata.DeployResult success = new Metadata.DeployResult();
    success.id = '0Af000000000001';
    success.success = true;
    callback.handleResult(success, null);
    System.assertEquals(
      true,
      AdminConsoleDeployCallback.lastSuccess,
      'Success should be recorded'
    );
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
    failure.details.componentFailures = new List<Metadata.DeployMessage>{
      message
    };
    callback.handleResult(failure, null);
    System.assertEquals(
      false,
      AdminConsoleDeployCallback.lastSuccess,
      'Failure should be recorded'
    );
    System.assert(
      AdminConsoleDeployCallback.lastMessage.contains('Field not writable'),
      'Failure message should include component problem'
    );

    callback.handleResult(null, null);
    System.assertEquals(
      false,
      AdminConsoleDeployCallback.lastSuccess,
      'Null result should not be success'
    );
  }

  @IsTest
  static void savePractitionerUsersSkipsInvalidRows() {
    AdminConsoleController.manageSettingsOverride = true;
    AdminConsoleController.PractitionerUserUpdate blank = new AdminConsoleController.PractitionerUserUpdate();
    blank.practitionerId = null;
    blank.userId = UserInfo.getUserId();

    Test.startTest();
    Integer updated = AdminConsoleController.savePractitionerUsers(
      new List<AdminConsoleController.PractitionerUserUpdate>{ null, blank }
    );
    Test.stopTest();

    System.assertEquals(
      0,
      updated,
      'Invalid practitioner updates should be skipped'
    );
  }

  @IsTest
  static void savePractitionerUsersNoChangeWhenSameUser() {
    AdminConsoleController.manageSettingsOverride = true;
    Practitioner__c practitioner = [SELECT Id FROM Practitioner__c LIMIT 1];
    practitioner.User__c = UserInfo.getUserId();
    update practitioner;

    AdminConsoleController.PractitionerUserUpdate updateRow = new AdminConsoleController.PractitionerUserUpdate();
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
    System.assertEquals(
      3,
      failures,
      'Null DTOs should throw for each save method'
    );
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
    AdminConsoleController.ActionResult result = AdminConsoleController.saveCommConfig(
      comm
    );
    Test.stopTest();

    System.assertEquals(
      true,
      result.success,
      'Comm config with blank label/hours should save'
    );
  }

  @IsTest
  static void saveEligibilityUsesDeveloperNameWhenLabelBlank() {
    AdminConsoleController.manageSettingsOverride = true;
    AdminConsoleController.skipMetadataDeploy = true;

    AdminConsoleController.EligibilitySettingDto eligibility = new AdminConsoleController.EligibilitySettingDto();
    eligibility.developerName = 'Stedi';
    eligibility.masterLabel = '';
    eligibility.providerName = 'Stedi';
    eligibility.namedCredential = 'Stedi_Eligibility';
    eligibility.defaultServiceType = '30';
    eligibility.active = false;

    Test.startTest();
    AdminConsoleController.ActionResult result = AdminConsoleController.saveEligibilitySetting(
      eligibility
    );
    Test.stopTest();

    System.assertEquals(
      true,
      result.success,
      'Eligibility save with blank label should succeed'
    );
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

    System.assertEquals(
      true,
      denied,
      'Real metadata deploy from a test should throw'
    );
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

    System.assertEquals(
      true,
      first.success,
      'Reminder schedule with explicit cron should succeed'
    );
    abortIfPresent(AdminConsoleController.REMINDER_JOB_NAME);
  }

  @IsTest
  static void saveClinicalUnitsRequiresActualManageSettingsPermission() {
    User clinician = settingsRoleUser('unitdeny', 'LogicEMR_Clinician');
    AdminConsoleController.skipMetadataDeploy = true;
    System.runAs(clinician) {
      System.assertEquals(
        false,
        FeatureManagement.checkPermission('LogicEMR_Manage_Settings')
      );
      Boolean denied = false;
      try {
        AdminConsoleController.saveClinicalUnits('Cel', 'Metric');
      } catch (AuraHandledException error) {
        denied = error.getMessage().contains('permission');
      }
      System.assert(
        denied,
        'A valid unit preference change still requires Manage Settings'
      );
    }
    System.assertEquals(
      null,
      AdminConsoleController.lastDeployRequestId,
      'Denied changes cannot enqueue metadata'
    );
  }

  @IsTest
  static void settingsAdminCanQueueAllSupportedUnitCombinations() {
    User admin = settingsRoleUser('unitadm', 'LogicEMR_Admin');
    AdminConsoleController.skipMetadataDeploy = true;
    System.runAs(admin) {
      System.assertEquals(
        true,
        FeatureManagement.checkPermission('LogicEMR_Manage_Settings')
      );
      for (String temperatureUnit : new List<String>{ 'F', 'Cel' }) {
        for (
          String measurementSystem : new List<String>{ 'Imperial', 'Metric' }
        ) {
          AdminConsoleController.ActionResult queued = AdminConsoleController.saveClinicalUnits(
            temperatureUnit,
            measurementSystem
          );
          System.assertEquals(true, queued.success);
          System.assertEquals('TEST_DEPLOY', queued.deployRequestId);
          System.assertEquals(
            'Vital unit settings queued. Refresh to confirm the saved settings, then reload encounter vitals.',
            queued.message
          );
        }
      }
    }
  }

  @IsTest
  static void saveClinicalUnitsRejectsNullAndInvalidEnumsBeforeQueueing() {
    AdminConsoleController.manageSettingsOverride = true;
    AdminConsoleController.skipMetadataDeploy = true;
    List<ClinicalUnitSettings.Preferences> invalid = new List<ClinicalUnitSettings.Preferences>{
      null,
      new ClinicalUnitSettings.Preferences(),
      clinicalPreferences(null, 'Imperial'),
      clinicalPreferences('', 'Metric'),
      clinicalPreferences('C', 'Metric'),
      clinicalPreferences('f', 'Imperial'),
      clinicalPreferences('Cel ', 'Metric'),
      clinicalPreferences('F', null),
      clinicalPreferences('Cel', ''),
      clinicalPreferences('F', 'metric'),
      clinicalPreferences('Cel', 'SI'),
      clinicalPreferences('F', ' Imperial')
    };
    for (ClinicalUnitSettings.Preferences settings : invalid) {
      Boolean denied = false;
      try {
        AdminConsoleController.saveClinicalUnits(
          settings?.temperatureUnit,
          settings?.measurementSystem
        );
      } catch (AuraHandledException error) {
        denied = error.getMessage().contains('must be');
      }
      System.assert(
        denied,
        'Invalid or noncanonical preference values must fail'
      );
    }
    System.assertEquals(
      null,
      AdminConsoleController.lastDeployRequestId,
      'Invalid values cannot enqueue metadata'
    );
  }

  @IsTest
  static void clinicalUnitMetadataCannotTargetClientChosenRecords() {
    ClinicalUnitSettings.Preferences settings = (ClinicalUnitSettings.Preferences) JSON.deserialize(
      '{"temperatureUnit":"Cel","measurementSystem":"Metric","developerName":"Other","fullName":"Other_Settings.Other"}',
      ClinicalUnitSettings.Preferences.class
    );
    Metadata.CustomMetadata record = AdminConsoleController.buildClinicalUnitMetadata(
      settings
    );
    String typeApiName = Clinical_Unit_Setting__mdt.SObjectType.getDescribe()
      .getName();
    System.assertEquals(
      typeApiName.substring(0, typeApiName.length() - '__mdt'.length()) +
      '.Default',
      record.fullName,
      'Only the fixed Default record in the package type may be changed'
    );
    System.assertEquals('Default', record.label);
    Map<String, Object> values = new Map<String, Object>();
    for (Metadata.CustomMetadataValue value : record.values) {
      values.put(value.field, value.value);
    }
    System.assertEquals(
      2,
      values.size(),
      'Only the two preference fields may be deployed'
    );
    System.assertEquals(
      'Cel',
      values.get(
        Clinical_Unit_Setting__mdt.Temperature_Unit__c.getDescribe().getName()
      )
    );
    System.assertEquals(
      'Metric',
      values.get(
        Clinical_Unit_Setting__mdt.Measurement_System__c.getDescribe().getName()
      )
    );
  }

  private static ClinicalUnitSettings.Preferences clinicalPreferences(
    String temperatureUnit,
    String measurementSystem
  ) {
    ClinicalUnitSettings.Preferences settings = new ClinicalUnitSettings.Preferences();
    settings.temperatureUnit = temperatureUnit;
    settings.measurementSystem = measurementSystem;
    return settings;
  }

  private static User settingsRoleUser(String alias, String permissionSetName) {
    Profile profile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Minimum Access - Salesforce'
      LIMIT 1
    ];
    User user = new User(
      Alias = alias,
      LastName = alias,
      Email = alias + '@logicemr.test',
      Username = alias + '.' + Crypto.getRandomInteger() + '@logicemr.test',
      ProfileId = profile.Id,
      TimeZoneSidKey = 'America/New_York',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    insert user;
    insert new PermissionSetAssignment(
      AssigneeId = user.Id,
      PermissionSetId = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = :permissionSetName
        LIMIT 1
      ]
      .Id
    );
    return user;
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
