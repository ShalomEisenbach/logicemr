@IsTest
private class EligibilityBatchTest {
    @IsTest
    static void batchReverifiesActiveCoverageWithUpcomingAppointment() {
        Fixture data = insertEligibleFixture();
        Coverage__c inactive = insertCoverage(data.patient.Id, data.payer.Id, 'MEM-INACT', 'Inactive');
        Patient__c other = insertPatient('MRN-ELIG-BAT-2');
        Coverage__c farOut = insertCoverage(other.Id, data.payer.Id, 'MEM-FAR', 'Active');
        insertAppointment(other.Id, Datetime.now().addDays(20), 'Booked');
        Patient__c cancelledPatient = insertPatient('MRN-ELIG-BAT-3');
        Coverage__c cancelledCoverage = insertCoverage(cancelledPatient.Id, data.payer.Id, 'MEM-CAN', 'Active');
        insertAppointment(cancelledPatient.Id, Datetime.now().addDays(2), 'Cancelled');

        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{ activeSetting() };
        Test.setMock(HttpCalloutMock.class, new ActiveMock());

        Test.startTest();
        Id jobId = EligibilityBatch.run();
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'run() should enqueue a batch job');
        List<Eligibility_Check__c> checks = [
            SELECT Coverage__c, Status__c, Plan_Name__c, Copay__c
            FROM Eligibility_Check__c
        ];
        System.assertEquals(1, checks.size(), 'Only the upcoming active coverage should be re-verified');
        System.assertEquals(data.coverage.Id, checks[0].Coverage__c, 'Matching coverage should be checked');
        System.assertEquals('Active', checks[0].Status__c, 'Batch should persist the parsed Active result');
        System.assertEquals('Gold Plan HMO', checks[0].Plan_Name__c, 'Parsed plan should be stored');
        System.assertEquals(15, checks[0].Copay__c, 'Parsed copay should be stored');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Eligibility_Check__c WHERE Coverage__c = :inactive.Id],
            'Inactive coverage should be skipped'
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Eligibility_Check__c WHERE Coverage__c = :farOut.Id],
            'Coverage outside the lookahead window should be skipped'
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Eligibility_Check__c WHERE Coverage__c = :cancelledCoverage.Id],
            'Coverage with only a cancelled appointment should be skipped'
        );
        System.assertNotEquals(null, EligibilityBatch.lastSummary, 'Finish should set a summary');
        System.assert(
            EligibilityBatch.lastSummary.contains('processed=1'),
            'Summary should count the successful check: ' + EligibilityBatch.lastSummary
        );
    }

    @IsTest
    static void batchRecordsFailuresWhenSettingMissing() {
        Fixture data = insertEligibleFixture();
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>();

        Test.startTest();
        Database.executeBatch(new EligibilityBatch(7), EligibilityBatch.DEFAULT_BATCH_SIZE);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Eligibility_Check__c WHERE Coverage__c = :data.coverage.Id],
            'A thrown factory error should not persist a check'
        );
        System.assert(
            EligibilityBatch.lastSummary != null && EligibilityBatch.lastSummary.contains('failed=1'),
            'Summary should count the failed coverage: ' + EligibilityBatch.lastSummary
        );
    }

    @IsTest
    static void constructorsDefaultInvalidLookahead() {
        EligibilityBatch fromNull = new EligibilityBatch(null);
        EligibilityBatch fromZero = new EligibilityBatch(0);
        EligibilityBatch fromDefault = new EligibilityBatch();
        EligibilityBatch custom = new EligibilityBatch(14);

        System.assertEquals(7, fromNull.lookaheadDays, 'Null lookahead should default to 7');
        System.assertEquals(7, fromZero.lookaheadDays, 'Lookahead below 1 should default to 7');
        System.assertEquals(7, fromDefault.lookaheadDays, 'No-arg constructor should use 7 days');
        System.assertEquals(14, custom.lookaheadDays, 'Explicit lookahead should be kept');
    }

    @IsTest
    static void schedulableEnqueuesBatch() {
        EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{ activeSetting() };

        Test.startTest();
        new EligibilityBatch().execute((SchedulableContext) null);
        Test.stopTest();

        System.assertNotEquals(null, EligibilityBatch.lastSummary, 'Schedulable should run the batch to finish');
        System.assert(
            EligibilityBatch.lastSummary.contains('processed=0'),
            'Empty org should finish with zero processed: ' + EligibilityBatch.lastSummary
        );
    }

    private static Fixture insertEligibleFixture() {
        Fixture data = new Fixture();
        data.patient = insertPatient('MRN-ELIG-BAT-1');
        data.payer = new Payer__c(
            Name = 'Aetna',
            Type__c = 'Commercial',
            Active__c = true,
            Payer_Identifier__c = '60054'
        );
        insert data.payer;
        data.coverage = insertCoverage(data.patient.Id, data.payer.Id, 'MEM-BAT-100', 'Active');
        insertAppointment(data.patient.Id, Datetime.now().addDays(2), 'Booked');
        insert new Practitioner__c(
            First_Name__c = 'Ada',
            Last_Name__c = 'Lovelace',
            NPI__c = '1234567893',
            Active__c = true
        );
        return data;
    }

    private static Patient__c insertPatient(String mrn) {
        Patient__c patient = new Patient__c(
            First_Name__c = 'Pat',
            Last_Name__c = 'Batch',
            Date_of_Birth__c = Date.newInstance(1975, 4, 1),
            MRN__c = mrn,
            Status__c = 'Active'
        );
        insert patient;
        return patient;
    }

    private static Coverage__c insertCoverage(Id patientId, Id payerId, String memberId, String status) {
        Coverage__c coverage = new Coverage__c(
            Patient__c = patientId,
            Payer__c = payerId,
            Member_Id__c = memberId,
            Type__c = 'Medical',
            Status__c = status,
            Priority__c = 'Primary'
        );
        insert coverage;
        return coverage;
    }

    private static Appointment__c insertAppointment(Id patientId, Datetime startAt, String status) {
        AppointmentCommunicationHandler.bypass = true;
        Appointment__c appointment = new Appointment__c(
            Patient__c = patientId,
            Start__c = startAt,
            End__c = startAt.addMinutes(30),
            Status__c = status,
            Appointment_Type__c = 'Routine'
        );
        insert appointment;
        AppointmentCommunicationHandler.bypass = false;
        return appointment;
    }

    private static Eligibility_Setting__mdt activeSetting() {
        return new Eligibility_Setting__mdt(
            Provider_Name__c = 'Stedi',
            Named_Credential__c = 'Stedi_Eligibility',
            Default_Service_Type__c = '30',
            Active__c = true
        );
    }

    private class Fixture {
        Patient__c patient;
        Payer__c payer;
        Coverage__c coverage;
    }

    private class ActiveMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            System.assert(request.getEndpoint().startsWith('callout:'), request.getEndpoint());
            System.assertEquals(null, request.getHeader('Authorization'));
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody(
                '{"benefitsInformation":[' +
                    '{"code":"1","name":"Active Coverage","planCoverage":"Gold Plan HMO","serviceTypeCodes":["30"]},' +
                    '{"code":"B","benefitAmount":"15","inPlanNetworkIndicatorCode":"Y","serviceTypeCodes":["30"]}' +
                    ']}'
            );
            return response;
        }
    }
}
