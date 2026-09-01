public with sharing class CareTeamMemberSharingHandler {
    public static void handle(
        List<CareTeamMember__c> newRecords,
        List<CareTeamMember__c> oldRecords
    ) {
        new SharingOperations().recalculate(newRecords, oldRecords);
    }

    private without sharing class SharingOperations {
        public void recalculate(
            List<CareTeamMember__c> newRecords,
            List<CareTeamMember__c> oldRecords
        ) {
            Set<Id> careTeamIds = collectCareTeamIds(newRecords, oldRecords);
            if (careTeamIds.isEmpty()) {
                return;
            }

            Set<Id> patientIds = queryPatientIds(careTeamIds);
            if (patientIds.isEmpty()) {
                return;
            }

            Map<Id, Id> careTeamToPatient = queryCareTeamPatients(patientIds);
            List<CareTeamMember__c> activeMembers = queryActiveMembers(
                careTeamToPatient.keySet()
            );
            Map<Id, Practitioner__c> practitioners = queryPractitioners(activeMembers);
            Map<Id, Patient__c> patients = new Map<Id, Patient__c>(
                [SELECT Id, OwnerId FROM Patient__c WHERE Id IN :patientIds]
            );

            Map<String, Patient__Share> desiredShares = buildDesiredShares(
                activeMembers,
                careTeamToPatient,
                practitioners,
                patients
            );
            syncShares(patientIds, desiredShares);
        }

        private Set<Id> collectCareTeamIds(
            List<CareTeamMember__c> newRecords,
            List<CareTeamMember__c> oldRecords
        ) {
            Set<Id> careTeamIds = new Set<Id>();
            addCareTeamIds(careTeamIds, newRecords);
            addCareTeamIds(careTeamIds, oldRecords);
            return careTeamIds;
        }

        private void addCareTeamIds(Set<Id> careTeamIds, List<CareTeamMember__c> records) {
            if (records == null) {
                return;
            }
            for (CareTeamMember__c member : records) {
                if (member.Care_Team__c != null) {
                    careTeamIds.add(member.Care_Team__c);
                }
            }
        }

        private Set<Id> queryPatientIds(Set<Id> careTeamIds) {
            Set<Id> patientIds = new Set<Id>();
            for (CareTeam__c careTeam : [
                SELECT Patient__c
                FROM CareTeam__c
                WHERE Id IN :careTeamIds AND Patient__c != NULL
            ]) {
                patientIds.add(careTeam.Patient__c);
            }
            return patientIds;
        }

        private Map<Id, Id> queryCareTeamPatients(Set<Id> patientIds) {
            Map<Id, Id> careTeamToPatient = new Map<Id, Id>();
            for (CareTeam__c careTeam : [
                SELECT Id, Patient__c
                FROM CareTeam__c
                WHERE Patient__c IN :patientIds
            ]) {
                careTeamToPatient.put(careTeam.Id, careTeam.Patient__c);
            }
            return careTeamToPatient;
        }

        private List<CareTeamMember__c> queryActiveMembers(Set<Id> careTeamIds) {
            return [
                SELECT
                    Id,
                    Care_Team__c,
                    Practitioner__c,
                    User__c,
                    Access_Level__c,
                    Active__c
                FROM CareTeamMember__c
                WHERE Care_Team__c IN :careTeamIds AND Active__c = TRUE
            ];
        }

        private Map<Id, Practitioner__c> queryPractitioners(
            List<CareTeamMember__c> members
        ) {
            Set<Id> practitionerIds = new Set<Id>();
            for (CareTeamMember__c member : members) {
                if (member.User__c == null && member.Practitioner__c != null) {
                    practitionerIds.add(member.Practitioner__c);
                }
            }
            if (practitionerIds.isEmpty()) {
                return new Map<Id, Practitioner__c>();
            }
            return new Map<Id, Practitioner__c>(
                [SELECT Id, User__c FROM Practitioner__c WHERE Id IN :practitionerIds]
            );
        }

        private Map<String, Patient__Share> buildDesiredShares(
            List<CareTeamMember__c> members,
            Map<Id, Id> careTeamToPatient,
            Map<Id, Practitioner__c> practitioners,
            Map<Id, Patient__c> patients
        ) {
            Map<String, Patient__Share> desiredShares = new Map<String, Patient__Share>();
            for (CareTeamMember__c member : members) {
                Id patientId = careTeamToPatient.get(member.Care_Team__c);
                Id userId = resolveUserId(member, practitioners);
                if (patientId == null || userId == null) {
                    continue;
                }
                Patient__c patient = patients.get(patientId);
                if (patient == null || patient.OwnerId == userId) {
                    continue;
                }

                String accessLevel = member.Access_Level__c == 'Edit' ? 'Edit' : 'Read';
                String shareKey = shareKey(patientId, userId);
                Patient__Share existingDesired = desiredShares.get(shareKey);
                if (existingDesired == null) {
                    Patient__Share shareRow = new Patient__Share();
                    shareRow.ParentId = patientId;
                    shareRow.UserOrGroupId = userId;
                    shareRow.AccessLevel = accessLevel;
                    shareRow.RowCause = Schema.Patient__Share.RowCause.Care_Team_Access__c;
                    desiredShares.put(shareKey, shareRow);
                } else if (accessLevel == 'Edit') {
                    existingDesired.AccessLevel = 'Edit';
                }
            }
            return desiredShares;
        }

        private Id resolveUserId(
            CareTeamMember__c member,
            Map<Id, Practitioner__c> practitioners
        ) {
            if (member.User__c != null) {
                return member.User__c;
            }
            Practitioner__c practitioner = practitioners.get(member.Practitioner__c);
            return practitioner == null ? null : practitioner.User__c;
        }

        private void syncShares(Set<Id> patientIds, Map<String, Patient__Share> desiredShares) {
            Map<String, Patient__Share> existingShares = new Map<String, Patient__Share>();
            for (Patient__Share shareRow : [
                SELECT Id, ParentId, UserOrGroupId, AccessLevel, RowCause
                FROM Patient__Share
                WHERE
                    ParentId IN :patientIds
                    AND RowCause = :Schema.Patient__Share.RowCause.Care_Team_Access__c
            ]) {
                existingShares.put(
                    shareKey(shareRow.ParentId, shareRow.UserOrGroupId),
                    shareRow
                );
            }

            List<Patient__Share> toInsert = new List<Patient__Share>();
            List<Patient__Share> toUpdate = new List<Patient__Share>();
            List<Patient__Share> toDelete = new List<Patient__Share>();

            for (String shareKey : desiredShares.keySet()) {
                Patient__Share desired = desiredShares.get(shareKey);
                Patient__Share existing = existingShares.get(shareKey);
                if (existing == null) {
                    toInsert.add(desired);
                } else if (existing.AccessLevel != desired.AccessLevel) {
                    existing.AccessLevel = desired.AccessLevel;
                    toUpdate.add(existing);
                }
            }
            for (String shareKey : existingShares.keySet()) {
                if (!desiredShares.containsKey(shareKey)) {
                    toDelete.add(existingShares.get(shareKey));
                }
            }

            if (!toInsert.isEmpty()) {
                insert toInsert;
            }
            if (!toUpdate.isEmpty()) {
                update toUpdate;
            }
            if (!toDelete.isEmpty()) {
                delete toDelete;
            }
        }

        private String shareKey(Id patientId, Id userId) {
            return String.valueOf(patientId) + ':' + String.valueOf(userId);
        }
    }
}
