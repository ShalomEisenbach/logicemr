public with sharing class DuplicatePatientController {
    private static final Integer MAX_GROUPS = 50;

    @TestVisible
    private static Integer groupLimitOverride;

    public class DuplicateFindResult {
        @AuraEnabled
        public List<DuplicateGroup> groups { get; set; }
        @AuraEnabled
        public Integer groupLimit { get; set; }
        @AuraEnabled
        public Boolean truncated { get; set; }

        public DuplicateFindResult() {
            this.groups = new List<DuplicateGroup>();
            this.truncated = false;
        }
    }

    public class DuplicateGroup {
        @AuraEnabled
        public String lastName { get; set; }
        @AuraEnabled
        public String firstName { get; set; }
        @AuraEnabled
        public Date dateOfBirth { get; set; }
        @AuraEnabled
        public Integer memberCount { get; set; }
        @AuraEnabled
        public List<Patient__c> members { get; set; }
    }

    /**
     * Groups patients that share Last_Name__c + First_Name__c + Date_of_Birth__c.
     * MRN__c is a Unique External ID so exact-MRN duplicates are impossible at the DB level;
     * this guard targets the same-person-different-record case.
     */
    @AuraEnabled
    public static DuplicateFindResult findDuplicates() {
        Integer groupLimit = groupLimitOverride != null ? groupLimitOverride : MAX_GROUPS;
        Integer queryLimit = groupLimit + 1;

        // MRN__c is a Unique External ID so exact-MRN duplicates are impossible at the DB level;
        // this guard targets the same-person-different-record case.
        List<AggregateResult> aggregates = [
            SELECT Last_Name__c, First_Name__c, Date_of_Birth__c, COUNT(Id) memberCount
            FROM Patient__c
            GROUP BY Last_Name__c, First_Name__c, Date_of_Birth__c
            HAVING COUNT(Id) > 1
            ORDER BY Last_Name__c, First_Name__c, Date_of_Birth__c
            LIMIT :queryLimit
        ];

        DuplicateFindResult result = new DuplicateFindResult();
        result.groupLimit = groupLimit;
        result.truncated = aggregates.size() > groupLimit;

        Integer take = Math.min(aggregates.size(), groupLimit);
        if (take == 0) {
            return result;
        }

        Set<String> lastNames = new Set<String>();
        Set<String> firstNames = new Set<String>();
        Set<Date> dobs = new Set<Date>();
        Boolean includeNullLast = false;
        Boolean includeNullFirst = false;
        Boolean includeNullDob = false;
        Map<String, DuplicateGroup> groupsByKey = new Map<String, DuplicateGroup>();

        for (Integer i = 0; i < take; i++) {
            AggregateResult row = aggregates[i];
            String lastName = (String) row.get('Last_Name__c');
            String firstName = (String) row.get('First_Name__c');
            Date dob = (Date) row.get('Date_of_Birth__c');

            if (lastName == null) {
                includeNullLast = true;
            } else {
                lastNames.add(lastName);
            }
            if (firstName == null) {
                includeNullFirst = true;
            } else {
                firstNames.add(firstName);
            }
            if (dob == null) {
                includeNullDob = true;
            } else {
                dobs.add(dob);
            }

            DuplicateGroup duplicateGroup = new DuplicateGroup();
            duplicateGroup.lastName = lastName;
            duplicateGroup.firstName = firstName;
            duplicateGroup.dateOfBirth = dob;
            duplicateGroup.memberCount = (Integer) row.get('memberCount');
            duplicateGroup.members = new List<Patient__c>();
            groupsByKey.put(groupKey(lastName, firstName, dob), duplicateGroup);
            result.groups.add(duplicateGroup);
        }

        for (
            Patient__c patient : queryMembers(
                lastNames,
                firstNames,
                dobs,
                includeNullLast,
                includeNullFirst,
                includeNullDob
            )
        ) {
            DuplicateGroup duplicateGroup = groupsByKey.get(
                groupKey(patient.Last_Name__c, patient.First_Name__c, patient.Date_of_Birth__c)
            );
            if (duplicateGroup != null) {
                duplicateGroup.members.add(patient);
            }
        }

        return result;
    }

    private static List<Patient__c> queryMembers(
        Set<String> lastNames,
        Set<String> firstNames,
        Set<Date> dobs,
        Boolean includeNullLast,
        Boolean includeNullFirst,
        Boolean includeNullDob
    ) {
        String soql =
            'SELECT Id, Name, MRN__c, Date_of_Birth__c, Status__c, CreatedDate, Last_Name__c, First_Name__c ' +
            'FROM Patient__c WHERE ' +
            inOrNull('Last_Name__c', ':lastNames', !lastNames.isEmpty(), includeNullLast) +
            ' AND ' +
            inOrNull('First_Name__c', ':firstNames', !firstNames.isEmpty(), includeNullFirst) +
            ' AND ' +
            inOrNull('Date_of_Birth__c', ':dobs', !dobs.isEmpty(), includeNullDob) +
            ' ORDER BY Last_Name__c, First_Name__c, Date_of_Birth__c, CreatedDate';
        return Database.query(soql);
    }

    private static String inOrNull(String fieldApiName, String bind, Boolean hasValues, Boolean includeNull) {
        List<String> parts = new List<String>();
        if (hasValues) {
            parts.add(fieldApiName + ' IN ' + bind);
        }
        if (includeNull) {
            parts.add(fieldApiName + ' = null');
        }
        return '(' + String.join(parts, ' OR ') + ')';
    }

    private static String groupKey(String lastName, String firstName, Date dob) {
        return normalize(lastName) + '\u0001' + normalize(firstName) + '\u0001' + (dob == null ? '' : String.valueOf(dob));
    }

    private static String normalize(String value) {
        return value == null ? '' : value.toLowerCase();
    }
}
