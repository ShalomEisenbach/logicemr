public with sharing class AdminConsoleController {
    private static final String MANAGE_SETTINGS_PERMISSION = 'LogicEMR_Manage_Settings';
    public static final String REMINDER_JOB_NAME = AppointmentReminderInvocable.JOB_NAME;
    public static final String ELIGIBILITY_JOB_NAME = 'Eligibility Re-verify';
    public static final String DEFAULT_ELIGIBILITY_CRON = '0 0 2 * * ?';
    public static final String STEDI_NAMED_CREDENTIAL = 'Stedi_Eligibility';
    public static final String DEFAULT_TWILIO_NAMED_CREDENTIAL = 'LogicEMR_Twilio';

    @TestVisible
    static Boolean manageSettingsOverride;

    @TestVisible
    static Boolean skipMetadataDeploy;

    @TestVisible
    static String lastDeployRequestId;

    public class OverviewPayload {
        @AuraEnabled
        public Boolean stediNamedCredentialPresent;
        @AuraEnabled
        public Boolean twilioNamedCredentialPresent;
        @AuraEnabled
        public String twilioNamedCredentialExpected;
        @AuraEnabled
        public JobStatus reminderJob;
        @AuraEnabled
        public JobStatus eligibilityJob;
        @AuraEnabled
        public Integer practitionersMissingUser;
        @AuraEnabled
        public Integer activeNoteTemplates;
        @AuraEnabled
        public Integer codeCatalogCount;
        @AuraEnabled
        public EligibilitySettingDto eligibilitySetting;
        @AuraEnabled
        public CommConfigDto commConfig;
        @AuraEnabled
        public List<MessageTemplateDto> messageTemplates;
        @AuraEnabled
        public List<NameFormatDto> nameFormats;
        @AuraEnabled
        public String stediSetupHint;
        @AuraEnabled
        public String twilioSetupHint;
    }

    public class JobStatus {
        @AuraEnabled
        public String jobName;
        @AuraEnabled
        public Boolean scheduled;
        @AuraEnabled
        public Id cronTriggerId;
        @AuraEnabled
        public String cronExpression;
        @AuraEnabled
        public String nextFireTime;
    }

    public class EligibilitySettingDto {
        @AuraEnabled
        public String developerName;
        @AuraEnabled
        public String masterLabel;
        @AuraEnabled
        public String providerName;
        @AuraEnabled
        public String namedCredential;
        @AuraEnabled
        public String defaultServiceType;
        @AuraEnabled
        public Boolean active;
    }

    public class CommConfigDto {
        @AuraEnabled
        public String developerName;
        @AuraEnabled
        public String masterLabel;
        @AuraEnabled
        public Boolean emailEnabled;
        @AuraEnabled
        public Boolean smsEnabled;
        @AuraEnabled
        public Boolean autoSendConfirmation;
        @AuraEnabled
        public Boolean autoSendReminder;
        @AuraEnabled
        public Decimal reminderHoursBefore;
        @AuraEnabled
        public String twilioNamedCredential;
        @AuraEnabled
        public String twilioAccountSid;
        @AuraEnabled
        public String twilioFromNumber;
        @AuraEnabled
        public String orgWideEmailAddress;
    }

    public class MessageTemplateDto {
        @AuraEnabled
        public String developerName;
        @AuraEnabled
        public String masterLabel;
        @AuraEnabled
        public String typeValue;
        @AuraEnabled
        public String channel;
        @AuraEnabled
        public String subject;
        @AuraEnabled
        public String body;
        @AuraEnabled
        public Boolean active;
    }

    public class NameFormatDto {
        @AuraEnabled
        public String developerName;
        @AuraEnabled
        public String masterLabel;
        @AuraEnabled
        public String objectApiName;
        @AuraEnabled
        public String formatPattern;
        @AuraEnabled
        public Boolean active;
    }

    public class PractitionerRow {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String firstName;
        @AuraEnabled
        public String lastName;
        @AuraEnabled
        public String npi;
        @AuraEnabled
        public Id userId;
        @AuraEnabled
        public String userName;
    }

    public class PractitionerUserUpdate {
        @AuraEnabled
        public Id practitionerId { get; set; }
        @AuraEnabled
        public Id userId { get; set; }
    }

    public class ActionResult {
        @AuraEnabled
        public Boolean success;
        @AuraEnabled
        public String message;
        @AuraEnabled
        public Id jobId;
        @AuraEnabled
        public String deployRequestId;
    }

    public class CatalogLinkOption {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String objectApiName;
        @AuraEnabled
        public String codeSystemField;
        @AuraEnabled
        public String codeField;
        @AuraEnabled
        public String lookupField;
    }

    @AuraEnabled(cacheable=true)
    public static OverviewPayload getOverview() {
        requireManageSettings();
        OverviewPayload payload = new OverviewPayload();
        CommConfigDto comm = loadCommConfig();
        payload.commConfig = comm;
        payload.twilioNamedCredentialExpected = String.isNotBlank(comm.twilioNamedCredential)
            ? comm.twilioNamedCredential
            : DEFAULT_TWILIO_NAMED_CREDENTIAL;
        Set<String> presentCredentials = queryNamedCredentialNames(
            new Set<String>{ STEDI_NAMED_CREDENTIAL, payload.twilioNamedCredentialExpected }
        );
        payload.stediNamedCredentialPresent = presentCredentials.contains(STEDI_NAMED_CREDENTIAL);
        payload.twilioNamedCredentialPresent = presentCredentials.contains(
            payload.twilioNamedCredentialExpected
        );
        payload.reminderJob = loadJobStatus(REMINDER_JOB_NAME);
        payload.eligibilityJob = loadJobStatus(ELIGIBILITY_JOB_NAME);
        payload.practitionersMissingUser = [
            SELECT COUNT()
            FROM Practitioner__c
            WHERE User__c = NULL
        ];
        payload.activeNoteTemplates = [
            SELECT COUNT()
            FROM NoteTemplate__c
            WHERE Active__c = TRUE
        ];
        payload.codeCatalogCount = [SELECT COUNT() FROM Code_Reference__c];
        payload.eligibilitySetting = loadEligibilitySetting();
        payload.messageTemplates = loadMessageTemplates();
        payload.nameFormats = loadNameFormats();
        payload.stediSetupHint =
            'Setup → Named Credentials → External Credentials → Stedi Eligibility. ' +
            'Create or edit principal Stedi_API with authentication parameter ApiKey = your Stedi API key. ' +
            'Then grant Stedi_Eligibility-Stedi_API on LogicEMR Admin, Clinician, and Billing permission sets.';
        payload.twilioSetupHint =
            'Create Named Credential ' +
            payload.twilioNamedCredentialExpected +
            ' (URL https://api.twilio.com, Password Authentication, Username = Account SID, ' +
            'Password = Auth Token, Generate Authorization Header enabled). ' +
            'Then set SMS Enabled, Account SID, and From Number on Communications.';
        return payload;
    }

    @AuraEnabled(cacheable=true)
    public static List<NoteTemplate__c> getNoteTemplates() {
        requireManageSettings();
        return [
            SELECT Id, Name, Shortcut__c, Category__c, Body__c, Active__c, LastModifiedDate
            FROM NoteTemplate__c
            ORDER BY Name ASC
            LIMIT 200
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<PractitionerRow> getPractitioners() {
        requireManageSettings();
        List<PractitionerRow> rows = new List<PractitionerRow>();
        for (Practitioner__c practitioner : [
            SELECT
                Id,
                Name,
                First_Name__c,
                Last_Name__c,
                NPI__c,
                User__c,
                User__r.Name
            FROM Practitioner__c
            ORDER BY Last_Name__c ASC NULLS LAST, First_Name__c ASC NULLS LAST
            LIMIT 500
        ]) {
            PractitionerRow row = new PractitionerRow();
            row.id = practitioner.Id;
            row.name = practitioner.Name;
            row.firstName = practitioner.First_Name__c;
            row.lastName = practitioner.Last_Name__c;
            row.npi = practitioner.NPI__c;
            row.userId = practitioner.User__c;
            row.userName = practitioner.User__r != null ? practitioner.User__r.Name : null;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static Integer savePractitionerUsers(List<PractitionerUserUpdate> updates) {
        requireManageSettings();
        if (updates == null || updates.isEmpty()) {
            return 0;
        }
        Map<Id, Id> userByPractitioner = new Map<Id, Id>();
        for (PractitionerUserUpdate row : updates) {
            if (row == null || row.practitionerId == null) {
                continue;
            }
            userByPractitioner.put(row.practitionerId, row.userId);
        }
        if (userByPractitioner.isEmpty()) {
            return 0;
        }
        List<Practitioner__c> toUpdate = new List<Practitioner__c>();
        for (Practitioner__c practitioner : [
            SELECT Id, User__c
            FROM Practitioner__c
            WHERE Id IN :userByPractitioner.keySet()
        ]) {
            Id nextUserId = userByPractitioner.get(practitioner.Id);
            if (practitioner.User__c != nextUserId) {
                toUpdate.add(new Practitioner__c(Id = practitioner.Id, User__c = nextUserId));
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        return toUpdate.size();
    }

    @AuraEnabled
    public static ActionResult saveEligibilitySetting(EligibilitySettingDto setting) {
        requireManageSettings();
        if (setting == null || String.isBlank(setting.developerName)) {
            throw auraError('Eligibility setting developer name is required.');
        }
        Metadata.CustomMetadata record = new Metadata.CustomMetadata();
        record.fullName = customMetadataFullName('Eligibility_Setting__mdt', setting.developerName);
        record.label = String.isNotBlank(setting.masterLabel) ? setting.masterLabel : setting.developerName;
        addValue(record, namespacedField('Provider_Name__c'), setting.providerName);
        addValue(record, namespacedField('Named_Credential__c'), setting.namedCredential);
        addValue(record, namespacedField('Default_Service_Type__c'), setting.defaultServiceType);
        addValue(record, namespacedField('Active__c'), setting.active == true);
        return enqueueMetadata(new List<Metadata.CustomMetadata>{ record });
    }

    @AuraEnabled
    public static ActionResult saveCommConfig(CommConfigDto config) {
        requireManageSettings();
        if (config == null || String.isBlank(config.developerName)) {
            throw auraError('Communications config developer name is required.');
        }
        Metadata.CustomMetadata record = new Metadata.CustomMetadata();
        record.fullName = customMetadataFullName('Appointment_Comm_Config__mdt', config.developerName);
        record.label = String.isNotBlank(config.masterLabel) ? config.masterLabel : config.developerName;
        addValue(record, namespacedField('Email_Enabled__c'), config.emailEnabled == true);
        addValue(record, namespacedField('SMS_Enabled__c'), config.smsEnabled == true);
        addValue(record, namespacedField('Auto_Send_Confirmation__c'), config.autoSendConfirmation == true);
        addValue(record, namespacedField('Auto_Send_Reminder__c'), config.autoSendReminder == true);
        addValue(
            record,
            namespacedField('Reminder_Hours_Before__c'),
            config.reminderHoursBefore == null ? 24 : config.reminderHoursBefore
        );
        addValue(record, namespacedField('Twilio_Named_Credential__c'), config.twilioNamedCredential);
        addValue(record, namespacedField('Twilio_Account_Sid__c'), config.twilioAccountSid);
        addValue(record, namespacedField('Twilio_From_Number__c'), config.twilioFromNumber);
        addValue(record, namespacedField('Org_Wide_Email_Address__c'), config.orgWideEmailAddress);
        return enqueueMetadata(new List<Metadata.CustomMetadata>{ record });
    }

    @AuraEnabled
    public static ActionResult saveMessageTemplate(MessageTemplateDto template) {
        requireManageSettings();
        if (template == null || String.isBlank(template.developerName)) {
            throw auraError('Message template developer name is required.');
        }
        Metadata.CustomMetadata record = new Metadata.CustomMetadata();
        record.fullName = customMetadataFullName(
            'Appointment_Message_Template__mdt',
            template.developerName
        );
        record.label = String.isNotBlank(template.masterLabel)
            ? template.masterLabel
            : template.developerName;
        addValue(record, namespacedField('Type__c'), template.typeValue);
        addValue(record, namespacedField('Channel__c'), template.channel);
        addValue(record, namespacedField('Subject__c'), template.subject);
        addValue(record, namespacedField('Body__c'), template.body);
        addValue(record, namespacedField('Active__c'), template.active == true);
        return enqueueMetadata(new List<Metadata.CustomMetadata>{ record });
    }

    @AuraEnabled
    public static ActionResult saveNameFormat(NameFormatDto nameFormat) {
        requireManageSettings();
        if (nameFormat == null || String.isBlank(nameFormat.developerName)) {
            throw auraError('Name format developer name is required.');
        }
        Metadata.CustomMetadata record = new Metadata.CustomMetadata();
        record.fullName = customMetadataFullName('Name_Format__mdt', nameFormat.developerName);
        record.label = String.isNotBlank(nameFormat.masterLabel)
            ? nameFormat.masterLabel
            : nameFormat.developerName;
        addValue(record, namespacedField('Object_API_Name__c'), nameFormat.objectApiName);
        addValue(record, namespacedField('Format__c'), nameFormat.formatPattern);
        addValue(record, namespacedField('Active__c'), nameFormat.active == true);
        return enqueueMetadata(new List<Metadata.CustomMetadata>{ record });
    }

    @AuraEnabled
    public static ActionResult scheduleReminderJob(String cronExpression) {
        requireManageSettings();
        AppointmentReminderInvocable.Request request = new AppointmentReminderInvocable.Request();
        request.cronExpression = String.isNotBlank(cronExpression)
            ? cronExpression
            : AppointmentReminderInvocable.DEFAULT_CRON;
        List<AppointmentReminderInvocable.Result> results = AppointmentReminderInvocable.scheduleReminders(
            new List<AppointmentReminderInvocable.Request>{ request }
        );
        AppointmentReminderInvocable.Result result = results[0];
        ActionResult action = new ActionResult();
        action.success = result.success == true;
        action.message = result.message;
        action.jobId = result.jobId;
        if (action.success != true) {
            throw auraError(String.isNotBlank(action.message) ? action.message : 'Failed to schedule reminder job.');
        }
        return action;
    }

    @AuraEnabled
    public static ActionResult abortReminderJob() {
        requireManageSettings();
        return abortJobByName(REMINDER_JOB_NAME);
    }

    @AuraEnabled
    public static ActionResult scheduleEligibilityJob(String cronExpression) {
        requireManageSettings();
        List<CronTrigger> existing = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :ELIGIBILITY_JOB_NAME
            LIMIT 1
        ];
        ActionResult action = new ActionResult();
        if (!existing.isEmpty()) {
            action.success = true;
            action.jobId = existing[0].Id;
            action.message = 'Eligibility re-verify job is already scheduled.';
            return action;
        }
        String cron = String.isNotBlank(cronExpression) ? cronExpression : DEFAULT_ELIGIBILITY_CRON;
        try {
            action.jobId = System.schedule(ELIGIBILITY_JOB_NAME, cron, new EligibilityBatch());
            action.success = true;
            action.message = 'Eligibility re-verify job scheduled.';
            return action;
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    @AuraEnabled
    public static ActionResult abortEligibilityJob() {
        requireManageSettings();
        return abortJobByName(ELIGIBILITY_JOB_NAME);
    }

    @AuraEnabled
    public static ActionResult runEligibilityNow(Integer lookaheadDays) {
        requireManageSettings();
        try {
            ActionResult action = new ActionResult();
            action.jobId = EligibilityBatch.run(lookaheadDays);
            action.success = true;
            action.message = 'Eligibility re-verify batch queued.';
            return action;
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    @AuraEnabled
    public static ActionResult enqueueNameBackfill(String objectApiName) {
        requireManageSettings();
        if (String.isBlank(objectApiName)) {
            throw auraError('Object API name is required for name backfill.');
        }
        try {
            ActionResult action = new ActionResult();
            action.jobId = Database.executeBatch(new NameBackfillBatch(objectApiName));
            action.success = true;
            action.message = 'Name backfill queued for ' + objectApiName + '.';
            return action;
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    @AuraEnabled
    public static ActionResult enqueueCatalogLinkBackfill(
        String objectApiName,
        String codeSystemField,
        String codeField,
        String lookupField
    ) {
        requireManageSettings();
        if (
            String.isBlank(objectApiName) ||
            String.isBlank(codeSystemField) ||
            String.isBlank(codeField) ||
            String.isBlank(lookupField)
        ) {
            throw auraError('Object and field API names are required for catalog link backfill.');
        }
        try {
            ActionResult action = new ActionResult();
            action.jobId = Database.executeBatch(
                new CatalogLinkBackfillBatch(objectApiName, codeSystemField, codeField, lookupField)
            );
            action.success = true;
            action.message = 'Catalog link backfill queued for ' + objectApiName + '.';
            return action;
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getNameBackfillObjects() {
        requireManageSettings();
        return new List<String>{
            'Patient__c',
            'Encounter__c',
            'Condition__c',
            'EncounterDiagnosis__c',
            'Observation__c',
            'AllergyIntolerance__c',
            'Immunization__c',
            'MedicationRequest__c',
            'MedicationStatement__c',
            'MedicationAdministration__c',
            'ServiceRequest__c',
            'DiagnosticReport__c',
            'Procedure__c',
            'ClinicalNote__c',
            'CareTeam__c',
            'CareTeamMember__c',
            'Practitioner__c',
            'Appointment__c',
            'Coverage__c'
        };
    }

    @AuraEnabled(cacheable=true)
    public static List<CatalogLinkOption> getCatalogLinkOptions() {
        requireManageSettings();
        List<CatalogLinkOption> options = new List<CatalogLinkOption>();
        options.add(
            catalogOption(
                'Condition (Diagnosis)',
                'Condition__c',
                'Diagnosis_Code_System__c',
                'Diagnosis_Code__c',
                'Diagnosis_Ref__c'
            )
        );
        options.add(
            catalogOption(
                'Observation',
                'Observation__c',
                'Observation_Code_System__c',
                'Observation_Code__c',
                'Observation_Ref__c'
            )
        );
        options.add(
            catalogOption(
                'Allergy Intolerance',
                'AllergyIntolerance__c',
                'Allergen_Code_System__c',
                'Allergen_Code__c',
                'Allergen_Ref__c'
            )
        );
        options.add(
            catalogOption(
                'Immunization',
                'Immunization__c',
                'Vaccine_Code_System__c',
                'Vaccine_Code__c',
                'Vaccine_Ref__c'
            )
        );
        options.add(
            catalogOption(
                'Medication Request',
                'MedicationRequest__c',
                'Medication_Code_System__c',
                'Medication_Code__c',
                'Medication_Ref__c'
            )
        );
        options.add(
            catalogOption(
                'Medication Statement',
                'MedicationStatement__c',
                'Medication_Code_System__c',
                'Medication_Code__c',
                'Medication_Ref__c'
            )
        );
        options.add(
            catalogOption(
                'Service Request',
                'ServiceRequest__c',
                'Service_Code_System__c',
                'Service_Code__c',
                'Service_Ref__c'
            )
        );
        options.add(
            catalogOption(
                'Diagnostic Report',
                'DiagnosticReport__c',
                'Report_Code_System__c',
                'Report_Code__c',
                'Report_Ref__c'
            )
        );
        options.add(
            catalogOption(
                'Procedure',
                'Procedure__c',
                'Procedure_Code_System__c',
                'Procedure_Code__c',
                'Procedure_Ref__c'
            )
        );
        return options;
    }

    private static CatalogLinkOption catalogOption(
        String label,
        String objectApiName,
        String codeSystemField,
        String codeField,
        String lookupField
    ) {
        CatalogLinkOption option = new CatalogLinkOption();
        option.label = label;
        option.objectApiName = objectApiName;
        option.codeSystemField = codeSystemField;
        option.codeField = codeField;
        option.lookupField = lookupField;
        return option;
    }

    private static ActionResult abortJobByName(String jobName) {
        List<CronTrigger> existing = [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name = :jobName
            LIMIT 1
        ];
        ActionResult action = new ActionResult();
        if (existing.isEmpty()) {
            action.success = true;
            action.message = jobName + ' is not scheduled.';
            return action;
        }
        System.abortJob(existing[0].Id);
        action.success = true;
        action.jobId = existing[0].Id;
        action.message = jobName + ' aborted.';
        return action;
    }

    private static ActionResult enqueueMetadata(List<Metadata.CustomMetadata> records) {
        ActionResult action = new ActionResult();
        if (skipMetadataDeploy == true) {
            action.success = true;
            action.message = 'Custom metadata deploy skipped in test.';
            action.deployRequestId = 'TEST_DEPLOY';
            lastDeployRequestId = action.deployRequestId;
            return action;
        }
        Metadata.DeployContainer container = new Metadata.DeployContainer();
        for (Metadata.CustomMetadata record : records) {
            container.addMetadata(record);
        }
        try {
            Id requestId = Metadata.Operations.enqueueDeployment(
                container,
                new AdminConsoleDeployCallback()
            );
            lastDeployRequestId = String.valueOf(requestId);
            action.success = true;
            action.deployRequestId = String.valueOf(requestId);
            action.message =
                'Custom metadata deploy queued. Refresh Overview after the deploy finishes. ' +
                'Requires Customize Application.';
            return action;
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    private static void addValue(Metadata.CustomMetadata record, String fieldApiName, Object value) {
        Metadata.CustomMetadataValue fieldValue = new Metadata.CustomMetadataValue();
        fieldValue.field = fieldApiName;
        fieldValue.value = value;
        record.values.add(fieldValue);
    }

    private static String customMetadataFullName(String objectApiName, String developerName) {
        String typeName = stripSuffix(objectApiName, '__mdt');
        String localType = stripNamespace(typeName);
        String ns = packageNamespace();
        String typeFull = String.isNotBlank(ns) ? ns + '__' + localType : localType;
        return typeFull + '.' + developerName;
    }

    private static String namespacedField(String fieldApiName) {
        String localField = stripNamespace(fieldApiName);
        String ns = packageNamespace();
        if (String.isBlank(ns) || localField.endsWith('__c') == false) {
            return localField;
        }
        // Already namespaced? e.g. lfemr__Email_Enabled__c has two __ segments before trailing __c
        if (localField.countMatches('__') >= 2) {
            return localField;
        }
        return ns + '__' + localField;
    }

    private static String packageNamespace() {
        String packagedName = Name_Format__mdt.SObjectType.getDescribe().getName();
        return packagedName.countMatches('__') >= 2 ? packagedName.substringBefore('__') : '';
    }

    private static String stripNamespace(String apiName) {
        if (String.isBlank(apiName)) {
            return apiName;
        }
        String working = apiName;
        if (working.endsWith('__c') || working.endsWith('__mdt')) {
            String suffix = working.endsWith('__mdt') ? '__mdt' : '__c';
            String withoutSuffix = working.substring(0, working.length() - suffix.length());
            if (withoutSuffix.contains('__')) {
                return withoutSuffix.substringAfterLast('__') + suffix;
            }
            return working;
        }
        if (working.contains('__')) {
            return working.substringAfterLast('__');
        }
        return working;
    }

    private static String stripSuffix(String value, String suffix) {
        if (String.isBlank(value) || String.isBlank(suffix) || !value.endsWith(suffix)) {
            return value;
        }
        return value.substring(0, value.length() - suffix.length());
    }

    private static Set<String> queryNamedCredentialNames(Set<String> developerNames) {
        Set<String> present = new Set<String>();
        if (developerNames == null || developerNames.isEmpty()) {
            return present;
        }
        try {
            for (NamedCredential credential : [
                SELECT DeveloperName
                FROM NamedCredential
                WHERE DeveloperName IN :developerNames
            ]) {
                present.add(credential.DeveloperName);
            }
        } catch (Exception e) {
            // View Setup may be missing; treat as absent.
        }
        return present;
    }

    private static JobStatus loadJobStatus(String jobName) {
        JobStatus status = new JobStatus();
        status.jobName = jobName;
        status.scheduled = false;
        List<CronTrigger> rows = [
            SELECT Id, CronExpression, NextFireTime, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name = :jobName
            LIMIT 1
        ];
        if (!rows.isEmpty()) {
            status.scheduled = true;
            status.cronTriggerId = rows[0].Id;
            status.cronExpression = rows[0].CronExpression;
            status.nextFireTime = rows[0].NextFireTime == null
                ? null
                : String.valueOf(rows[0].NextFireTime);
        }
        return status;
    }

    private static EligibilitySettingDto loadEligibilitySetting() {
        List<Eligibility_Setting__mdt> rows = [
            SELECT
                DeveloperName,
                MasterLabel,
                Provider_Name__c,
                Named_Credential__c,
                Default_Service_Type__c,
                Active__c
            FROM Eligibility_Setting__mdt
            WHERE Active__c = TRUE
            ORDER BY Provider_Name__c ASC
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            rows = [
                SELECT
                    DeveloperName,
                    MasterLabel,
                    Provider_Name__c,
                    Named_Credential__c,
                    Default_Service_Type__c,
                    Active__c
                FROM Eligibility_Setting__mdt
                ORDER BY DeveloperName ASC
                LIMIT 1
            ];
        }
        if (rows.isEmpty()) {
            return null;
        }
        Eligibility_Setting__mdt row = rows[0];
        EligibilitySettingDto dto = new EligibilitySettingDto();
        dto.developerName = row.DeveloperName;
        dto.masterLabel = row.MasterLabel;
        dto.providerName = row.Provider_Name__c;
        dto.namedCredential = row.Named_Credential__c;
        dto.defaultServiceType = row.Default_Service_Type__c;
        dto.active = row.Active__c;
        return dto;
    }

    private static CommConfigDto loadCommConfig() {
        List<Appointment_Comm_Config__mdt> rows = [
            SELECT
                DeveloperName,
                MasterLabel,
                Email_Enabled__c,
                SMS_Enabled__c,
                Auto_Send_Confirmation__c,
                Auto_Send_Reminder__c,
                Reminder_Hours_Before__c,
                Twilio_Named_Credential__c,
                Twilio_Account_Sid__c,
                Twilio_From_Number__c,
                Org_Wide_Email_Address__c
            FROM Appointment_Comm_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            rows = [
                SELECT
                    DeveloperName,
                    MasterLabel,
                    Email_Enabled__c,
                    SMS_Enabled__c,
                    Auto_Send_Confirmation__c,
                    Auto_Send_Reminder__c,
                    Reminder_Hours_Before__c,
                    Twilio_Named_Credential__c,
                    Twilio_Account_Sid__c,
                    Twilio_From_Number__c,
                    Org_Wide_Email_Address__c
                FROM Appointment_Comm_Config__mdt
                ORDER BY DeveloperName ASC
                LIMIT 1
            ];
        }
        CommConfigDto dto = new CommConfigDto();
        if (rows.isEmpty()) {
            dto.developerName = 'Default';
            dto.masterLabel = 'Default';
            dto.emailEnabled = true;
            dto.smsEnabled = false;
            dto.autoSendConfirmation = true;
            dto.autoSendReminder = true;
            dto.reminderHoursBefore = 24;
            dto.twilioNamedCredential = DEFAULT_TWILIO_NAMED_CREDENTIAL;
            return dto;
        }
        Appointment_Comm_Config__mdt row = rows[0];
        dto.developerName = row.DeveloperName;
        dto.masterLabel = row.MasterLabel;
        dto.emailEnabled = row.Email_Enabled__c;
        dto.smsEnabled = row.SMS_Enabled__c;
        dto.autoSendConfirmation = row.Auto_Send_Confirmation__c;
        dto.autoSendReminder = row.Auto_Send_Reminder__c;
        dto.reminderHoursBefore = row.Reminder_Hours_Before__c;
        dto.twilioNamedCredential = row.Twilio_Named_Credential__c;
        dto.twilioAccountSid = row.Twilio_Account_Sid__c;
        dto.twilioFromNumber = row.Twilio_From_Number__c;
        dto.orgWideEmailAddress = row.Org_Wide_Email_Address__c;
        return dto;
    }

    private static List<MessageTemplateDto> loadMessageTemplates() {
        List<MessageTemplateDto> templates = new List<MessageTemplateDto>();
        for (Appointment_Message_Template__mdt row : [
            SELECT
                DeveloperName,
                MasterLabel,
                Type__c,
                Channel__c,
                Subject__c,
                Body__c,
                Active__c
            FROM Appointment_Message_Template__mdt
            ORDER BY Type__c ASC, Channel__c ASC
        ]) {
            MessageTemplateDto dto = new MessageTemplateDto();
            dto.developerName = row.DeveloperName;
            dto.masterLabel = row.MasterLabel;
            dto.typeValue = row.Type__c;
            dto.channel = row.Channel__c;
            dto.subject = row.Subject__c;
            dto.body = row.Body__c;
            dto.active = row.Active__c;
            templates.add(dto);
        }
        return templates;
    }

    private static List<NameFormatDto> loadNameFormats() {
        List<NameFormatDto> formats = new List<NameFormatDto>();
        for (Name_Format__mdt row : [
            SELECT DeveloperName, MasterLabel, Object_API_Name__c, Format__c, Active__c
            FROM Name_Format__mdt
            ORDER BY Object_API_Name__c ASC
        ]) {
            NameFormatDto dto = new NameFormatDto();
            dto.developerName = row.DeveloperName;
            dto.masterLabel = row.MasterLabel;
            dto.objectApiName = row.Object_API_Name__c;
            dto.formatPattern = row.Format__c;
            dto.active = row.Active__c;
            formats.add(dto);
        }
        return formats;
    }

    private static void requireManageSettings() {
        Boolean allowed = manageSettingsOverride != null
            ? manageSettingsOverride
            : FeatureManagement.checkPermission(MANAGE_SETTINGS_PERMISSION);
        if (!allowed) {
            throw auraError('You do not have permission to manage LogicEMR settings.');
        }
    }

    private static AuraHandledException auraError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
