public with sharing class PatientChartSummaryController {
    public ClinicalDocumentService.ChartSummary summary { get; private set; }

    public PatientChartSummaryController() {
        Id patientId = ApexPages.currentPage().getParameters().get('id');
        summary = ClinicalDocumentService.getChartSummary(patientId);
    }

    public Boolean getHasPatient() {
        return summary != null && summary.patient != null;
    }
}
