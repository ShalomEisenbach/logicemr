public with sharing class NameFormatterHandler {
    private static final Integer NAME_MAX_LENGTH = 80;
    private static final Pattern TOKEN_PATTERN = Pattern.compile('\\{([^{}]+)\\}');

    private static Map<String, Name_Format__mdt> formatsByObjectApi;

    public static void format(List<SObject> records) {
        if (records == null || records.isEmpty()) {
            return;
        }

        Map<Schema.SObjectType, List<SObject>> recordsByType = new Map<Schema.SObjectType, List<SObject>>();
        for (SObject record : records) {
            if (record == null) {
                continue;
            }
            Schema.SObjectType sObjectType = record.getSObjectType();
            if (!recordsByType.containsKey(sObjectType)) {
                recordsByType.put(sObjectType, new List<SObject>());
            }
            recordsByType.get(sObjectType).add(record);
        }

        for (Schema.SObjectType sObjectType : recordsByType.keySet()) {
            formatType(sObjectType, recordsByType.get(sObjectType));
        }
    }

    private static void formatType(Schema.SObjectType sObjectType, List<SObject> records) {
        Name_Format__mdt nameFormat = getActiveFormat(sObjectType);
        if (nameFormat == null || String.isBlank(nameFormat.Format__c)) {
            return;
        }

        Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
        Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();
        List<Token> tokens = parseTokens(nameFormat.Format__c);
        Map<String, ParentQuery> parentQueries = buildParentQueries(tokens, fieldMap, records);

        for (SObject record : records) {
            record.put('Name', composeName(nameFormat.Format__c, tokens, record, fieldMap, parentQueries));
        }
    }

    private static Name_Format__mdt getActiveFormat(Schema.SObjectType sObjectType) {
        ensureFormatCache();
        Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
        Name_Format__mdt nameFormat = formatsByObjectApi.get(describeResult.getLocalName());
        if (nameFormat == null) {
            nameFormat = formatsByObjectApi.get(describeResult.getName());
        }
        return nameFormat;
    }

    private static void ensureFormatCache() {
        if (formatsByObjectApi != null) {
            return;
        }
        formatsByObjectApi = new Map<String, Name_Format__mdt>();
        for (Name_Format__mdt row : Name_Format__mdt.getAll().values()) {
            if (row.Active__c != true || String.isBlank(row.Object_API_Name__c)) {
                continue;
            }
            formatsByObjectApi.put(row.Object_API_Name__c, row);
            String localApiName = toLocalApiName(row.Object_API_Name__c);
            if (localApiName != row.Object_API_Name__c) {
                formatsByObjectApi.put(localApiName, row);
            }
        }
    }

    private static List<Token> parseTokens(String template) {
        List<Token> tokens = new List<Token>();
        Matcher matcher = TOKEN_PATTERN.matcher(template);
        while (matcher.find()) {
            tokens.add(new Token(matcher.group(1)));
        }
        return tokens;
    }

    private static Map<String, ParentQuery> buildParentQueries(
        List<Token> tokens,
        Map<String, Schema.SObjectField> fieldMap,
        List<SObject> records
    ) {
        Map<String, ParentQuery> parentQueries = new Map<String, ParentQuery>();
        for (Token token : tokens) {
            if (!token.isParent) {
                continue;
            }
            ParentQuery parentQuery = parentQueries.get(token.relationshipName);
            if (parentQuery == null) {
                Schema.SObjectField lookupField = findLookupField(fieldMap, token.relationshipName);
                if (lookupField == null) {
                    continue;
                }
                Schema.DescribeFieldResult lookupDescribe = lookupField.getDescribe();
                List<Schema.SObjectType> references = lookupDescribe.getReferenceTo();
                if (references == null || references.isEmpty()) {
                    continue;
                }
                parentQuery = new ParentQuery(lookupDescribe.getName(), references[0]);
                parentQueries.put(token.relationshipName, parentQuery);
            }
            parentQuery.fieldApiNames.add(token.fieldName);
        }

        for (SObject record : records) {
            for (ParentQuery parentQuery : parentQueries.values()) {
                Object lookupValue = record.get(parentQuery.lookupFieldName);
                if (lookupValue instanceof Id) {
                    parentQuery.parentIds.add((Id) lookupValue);
                }
            }
        }

        for (ParentQuery parentQuery : parentQueries.values()) {
            parentQuery.parentsById = queryParents(parentQuery);
        }
        return parentQueries;
    }

    private static Map<Id, SObject> queryParents(ParentQuery parentQuery) {
        if (parentQuery.parentIds.isEmpty()) {
            return new Map<Id, SObject>();
        }

        Schema.DescribeSObjectResult parentDescribe = parentQuery.parentType.getDescribe();
        Map<String, Schema.SObjectField> parentFields = parentDescribe.fields.getMap();
        Set<String> selectFields = new Set<String>{ 'Id' };
        for (String requestedField : parentQuery.fieldApiNames) {
            Schema.SObjectField parentField = findField(parentFields, requestedField);
            if (parentField != null) {
                selectFields.add(parentField.getDescribe().getName());
            }
        }

        String soql =
            'SELECT ' +
            String.join(new List<String>(selectFields), ', ') +
            ' FROM ' +
            parentDescribe.getName() +
            ' WHERE Id IN :parentIds';
        Set<Id> parentIds = parentQuery.parentIds;
        return new Map<Id, SObject>(Database.query(soql));
    }

    private static String composeName(
        String template,
        List<Token> tokens,
        SObject record,
        Map<String, Schema.SObjectField> fieldMap,
        Map<String, ParentQuery> parentQueries
    ) {
        Map<String, String> tokenValues = new Map<String, String>();
        for (Token token : tokens) {
            tokenValues.put(token.raw, resolveToken(token, record, fieldMap, parentQueries));
        }

        Matcher matcher = TOKEN_PATTERN.matcher(template);
        String composed = '';
        Integer lastEnd = 0;
        while (matcher.find()) {
            composed += template.substring(lastEnd, matcher.start());
            String resolved = tokenValues.get(matcher.group(1));
            composed += resolved == null ? '' : resolved;
            lastEnd = matcher.end();
        }
        composed += template.substring(lastEnd);
        return finalizeComposedName(composed);
    }

    private static String resolveToken(
        Token token,
        SObject record,
        Map<String, Schema.SObjectField> fieldMap,
        Map<String, ParentQuery> parentQueries
    ) {
        if (token.isParent) {
            ParentQuery parentQuery = parentQueries.get(token.relationshipName);
            if (parentQuery == null) {
                return '';
            }
            Object lookupValue = record.get(parentQuery.lookupFieldName);
            if (!(lookupValue instanceof Id)) {
                return '';
            }
            SObject parentRecord = parentQuery.parentsById.get((Id) lookupValue);
            if (parentRecord == null) {
                return '';
            }
            Schema.SObjectField parentField = findField(
                parentRecord.getSObjectType().getDescribe().fields.getMap(),
                token.fieldName
            );
            return parentField == null ? '' : stringify(parentRecord.get(parentField));
        }

        Schema.SObjectField localField = findField(fieldMap, token.fieldName);
        return localField == null ? '' : stringify(record.get(localField));
    }

    private static Schema.SObjectField findLookupField(
        Map<String, Schema.SObjectField> fieldMap,
        String relationshipName
    ) {
        for (Schema.SObjectField field : fieldMap.values()) {
            String describedRelationship = field.getDescribe().getRelationshipName();
            if (
                describedRelationship != null &&
                (describedRelationship.equalsIgnoreCase(relationshipName) ||
                toLocalRelationship(describedRelationship).equalsIgnoreCase(relationshipName))
            ) {
                return field;
            }
        }
        return null;
    }

    private static Schema.SObjectField findField(Map<String, Schema.SObjectField> fieldMap, String apiName) {
        if (String.isBlank(apiName) || fieldMap == null) {
            return null;
        }
        if (fieldMap.containsKey(apiName)) {
            return fieldMap.get(apiName);
        }
        String localApiName = toLocalApiName(apiName);
        if (fieldMap.containsKey(localApiName)) {
            return fieldMap.get(localApiName);
        }
        for (Schema.SObjectField field : fieldMap.values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            if (
                fieldDescribe.getLocalName().equalsIgnoreCase(apiName) ||
                fieldDescribe.getName().equalsIgnoreCase(apiName) ||
                fieldDescribe.getLocalName().equalsIgnoreCase(localApiName)
            ) {
                return field;
            }
        }
        return null;
    }

    private static String toLocalRelationship(String apiName) {
        if (String.isBlank(apiName) || !apiName.endsWith('__r')) {
            return apiName;
        }
        List<String> parts = apiName.split('__');
        if (parts.size() >= 2) {
            return parts[parts.size() - 2] + '__r';
        }
        return apiName;
    }

    private static String toLocalApiName(String apiName) {
        if (String.isBlank(apiName)) {
            return apiName;
        }
        List<String> parts = apiName.split('__');
        if (parts.size() == 3) {
            return parts[1] + '__c';
        }
        return apiName;
    }

    private static String finalizeComposedName(String composed) {
        if (String.isBlank(composed)) {
            return composed;
        }
        composed = removeEmptyParentheses(composed.normalizeSpace());
        if (composed.length() > NAME_MAX_LENGTH) {
            String withoutOptionalName = removeFirstParenthetical(composed);
            if (withoutOptionalName.length() <= NAME_MAX_LENGTH) {
                composed = withoutOptionalName;
            } else {
                composed = composed.substring(0, NAME_MAX_LENGTH);
            }
        }
        return composed;
    }

    private static String removeEmptyParentheses(String value) {
        String previous;
        do {
            previous = value;
            value = value.replace('( )', '').replace('()', '');
            value = value.normalizeSpace();
        } while (value != previous);
        value = value.replace('( ', '(').replace(' )', ')');
        if (value.contains('()')) {
            value = value.replace('()', '').normalizeSpace();
        }
        return value;
    }

    private static String removeFirstParenthetical(String value) {
        Integer openAt = value.indexOf(' (');
        if (openAt < 0) {
            return value;
        }
        Integer closeAt = value.indexOf(')', openAt);
        if (closeAt < 0) {
            return value;
        }
        return (value.substring(0, openAt) + value.substring(closeAt + 1)).normalizeSpace();
    }

    private static String stringify(Object value) {
        if (value == null) {
            return '';
        }
        if (value instanceof Date) {
            return String.valueOf((Date) value);
        }
        if (value instanceof Datetime) {
            return String.valueOf((Datetime) value);
        }
        if (value instanceof Decimal) {
            return String.valueOf((Decimal) value);
        }
        return String.valueOf(value);
    }

    private class Token {
        String raw;
        Boolean isParent;
        String relationshipName;
        String fieldName;

        Token(String rawToken) {
            raw = rawToken == null ? '' : rawToken.trim();
            Integer dotIndex = raw.indexOf('.');
            if (dotIndex > 0 && dotIndex < raw.length() - 1) {
                isParent = true;
                relationshipName = raw.substring(0, dotIndex);
                fieldName = raw.substring(dotIndex + 1);
            } else {
                isParent = false;
                fieldName = raw;
            }
        }
    }

    private class ParentQuery {
        String lookupFieldName;
        Schema.SObjectType parentType;
        Set<String> fieldApiNames = new Set<String>();
        Set<Id> parentIds = new Set<Id>();
        Map<Id, SObject> parentsById = new Map<Id, SObject>();

        ParentQuery(String lookupFieldName, Schema.SObjectType parentType) {
            this.lookupFieldName = lookupFieldName;
            this.parentType = parentType;
        }
    }
}
