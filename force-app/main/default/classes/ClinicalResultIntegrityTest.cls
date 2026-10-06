@IsTest
private class ClinicalResultIntegrityTest {
  @IsTest
  static void measurementCorrectionClearsStaleClassificationAndReopensReviewedReport() {
    Patient__c patient = patient('RESULT-CORRECTION');
    DiagnosticReport__c report = report(patient.Id);
    Observation__c observation = observation(
      patient.Id,
      report.Id,
      6.2,
      'Critical'
    );
    update new DiagnosticReport__c(Id = report.Id, Reviewed__c = true);
    update new Observation__c(Id = observation.Id, Value_Quantity__c = 4.2);
    Observation__c corrected = [
      SELECT Interpretation__c
      FROM Observation__c
      WHERE Id = :observation.Id
    ];
    DiagnosticReport__c amended = [
      SELECT Status__c, Reviewed__c, Reviewed_By__c, Reviewed_Date__c
      FROM DiagnosticReport__c
      WHERE Id = :report.Id
    ];
    System.assertEquals(
      null,
      corrected.Interpretation__c,
      'Old critical classification must not survive a changed measurement'
    );
    System.assertEquals('Amended', amended.Status__c);
    System.assertEquals(false, amended.Reviewed__c);
    System.assertEquals(null, amended.Reviewed_By__c);
    System.assertEquals(null, amended.Reviewed_Date__c);
  }

  @IsTest
  static void updatedClassificationPersistsAndUnrelatedEditKeepsInterpretation() {
    Patient__c patient = patient('RESULT-CLASSIFY');
    Observation__c observation = observation(patient.Id, null, 6.2, 'Critical');
    update new Observation__c(
      Id = observation.Id,
      Value_Quantity__c = 4.2,
      Interpretation__c = 'Normal'
    );
    update new Observation__c(
      Id = observation.Id,
      Observation_Display__c = 'Serum potassium'
    );
    System.assertEquals(
      'Normal',
      [SELECT Interpretation__c FROM Observation__c WHERE Id = :observation.Id]
      .Interpretation__c
    );
  }

  @IsTest
  static void reviewedConclusionAmendmentRequiresAnotherReviewAndCannotForgeReviewer() {
    Patient__c patient = patient('RESULT-PROVENANCE');
    DiagnosticReport__c report = report(patient.Id);
    update new DiagnosticReport__c(
      Id = report.Id,
      Reviewed__c = true,
      Reviewed_Date__c = Datetime.newInstance(2000, 1, 1, 0, 0, 0)
    );
    DiagnosticReport__c reviewed = [
      SELECT Reviewed_By__c, Reviewed_Date__c
      FROM DiagnosticReport__c
      WHERE Id = :report.Id
    ];
    System.assertEquals(UserInfo.getUserId(), reviewed.Reviewed_By__c);
    System.assert(
      reviewed.Reviewed_Date__c > Datetime.newInstance(2000, 1, 1, 0, 0, 0)
    );
    update new DiagnosticReport__c(
      Id = report.Id,
      Reviewed_Date__c = Datetime.newInstance(2000, 1, 1, 0, 0, 0)
    );
    System.assertEquals(
      reviewed.Reviewed_Date__c,
      [SELECT Reviewed_Date__c FROM DiagnosticReport__c WHERE Id = :report.Id]
      .Reviewed_Date__c,
      'Review provenance is server-controlled'
    );
    update new DiagnosticReport__c(
      Id = report.Id,
      Status__c = 'Amended',
      Conclusion__c = 'Updated conclusion'
    );
    System.assertEquals(
      false,
      [SELECT Reviewed__c FROM DiagnosticReport__c WHERE Id = :report.Id]
      .Reviewed__c
    );
  }

  @IsTest
  static void linkedFinalReportCompletesOrderAndInfersItsEncounter() {
    Patient__c patient = patient('RESULT-ORDER');
    Encounter__c encounter = new Encounter__c(
      Patient__c = patient.Id,
      Status__c = 'In Progress',
      Class__c = 'Outpatient'
    );
    insert encounter;
    ServiceRequest__c order = new ServiceRequest__c(
      Patient__c = patient.Id,
      Encounter__c = encounter.Id,
      Status__c = 'Active',
      Service_Display__c = 'Metabolic panel'
    );
    insert order;
    DiagnosticReport__c added = DiagnosticReportPanelController.addLinkedReport(
      patient.Id,
      'LOINC',
      '24323-8',
      'Metabolic panel',
      null,
      'Laboratory',
      'Final',
      Datetime.now(),
      Datetime.now(),
      'Completed result',
      null,
      order.Id
    );
    DiagnosticReport__c stored = [
      SELECT Encounter__c, ServiceRequest__c, Status__c, Reviewed__c
      FROM DiagnosticReport__c
      WHERE Id = :added.Id
    ];
    System.assertEquals(encounter.Id, stored.Encounter__c);
    System.assertEquals(order.Id, stored.ServiceRequest__c);
    System.assertEquals(
      'Final',
      stored.Status__c,
      'Creating a linked final report is not an amendment'
    );
    System.assertEquals(false, stored.Reviewed__c);
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM DiagnosticReport__c
        WHERE ServiceRequest__c = :order.Id
      ]
    );
    System.assertEquals(
      'Completed',
      [SELECT Status__c FROM ServiceRequest__c WHERE Id = :order.Id].Status__c
    );
  }

  @IsTest
  static void crossPatientReportOrderAndObservationLinksAreRejected() {
    Patient__c first = patient('RESULT-FIRST');
    Patient__c second = patient('RESULT-SECOND');
    ServiceRequest__c order = new ServiceRequest__c(
      Patient__c = first.Id,
      Status__c = 'Active',
      Service_Display__c = 'Lab'
    );
    insert order;
    DiagnosticReport__c invalid = new DiagnosticReport__c(
      Patient__c = second.Id,
      ServiceRequest__c = order.Id,
      Status__c = 'Final',
      Report_Display__c = 'Wrong patient'
    );
    System.assertEquals(false, Database.insert(invalid, false).isSuccess());
    DiagnosticReport__c report = report(first.Id);
    Observation__c wrong = new Observation__c(
      Patient__c = second.Id,
      DiagnosticReport__c = report.Id,
      Status__c = 'Final',
      Observation_Code__c = '2823-3',
      Observation_Display__c = 'Potassium',
      Value_Quantity__c = 4.2
    );
    System.assertEquals(false, Database.insert(wrong, false).isSuccess());
  }

  private static Patient__c patient(String mrn) {
    Patient__c row = new Patient__c(MRN__c = mrn, Last_Name__c = 'Results');
    insert row;
    return row;
  }
  private static DiagnosticReport__c report(Id patientId) {
    DiagnosticReport__c row = new DiagnosticReport__c(
      Patient__c = patientId,
      Status__c = 'Final',
      Report_Display__c = 'Metabolic panel',
      Conclusion__c = 'Initial result'
    );
    insert row;
    return row;
  }
  private static Observation__c observation(
    Id patientId,
    Id reportId,
    Decimal value,
    String interpretation
  ) {
    Observation__c row = new Observation__c(
      Patient__c = patientId,
      DiagnosticReport__c = reportId,
      Status__c = 'Final',
      Category__c = 'Laboratory',
      Observation_Code_System__c = 'LOINC',
      Observation_Code__c = '2823-3',
      Observation_Display__c = 'Potassium',
      Value_Quantity__c = value,
      Value_Unit__c = 'mmol/L',
      Interpretation__c = interpretation,
      Effective_DateTime__c = Datetime.now()
    );
    insert row;
    return row;
  }
}
