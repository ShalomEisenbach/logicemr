@IsTest
private class ClinicalUnitSettingsTest {
  @IsTest
  static void missingSettingsUseImperialFahrenheitDefaults() {
    ClinicalUnitSettings.Preferences settings = ClinicalUnitSettings.preferencesFromMetadata(
      null
    );
    System.assertEquals('F', settings.temperatureUnit);
    System.assertEquals('Imperial', settings.measurementSystem);
  }

  @IsTest
  static void invalidFieldsFallBackIndependentlyWithoutChangingMetadata() {
    Clinical_Unit_Setting__mdt invalid = new Clinical_Unit_Setting__mdt(
      Temperature_Unit__c = 'C',
      Measurement_System__c = 'metric'
    );
    ClinicalUnitSettings.Preferences fallback = ClinicalUnitSettings.preferencesFromMetadata(
      invalid
    );
    System.assertEquals('F', fallback.temperatureUnit);
    System.assertEquals('Imperial', fallback.measurementSystem);
    System.assertEquals('C', invalid.Temperature_Unit__c);
    System.assertEquals('metric', invalid.Measurement_System__c);

    invalid.Measurement_System__c = 'Metric';
    ClinicalUnitSettings.Preferences metric = ClinicalUnitSettings.preferencesFromMetadata(
      invalid
    );
    System.assertEquals('F', metric.temperatureUnit);
    System.assertEquals('Metric', metric.measurementSystem);

    invalid.Temperature_Unit__c = 'Cel';
    invalid.Measurement_System__c = null;
    ClinicalUnitSettings.Preferences celsius = ClinicalUnitSettings.preferencesFromMetadata(
      invalid
    );
    System.assertEquals('Cel', celsius.temperatureUnit);
    System.assertEquals('Imperial', celsius.measurementSystem);
  }

  @IsTest
  static void getPreferencesReadsTheFixedDefaultRecord() {
    Clinical_Unit_Setting__mdt persisted = Clinical_Unit_Setting__mdt.getInstance(
      'Default'
    );
    System.assertNotEquals(null, persisted, 'The packaged default must exist');
    ClinicalUnitSettings.Preferences settings = ClinicalUnitSettings.getPreferences();
    System.assertEquals(
      persisted.Temperature_Unit__c,
      settings.temperatureUnit
    );
    System.assertEquals(
      persisted.Measurement_System__c,
      settings.measurementSystem
    );
  }

  @IsTest
  static void preferenceOverrideReturnsValidatedIndependentValues() {
    ClinicalUnitSettings.Preferences overrideValue = new ClinicalUnitSettings.Preferences();
    overrideValue.temperatureUnit = 'Cel';
    overrideValue.measurementSystem = 'Metric';
    ClinicalUnitSettings.preferenceOverride = overrideValue;
    ClinicalUnitSettings.Preferences result = ClinicalUnitSettings.getPreferences();
    System.assertEquals('Cel', result.temperatureUnit);
    System.assertEquals('Metric', result.measurementSystem);
    result.temperatureUnit = 'F';
    result.measurementSystem = 'Imperial';
    System.assertEquals(
      'Cel',
      ClinicalUnitSettings.getPreferences().temperatureUnit,
      'Consumers must not mutate the configured preference through a returned DTO'
    );
    System.assertEquals(
      'Metric',
      ClinicalUnitSettings.getPreferences().measurementSystem
    );
    overrideValue.temperatureUnit = 'cel';
    System.assertEquals(
      'F',
      ClinicalUnitSettings.getPreferences().temperatureUnit
    );
    System.assertEquals(
      'Metric',
      ClinicalUnitSettings.getPreferences().measurementSystem
    );
  }
}
