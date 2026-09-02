@IsTest
private class FlowsheetControllerTest {
    @IsTest
    static void getDataGroupsDistinctObservationsIntoRowsAndTimeColumns() {
        Patient__c patient = insertPatient('MRN-FS-1');
        Datetime newer = Datetime.now().addHours(-2);
        Datetime older = Datetime.now().addHours(-10);

        Observation__c newerHr = insertObservation(
            patient.Id,
            'Vital Signs',
            '8867-4',
            'Heart rate',
            110,
            null,
            '/min',
            'High',
            newer
        );
        Observation__c olderHr = insertObservation(
            patient.Id,
            'Vital Signs',
            '8867-4',
            'Heart rate',
            70,
            null,
            '/min',
            'Normal',
            older
        );
        Observation__c temp = insertObservation(
            patient.Id,
            'Vital Signs',
            '8310-5',
            'Body temperature',
            38.50,
            null,
            'Cel',
            'High',
            newer
        );
        insertObservation(
            patient.Id,
            'Laboratory',
            '2345-7',
            'Glucose',
            180,
            null,
            'mg/dL',
            'High',
            newer
        );
        insertObservation(
            patient.Id,
            'Imaging',
            '36643-5',
            'Chest X-ray',
            null,
            'Normal',
            null,
            'Normal',
            newer
        );

        Test.startTest();
        FlowsheetController.FlowsheetData vitals = FlowsheetController.getData(
            patient.Id,
            'Vitals',
            '7d'
        );
        Test.stopTest();

        System.assertEquals(3, vitals.observations.size(), 'Vitals query should exclude labs and imaging');
        System.assertEquals(2, vitals.columns.size(), 'Distinct effective times should become columns');
        System.assertEquals(
            newer.getTime(),
            vitals.columns[0].effectiveDateTime.getTime(),
            'Most recent time point should be the first column'
        );
        System.assertEquals(
            older.getTime(),
            vitals.columns[1].effectiveDateTime.getTime(),
            'Older time point should follow'
        );
        System.assertEquals(2, vitals.rows.size(), 'Heart rate and temperature should be distinct rows');
        System.assertEquals(
            'Body temperature',
            vitals.rows[0].display,
            'Rows should sort by display name'
        );
        System.assertEquals('8310-5', vitals.rows[0].code, 'Row should expose observation code');
        System.assertEquals('Heart rate', vitals.rows[1].display, 'Second row should be heart rate');
        System.assertEquals(2, vitals.rows[0].cells.size(), 'Each row should have a cell per column');
        System.assertEquals('38.5', vitals.rows[0].cells[0].value, 'Quantity should drop trailing zeros');
        System.assertEquals('Cel', vitals.rows[0].cells[0].unit, 'Cell should include unit');
        System.assertEquals('High', vitals.rows[0].cells[0].interpretation, 'Cell should include interpretation');
        System.assertEquals(temp.Id, vitals.rows[0].cells[0].observationId, 'Newer temp cell should map to temp');
        System.assertEquals(null, vitals.rows[0].cells[1].value, 'Missing time point should be an empty cell');
        System.assertEquals('110', vitals.rows[1].cells[0].value, 'Newer heart rate should sit in first column');
        System.assertEquals(newerHr.Id, vitals.rows[1].cells[0].observationId, 'Newer HR cell Id should match');
        System.assertEquals('70', vitals.rows[1].cells[1].value, 'Older heart rate should sit in second column');
        System.assertEquals(olderHr.Id, vitals.rows[1].cells[1].observationId, 'Older HR cell Id should match');
        System.assertEquals(false, vitals.truncated, 'Small result should not be truncated');
    }

    @IsTest
    static void getDataFiltersByCategoryDateRangeAndPatient() {
        Patient__c patient = insertPatient('MRN-FS-2');
        Patient__c other = insertPatient('MRN-FS-3');
        Datetime recent = Datetime.now().addDays(-2);
        Datetime stale = Datetime.now().addDays(-20);

        insertObservation(
            patient.Id,
            'Laboratory',
            '2345-7',
            'Glucose',
            95,
            null,
            'mg/dL',
            'Normal',
            recent
        );
        insertObservation(
            patient.Id,
            'Laboratory',
            '2345-7',
            'Glucose',
            140,
            null,
            'mg/dL',
            'High',
            stale
        );
        insertObservation(
            other.Id,
            'Laboratory',
            '2345-7',
            'Glucose',
            200,
            null,
            'mg/dL',
            'Critical',
            recent
        );
        insertObservation(
            patient.Id,
            'Vital Signs',
            '8867-4',
            'Heart rate',
            64,
            null,
            '/min',
            'Normal',
            recent
        );

        Test.startTest();
        FlowsheetController.FlowsheetData labs7d = FlowsheetController.getData(
            patient.Id,
            'Labs',
            '7d'
        );
        FlowsheetController.FlowsheetData labs30d = FlowsheetController.getData(
            patient.Id,
            'Laboratory',
            '30d'
        );
        FlowsheetController.FlowsheetData blank = FlowsheetController.getData(null, 'Vitals', '7d');
        Test.stopTest();

        System.assertEquals(1, labs7d.rows.size(), '7d labs should keep one glucose row');
        System.assertEquals(1, labs7d.columns.size(), 'Stale lab should be outside 7d');
        System.assertEquals('95', labs7d.rows[0].cells[0].value, 'Only the recent glucose should remain');
        System.assertEquals(1, labs30d.rows.size(), '30d should still be a single glucose row');
        System.assertEquals(2, labs30d.columns.size(), '30d should include both glucose times');
        System.assertEquals('140', labs30d.rows[0].cells[1].value, 'Older glucose should be the later column');
        System.assertEquals(0, blank.rows.size(), 'Null patient should return no rows');
        System.assertEquals(0, blank.columns.size(), 'Null patient should return no columns');
        System.assertEquals(0, blank.observations.size(), 'Null patient should return no observations');
    }

    @IsTest
    static void getDataUsesStringValueAndAllRangeAndSkipsNullDatetime() {
        Patient__c patient = insertPatient('MRN-FS-4');
        Datetime recent = Datetime.now().addHours(-3);
        Datetime lastYear = Datetime.now().addDays(-200);

        insertObservation(
            patient.Id,
            'Laboratory',
            '718-7',
            'Hemoglobin',
            null,
            'See note',
            null,
            'Abnormal',
            recent
        );
        insertObservation(
            patient.Id,
            'Laboratory',
            '6690-2',
            'WBC',
            3.2,
            null,
            '10*3/uL',
            'Low',
            lastYear
        );
        insertObservation(
            patient.Id,
            'Laboratory',
            '4544-3',
            'Hematocrit',
            44,
            null,
            '%',
            'Normal',
            null
        );

        Test.startTest();
        FlowsheetController.FlowsheetData sevenDay = FlowsheetController.getData(
            patient.Id,
            'lab',
            null
        );
        FlowsheetController.FlowsheetData allTime = FlowsheetController.getData(
            patient.Id,
            'All',
            'all'
        );
        Set<String> vitalsOnly = FlowsheetController.resolveCategories('Vital Signs');
        Datetime start24h = FlowsheetController.resolveStart('24h');
        Datetime start90d = FlowsheetController.resolveStart('90d');
        Datetime start1y = FlowsheetController.resolveStart('1y');
        Test.stopTest();

        System.assertEquals(1, sevenDay.rows.size(), 'Default 7d should exclude last-year WBC and undated HCT');
        System.assertEquals('See note', sevenDay.rows[0].cells[0].value, 'String values should populate the cell');
        System.assertEquals('Abnormal', sevenDay.rows[0].cells[0].interpretation, 'String-value interp should pass through');
        System.assertEquals(2, allTime.rows.size(), 'All range should include hemoglobin and WBC rows');
        System.assertEquals(2, allTime.columns.size(), 'Undated hematocrit should not create a column');
        System.assertEquals(true, vitalsOnly.contains('Vital Signs'), 'Vital Signs category should resolve to vitals');
        System.assertEquals(1, vitalsOnly.size(), 'Unspecified category should not include labs');
        System.assertEquals(true, start24h < Datetime.now(), '24h start should be in the past');
        System.assertEquals(true, start90d < start24h, '90d start should be earlier than 24h');
        System.assertEquals(true, start1y < start90d, '1y start should be earlier than 90d');
        System.assertEquals(3, allTime.observations.size(), 'Undated hematocrit should still be returned as an observation');
    }

    @IsTest
    static void getDataKeepsFirstCellWhenSameCodeAndTimeAndHandlesEmpty() {
        Patient__c patient = insertPatient('MRN-FS-6');
        Patient__c emptyPatient = insertPatient('MRN-FS-7');
        Datetime whenTaken = Datetime.now().addHours(-1);
        insertObservation(
            patient.Id,
            'Vital Signs',
            '8867-4',
            'Heart rate',
            80,
            null,
            '/min',
            'Normal',
            whenTaken
        );
        insertObservation(
            patient.Id,
            'Vital Signs',
            '8867-4',
            'Heart rate',
            99,
            null,
            '/min',
            'High',
            whenTaken
        );

        Test.startTest();
        FlowsheetController.FlowsheetData data = FlowsheetController.getData(
            patient.Id,
            'Vitals',
            '24h'
        );
        FlowsheetController.FlowsheetData none = FlowsheetController.getData(
            emptyPatient.Id,
            'Vitals',
            '7d'
        );
        FlowsheetController.FlowsheetData builtNull = FlowsheetController.buildGrid(null);
        List<Observation__c> manyRows = new List<Observation__c>();
        Datetime sharedTime = Datetime.now();
        for (Integer i = 0; i < FlowsheetController.MAX_ROWS + 3; i++) {
            manyRows.add(
                new Observation__c(
                    Observation_Code__c = 'C' + String.valueOf(i),
                    Observation_Display__c = i == 0 ? null : 'Obs ' + String.valueOf(i).leftPad(3, '0'),
                    Value_Quantity__c = i,
                    Value_Unit__c = 'u',
                    Effective_DateTime__c = sharedTime
                )
            );
        }
        FlowsheetController.FlowsheetData rowCapped = FlowsheetController.buildGrid(manyRows);
        Test.stopTest();

        System.assertEquals(1, data.rows.size(), 'Same code and display should collapse to one row');
        System.assertEquals(1, data.columns.size(), 'Same effective time should collapse to one column');
        System.assertEquals(
            true,
            data.rows[0].cells[0].value == '80' || data.rows[0].cells[0].value == '99',
            'The retained cell should be one of the two same-time heart rates'
        );
        System.assertEquals(
            true,
            data.rows[0].cells[0].observationId != null,
            'The retained cell should point at one observation'
        );
        System.assertEquals(0, none.rows.size(), 'Patient with no observations should have no rows');
        System.assertEquals(0, none.columns.size(), 'Patient with no observations should have no columns');
        System.assertEquals(0, builtNull.observations.size(), 'Null observation list should build an empty grid');
        System.assertEquals(false, builtNull.truncated, 'Empty grid should not be truncated');
        System.assertEquals(
            FlowsheetController.MAX_ROWS,
            rowCapped.rows.size(),
            'Distinct observation types should cap at MAX_ROWS'
        );
        System.assertEquals(true, rowCapped.truncated, 'Row overflow should set truncated');
        System.assertEquals(
            'C0',
            rowCapped.rows[0].display,
            'Blank display should fall back to the observation code'
        );
    }

    @IsTest
    static void getDataTruncatesWhenTimePointsExceedColumnCap() {
        Patient__c patient = insertPatient('MRN-FS-5');
        Datetime newest = Datetime.now().addMinutes(-1);
        List<Observation__c> rows = new List<Observation__c>();
        for (Integer i = 0; i < FlowsheetController.MAX_COLUMNS + 2; i++) {
            rows.add(
                new Observation__c(
                    Patient__c = patient.Id,
                    Category__c = 'Vital Signs',
                    Status__c = 'Final',
                    Observation_Code__c = '8867-4',
                    Observation_Display__c = 'Heart rate',
                    Value_Quantity__c = 60 + i,
                    Value_Unit__c = '/min',
                    Interpretation__c = 'Normal',
                    Effective_DateTime__c = newest.addHours(-i)
                )
            );
        }
        insert rows;

        Test.startTest();
        FlowsheetController.FlowsheetData data = FlowsheetController.getData(
            patient.Id,
            'Vital Signs',
            'all'
        );
        Test.stopTest();

        System.assertEquals(
            FlowsheetController.MAX_COLUMNS,
            data.columns.size(),
            'Columns should cap at MAX_COLUMNS'
        );
        System.assertEquals(
            newest.getTime(),
            data.columns[0].effectiveDateTime.getTime(),
            'Truncation should keep the most recent time points'
        );
        System.assertEquals(1, data.rows.size(), 'Same code/display should remain one row');
        System.assertEquals(
            FlowsheetController.MAX_COLUMNS,
            data.rows[0].cells.size(),
            'Truncated row should still align to remaining columns'
        );
        System.assertEquals(true, data.truncated, 'Overflowing time points should set truncated');
        System.assertEquals(
            FlowsheetController.MAX_COLUMNS + 2,
            data.totalObservationCount,
            'Raw observation count should include truncated points'
        );
    }

    private static Patient__c insertPatient(String mrn) {
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'Flowsheet');
        insert patient;
        return patient;
    }

    private static Observation__c insertObservation(
        Id patientId,
        String category,
        String code,
        String display,
        Decimal quantity,
        String valueString,
        String unit,
        String interpretation,
        Datetime effective
    ) {
        Observation__c observation = new Observation__c(
            Patient__c = patientId,
            Category__c = category,
            Status__c = 'Final',
            Observation_Code__c = code,
            Observation_Display__c = display,
            Value_Quantity__c = quantity,
            Value_String__c = valueString,
            Value_Unit__c = unit,
            Interpretation__c = interpretation,
            Effective_DateTime__c = effective
        );
        insert observation;
        return observation;
    }
}
