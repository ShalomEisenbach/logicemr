public with sharing class PrescriptionPadController {
    public ClinicalDocumentService.PrescriptionPad pad { get; private set; }

    public PrescriptionPadController() {
        Id patientId = ApexPages.currentPage().getParameters().get('id');
        String idsParam = ApexPages.currentPage().getParameters().get('ids');
        List<Id> requestIds = new List<Id>();
        if (String.isNotBlank(idsParam)) {
            for (String token : idsParam.split(',')) {
                String trimmed = token == null ? '' : token.trim();
                if (String.isBlank(trimmed)) {
                    continue;
                }
                try {
                    requestIds.add((Id) trimmed);
                } catch (Exception e) {
                    // Ignore malformed ids so PDF can still render valid selections.
                }
            }
        }
        pad = ClinicalDocumentService.getPrescriptionPad(patientId, requestIds);
    }

    public Boolean getHasPatient() {
        return pad != null && pad.patient != null;
    }

    public Boolean getHasPrescriptions() {
        return pad != null && pad.prescriptions != null && !pad.prescriptions.isEmpty();
    }
}
