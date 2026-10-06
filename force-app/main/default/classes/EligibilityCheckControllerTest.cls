@IsTest
private class EligibilityCheckControllerTest {
  @IsTest
  static void runCheckReturnsPersistedResultForCoverage() {
    Fixture data = insertFixture(true);
    EligibilityCheckController.runEligibilityOverride = true;
    EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
      activeSetting()
    };
    Test.setMock(HttpCalloutMock.class, new ActiveMock());

    Test.startTest();
    Eligibility_Check__c stored = EligibilityCheckController.runCheck(
      data.coverage.Id
    );
    List<Eligibility_Check__c> prior = EligibilityCheckController.getChecks(
      data.coverage.Id
    );
    List<Eligibility_Check__c> blank = EligibilityCheckController.getChecks(
      null
    );
    Test.stopTest();

    System.assertNotEquals(
      null,
      stored.Id,
      'Controller should return the persisted check'
    );
    System.assertEquals(
      data.coverage.Id,
      stored.Coverage__c,
      'Check should belong to the coverage'
    );
    System.assertEquals(
      'Active',
      stored.Status__c,
      'Parsed status should be Active'
    );
    System.assertEquals(
      'Gold Plan HMO (John Doe)',
      stored.Plan_Name__c,
      'Parsed plan should identify the checked patient'
    );
    System.assertEquals(15, stored.Copay__c, 'Parsed copay should be returned');
    System.assertEquals(1, prior.size(), 'getChecks should list the new check');
    System.assertEquals(
      stored.Id,
      prior[0].Id,
      'Prior list should start with the latest check'
    );
    System.assertEquals(
      0,
      blank.size(),
      'Null coverage should return no checks'
    );
  }

  @IsTest
  static void getChecksOrdersPriorRowsNewestFirst() {
    Fixture data = insertFixture(true);
    Eligibility_Check__c older = new Eligibility_Check__c(
      Patient__c = data.patient.Id,
      Coverage__c = data.coverage.Id,
      Status__c = 'Inactive',
      Plan_Name__c = 'Old Plan',
      Checked_Date__c = Datetime.now().addDays(-3)
    );
    Eligibility_Check__c newer = new Eligibility_Check__c(
      Patient__c = data.patient.Id,
      Coverage__c = data.coverage.Id,
      Status__c = 'Active',
      Plan_Name__c = 'New Plan',
      Checked_Date__c = Datetime.now().addHours(-1)
    );
    insert new List<Eligibility_Check__c>{ older, newer };

    Test.startTest();
    List<Eligibility_Check__c> rows = EligibilityCheckController.getChecks(
      data.coverage.Id
    );
    Test.stopTest();

    System.assertEquals(2, rows.size(), 'Both prior checks should be returned');
    System.assertEquals(
      newer.Id,
      rows[0].Id,
      'Newest checked date should be first'
    );
    System.assertEquals(
      older.Id,
      rows[1].Id,
      'Older checked date should be second'
    );
  }

  @IsTest
  static void runCheckRequiresAnExistingCoverage() {
    EligibilityCheckController.runEligibilityOverride = true;
    Boolean missingThrown = false;
    Boolean unknownThrown = false;

    Test.startTest();
    try {
      EligibilityCheckController.runCheck(null);
    } catch (AuraHandledException e) {
      missingThrown = e.getMessage().contains('Coverage Id is required');
    }
    try {
      EligibilityCheckController.runCheck(UserInfo.getUserId());
    } catch (AuraHandledException e) {
      unknownThrown = e.getMessage().contains('Coverage was not found');
    }
    Test.stopTest();

    System.assertEquals(true, missingThrown, 'Null coverage should throw');
    System.assertEquals(
      true,
      unknownThrown,
      'Unknown coverage Id should throw'
    );
  }

  @IsTest
  static void runCheckDeniedWithoutPermission() {
    Fixture data = insertFixture(true);
    EligibilityCheckController.runEligibilityOverride = false;
    Boolean thrown = false;

    Test.startTest();
    try {
      EligibilityCheckController.runCheck(data.coverage.Id);
    } catch (AuraHandledException e) {
      thrown = e.getMessage().contains('do not have permission');
    }
    Test.stopTest();

    System.assertEquals(
      true,
      thrown,
      'Users without LogicEMR_Run_Eligibility should be blocked'
    );
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Eligibility_Check__c
        WHERE Coverage__c = :data.coverage.Id
      ],
      'Denied checks should not persist a result'
    );
  }

  @IsTest
  static void runCheckSurfacesServiceErrors() {
    Fixture data = insertFixture(true);
    EligibilityCheckController.runEligibilityOverride = true;
    EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>();
    Boolean thrown = false;

    Test.startTest();
    try {
      EligibilityCheckController.runCheck(data.coverage.Id);
    } catch (AuraHandledException e) {
      thrown = e.getMessage().contains('No active Eligibility Setting');
    }
    Test.stopTest();

    System.assertEquals(
      true,
      thrown,
      'Missing setting should surface as AuraHandledException'
    );
  }

  @IsTest
  static void queueFiltersAndSummarizesAttemptDetails() {
    Fixture data = insertFixture(false);
    EligibilityCheckController.runEligibilityOverride = true;
    insert new List<Eligibility_Check__c>{
      new Eligibility_Check__c(
        Patient__c = data.patient.Id,
        Coverage__c = data.coverage.Id,
        Status__c = 'Error',
        Checked_Date__c = Datetime.now(),
        Error_Message__c = 'Invalid member',
        Application_Mode__c = 'test',
        Stedi_Trace_Id__c = 'trace-123'
      ),
      new Eligibility_Check__c(
        Patient__c = data.patient.Id,
        Coverage__c = data.coverage.Id,
        Status__c = 'Inactive',
        Checked_Date__c = Datetime.now().addDays(-2)
      ),
      new Eligibility_Check__c(
        Patient__c = data.patient.Id,
        Status__c = 'Pending'
      )
    };
    Test.startTest();
    EligibilityCheckController.QueueResult errors = EligibilityCheckController.getWorkQueue(
      'Error',
      '60054',
      'Doe',
      Date.today(),
      Date.today()
    );
    System.assertEquals(
      1,
      errors.rows.size(),
      'All filters should combine, including the entire end date'
    );
    System.assertEquals('test', errors.rows[0].mode);
    System.assertEquals('trace-123', errors.rows[0].traceId);
    System.assertEquals('Invalid member', errors.rows[0].error);
    System.assertEquals('Aetna', errors.rows[0].payer);
    System.assertEquals(true, errors.rows[0].canRetry);
    System.assertEquals(false, errors.hasMore);
    EligibilityCheckController.QueueResult success = EligibilityCheckController.getWorkQueue(
      'Success',
      null,
      null,
      null,
      null
    );
    System.assertEquals(
      1,
      success.rows.size(),
      'Inactive coverage is a successful check'
    );
    System.assertEquals(false, success.rows[0].canRetry);
    System.assertEquals(
      'Unknown',
      success.rows[0].mode,
      'Never infer production for historical records'
    );
    System.assertEquals(
      1,
      EligibilityCheckController.getWorkQueue(
          'Pending',
          null,
          null,
          Date.today(),
          Date.today()
        )
        .rows.size(),
      'Missing checked date falls back to creation'
    );
    System.assertEquals(
      0,
      EligibilityCheckController.getWorkQueue(
          'All',
          'missing',
          null,
          null,
          null
        )
        .rows.size()
    );
    System.assertEquals(
      0,
      EligibilityCheckController.getWorkQueue('All', null, '%', null, null)
        .rows.size(),
      'Search wildcards must be literal'
    );
    System.assertEquals(
      3,
      EligibilityCheckController.getWorkQueue(
          null,
          null,
          data.patient.MRN__c,
          null,
          null
        )
        .rows.size()
    );
    Test.stopTest();
  }

  @IsTest
  static void queueDisclosesResultLimit() {
    Fixture data = insertFixture(false);
    EligibilityCheckController.runEligibilityOverride = true;
    List<Eligibility_Check__c> checks = new List<Eligibility_Check__c>();
    for (Integer i = 0; i < 101; i++)
      checks.add(
        new Eligibility_Check__c(
          Patient__c = data.patient.Id,
          Status__c = 'Error'
        )
      );
    insert checks;
    Test.startTest();
    EligibilityCheckController.QueueResult result = EligibilityCheckController.getWorkQueue(
      'All',
      null,
      null,
      null,
      null
    );
    Test.stopTest();
    System.assertEquals(100, result.rows.size());
    System.assertEquals(true, result.hasMore);
    System.assertEquals(
      false,
      result.rows[0].canRetry,
      'A check with no coverage cannot be retried'
    );
  }

  @IsTest
  static void queueRejectsBadFiltersAndUnauthorizedAccess() {
    EligibilityCheckController.runEligibilityOverride = true;
    for (String outcome : new List<String>{ 'Invalid', 'All' }) {
      try {
        EligibilityCheckController.getWorkQueue(
          outcome,
          null,
          null,
          Date.today(),
          Date.today().addDays(-1)
        );
        System.assert(false, 'Reversed dates must fail');
      } catch (AuraHandledException e) {
        System.assert(e.getMessage().contains('Start date'));
      }
    }
    try {
      EligibilityCheckController.getWorkQueue(
        'Invalid',
        null,
        null,
        null,
        null
      );
      System.assert(false);
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('valid outcome'));
    }
    EligibilityCheckController.runEligibilityOverride = false;
    try {
      EligibilityCheckController.getWorkQueue('All', null, null, null, null);
      System.assert(false);
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('permission'));
    }
    try {
      EligibilityCheckController.retryCheck(null);
      System.assert(false);
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('permission'));
    }
  }

  @IsTest
  static void retryPreservesOriginalAndServiceType() {
    Fixture data = insertFixture(true);
    Eligibility_Check__c original = new Eligibility_Check__c(
      Patient__c = data.patient.Id,
      Coverage__c = data.coverage.Id,
      Status__c = 'Error',
      Service_Type__c = '98',
      Error_Message__c = 'Original failure'
    );
    insert original;
    EligibilityCheckController.runEligibilityOverride = true;
    EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>{
      activeSetting()
    };
    Test.setMock(HttpCalloutMock.class, new ActiveMock());
    Test.startTest();
    Eligibility_Check__c retried = EligibilityCheckController.retryCheck(
      original.Id
    );
    Test.stopTest();
    System.assertNotEquals(original.Id, retried.Id);
    System.assertEquals(data.patient.Id, retried.Patient__c);
    System.assertEquals(data.coverage.Id, retried.Coverage__c);
    System.assertEquals('98', retried.Service_Type__c);
    System.assertEquals(
      'Error',
      [SELECT Status__c FROM Eligibility_Check__c WHERE Id = :original.Id]
      .Status__c
    );
    System.assertEquals(
      2,
      [
        SELECT COUNT()
        FROM Eligibility_Check__c
        WHERE Coverage__c = :data.coverage.Id
      ]
    );
  }

  @IsTest
  static void retryValidatesOriginalAndSurfacesErrors() {
    Fixture data = insertFixture(false);
    EligibilityCheckController.runEligibilityOverride = true;
    for (Id invalidId : new List<Id>{ null, data.patient.Id }) {
      try {
        EligibilityCheckController.retryCheck(invalidId);
        System.assert(false);
      } catch (AuraHandledException e) {
        System.assert(
          e.getMessage().contains(invalidId == null ? 'required' : 'not found')
        );
      }
    }
    Eligibility_Check__c check = new Eligibility_Check__c(
      Patient__c = data.patient.Id,
      Status__c = 'Active'
    );
    insert check;
    try {
      EligibilityCheckController.retryCheck(check.Id);
      System.assert(false);
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('Only failed'));
    }
    check.Status__c = 'Error';
    update check;
    try {
      EligibilityCheckController.retryCheck(check.Id);
      System.assert(false);
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('original patient'));
    }
    check.Coverage__c = data.coverage.Id;
    update check;
    EligibilityProviderFactory.settingsOverride = new List<Eligibility_Setting__mdt>();
    try {
      EligibilityCheckController.retryCheck(check.Id);
      System.assert(false);
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('No active Eligibility Setting'));
    }
  }

  private static Fixture insertFixture(Boolean withNpi) {
    Fixture data = new Fixture();
    data.patient = new Patient__c(
      First_Name__c = 'John',
      Last_Name__c = 'Doe',
      Date_of_Birth__c = Date.newInstance(1970, 1, 1),
      MRN__c = 'MRN-ELIG-UI-' +
        String.valueOf(Math.abs(Crypto.getRandomInteger())),
      Status__c = 'Active'
    );
    insert data.patient;
    data.payer = new Payer__c(
      Name = 'Aetna',
      Type__c = 'Commercial',
      Active__c = true,
      Payer_Identifier__c = '60054'
    );
    insert data.payer;
    data.coverage = new Coverage__c(
      Patient__c = data.patient.Id,
      Payer__c = data.payer.Id,
      Member_Id__c = 'MEM-UI-100',
      Type__c = 'Medical',
      Status__c = 'Active',
      Priority__c = 'Primary'
    );
    insert data.coverage;
    if (withNpi) {
      insert new Practitioner__c(
        First_Name__c = 'Ada',
        Last_Name__c = 'Lovelace',
        NPI__c = '1234567893',
        Active__c = true
      );
    }
    return data;
  }

  private static Eligibility_Setting__mdt activeSetting() {
    return new Eligibility_Setting__mdt(
      Provider_Name__c = 'Stedi',
      Named_Credential__c = 'Stedi_Eligibility',
      Default_Service_Type__c = '30',
      Active__c = true
    );
  }

  private class Fixture {
    Patient__c patient;
    Payer__c payer;
    Coverage__c coverage;
  }

  private class ActiveMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      System.assert(
        request.getEndpoint().startsWith('callout:'),
        request.getEndpoint()
      );
      System.assertEquals(null, request.getHeader('Authorization'));
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody(
        '{"benefitsInformation":[' +
          '{"code":"1","name":"Active Coverage","planCoverage":"Gold Plan HMO","serviceTypeCodes":["30"]},' +
          '{"code":"B","benefitAmount":"15","inPlanNetworkIndicatorCode":"Y","serviceTypeCodes":["30"]}' +
          ']}'
      );
      return response;
    }
  }
}
