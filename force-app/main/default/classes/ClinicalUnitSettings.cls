public with sharing class ClinicalUnitSettings {
  public static final String DEFAULT_RECORD_NAME = 'Default';
  public static final String DEFAULT_TEMPERATURE_UNIT = 'F';
  public static final String DEFAULT_MEASUREMENT_SYSTEM = 'Imperial';

  @TestVisible
  private static Preferences preferenceOverride;

  public class Preferences {
    @AuraEnabled
    public String temperatureUnit { get; set; }
    @AuraEnabled
    public String measurementSystem { get; set; }
  }

  public static Preferences getPreferences() {
    if (preferenceOverride != null) {
      return normalizedPreferences(preferenceOverride);
    }
    return preferencesFromMetadata(
      Clinical_Unit_Setting__mdt.getInstance(DEFAULT_RECORD_NAME)
    );
  }

  @TestVisible
  private static Preferences preferencesFromMetadata(
    Clinical_Unit_Setting__mdt setting
  ) {
    Preferences configured = new Preferences();
    if (setting != null) {
      configured.temperatureUnit = setting.Temperature_Unit__c;
      configured.measurementSystem = setting.Measurement_System__c;
    }
    return normalizedPreferences(configured);
  }

  private static Preferences normalizedPreferences(Preferences configured) {
    Preferences result = new Preferences();
    result.temperatureUnit = DEFAULT_TEMPERATURE_UNIT;
    result.measurementSystem = DEFAULT_MEASUREMENT_SYSTEM;
    if (new Set<String>{ 'F', 'Cel' }.contains(configured.temperatureUnit)) {
      result.temperatureUnit = configured.temperatureUnit;
    }
    if (
      new Set<String>{ 'Imperial', 'Metric' }
        .contains(configured.measurementSystem)
    ) {
      result.measurementSystem = configured.measurementSystem;
    }
    return result;
  }
}
