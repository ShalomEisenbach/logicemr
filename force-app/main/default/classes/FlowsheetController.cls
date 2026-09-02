public with sharing class FlowsheetController {
    private static final Integer MAX_QUERY = 2000;
    @TestVisible
    private static final Integer MAX_COLUMNS = 30;
    @TestVisible
    private static final Integer MAX_ROWS = 100;

    private static final String CATEGORY_VITALS = 'Vital Signs';
    private static final String CATEGORY_LABS = 'Laboratory';

    public class FlowsheetData {
        @AuraEnabled
        public List<Observation__c> observations;
        @AuraEnabled
        public List<FlowsheetColumn> columns;
        @AuraEnabled
        public List<FlowsheetRow> rows;
        @AuraEnabled
        public Boolean truncated;
        @AuraEnabled
        public Integer totalObservationCount;
    }

    public class FlowsheetColumn {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public Datetime effectiveDateTime;
    }

    public class FlowsheetRow implements Comparable {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String display;
        @AuraEnabled
        public String code;
        @AuraEnabled
        public List<FlowsheetCell> cells;

        public Integer compareTo(Object other) {
            FlowsheetRow that = (FlowsheetRow) other;
            String leftDisplay = this.display == null ? '' : this.display.toLowerCase();
            String rightDisplay = that.display == null ? '' : that.display.toLowerCase();
            Integer byDisplay = leftDisplay.compareTo(rightDisplay);
            if (byDisplay != 0) {
                return byDisplay;
            }
            String leftCode = this.code == null ? '' : this.code;
            String rightCode = that.code == null ? '' : that.code;
            return leftCode.compareTo(rightCode);
        }
    }

    public class FlowsheetCell {
        @AuraEnabled
        public String columnKey;
        @AuraEnabled
        public String value;
        @AuraEnabled
        public String unit;
        @AuraEnabled
        public String interpretation;
        @AuraEnabled
        public Id observationId;
    }

    @AuraEnabled(cacheable=true)
    public static FlowsheetData getData(Id patientId, String category, String dateRange) {
        FlowsheetData empty = newEmpty();
        if (patientId == null) {
            return empty;
        }
        return buildGrid(queryObservations(new Set<Id>{ patientId }, category, dateRange));
    }

    private static FlowsheetData newEmpty() {
        FlowsheetData data = new FlowsheetData();
        data.observations = new List<Observation__c>();
        data.columns = new List<FlowsheetColumn>();
        data.rows = new List<FlowsheetRow>();
        data.truncated = false;
        data.totalObservationCount = 0;
        return data;
    }

    private static List<Observation__c> queryObservations(
        Set<Id> patientIds,
        String category,
        String dateRange
    ) {
        Set<String> categories = resolveCategories(category);
        Datetime startAt = resolveStart(dateRange);
        if (startAt == null) {
            return [
                SELECT
                    Id,
                    Observation_Code__c,
                    Observation_Display__c,
                    Value_Quantity__c,
                    Value_String__c,
                    Value_Unit__c,
                    Interpretation__c,
                    Effective_DateTime__c,
                    Category__c
                FROM Observation__c
                WHERE Patient__c IN :patientIds AND Category__c IN :categories
                ORDER BY Effective_DateTime__c DESC NULLS LAST, Observation_Display__c ASC NULLS LAST
                LIMIT :MAX_QUERY
            ];
        }
        return [
            SELECT
                Id,
                Observation_Code__c,
                Observation_Display__c,
                Value_Quantity__c,
                Value_String__c,
                Value_Unit__c,
                Interpretation__c,
                Effective_DateTime__c,
                Category__c
            FROM Observation__c
            WHERE
                Patient__c IN :patientIds
                AND Category__c IN :categories
                AND Effective_DateTime__c >= :startAt
            ORDER BY Effective_DateTime__c DESC NULLS LAST, Observation_Display__c ASC NULLS LAST
            LIMIT :MAX_QUERY
        ];
    }

    @TestVisible
    private static Set<String> resolveCategories(String category) {
        String key = category == null ? '' : category.trim().toLowerCase();
        if (key == 'all' || key == 'both') {
            return new Set<String>{ CATEGORY_VITALS, CATEGORY_LABS };
        }
        if (key == 'labs' || key == 'laboratory' || key == 'lab') {
            return new Set<String>{ CATEGORY_LABS };
        }
        return new Set<String>{ CATEGORY_VITALS };
    }

    @TestVisible
    private static Datetime resolveStart(String dateRange) {
        String key = String.isBlank(dateRange) ? '7d' : dateRange.trim().toLowerCase();
        Datetime now = Datetime.now();
        if (key == 'all') {
            return null;
        }
        if (key == '24h' || key == '1d') {
            return now.addHours(-24);
        }
        if (key == '30d') {
            return now.addDays(-30);
        }
        if (key == '90d') {
            return now.addDays(-90);
        }
        if (key == '1y' || key == '365d') {
            return now.addDays(-365);
        }
        return now.addDays(-7);
    }

    @TestVisible
    private static FlowsheetData buildGrid(List<Observation__c> observations) {
        FlowsheetData data = newEmpty();
        data.observations = observations == null ? new List<Observation__c>() : observations;
        data.totalObservationCount = data.observations.size();

        List<Datetime> times = new List<Datetime>();
        Set<String> seenTimes = new Set<String>();
        for (Observation__c observation : data.observations) {
            if (observation.Effective_DateTime__c == null) {
                continue;
            }
            String key = columnKey(observation.Effective_DateTime__c);
            if (!seenTimes.contains(key)) {
                seenTimes.add(key);
                times.add(observation.Effective_DateTime__c);
            }
        }

        Integer columnCount = Math.min(times.size(), MAX_COLUMNS);
        data.truncated = times.size() > MAX_COLUMNS || data.totalObservationCount >= MAX_QUERY;
        Set<String> allowedColumnKeys = new Set<String>();
        for (Integer i = 0; i < columnCount; i++) {
            FlowsheetColumn column = new FlowsheetColumn();
            column.effectiveDateTime = times[i];
            column.key = columnKey(times[i]);
            data.columns.add(column);
            allowedColumnKeys.add(column.key);
        }

        Map<String, FlowsheetRow> rowsByKey = new Map<String, FlowsheetRow>();
        Set<String> placedCells = new Set<String>();
        for (Observation__c observation : data.observations) {
            if (observation.Effective_DateTime__c == null) {
                continue;
            }
            String colKey = columnKey(observation.Effective_DateTime__c);
            if (!allowedColumnKeys.contains(colKey)) {
                continue;
            }
            String rKey = rowKey(observation);
            if (!rowsByKey.containsKey(rKey)) {
                FlowsheetRow row = new FlowsheetRow();
                row.key = rKey;
                row.display = String.isNotBlank(observation.Observation_Display__c)
                    ? observation.Observation_Display__c
                    : observation.Observation_Code__c;
                row.code = observation.Observation_Code__c;
                row.cells = new List<FlowsheetCell>();
                rowsByKey.put(rKey, row);
            }
            String cellKey = rKey + '|' + colKey;
            if (placedCells.contains(cellKey)) {
                continue;
            }
            placedCells.add(cellKey);
            FlowsheetCell cell = new FlowsheetCell();
            cell.columnKey = colKey;
            cell.value = formatValue(observation);
            cell.unit = observation.Value_Unit__c;
            cell.interpretation = observation.Interpretation__c;
            cell.observationId = observation.Id;
            rowsByKey.get(rKey).cells.add(cell);
        }

        List<FlowsheetRow> sortedRows = rowsByKey.values();
        sortedRows.sort();
        if (sortedRows.size() > MAX_ROWS) {
            data.truncated = true;
        }
        Integer rowCount = Math.min(sortedRows.size(), MAX_ROWS);
        for (Integer i = 0; i < rowCount; i++) {
            data.rows.add(alignCells(sortedRows[i], data.columns));
        }
        return data;
    }

    private static FlowsheetRow alignCells(FlowsheetRow row, List<FlowsheetColumn> columns) {
        Map<String, FlowsheetCell> byColumn = new Map<String, FlowsheetCell>();
        if (row.cells != null) {
            for (FlowsheetCell cell : row.cells) {
                byColumn.put(cell.columnKey, cell);
            }
        }
        List<FlowsheetCell> aligned = new List<FlowsheetCell>();
        for (FlowsheetColumn column : columns) {
            if (byColumn.containsKey(column.key)) {
                aligned.add(byColumn.get(column.key));
            } else {
                FlowsheetCell empty = new FlowsheetCell();
                empty.columnKey = column.key;
                aligned.add(empty);
            }
        }
        row.cells = aligned;
        return row;
    }

    private static String rowKey(Observation__c observation) {
        String code = observation.Observation_Code__c == null ? '' : observation.Observation_Code__c;
        String display = observation.Observation_Display__c == null
            ? ''
            : observation.Observation_Display__c;
        return code + '|' + display;
    }

    private static String columnKey(Datetime effective) {
        return String.valueOf(effective.getTime());
    }

    private static String formatValue(Observation__c observation) {
        if (observation.Value_Quantity__c != null) {
            return observation.Value_Quantity__c.stripTrailingZeros().toPlainString();
        }
        return observation.Value_String__c;
    }
}
