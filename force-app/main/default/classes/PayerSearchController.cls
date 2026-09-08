public with sharing class PayerSearchController {
    @AuraEnabled
    public static List<EligibilityPayerMatch> searchPayers(String query) {
        try {
            return EligibilityProviderFactory.getProvider().searchPayers(query);
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    @AuraEnabled
    public static Payer__c getPayer(Id payerId) {
        if (payerId == null) {
            throw auraError('Payer Id is required.');
        }
        List<Payer__c> rows = [
            SELECT Id, Name, Payer_Identifier__c
            FROM Payer__c
            WHERE Id = :payerId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw auraError('Payer was not found.');
        }
        return rows[0];
    }

    @AuraEnabled
    public static Payer__c savePayerIdentifier(Id payerId, String stediPayerId) {
        if (payerId == null) {
            throw auraError('Payer Id is required.');
        }
        if (String.isBlank(stediPayerId)) {
            throw auraError('Stedi payer id is required.');
        }
        List<Payer__c> rows = [
            SELECT Id, Name, Payer_Identifier__c
            FROM Payer__c
            WHERE Id = :payerId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw auraError('Payer was not found.');
        }
        Payer__c payer = rows[0];
        payer.Payer_Identifier__c = stediPayerId.trim();
        update payer;
        return payer;
    }

    private static AuraHandledException auraError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
