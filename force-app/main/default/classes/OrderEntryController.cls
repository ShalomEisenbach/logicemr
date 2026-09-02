public with sharing class OrderEntryController {
    public class ServiceOrderInput {
        @AuraEnabled
        public String category { get; set; }
        @AuraEnabled
        public String codeSystem { get; set; }
        @AuraEnabled
        public String code { get; set; }
        @AuraEnabled
        public String display { get; set; }
        @AuraEnabled
        public Id codeReferenceId { get; set; }
        @AuraEnabled
        public String priority { get; set; }
        @AuraEnabled
        public String reason { get; set; }
    }

    public class MedicationOrderInput {
        @AuraEnabled
        public String codeSystem { get; set; }
        @AuraEnabled
        public String code { get; set; }
        @AuraEnabled
        public String display { get; set; }
        @AuraEnabled
        public Id codeReferenceId { get; set; }
        @AuraEnabled
        public String dosageText { get; set; }
        @AuraEnabled
        public Decimal doseQuantity { get; set; }
        @AuraEnabled
        public String doseUnit { get; set; }
        @AuraEnabled
        public String frequency { get; set; }
        @AuraEnabled
        public String route { get; set; }
    }

    private static final Set<String> SERVICE_CATEGORIES = new Set<String>{
        'Lab',
        'Imaging',
        'Referral'
    };
    private static final Set<String> SERVICE_CODE_SYSTEMS = new Set<String>{ 'CPT', 'LOINC' };
    private static final String MED_CODE_SYSTEM = 'RxNorm';
    private static final String SERVICE_STATUS_ACTIVE = 'Active';
    private static final String MED_STATUS_ACTIVE = 'Active';
    private static final String MED_INTENT_ORDER = 'Order';

    @AuraEnabled
    public static List<ServiceRequest__c> createServiceOrders(
        Id encounterId,
        List<ServiceOrderInput> inputs
    ) {
        Encounter__c encounter = requireEncounter(encounterId);
        if (inputs == null || inputs.isEmpty()) {
            throw new AuraHandledException('At least one service order is required.');
        }

        List<ServiceRequest__c> rows = new List<ServiceRequest__c>();
        Datetime authored = Datetime.now();
        for (ServiceOrderInput input : inputs) {
            if (input == null) {
                throw new AuraHandledException('Service order is required.');
            }
            if (String.isBlank(input.display)) {
                throw new AuraHandledException('Service display is required.');
            }
            if (String.isBlank(input.category) || !SERVICE_CATEGORIES.contains(input.category)) {
                throw new AuraHandledException('Category must be Lab, Imaging, or Referral.');
            }
            if (String.isBlank(input.codeSystem) || !SERVICE_CODE_SYSTEMS.contains(input.codeSystem)) {
                throw new AuraHandledException('Code system must be CPT or LOINC.');
            }
            rows.add(
                new ServiceRequest__c(
                    Patient__c = encounter.Patient__c,
                    Encounter__c = encounter.Id,
                    Category__c = input.category,
                    Status__c = SERVICE_STATUS_ACTIVE,
                    Service_Ref__c = input.codeReferenceId,
                    Service_Code_System__c = input.codeSystem,
                    Service_Code__c = input.code,
                    Service_Display__c = input.display,
                    Priority__c = input.priority,
                    Reason__c = input.reason,
                    Authored_On__c = authored
                )
            );
        }
        insert rows;
        return rows;
    }

    @AuraEnabled
    public static List<MedicationRequest__c> createMedicationOrders(
        Id encounterId,
        List<MedicationOrderInput> inputs
    ) {
        Encounter__c encounter = requireEncounter(encounterId);
        if (inputs == null || inputs.isEmpty()) {
            throw new AuraHandledException('At least one medication order is required.');
        }

        List<MedicationRequest__c> rows = new List<MedicationRequest__c>();
        Datetime authored = Datetime.now();
        for (MedicationOrderInput input : inputs) {
            if (input == null) {
                throw new AuraHandledException('Medication order is required.');
            }
            if (String.isBlank(input.display)) {
                throw new AuraHandledException('Medication display is required.');
            }
            if (String.isBlank(input.codeSystem) || input.codeSystem != MED_CODE_SYSTEM) {
                throw new AuraHandledException('Code system must be RxNorm.');
            }
            rows.add(
                new MedicationRequest__c(
                    Patient__c = encounter.Patient__c,
                    Encounter__c = encounter.Id,
                    Status__c = MED_STATUS_ACTIVE,
                    Intent__c = MED_INTENT_ORDER,
                    Medication_Ref__c = input.codeReferenceId,
                    Medication_Code_System__c = MED_CODE_SYSTEM,
                    Medication_Code__c = input.code,
                    Medication_Display__c = input.display,
                    Dosage_Text__c = input.dosageText,
                    Dose_Quantity__c = input.doseQuantity,
                    Dose_Unit__c = input.doseUnit,
                    Frequency__c = input.frequency,
                    Route__c = input.route,
                    Authored_On__c = authored
                )
            );
        }
        insert rows;
        return rows;
    }

    private static Encounter__c requireEncounter(Id encounterId) {
        if (encounterId == null) {
            throw new AuraHandledException('Encounter Id is required.');
        }
        List<Encounter__c> encounters = [
            SELECT Id, Patient__c
            FROM Encounter__c
            WHERE Id = :encounterId
            LIMIT 1
        ];
        if (encounters.isEmpty()) {
            throw new AuraHandledException('Encounter was not found.');
        }
        return encounters[0];
    }
}
