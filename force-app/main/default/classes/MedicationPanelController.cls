public with sharing class MedicationPanelController {
    private static final Integer MAX_RESULTS = 200;
    private static final String STATUS_ACTIVE = 'Active';
    private static final String STATUS_STOPPED = 'Stopped';
    private static final String INTENT_ORDER = 'Order';
    private static final String CODE_SYSTEM_RXNORM = 'RxNorm';
    private static final Set<String> ALLOWED_ROUTES = new Set<String>{
        'Oral',
        'Intravenous',
        'Intramuscular',
        'Subcutaneous',
        'Topical',
        'Inhalation',
        'Transdermal',
        'Other'
    };
    private static final Set<String> ALLOWED_INTENTS = new Set<String>{ 'Order', 'Plan', 'Proposal' };
    private static final Set<String> ALLOWED_STATUSES = new Set<String>{
        'Active',
        'On Hold',
        'Cancelled',
        'Completed',
        'Stopped',
        'Draft'
    };

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
        Id codeReferenceId,
        String dosageText,
        Decimal doseQuantity,
        String doseUnit,
        String frequency,
        String route,
        String intent,
        String status,
        Id requesterId
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
        if (!String.isBlank(route) && !ALLOWED_ROUTES.contains(route)) {
            throw new AuraHandledException('Route is not a valid medication route.');
        }
        String resolvedIntent = String.isBlank(intent) ? INTENT_ORDER : intent;
        if (!ALLOWED_INTENTS.contains(resolvedIntent)) {
            throw new AuraHandledException('Intent must be Order, Plan, or Proposal.');
        }
        String resolvedStatus = String.isBlank(status) ? STATUS_ACTIVE : status;
        if (!ALLOWED_STATUSES.contains(resolvedStatus)) {
            throw new AuraHandledException('Status is not a valid medication status.');
        }

        MedicationRequest__c request = new MedicationRequest__c(
            Patient__c = patientId,
            Status__c = resolvedStatus,
            Intent__c = resolvedIntent,
            Medication_Ref__c = codeReferenceId,
            Medication_Code_System__c = codeSystem,
            Medication_Code__c = code,
            Medication_Display__c = display,
            Dosage_Text__c = dosageText,
            Dose_Quantity__c = doseQuantity,
            Dose_Unit__c = doseUnit,
            Frequency__c = frequency,
            Route__c = route,
            Requester__c = requesterId,
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

    @AuraEnabled
    public static void deleteOrders(List<Id> requestIds) {
        if (requestIds == null || requestIds.isEmpty()) {
            return;
        }
        delete [SELECT Id FROM MedicationRequest__c WHERE Id IN :requestIds];
    }

    @AuraEnabled
    public static void deleteReportedMedications(List<Id> statementIds) {
        if (statementIds == null || statementIds.isEmpty()) {
            return;
        }
        delete [SELECT Id FROM MedicationStatement__c WHERE Id IN :statementIds];
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
                Dose_Quantity__c,
                Dose_Unit__c,
                Frequency__c,
                Route__c,
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
