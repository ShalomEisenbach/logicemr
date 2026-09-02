@IsTest
private class TimelineControllerTest {
    @IsTest
    static void getEventsMergesObjectTypesAndSortsNewestFirst() {
        Patient__c patient = insertPatient('MRN-TL-1');
        Patient__c other = insertPatient('MRN-TL-2');

        Datetime older = Datetime.newInstance(2024, 3, 15, 10, 0, 0);
        Datetime middle = Datetime.newInstance(2024, 6, 1, 12, 0, 0);
        Datetime newer = Datetime.newInstance(2024, 8, 20, 14, 0, 0);
        Datetime newest = Datetime.newInstance(2024, 11, 5, 16, 30, 0);

        Encounter__c encounter = insertEncounter(patient.Id, 'Finished', 'Inpatient', older, 'Chest pain');
        Condition__c condition = insertCondition(patient.Id, 'Type 2 diabetes', 'Active', older.date());
        Observation__c observation = insertObservation(patient.Id, 'Heart rate', 88, 'bpm', middle);
        MedicationRequest__c medication = insertMedicationRequest(
            patient.Id,
            'Metformin 500 mg',
            'Active',
            '1 tablet twice daily',
            newer
        );
        Procedure__c procedure = insertProcedure(patient.Id, 'Colonoscopy', 'Completed', 'Diagnostic', newest);

        insertEncounter(other.Id, 'Planned', 'Virtual', newest, 'Other patient');
        insertCondition(other.Id, 'Asthma', 'Active', newest.date());
        insertObservation(other.Id, 'Temperature', 98.6, 'F', newest);
        insertMedicationRequest(other.Id, 'Albuterol', 'Active', '2 puffs', newest);
        insertProcedure(other.Id, 'X-ray', 'Completed', 'Diagnostic', newest);

        Test.startTest();
        List<TimelineController.TimelineEvent> events = TimelineController.getEvents(patient.Id);
        Test.stopTest();

        System.assertEquals(5, events.size(), 'Should merge one event from each object type for this patient');
        System.assertEquals(procedure.Id, events[0].recordId, 'Newest procedure should be first');
        System.assertEquals('Procedure', events[0].type, 'First event type should be Procedure');
        System.assertEquals(newest, events[0].eventDateTime, 'Procedure date should be Performed_DateTime__c');
        System.assertEquals('Colonoscopy', events[0].title, 'Procedure title should be the display name');
        System.assertEquals(
            'Completed · Diagnostic',
            events[0].subtitle,
            'Procedure subtitle should include status and category'
        );

        System.assertEquals(medication.Id, events[1].recordId, 'Medication request should be second');
        System.assertEquals('MedicationRequest', events[1].type, 'Second event type should be MedicationRequest');
        System.assertEquals(newer, events[1].eventDateTime, 'Medication date should be Authored_On__c');
        System.assertEquals('Metformin 500 mg', events[1].title, 'Medication title should be the display name');
        System.assertEquals(
            'Active · 1 tablet twice daily',
            events[1].subtitle,
            'Medication subtitle should include status and dosage'
        );

        System.assertEquals(observation.Id, events[2].recordId, 'Observation should be third');
        System.assertEquals('Observation', events[2].type, 'Third event type should be Observation');
        System.assertEquals(middle, events[2].eventDateTime, 'Observation date should be Effective_DateTime__c');
        System.assertEquals('Heart rate', events[2].title, 'Observation title should be the display name');
        System.assertEquals(
            '88 bpm · Final',
            events[2].subtitle,
            'Observation subtitle should include value, unit, and status'
        );

        Set<Id> olderIds = new Set<Id>{ encounter.Id, condition.Id };
        System.assertEquals(true, olderIds.contains(events[3].recordId), 'Fourth event should be encounter or condition');
        System.assertEquals(true, olderIds.contains(events[4].recordId), 'Fifth event should be the remaining older row');
        System.assertEquals(false, events[3].recordId == events[4].recordId, 'Older events should be distinct');

        Map<Id, TimelineController.TimelineEvent> byId = new Map<Id, TimelineController.TimelineEvent>();
        for (TimelineController.TimelineEvent event : events) {
            byId.put(event.recordId, event);
        }

        TimelineController.TimelineEvent encounterEvent = byId.get(encounter.Id);
        System.assertEquals('Encounter', encounterEvent.type, 'Encounter type should be set');
        System.assertEquals(older, encounterEvent.eventDateTime, 'Encounter date should be Start__c');
        System.assertEquals('Chest pain', encounterEvent.title, 'Encounter title should prefer chief complaint');
        System.assertEquals(
            'Finished · Inpatient',
            encounterEvent.subtitle,
            'Encounter subtitle should include status and class'
        );

        TimelineController.TimelineEvent conditionEvent = byId.get(condition.Id);
        System.assertEquals('Condition', conditionEvent.type, 'Condition type should be set');
        System.assertEquals(
            Datetime.newInstance(older.date(), Time.newInstance(0, 0, 0, 0)),
            conditionEvent.eventDateTime,
            'Condition date should be Onset_Date__c converted to Datetime'
        );
        System.assertEquals('Type 2 diabetes', conditionEvent.title, 'Condition title should be the diagnosis display');
        System.assertEquals(
            'Active · Problem List Item',
            conditionEvent.subtitle,
            'Condition subtitle should include clinical status and category'
        );
    }

    @IsTest
    static void getEventsReturnsEmptyForBlankOrUnrelatedPatient() {
        Patient__c patient = insertPatient('MRN-TL-3');

        Test.startTest();
        List<TimelineController.TimelineEvent> blankId = TimelineController.getEvents(null);
        List<TimelineController.TimelineEvent> none = TimelineController.getEvents(patient.Id);
        Test.stopTest();

        System.assertEquals(0, blankId.size(), 'Null patient Id should return no events');
        System.assertEquals(0, none.size(), 'A patient with no clinical records should return no events');
    }

    @IsTest
    static void getEventsSortsNullDatesLastAndUsesFallbacks() {
        Patient__c patient = insertPatient('MRN-TL-4');
        Datetime dated = Datetime.newInstance(2025, 2, 1, 9, 0, 0);

        Encounter__c datedEncounter = insertEncounter(patient.Id, 'In Progress', 'Outpatient', dated, null);
        Encounter__c undatedEncounter = insertEncounter(patient.Id, 'Planned', 'Virtual', null, null);
        Observation__c stringObs = new Observation__c(
            Patient__c = patient.Id,
            Category__c = 'Survey',
            Status__c = 'Final',
            Observation_Display__c = 'Pain scale',
            Value_String__c = 'Moderate',
            Effective_DateTime__c = dated.addDays(-1)
        );
        insert stringObs;

        Test.startTest();
        List<TimelineController.TimelineEvent> events = TimelineController.getEvents(patient.Id);
        Test.stopTest();

        System.assertEquals(3, events.size(), 'Should include dated and undated rows');
        System.assertEquals(datedEncounter.Id, events[0].recordId, 'Dated encounter should sort before older and null dates');
        System.assertEquals('Outpatient', events[0].title, 'Encounter without reason should fall back to class');
        System.assertEquals(stringObs.Id, events[1].recordId, 'Observation should be second');
        System.assertEquals(
            'Moderate · Final',
            events[1].subtitle,
            'Observation without quantity should use the string value'
        );
        System.assertEquals(undatedEncounter.Id, events[2].recordId, 'Null dates should sort last');
        System.assertEquals(null, events[2].eventDateTime, 'Undated encounter should keep a null event date');
    }

    private static Patient__c insertPatient(String mrn) {
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'Timeline');
        insert patient;
        return patient;
    }

    private static Encounter__c insertEncounter(
        Id patientId,
        String status,
        String encounterClass,
        Datetime startTime,
        String reason
    ) {
        Encounter__c encounter = new Encounter__c(
            Patient__c = patientId,
            Status__c = status,
            Class__c = encounterClass,
            Start__c = startTime,
            Reason__c = reason
        );
        insert encounter;
        return encounter;
    }

    private static Condition__c insertCondition(Id patientId, String display, String clinicalStatus, Date onset) {
        Condition__c condition = new Condition__c(
            Patient__c = patientId,
            Diagnosis_Display__c = display,
            Clinical_Status__c = clinicalStatus,
            Category__c = 'Problem List Item',
            Onset_Date__c = onset
        );
        insert condition;
        return condition;
    }

    private static Observation__c insertObservation(
        Id patientId,
        String display,
        Decimal quantity,
        String unit,
        Datetime effective
    ) {
        Observation__c observation = new Observation__c(
            Patient__c = patientId,
            Observation_Display__c = display,
            Category__c = 'Vital Signs',
            Status__c = 'Final',
            Value_Quantity__c = quantity,
            Value_Unit__c = unit,
            Effective_DateTime__c = effective
        );
        insert observation;
        return observation;
    }

    private static MedicationRequest__c insertMedicationRequest(
        Id patientId,
        String display,
        String status,
        String dosage,
        Datetime authoredOn
    ) {
        MedicationRequest__c request = new MedicationRequest__c(
            Patient__c = patientId,
            Medication_Display__c = display,
            Status__c = status,
            Dosage_Text__c = dosage,
            Authored_On__c = authoredOn
        );
        insert request;
        return request;
    }

    private static Procedure__c insertProcedure(
        Id patientId,
        String display,
        String status,
        String category,
        Datetime performed
    ) {
        Procedure__c procedure = new Procedure__c(
            Patient__c = patientId,
            Procedure_Display__c = display,
            Status__c = status,
            Category__c = category,
            Performed_DateTime__c = performed
        );
        insert procedure;
        return procedure;
    }
}
