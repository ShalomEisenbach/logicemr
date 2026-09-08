public with sharing class EligibilityPayerMatch {
    @AuraEnabled
    public String payerId;
    @AuraEnabled
    public String name;

    public EligibilityPayerMatch() {
    }

    public EligibilityPayerMatch(String payerId, String name) {
        this.payerId = payerId;
        this.name = name;
    }
}
