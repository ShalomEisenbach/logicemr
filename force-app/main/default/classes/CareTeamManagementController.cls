public with sharing class CareTeamManagementController {
    public class CareTeamView {
        @AuraEnabled
        public Id careTeamId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public List<MemberView> members;
    }

    public class MemberView {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public Id practitionerId;
        @AuraEnabled
        public String practitionerName;
        @AuraEnabled
        public String role;
        @AuraEnabled
        public String accessLevel;
        @AuraEnabled
        public Boolean active;
    }

    @AuraEnabled
    public static CareTeamView getOrCreateCareTeam(Id patientId) {
        if (patientId == null) {
            throw new AuraHandledException('Patient Id is required.');
        }

        CareTeam__c careTeam = queryCareTeam(patientId);
        if (careTeam == null) {
            insert new CareTeam__c(Patient__c = patientId, Status__c = 'Active');
            careTeam = queryCareTeam(patientId);
        }
        return toView(careTeam, queryMembers(new Set<Id>{ careTeam.Id }));
    }

    @AuraEnabled
    public static CareTeamMember__c addMember(
        Id careTeamId,
        Id practitionerId,
        String role,
        String accessLevel
    ) {
        if (careTeamId == null || practitionerId == null) {
            throw new AuraHandledException('Care team and practitioner are required.');
        }

        List<CareTeamMember__c> members = new List<CareTeamMember__c>{
            new CareTeamMember__c(
                Care_Team__c = careTeamId,
                Practitioner__c = practitionerId,
                Role__c = role,
                Access_Level__c = String.isBlank(accessLevel) ? 'Read' : accessLevel,
                Active__c = true
            )
        };
        insert members;
        return members[0];
    }

    @AuraEnabled
    public static void deactivateMembers(List<Id> memberIds) {
        if (memberIds == null || memberIds.isEmpty()) {
            return;
        }

        List<CareTeamMember__c> members = [
            SELECT Id, Active__c
            FROM CareTeamMember__c
            WHERE Id IN :memberIds AND Active__c = TRUE
        ];
        for (CareTeamMember__c member : members) {
            member.Active__c = false;
        }
        if (!members.isEmpty()) {
            update members;
        }
    }

    @AuraEnabled
    public static void removeMembers(List<Id> memberIds) {
        if (memberIds == null || memberIds.isEmpty()) {
            return;
        }
        delete [SELECT Id FROM CareTeamMember__c WHERE Id IN :memberIds];
    }

    private static CareTeam__c queryCareTeam(Id patientId) {
        List<CareTeam__c> teams = [
            SELECT Id, Name, Status__c
            FROM CareTeam__c
            WHERE Patient__c = :patientId
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        return teams.isEmpty() ? null : teams[0];
    }

    private static List<CareTeamMember__c> queryMembers(Set<Id> careTeamIds) {
        return [
            SELECT
                Id,
                Practitioner__c,
                Practitioner__r.First_Name__c,
                Practitioner__r.Last_Name__c,
                Role__c,
                Access_Level__c,
                Active__c
            FROM CareTeamMember__c
            WHERE Care_Team__c IN :careTeamIds
            ORDER BY Active__c DESC, CreatedDate ASC
        ];
    }

    private static CareTeamView toView(CareTeam__c careTeam, List<CareTeamMember__c> members) {
        CareTeamView view = new CareTeamView();
        view.careTeamId = careTeam.Id;
        view.name = careTeam.Name;
        view.status = careTeam.Status__c;
        view.members = new List<MemberView>();
        for (CareTeamMember__c member : members) {
            MemberView row = new MemberView();
            row.id = member.Id;
            row.practitionerId = member.Practitioner__c;
            row.practitionerName = practitionerName(member);
            row.role = member.Role__c;
            row.accessLevel = member.Access_Level__c;
            row.active = member.Active__c;
            view.members.add(row);
        }
        return view;
    }

    private static String practitionerName(CareTeamMember__c member) {
        if (member.Practitioner__r == null) {
            return '';
        }
        String first = member.Practitioner__r.First_Name__c == null
            ? ''
            : member.Practitioner__r.First_Name__c;
        String last = member.Practitioner__r.Last_Name__c == null
            ? ''
            : member.Practitioner__r.Last_Name__c;
        return (first + ' ' + last).trim();
    }
}
