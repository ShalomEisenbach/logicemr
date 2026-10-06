public with sharing class VitalsCaptureController {
  public class VitalInput {
    @AuraEnabled
    public String key { get; set; }
    @AuraEnabled
    public Decimal value { get; set; }
    @AuraEnabled
    public String unit { get; set; }
  }

  public class VitalValue {
    @AuraEnabled
    public Decimal value { get; set; }
    @AuraEnabled
    public String unit { get; set; }
    @AuraEnabled
    public String displayUnit { get; set; }
    @AuraEnabled
    public Boolean supportedUnit { get; set; }
    @AuraEnabled
    public Decimal minValue { get; set; }
    @AuraEnabled
    public Decimal maxValue { get; set; }
  }

  @TestVisible
  private class VitalDef {
    public String loinc;
    public String display;
    public String unit;
    public Decimal minValue;
    public Decimal maxValue;

    public VitalDef(
      String loinc,
      String display,
      String unit,
      Decimal minValue,
      Decimal maxValue
    ) {
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
    KEY_SYSTOLIC => new VitalDef(
      '8480-6',
      'Systolic blood pressure',
      'mmHg',
      50,
      250
    ),
    KEY_DIASTOLIC => new VitalDef(
      '8462-4',
      'Diastolic blood pressure',
      'mmHg',
      30,
      160
    ),
    'hr' => new VitalDef('8867-4', 'Heart rate', '/min', 20, 250),
    'rr' => new VitalDef('9279-1', 'Respiratory rate', '/min', 4, 80),
    'temp' => new VitalDef('8310-5', 'Body temperature', 'F', 86, 113),
    'spo2' => new VitalDef('59408-5', 'Oxygen saturation', '%', 50, 100),
    'height' => new VitalDef('8302-2', 'Body height', 'in', 12, 108),
    'weight' => new VitalDef('29463-7', 'Body weight', 'lbs', 1, 1100)
  };

  @AuraEnabled
  public static List<Observation__c> saveVitals(
    Id encounterId,
    List<VitalInput> vitals
  ) {
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

    Map<String, Observation__c> latestByCode = latestObservations(encounterId);
    List<VitalInput> validationInputs = new List<VitalInput>();
    validationInputs.addAll(filled);
    Set<String> suppliedKeys = new Set<String>();
    for (VitalInput row : filled) {
      if (suppliedKeys.contains(row.key)) {
        throw new AuraHandledException('Each vital may be supplied only once.');
      }
      suppliedKeys.add(row.key);
    }
    // A partial autosave must still validate BP against its recorded counterpart.
    if (
      suppliedKeys.contains(KEY_SYSTOLIC) ||
      suppliedKeys.contains(KEY_DIASTOLIC)
    ) {
      for (String key : new List<String>{ KEY_SYSTOLIC, KEY_DIASTOLIC }) {
        Observation__c existing = latestByCode.get(VITAL_DEFS.get(key).loinc);
        if (
          !suppliedKeys.contains(key) &&
          existing != null &&
          existing.Value_Quantity__c != null
        ) {
          VitalInput counterpart = new VitalInput();
          counterpart.key = key;
          counterpart.value = existing.Value_Quantity__c;
          counterpart.unit = existing.Value_Unit__c;
          if (normalizedUnit(key, counterpart.unit) == null) {
            throw new AuraHandledException(
              'Review the recorded blood pressure unit before editing it.'
            );
          }
          validationInputs.add(counterpart);
        }
      }
    }
    List<String> errors = validateVitals(validationInputs);
    if (!errors.isEmpty()) {
      throw new AuraHandledException(String.join(errors, ' '));
    }

    Datetime effective = Datetime.now();
    Id patientId = encounters[0].Patient__c;
    List<Observation__c> toInsert = new List<Observation__c>();
    List<Observation__c> toUpdate = new List<Observation__c>();
    for (VitalInput row : filled) {
      VitalDef def = VITAL_DEFS.get(row.key);
      String inputUnit = String.isBlank(row.unit) ? def.unit : row.unit.trim();
      Observation__c existing = latestByCode.get(def.loinc);
      if (existing != null) {
        if (normalizedUnit(row.key, existing.Value_Unit__c) == null) {
          throw new AuraHandledException(
            'Review the recorded unit for ' +
              def.display +
              ' before editing it.'
          );
        }
        Decimal storedValue = fromDefaultUnit(
            row.key,
            toDefaultUnit(row.key, row.value, inputUnit),
            existing.Value_Unit__c
          )
          .setScale(4);
        if (existing.Value_Quantity__c == storedValue) {
          continue;
        }
        existing.Value_Quantity__c = storedValue;
        // Keep supported source units; convert the entered quantity instead of relabeling it.
        existing.Effective_DateTime__c = effective;
        toUpdate.add(existing);
      } else {
        toInsert.add(
          new Observation__c(
            Patient__c = patientId,
            Encounter__c = encounterId,
            Category__c = CATEGORY_VITALS,
            Status__c = STATUS_FINAL,
            Observation_Code_System__c = CODE_SYSTEM_LOINC,
            Observation_Code__c = def.loinc,
            Observation_Display__c = def.display,
            Value_Quantity__c = row.value,
            Value_Unit__c = inputUnit,
            Effective_DateTime__c = effective
          )
        );
      }
    }
    if (!toUpdate.isEmpty()) {
      update toUpdate;
    }
    if (!toInsert.isEmpty()) {
      insert toInsert;
    }

    List<Observation__c> observations = new List<Observation__c>();
    observations.addAll(toUpdate);
    observations.addAll(toInsert);
    return observations;
  }

  @AuraEnabled
  public static Map<String, Decimal> getEncounterVitals(Id encounterId) {
    Map<String, Decimal> result = new Map<String, Decimal>();
    Map<String, VitalValue> details = getEncounterVitalDetails(encounterId);
    for (String key : details.keySet()) {
      VitalValue detail = details.get(key);
      if (detail.supportedUnit) {
        // Preserve the legacy API's F/in/lbs contract without discarding source units.
        result.put(key, toDefaultUnit(key, detail.value, detail.unit));
      }
    }
    return result;
  }

  @AuraEnabled
  public static Map<String, VitalValue> getEncounterVitalDetails(
    Id encounterId
  ) {
    Map<String, VitalValue> result = new Map<String, VitalValue>();
    if (encounterId == null) {
      return result;
    }

    Map<String, String> keyByLoinc = new Map<String, String>();
    for (String key : VITAL_DEFS.keySet()) {
      keyByLoinc.put(VITAL_DEFS.get(key).loinc, key);
    }

    for (Observation__c row : latestObservations(encounterId).values()) {
      String key = keyByLoinc.get(row.Observation_Code__c);
      if (key != null && row.Value_Quantity__c != null) {
        VitalDef def = VITAL_DEFS.get(key);
        String canonical = normalizedUnit(key, row.Value_Unit__c);
        VitalValue detail = new VitalValue();
        detail.value = row.Value_Quantity__c;
        detail.unit = row.Value_Unit__c;
        detail.supportedUnit = canonical != null;
        detail.displayUnit = canonical == 'Cel'
          ? '°C'
          : canonical == 'F' ? '°F' : row.Value_Unit__c;
        if (detail.supportedUnit) {
          detail.minValue = fromDefaultUnit(key, def.minValue, detail.unit);
          detail.maxValue = fromDefaultUnit(key, def.maxValue, detail.unit);
        }
        result.put(key, detail);
      }
    }
    return result;
  }

  private static Map<String, Observation__c> latestObservations(
    Id encounterId
  ) {
    Set<String> codes = new Set<String>();
    for (VitalDef def : VITAL_DEFS.values()) {
      codes.add(def.loinc);
    }
    Map<String, Observation__c> latestByCode = new Map<String, Observation__c>();
    for (Observation__c row : [
      SELECT
        Id,
        Observation_Code__c,
        Value_Quantity__c,
        Value_Unit__c,
        Effective_DateTime__c
      FROM Observation__c
      WHERE
        Encounter__c = :encounterId
        AND Category__c = :CATEGORY_VITALS
        AND Observation_Code__c IN :codes
        AND (Status__c = NULL
        OR Status__c != 'Cancelled')
      ORDER BY Effective_DateTime__c DESC NULLS LAST, CreatedDate DESC, Id DESC
    ]) {
      if (!latestByCode.containsKey(row.Observation_Code__c)) {
        latestByCode.put(row.Observation_Code__c, row);
      }
    }
    return latestByCode;
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
      String unit = String.isBlank(row.unit) ? def.unit : row.unit;
      if (normalizedUnit(row.key, unit) == null) {
        errors.add('Unsupported unit for ' + def.display + ': ' + unit + '.');
        continue;
      }
      Decimal defaultValue = toDefaultUnit(row.key, row.value, unit);
      if (defaultValue < def.minValue || defaultValue > def.maxValue) {
        errors.add(
          def.display +
            ' must be between ' +
            String.valueOf(fromDefaultUnit(row.key, def.minValue, unit)) +
            ' and ' +
            String.valueOf(fromDefaultUnit(row.key, def.maxValue, unit)) +
            ' ' +
            unit +
            '.'
        );
      }
      if (row.key == KEY_SYSTOLIC) {
        systolic = defaultValue;
      } else if (row.key == KEY_DIASTOLIC) {
        diastolic = defaultValue;
      }
    }
    if (systolic != null && diastolic != null && systolic < diastolic) {
      errors.add(
        'Systolic blood pressure must be greater than or equal to diastolic.'
      );
    }
    return errors;
  }

  private static String normalizedUnit(String key, String unit) {
    String candidate = unit == null ? '' : unit.trim().toLowerCase();
    if (key == 'temp') {
      if (new Set<String>{ 'f', '[degf]', 'degf', '°f' }.contains(candidate)) {
        return 'F';
      }
      if (new Set<String>{ 'cel', 'c', 'degc', '°c' }.contains(candidate)) {
        return 'Cel';
      }
    } else if (key == 'height') {
      if (new Set<String>{ 'in', '[in_i]' }.contains(candidate)) {
        return 'in';
      }
      if (candidate == 'cm' || candidate == 'm') {
        return candidate;
      }
    } else if (key == 'weight') {
      if (new Set<String>{ 'lbs', 'lb', '[lb_av]' }.contains(candidate)) {
        return 'lbs';
      }
      if (candidate == 'kg' || candidate == 'g') {
        return candidate;
      }
    } else if (key == KEY_SYSTOLIC || key == KEY_DIASTOLIC) {
      if (candidate == 'mmhg' || candidate == 'mm[hg]') {
        return 'mmHg';
      }
    } else if (key == 'hr' || key == 'rr') {
      if (candidate == '/min' || candidate == 'min-1') {
        return '/min';
      }
    } else if (key == 'spo2' && candidate == '%') {
      return '%';
    }
    return null;
  }

  private static Decimal toDefaultUnit(String key, Decimal value, String unit) {
    String canonical = normalizedUnit(key, unit);
    if (canonical == 'Cel') {
      return value * 9 / 5 + 32;
    }
    if (canonical == 'cm') {
      return value / 2.54;
    }
    if (canonical == 'm') {
      return value * 100 / 2.54;
    }
    if (canonical == 'kg') {
      return value / 0.45359237;
    }
    if (canonical == 'g') {
      return value / 453.59237;
    }
    return value;
  }

  private static Decimal fromDefaultUnit(
    String key,
    Decimal value,
    String unit
  ) {
    String canonical = normalizedUnit(key, unit);
    if (canonical == 'Cel') {
      return (value - 32) * 5 / 9;
    }
    if (canonical == 'cm') {
      return value * 2.54;
    }
    if (canonical == 'm') {
      return value * 2.54 / 100;
    }
    if (canonical == 'kg') {
      return value * 0.45359237;
    }
    if (canonical == 'g') {
      return value * 453.59237;
    }
    return value;
  }
}
