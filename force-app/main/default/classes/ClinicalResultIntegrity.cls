public with sharing class ClinicalResultIntegrity {
  public static void beforeObservations(
    List<Observation__c> rows,
    Map<Id, Observation__c> oldMap
  ) {
    Set<Id> reportIds = new Set<Id>();
    for (Observation__c row : rows)
      if (row.DiagnosticReport__c != null)
        reportIds.add(row.DiagnosticReport__c);
    Map<Id, DiagnosticReport__c> reports = reportIds.isEmpty()
      ? new Map<Id, DiagnosticReport__c>()
      : new Map<Id, DiagnosticReport__c>(
          [
            SELECT Id, Patient__c, Encounter__c
            FROM DiagnosticReport__c
            WHERE Id IN :reportIds
          ]
        );
    for (Observation__c row : rows) {
      if (row.DiagnosticReport__c != null) {
        DiagnosticReport__c report = reports.get(row.DiagnosticReport__c);
        if (
          report == null ||
          report.Patient__c != row.Patient__c ||
          (row.Encounter__c != null &&
          report.Encounter__c != null &&
          row.Encounter__c != report.Encounter__c)
        ) {
          row.addError(
            'The observation report must belong to the same patient and encounter.'
          );
        } else if (row.Encounter__c == null) {
          row.Encounter__c = report.Encounter__c;
        }
      }
      Observation__c prior = oldMap == null ? null : oldMap.get(row.Id);
      if (
        prior != null &&
        measurementChanged(row, prior) &&
        row.Interpretation__c == prior.Interpretation__c
      ) {
        row.Interpretation__c = null;
      }
    }
  }

  public static void afterObservations(
    List<Observation__c> rows,
    Map<Id, Observation__c> oldMap
  ) {
    Set<Id> reportIds = new Set<Id>();
    Set<Id> amendedReportIds = new Set<Id>();
    for (Observation__c row : rows) {
      Observation__c prior = oldMap == null ? null : oldMap.get(row.Id);
      if (
        prior == null ||
        measurementChanged(row, prior) ||
        row.Interpretation__c != prior.Interpretation__c ||
        row.Status__c != prior.Status__c ||
        row.Effective_DateTime__c != prior.Effective_DateTime__c ||
        row.DiagnosticReport__c != prior.DiagnosticReport__c
      ) {
        if (row.DiagnosticReport__c != null) {
          reportIds.add(row.DiagnosticReport__c);
          if (prior != null)
            amendedReportIds.add(row.DiagnosticReport__c);
        }
        if (prior != null && prior.DiagnosticReport__c != null) {
          reportIds.add(prior.DiagnosticReport__c);
          amendedReportIds.add(prior.DiagnosticReport__c);
        }
      }
    }
    reopenReports(reportIds, amendedReportIds);
  }

  public static void afterDeletedObservations(List<Observation__c> rows) {
    Set<Id> reportIds = new Set<Id>();
    for (Observation__c row : rows)
      if (row.DiagnosticReport__c != null)
        reportIds.add(row.DiagnosticReport__c);
    reopenReports(reportIds, reportIds);
  }

  private static void reopenReports(
    Set<Id> reportIds,
    Set<Id> amendedReportIds
  ) {
    if (reportIds.isEmpty())
      return;
    List<DiagnosticReport__c> updates = [
      SELECT Id, Reviewed__c, Status__c
      FROM DiagnosticReport__c
      WHERE
        Id IN :reportIds
        AND (Reviewed__c = TRUE
        OR (Id IN :amendedReportIds
        AND Status__c = 'Final'))
    ];
    for (DiagnosticReport__c report : updates) {
      report.Reviewed__c = false;
      report.Reviewed_By__c = null;
      report.Reviewed_Date__c = null;
      if (report.Status__c == 'Final') {
        report.Status__c = 'Amended';
      }
    }
    if (!updates.isEmpty()) {
      update updates;
    }
  }

  public static void beforeReports(
    List<DiagnosticReport__c> rows,
    Map<Id, DiagnosticReport__c> oldMap
  ) {
    Set<Id> requestIds = new Set<Id>();
    Set<Id> encounterIds = new Set<Id>();
    for (DiagnosticReport__c row : rows) {
      if (row.ServiceRequest__c != null)
        requestIds.add(row.ServiceRequest__c);
      if (row.Encounter__c != null)
        encounterIds.add(row.Encounter__c);
    }
    Map<Id, ServiceRequest__c> requests = requestIds.isEmpty()
      ? new Map<Id, ServiceRequest__c>()
      : new Map<Id, ServiceRequest__c>(
          [
            SELECT Id, Patient__c, Encounter__c
            FROM ServiceRequest__c
            WHERE Id IN :requestIds
          ]
        );
    for (ServiceRequest__c request : requests.values()) {
      if (request.Encounter__c != null)
        encounterIds.add(request.Encounter__c);
    }
    Map<Id, Encounter__c> encounters = encounterIds.isEmpty()
      ? new Map<Id, Encounter__c>()
      : new Map<Id, Encounter__c>(
          [SELECT Id, Patient__c FROM Encounter__c WHERE Id IN :encounterIds]
        );
    for (DiagnosticReport__c row : rows) {
      if (row.ServiceRequest__c != null) {
        ServiceRequest__c request = requests.get(row.ServiceRequest__c);
        if (
          request == null ||
          request.Patient__c != row.Patient__c ||
          (row.Encounter__c != null &&
          request.Encounter__c != null &&
          row.Encounter__c != request.Encounter__c)
        ) {
          row.addError(
            'The service order must belong to the same patient and encounter as the report.'
          );
        } else if (row.Encounter__c == null) {
          row.Encounter__c = request.Encounter__c;
        }
      }
      if (
        row.Encounter__c != null &&
        (!encounters.containsKey(row.Encounter__c) ||
        encounters.get(row.Encounter__c).Patient__c != row.Patient__c)
      ) {
        row.addError('The report encounter must belong to the same patient.');
      }
      DiagnosticReport__c prior = oldMap == null ? null : oldMap.get(row.Id);
      Boolean changed =
        prior != null &&
        (row.Conclusion__c != prior.Conclusion__c ||
        row.Status__c != prior.Status__c ||
        row.Report_Code__c != prior.Report_Code__c ||
        row.Report_Code_System__c != prior.Report_Code_System__c ||
        row.Report_Display__c != prior.Report_Display__c ||
        row.Effective_DateTime__c != prior.Effective_DateTime__c ||
        row.Patient__c != prior.Patient__c ||
        row.Encounter__c != prior.Encounter__c ||
        row.ServiceRequest__c != prior.ServiceRequest__c);
      if (changed) {
        if (prior.Status__c == 'Final' && row.Status__c == 'Final')
          row.Status__c = 'Amended';
        row.Reviewed__c = false;
        row.Reviewed_By__c = null;
        row.Reviewed_Date__c = null;
      } else if (
        row.Reviewed__c == true && (prior == null || prior.Reviewed__c != true)
      ) {
        row.Reviewed_By__c = UserInfo.getUserId();
        row.Reviewed_Date__c = Datetime.now();
      } else if (row.Reviewed__c != true) {
        row.Reviewed_By__c = null;
        row.Reviewed_Date__c = null;
      } else if (prior != null) {
        row.Reviewed_By__c = prior.Reviewed_By__c;
        row.Reviewed_Date__c = prior.Reviewed_Date__c;
      }
    }
  }

  public static void afterReports(List<DiagnosticReport__c> rows) {
    Set<Id> completedRequestIds = new Set<Id>();
    for (DiagnosticReport__c row : rows) {
      if (
        row.ServiceRequest__c != null &&
        (row.Status__c == 'Final' ||
        row.Status__c == 'Amended')
      ) {
        completedRequestIds.add(row.ServiceRequest__c);
      }
    }
    if (completedRequestIds.isEmpty())
      return;
    List<ServiceRequest__c> requests = [
      SELECT Id, Status__c
      FROM ServiceRequest__c
      WHERE Id IN :completedRequestIds AND Status__c IN ('Active', 'On Hold')
    ];
    for (ServiceRequest__c request : requests)
      request.Status__c = 'Completed';
    if (!requests.isEmpty())
      update requests;
  }

  private static Boolean measurementChanged(
    Observation__c row,
    Observation__c prior
  ) {
    return row.Value_Quantity__c != prior.Value_Quantity__c ||
      row.Value_String__c != prior.Value_String__c ||
      row.Value_Unit__c != prior.Value_Unit__c ||
      row.Observation_Code__c != prior.Observation_Code__c ||
      row.Observation_Code_System__c != prior.Observation_Code_System__c;
  }
}
