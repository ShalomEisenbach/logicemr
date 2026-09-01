public with sharing class PatientSearchController {
    private static final Integer MAX_RESULTS = 50;

    @AuraEnabled(cacheable=true)
    public static List<Patient__c> search(String searchTerm) {
        if (String.isBlank(searchTerm)) {
            return new List<Patient__c>();
        }

        String likePattern = '%' + searchTerm.trim() + '%';
        return [
            SELECT
                Id,
                Last_Name__c,
                First_Name__c,
                MRN__c,
                Date_of_Birth__c,
                Status__c
            FROM Patient__c
            WHERE
                Last_Name__c LIKE :likePattern
                OR First_Name__c LIKE :likePattern
                OR MRN__c LIKE :likePattern
            ORDER BY Last_Name__c, First_Name__c, MRN__c
            LIMIT :MAX_RESULTS
        ];
    }
}
