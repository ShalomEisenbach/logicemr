public with sharing class PatientClaimsController {
    private static final String MANAGE_CLAIMS_PERMISSION = 'LogicEMR_Manage_Claims';

    @TestVisible
    private static Boolean manageClaimsOverride;

    public class ClaimSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Id encounterId;
        @AuraEnabled public String encounterName;
        @AuraEnabled public Date dateOfService;
        @AuraEnabled public String status;
        @AuraEnabled public String renderingPractitionerName;
        @AuraEnabled public String payerName;
        @AuraEnabled public Decimal totalCharges;
        @AuraEnabled public Datetime readyDate;
        @AuraEnabled public String validationMessages;
    }

    @AuraEnabled(cacheable=true)
    public static List<ClaimSummary> getPatientSuperbills(Id patientId) {
        requireManageClaims();
        if (patientId == null) {
            throw new AuraHandledException('Patient Id is required.');
        }

        List<ClaimSummary> summaries = new List<ClaimSummary>();
        for (Superbill__c superbill : [
            SELECT Id, Name, Encounter__c, Encounter__r.Name, Date_of_Service__c, Status__c,
                   Rendering_Practitioner__r.Name, Coverage__r.Payer__r.Name, Ready_Date__c,
                   Validation_Messages__c,
                   (SELECT Charge_Amount__c FROM Charge_Lines__r)
            FROM Superbill__c
            WHERE Patient__c = :patientId
            ORDER BY Date_of_Service__c DESC NULLS LAST, CreatedDate DESC
            LIMIT 100
        ]) {
            ClaimSummary summary = new ClaimSummary();
            summary.id = superbill.Id;
            summary.name = superbill.Name;
            summary.encounterId = superbill.Encounter__c;
            summary.encounterName = superbill.Encounter__r == null ? null : superbill.Encounter__r.Name;
            summary.dateOfService = superbill.Date_of_Service__c;
            summary.status = superbill.Status__c;
            summary.renderingPractitionerName = superbill.Rendering_Practitioner__r == null
                ? null
                : superbill.Rendering_Practitioner__r.Name;
            summary.payerName = superbill.Coverage__r == null || superbill.Coverage__r.Payer__r == null
                ? null
                : superbill.Coverage__r.Payer__r.Name;
            summary.totalCharges = 0;
            for (Charge_Line__c charge : superbill.Charge_Lines__r) {
                if (charge.Charge_Amount__c != null) {
                    summary.totalCharges += charge.Charge_Amount__c;
                }
            }
            summary.readyDate = superbill.Ready_Date__c;
            summary.validationMessages = superbill.Validation_Messages__c;
            summaries.add(summary);
        }
        return summaries;
    }

    private static void requireManageClaims() {
        Boolean allowed = manageClaimsOverride != null
            ? manageClaimsOverride
            : FeatureManagement.checkPermission(MANAGE_CLAIMS_PERMISSION);
        if (!allowed) {
            throw new AuraHandledException('You do not have permission to manage claims.');
        }
    }
}
