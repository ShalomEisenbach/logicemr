public with sharing class MedicationPanelController {
    private static final Integer MAX_RESULTS = 200;
    private static final String STATUS_ACTIVE = 'Active';
    private static final String STATUS_STOPPED = 'Stopped';
    private static final String INTENT_ORDER = 'Order';
    private static final String CODE_SYSTEM_RXNORM = 'RxNorm';

    public class MedicationPanelView {
        @AuraEnabled
        public List<MedicationRequest__c> activeOrders;
        @AuraEnabled
        public List<MedicationStatement__c> reportedMedications;
    }

    @AuraEnabled(cacheable=true)
    public static MedicationPanelView getMedications(Id patientId) {
        MedicationPanelView view = new MedicationPanelView();
        view.activeOrders = new List<MedicationRequest__c>();
        view.reportedMedications = new List<MedicationStatement__c>();
        if (patientId == null) {
            return view;
        }

        Set<Id> patientIds = new Set<Id>{ patientId };
        view.activeOrders = queryActiveOrders(patientIds);
        view.reportedMedications = queryReportedMedications(patientIds);
        return view;
    }

    @AuraEnabled
    public static MedicationRequest__c addMedication(
        Id patientId,
        String codeSystem,
        String code,
        String display,
        Id codeReferenceId
    ) {
        if (patientId == null) {
            throw new AuraHandledException('Patient Id is required.');
        }
        if (String.isBlank(display)) {
            throw new AuraHandledException('Medication display is required.');
        }
        if (String.isBlank(codeSystem) || codeSystem != CODE_SYSTEM_RXNORM) {
            throw new AuraHandledException('Code system must be RxNorm.');
        }

        MedicationRequest__c request = new MedicationRequest__c(
            Patient__c = patientId,
            Status__c = STATUS_ACTIVE,
            Intent__c = INTENT_ORDER,
            Medication_Ref__c = codeReferenceId,
            Medication_Code_System__c = codeSystem,
            Medication_Code__c = code,
            Medication_Display__c = display,
            Authored_On__c = System.now()
        );
        insert request;
        return request;
    }

    @AuraEnabled
    public static void renewOrders(List<Id> requestIds) {
        if (requestIds == null || requestIds.isEmpty()) {
            return;
        }

        Datetime authoredOn = System.now();
        List<MedicationRequest__c> requests = [
            SELECT Id, Status__c, Authored_On__c
            FROM MedicationRequest__c
            WHERE Id IN :requestIds
        ];
        for (MedicationRequest__c request : requests) {
            request.Status__c = STATUS_ACTIVE;
            request.Authored_On__c = authoredOn;
        }
        if (!requests.isEmpty()) {
            update requests;
        }
    }

    @AuraEnabled
    public static void discontinueOrders(List<Id> requestIds) {
        if (requestIds == null || requestIds.isEmpty()) {
            return;
        }

        List<MedicationRequest__c> requests = [
            SELECT Id, Status__c
            FROM MedicationRequest__c
            WHERE Id IN :requestIds AND Status__c != :STATUS_STOPPED
        ];
        for (MedicationRequest__c request : requests) {
            request.Status__c = STATUS_STOPPED;
        }
        if (!requests.isEmpty()) {
            update requests;
        }
    }

    private static List<MedicationRequest__c> queryActiveOrders(Set<Id> patientIds) {
        return [
            SELECT
                Id,
                Medication_Code_System__c,
                Medication_Code__c,
                Medication_Display__c,
                Status__c,
                Intent__c,
                Dosage_Text__c,
                Authored_On__c
            FROM MedicationRequest__c
            WHERE Patient__c IN :patientIds AND Status__c = :STATUS_ACTIVE
            ORDER BY Medication_Display__c ASC NULLS LAST
            LIMIT :MAX_RESULTS
        ];
    }

    private static List<MedicationStatement__c> queryReportedMedications(Set<Id> patientIds) {
        return [
            SELECT
                Id,
                Medication_Code_System__c,
                Medication_Code__c,
                Medication_Display__c,
                Status__c,
                Source__c,
                Dosage_Text__c
            FROM MedicationStatement__c
            WHERE Patient__c IN :patientIds AND Status__c = :STATUS_ACTIVE
            ORDER BY Medication_Display__c ASC NULLS LAST
            LIMIT :MAX_RESULTS
        ];
    }
}
