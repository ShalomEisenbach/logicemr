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

    public class EncounterOrderRow implements Comparable {
        @AuraEnabled
        public Id id { get; set; }
        @AuraEnabled
        public String orderType { get; set; }
        @AuraEnabled
        public String display { get; set; }
        @AuraEnabled
        public String code { get; set; }
        @AuraEnabled
        public String codeSystem { get; set; }
        @AuraEnabled
        public String status { get; set; }
        @AuraEnabled
        public String detail { get; set; }
        @AuraEnabled
        public Datetime authoredOn { get; set; }
        @AuraEnabled
        public String orderedBy { get; set; }
        @AuraEnabled
        public String objectApiName { get; set; }

        public Integer compareTo(Object other) {
            EncounterOrderRow that = (EncounterOrderRow) other;
            if (this.authoredOn == that.authoredOn) {
                return 0;
            }
            if (this.authoredOn == null) {
                return 1;
            }
            if (that.authoredOn == null) {
                return -1;
            }
            return this.authoredOn > that.authoredOn ? -1 : 1;
        }
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
    private static final String ORDER_TYPE_PRESCRIPTION = 'Prescription';
    private static final Integer MAX_ORDERS = 200;

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
        Id requesterId = currentPractitionerId();
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
                    Requester__c = requesterId,
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
        Id requesterId = currentPractitionerId();
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
                    Requester__c = requesterId,
                    Authored_On__c = authored
                )
            );
        }
        insert rows;
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<EncounterOrderRow> getEncounterOrders(Id encounterId) {
        List<EncounterOrderRow> rows = new List<EncounterOrderRow>();
        if (encounterId == null) {
            return rows;
        }

        for (ServiceRequest__c request : [
            SELECT
                Id,
                Category__c,
                Service_Display__c,
                Service_Code__c,
                Service_Code_System__c,
                Status__c,
                Priority__c,
                Reason__c,
                Authored_On__c,
                Requester__r.First_Name__c,
                Requester__r.Last_Name__c,
                CreatedBy.Name
            FROM ServiceRequest__c
            WHERE Encounter__c = :encounterId
            ORDER BY Authored_On__c DESC NULLS LAST
            LIMIT :MAX_ORDERS
        ]) {
            EncounterOrderRow row = new EncounterOrderRow();
            row.id = request.Id;
            row.orderType = request.Category__c;
            row.display = request.Service_Display__c;
            row.code = request.Service_Code__c;
            row.codeSystem = request.Service_Code_System__c;
            row.status = request.Status__c;
            row.detail = firstNonBlank(request.Priority__c, request.Reason__c);
            row.authoredOn = request.Authored_On__c;
            row.orderedBy = orderedByName(
                request.Requester__r,
                request.CreatedBy.Name
            );
            row.objectApiName = ServiceRequest__c.SObjectType.getDescribe().getName();
            rows.add(row);
        }

        for (MedicationRequest__c request : [
            SELECT
                Id,
                Medication_Display__c,
                Medication_Code__c,
                Medication_Code_System__c,
                Status__c,
                Dosage_Text__c,
                Frequency__c,
                Route__c,
                Authored_On__c,
                Requester__r.First_Name__c,
                Requester__r.Last_Name__c,
                CreatedBy.Name
            FROM MedicationRequest__c
            WHERE Encounter__c = :encounterId
            ORDER BY Authored_On__c DESC NULLS LAST
            LIMIT :MAX_ORDERS
        ]) {
            EncounterOrderRow row = new EncounterOrderRow();
            row.id = request.Id;
            row.orderType = ORDER_TYPE_PRESCRIPTION;
            row.display = request.Medication_Display__c;
            row.code = request.Medication_Code__c;
            row.codeSystem = request.Medication_Code_System__c;
            row.status = request.Status__c;
            row.detail = firstNonBlank(
                request.Dosage_Text__c,
                firstNonBlank(request.Frequency__c, request.Route__c)
            );
            row.authoredOn = request.Authored_On__c;
            row.orderedBy = orderedByName(
                request.Requester__r,
                request.CreatedBy.Name
            );
            row.objectApiName = MedicationRequest__c.SObjectType.getDescribe().getName();
            rows.add(row);
        }

        rows.sort();
        if (rows.size() <= MAX_ORDERS) {
            return rows;
        }

        List<EncounterOrderRow> trimmed = new List<EncounterOrderRow>();
        for (Integer i = 0; i < MAX_ORDERS; i++) {
            trimmed.add(rows[i]);
        }
        return trimmed;
    }

    private static String orderedByName(Practitioner__c requester, String createdByName) {
        if (requester != null) {
            String composed = ((requester.First_Name__c == null ? '' : requester.First_Name__c) +
                    ' ' +
                    (requester.Last_Name__c == null ? '' : requester.Last_Name__c))
                .trim();
            if (String.isNotBlank(composed)) {
                return composed;
            }
        }
        return createdByName;
    }

    private static Id currentPractitionerId() {
        List<Practitioner__c> practitioners = [
            SELECT Id
            FROM Practitioner__c
            WHERE User__c = :UserInfo.getUserId()
            LIMIT 1
        ];
        return practitioners.isEmpty() ? null : practitioners[0].Id;
    }

    private static String firstNonBlank(String left, String right) {
        return String.isBlank(left) ? right : left;
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
