public with sharing class VitalsCaptureController {
    public class VitalInput {
        @AuraEnabled
        public String key { get; set; }
        @AuraEnabled
        public Decimal value { get; set; }
    }

    @TestVisible
    private class VitalDef {
        public String loinc;
        public String display;
        public String unit;
        public Decimal minValue;
        public Decimal maxValue;

        public VitalDef(String loinc, String display, String unit, Decimal minValue, Decimal maxValue) {
            this.loinc = loinc;
            this.display = display;
            this.unit = unit;
            this.minValue = minValue;
            this.maxValue = maxValue;
        }
    }

    private static final String CATEGORY_VITALS = 'Vital Signs';
    private static final String STATUS_FINAL = 'Final';
    private static final String CODE_SYSTEM_LOINC = 'LOINC';
    private static final String KEY_SYSTOLIC = 'systolic';
    private static final String KEY_DIASTOLIC = 'diastolic';

    @TestVisible
    private static final Map<String, VitalDef> VITAL_DEFS = new Map<String, VitalDef>{
        KEY_SYSTOLIC => new VitalDef('8480-6', 'Systolic blood pressure', 'mmHg', 50, 250),
        KEY_DIASTOLIC => new VitalDef('8462-4', 'Diastolic blood pressure', 'mmHg', 30, 160),
        'hr' => new VitalDef('8867-4', 'Heart rate', '/min', 20, 250),
        'rr' => new VitalDef('9279-1', 'Respiratory rate', '/min', 4, 80),
        'temp' => new VitalDef('8310-5', 'Body temperature', 'Cel', 30, 45),
        'spo2' => new VitalDef('59408-5', 'Oxygen saturation', '%', 50, 100),
        'height' => new VitalDef('8302-2', 'Body height', 'cm', 30, 250),
        'weight' => new VitalDef('29463-7', 'Body weight', 'kg', 0.5, 500)
    };

    @AuraEnabled
    public static List<Observation__c> saveVitals(Id encounterId, List<VitalInput> vitals) {
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

        List<VitalInput> filled = new List<VitalInput>();
        if (vitals != null) {
            for (VitalInput row : vitals) {
                if (row != null && row.value != null) {
                    filled.add(row);
                }
            }
        }
        if (filled.isEmpty()) {
            throw new AuraHandledException('Enter at least one vital.');
        }

        List<String> errors = validateVitals(filled);
        if (!errors.isEmpty()) {
            throw new AuraHandledException(String.join(errors, ' '));
        }

        Datetime effective = Datetime.now();
        Id patientId = encounters[0].Patient__c;
        List<Observation__c> observations = new List<Observation__c>();
        for (VitalInput row : filled) {
            VitalDef def = VITAL_DEFS.get(row.key);
            observations.add(
                new Observation__c(
                    Patient__c = patientId,
                    Encounter__c = encounterId,
                    Category__c = CATEGORY_VITALS,
                    Status__c = STATUS_FINAL,
                    Observation_Code_System__c = CODE_SYSTEM_LOINC,
                    Observation_Code__c = def.loinc,
                    Observation_Display__c = def.display,
                    Value_Quantity__c = row.value,
                    Value_Unit__c = def.unit,
                    Effective_DateTime__c = effective
                )
            );
        }
        insert observations;
        return observations;
    }

    @TestVisible
    private static List<String> validateVitals(List<VitalInput> vitals) {
        List<String> errors = new List<String>();
        Decimal systolic;
        Decimal diastolic;
        for (VitalInput row : vitals) {
            if (String.isBlank(row.key) || !VITAL_DEFS.containsKey(row.key)) {
                errors.add('Unknown vital: ' + String.valueOf(row.key) + '.');
                continue;
            }
            VitalDef def = VITAL_DEFS.get(row.key);
            if (row.value < def.minValue || row.value > def.maxValue) {
                errors.add(
                    def.display +
                        ' must be between ' +
                        String.valueOf(def.minValue) +
                        ' and ' +
                        String.valueOf(def.maxValue) +
                        ' ' +
                        def.unit +
                        '.'
                );
            }
            if (row.key == KEY_SYSTOLIC) {
                systolic = row.value;
            } else if (row.key == KEY_DIASTOLIC) {
                diastolic = row.value;
            }
        }
        if (systolic != null && diastolic != null && systolic < diastolic) {
            errors.add('Systolic blood pressure must be greater than or equal to diastolic.');
        }
        return errors;
    }
}
