@IsTest
private class AllergyReviewServiceTest {
  @IsTest
  static void allergyMutationsAndAttestationsRequirePermission() {
    Profile minimumProfile = [
      SELECT Id
      FROM Profile
      WHERE Name IN ('Minimum Access - Salesforce', 'Standard User')
      ORDER BY Name
      LIMIT 1
    ];
    User reader = new User(
      Alias = 'allread',
      LastName = 'AllergyReader',
      Email = 'allergy.reader@logicemr.test',
      Username = 'allergy.reader.' +
        Crypto.getRandomInteger() +
        '@logicemr.test',
      ProfileId = minimumProfile.Id,
      TimeZoneSidKey = 'America/New_York',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    insert reader;
    Patient__c patient;
    AllergyIntolerance__c allergy;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      patient = new Patient__c(
        MRN__c = 'ALL-PERMISSIONS',
        Last_Name__c = 'Review'
      );
      insert patient;
      allergy = new AllergyIntolerance__c(
        Patient__c = patient.Id,
        Allergen_Display__c = 'Penicillin',
        Clinical_Status__c = 'Active'
      );
      insert allergy;
    }
    Integer denied = 0;
    System.runAs(reader) {
      try {
        AllergyPanelController.reviewAllergies(patient.Id, false);
      } catch (AuraHandledException expected) {
        denied++;
      }
      try {
        AllergyPanelController.addAllergy(
          patient.Id,
          'RxNorm',
          null,
          'Other allergy',
          null,
          null,
          null,
          null,
          null
        );
      } catch (AuraHandledException expected) {
        denied++;
      }
      try {
        AllergyPanelController.inactivateAllergies(new List<Id>{ allergy.Id });
      } catch (AuraHandledException expected) {
        denied++;
      }
      try {
        AllergyPanelController.deleteAllergies(new List<Id>{ allergy.Id });
      } catch (AuraHandledException expected) {
        denied++;
      }
    }
    System.assertEquals(
      4,
      denied,
      'Allergy writes must enforce the current user permissions.'
    );
    System.assertEquals(
      'Unknown',
      AllergyPanelController.getReviewState(patient.Id).status
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM AllergyIntolerance__c WHERE Patient__c = :patient.Id]
    );
    System.assertEquals(
      'Active',
      [
        SELECT Clinical_Status__c
        FROM AllergyIntolerance__c
        WHERE Id = :allergy.Id
      ]
      .Clinical_Status__c
    );
  }
  @IsTest
  static void emptyChartRemainsUnknownUntilExplicitlyReviewed() {
    Patient__c patient = new Patient__c(
      MRN__c = 'ALL-REVIEW-1',
      Last_Name__c = 'Review'
    );
    insert patient;
    System.assertEquals(
      'Unknown',
      AllergyPanelController.getReviewState(patient.Id).status
    );
    AllergyPanelController.reviewAllergies(patient.Id, true);
    Patient__c reviewed = [
      SELECT
        Allergy_Review_Status__c,
        Allergy_Reviewed_By__c,
        Allergy_Reviewed_At__c
      FROM Patient__c
      WHERE Id = :patient.Id
    ];
    System.assertEquals(
      'No known allergies',
      reviewed.Allergy_Review_Status__c
    );
    System.assertEquals(UserInfo.getUserId(), reviewed.Allergy_Reviewed_By__c);
    System.assertNotEquals(null, reviewed.Allergy_Reviewed_At__c);
  }

  @IsTest
  static void changedAllergyInvalidatesReviewAndBlocksContradictoryNkda() {
    Patient__c patient = new Patient__c(
      MRN__c = 'ALL-REVIEW-2',
      Last_Name__c = 'Review'
    );
    insert patient;
    AllergyPanelController.reviewAllergies(patient.Id, true);
    AllergyIntolerance__c allergy = new AllergyIntolerance__c(
      Patient__c = patient.Id,
      Allergen_Display__c = 'Penicillin',
      Clinical_Status__c = 'Active'
    );
    insert allergy;
    System.assertEquals(
      'Unknown',
      AllergyPanelController.getReviewState(patient.Id).status
    );
    Patient__c contradictory = new Patient__c(
      Id = patient.Id,
      Allergy_Review_Status__c = 'No known allergies'
    );
    Database.SaveResult result = Database.update(contradictory, false);
    System.assertEquals(false, result.isSuccess());
    System.assert(
      result.getErrors()[0].getMessage().contains('Active allergies')
    );
    AllergyPanelController.reviewAllergies(patient.Id, false);
    System.assertEquals(
      'Allergies recorded',
      AllergyPanelController.getReviewState(patient.Id).status
    );
    allergy.Reaction__c = 'Rash';
    update allergy;
    System.assertEquals(
      'Unknown',
      AllergyPanelController.getReviewState(patient.Id).status
    );
    allergy.Clinical_Status__c = 'Inactive';
    update allergy;
    AllergyPanelController.reviewAllergies(patient.Id, true);
    System.assertEquals(
      'No known allergies',
      AllergyPanelController.getReviewState(patient.Id).status
    );
  }
}
