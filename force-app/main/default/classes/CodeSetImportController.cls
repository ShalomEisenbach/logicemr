public with sharing class CodeSetImportController {
    @TestVisible
    private static final Set<String> CODE_SYSTEMS = new Set<String>{
        'ICD-10',
        'CPT',
        'LOINC',
        'RxNorm',
        'SNOMED',
        'CVX'
    };
    @TestVisible
    private static final Integer NAME_MAX_LENGTH = 80;
    @TestVisible
    private static final Integer CODE_MAX_LENGTH = 50;
    @TestVisible
    private static final Integer DISPLAY_MAX_LENGTH = 255;

    public class CodeRow {
        @AuraEnabled
        public String codeSystem { get; set; }
        @AuraEnabled
        public String code { get; set; }
        @AuraEnabled
        public String display { get; set; }
        @AuraEnabled
        public Integer rowNumber { get; set; }
    }

    public class ImportResult {
        @AuraEnabled
        public Integer created { get; set; }
        @AuraEnabled
        public Integer updated { get; set; }
        @AuraEnabled
        public Integer failed { get; set; }
        @AuraEnabled
        public List<String> errors { get; set; }

        public ImportResult() {
            this.created = 0;
            this.updated = 0;
            this.failed = 0;
            this.errors = new List<String>();
        }
    }

    @AuraEnabled
    public static String getCsvContent(Id contentDocumentId) {
        try {
            return readCsvContent(contentDocumentId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static ImportResult importCodes(List<CodeRow> rows) {
        try {
            return upsertCodes(rows);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static String readCsvContent(Id contentDocumentId) {
        if (contentDocumentId == null) {
            throw new AuraHandledException('A file is required.');
        }
        List<ContentVersion> versions = [
            SELECT VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId AND IsLatest = true
            LIMIT 1
        ];
        if (versions.isEmpty() || versions[0].VersionData == null) {
            throw new AuraHandledException('The uploaded file was not found.');
        }
        return versions[0].VersionData.toString();
    }

    private static ImportResult upsertCodes(List<CodeRow> rows) {
        if (rows == null || rows.isEmpty()) {
            throw new AuraHandledException('At least one code row is required.');
        }

        ImportResult result = new ImportResult();
        Map<String, PreparedRow> preparedByKey = new Map<String, PreparedRow>();
        Set<String> codes = new Set<String>();
        Set<String> codeSystems = new Set<String>();

        for (Integer i = 0; i < rows.size(); i++) {
            CodeRow row = rows[i];
            Integer displayIndex = row != null && row.rowNumber != null ? row.rowNumber : i + 1;
            PreparedRow prepared = prepareRow(row, displayIndex, result);
            if (prepared == null) {
                continue;
            }
            preparedByKey.put(prepared.key, prepared);
            codes.add(prepared.code);
            codeSystems.add(prepared.codeSystem);
        }

        if (preparedByKey.isEmpty()) {
            return result;
        }

        Map<String, Code_Reference__c> existingByKey = queryExisting(codes, codeSystems);
        List<Code_Reference__c> toInsert = new List<Code_Reference__c>();
        List<Code_Reference__c> toUpdate = new List<Code_Reference__c>();
        List<PreparedRow> insertRows = new List<PreparedRow>();
        List<PreparedRow> updateRows = new List<PreparedRow>();

        for (PreparedRow prepared : preparedByKey.values()) {
            Code_Reference__c existing = existingByKey.get(prepared.key);
            Code_Reference__c record = toRecord(prepared);
            if (existing != null) {
                record.Id = existing.Id;
                toUpdate.add(record);
                updateRows.add(prepared);
            } else {
                toInsert.add(record);
                insertRows.add(prepared);
            }
        }

        applySaveResults(Database.insert(toInsert, false), insertRows, result, true);
        applySaveResults(Database.update(toUpdate, false), updateRows, result, false);
        return result;
    }

    private static PreparedRow prepareRow(CodeRow row, Integer displayIndex, ImportResult result) {
        if (row == null) {
            result.failed++;
            result.errors.add(formatError(displayIndex, null, null, 'Row is required.'));
            return null;
        }

        String codeSystem = canonicalizeCodeSystem(row.codeSystem);
        String code = row.code == null ? '' : row.code.trim();
        String display = row.display == null ? '' : row.display.trim();

        if (String.isBlank(row.codeSystem)) {
            result.failed++;
            result.errors.add(formatError(displayIndex, row.codeSystem, code, 'Code System is required.'));
            return null;
        }
        if (codeSystem == null) {
            result.failed++;
            result.errors.add(
                formatError(displayIndex, row.codeSystem, code, 'Unknown Code System: ' + row.codeSystem.trim())
            );
            return null;
        }
        if (String.isBlank(code)) {
            result.failed++;
            result.errors.add(formatError(displayIndex, codeSystem, code, 'Code is required.'));
            return null;
        }
        if (code.length() > CODE_MAX_LENGTH) {
            result.failed++;
            result.errors.add(
                formatError(displayIndex, codeSystem, code, 'Code must be ' + CODE_MAX_LENGTH + ' characters or fewer.')
            );
            return null;
        }

        PreparedRow prepared = new PreparedRow();
        prepared.rowNumber = displayIndex;
        prepared.codeSystem = codeSystem;
        prepared.code = code;
        prepared.display = truncate(display, DISPLAY_MAX_LENGTH);
        prepared.name = truncate(String.isNotBlank(display) ? display : code, NAME_MAX_LENGTH);
        prepared.key = rowKey(codeSystem, code);
        return prepared;
    }

    private static Map<String, Code_Reference__c> queryExisting(Set<String> codes, Set<String> codeSystems) {
        Map<String, Code_Reference__c> existingByKey = new Map<String, Code_Reference__c>();
        if (codes.isEmpty() || codeSystems.isEmpty()) {
            return existingByKey;
        }
        for (Code_Reference__c record : [
            SELECT Id, Code_System__c, Code__c
            FROM Code_Reference__c
            WHERE Code__c IN :codes AND Code_System__c IN :codeSystems
        ]) {
            existingByKey.put(rowKey(record.Code_System__c, record.Code__c), record);
        }
        return existingByKey;
    }

    private static Code_Reference__c toRecord(PreparedRow prepared) {
        return new Code_Reference__c(
            Name = prepared.name,
            Code_System__c = prepared.codeSystem,
            Code__c = prepared.code,
            Display__c = prepared.display,
            Active__c = true
        );
    }

    private static void applySaveResults(
        List<Database.SaveResult> saveResults,
        List<PreparedRow> sourceRows,
        ImportResult result,
        Boolean isInsert
    ) {
        for (Integer i = 0; i < saveResults.size(); i++) {
            Database.SaveResult saveResult = saveResults[i];
            PreparedRow prepared = sourceRows[i];
            if (saveResult.isSuccess()) {
                if (isInsert) {
                    result.created++;
                } else {
                    result.updated++;
                }
                continue;
            }
            result.failed++;
            result.errors.add(
                formatError(prepared.rowNumber, prepared.codeSystem, prepared.code, firstError(saveResult))
            );
        }
    }

    private static String firstError(Database.SaveResult saveResult) {
        if (saveResult.getErrors() == null || saveResult.getErrors().isEmpty()) {
            return 'Unable to save this row.';
        }
        return saveResult.getErrors()[0].getMessage();
    }

    private static String canonicalizeCodeSystem(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String trimmed = raw.trim();
        for (String allowed : CODE_SYSTEMS) {
            if (allowed.equalsIgnoreCase(trimmed)) {
                return allowed;
            }
        }
        return null;
    }

    private static String rowKey(String codeSystem, String code) {
        return codeSystem + '\n' + (code == null ? '' : code.trim().toLowerCase());
    }

    private static String truncate(String value, Integer maxLen) {
        if (value == null) {
            return null;
        }
        return value.length() <= maxLen ? value : value.substring(0, maxLen);
    }

    private static String formatError(Integer rowNumber, String codeSystem, String code, String message) {
        String prefix = 'Row ' + rowNumber;
        if (String.isNotBlank(codeSystem) || String.isNotBlank(code)) {
            prefix += ' (' + (codeSystem == null ? '' : codeSystem) + ' / ' + (code == null ? '' : code) + ')';
        }
        return prefix + ': ' + message;
    }

    private class PreparedRow {
        public Integer rowNumber;
        public String codeSystem;
        public String code;
        public String display;
        public String name;
        public String key;
    }
}
