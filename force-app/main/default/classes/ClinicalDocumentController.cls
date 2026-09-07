public with sharing class ClinicalDocumentController {
    public static final String DOC_CHART_SUMMARY = 'ChartSummary';
    public static final String DOC_PRESCRIPTION = 'Prescription';

    public class SendResult {
        @AuraEnabled
        public Boolean success { get; set; }
        @AuraEnabled
        public String message { get; set; }
    }

    public class DocumentContext {
        @AuraEnabled
        public String defaultEmail { get; set; }
        @AuraEnabled
        public String patientName { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static String getDefaultEmail(Id patientId) {
        DocumentContext context = getDocumentContext(patientId);
        return context == null ? null : context.defaultEmail;
    }

    @AuraEnabled(cacheable=true)
    public static DocumentContext getDocumentContext(Id patientId) {
        DocumentContext context = new DocumentContext();
        if (patientId == null) {
            return context;
        }
        Patient__c patient = ClinicalDocumentService.queryPatient(patientId);
        if (patient == null) {
            return context;
        }
        context.defaultEmail = patient.Email__c;
        String first = patient.First_Name__c == null ? '' : patient.First_Name__c.trim();
        String last = patient.Last_Name__c == null ? '' : patient.Last_Name__c.trim();
        context.patientName = (first + ' ' + last).trim();
        if (String.isBlank(context.patientName)) {
            context.patientName = 'Patient';
        }
        return context;
    }

    @AuraEnabled
    public static String getDocumentUrl(Id patientId, String docType, List<Id> recordIds) {
        PageReference pageRef = buildPageReference(patientId, docType, recordIds);
        return pageRef.getUrl();
    }

    @AuraEnabled
    public static SendResult sendDocument(
        Id patientId,
        String docType,
        List<Id> recordIds,
        String toAddress,
        String subject,
        String message
    ) {
        SendResult result = new SendResult();
        result.success = false;

        if (patientId == null) {
            result.message = 'Patient Id is required.';
            return result;
        }
        if (String.isBlank(toAddress)) {
            result.message = 'A recipient email address is required.';
            return result;
        }
        String normalizedType = normalizeDocType(docType);
        if (normalizedType == null) {
            result.message = 'Document type must be ChartSummary or Prescription.';
            return result;
        }

        Patient__c patient = ClinicalDocumentService.queryPatient(patientId);
        if (patient == null) {
            result.message = 'Patient not found.';
            return result;
        }

        List<Id> resolvedIds = recordIds == null ? new List<Id>() : recordIds;
        if (normalizedType == DOC_PRESCRIPTION) {
            if (resolvedIds.isEmpty()) {
                result.message = 'Select at least one prescription to email.';
                return result;
            }
            Integer ownedCount = [
                SELECT COUNT()
                FROM MedicationRequest__c
                WHERE Id IN :resolvedIds AND Patient__c = :patientId
            ];
            if (ownedCount == 0) {
                result.message = 'No matching prescriptions found for this patient.';
                return result;
            }
        }

        PageReference pageRef = buildPageReference(patientId, normalizedType, resolvedIds);
        Blob pdfBlob;
        if (Test.isRunningTest()) {
            pdfBlob = Blob.valueOf('TEST_PDF_CONTENT');
        } else {
            pdfBlob = pageRef.getContentAsPDF();
        }

        String fileName = normalizedType == DOC_PRESCRIPTION
            ? 'Prescription.pdf'
            : 'PatientChartSummary.pdf';
        String resolvedSubject = String.isBlank(subject)
            ? defaultSubject(normalizedType, patient)
            : subject.trim();

        Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
        attachment.setFileName(fileName);
        attachment.setBody(pdfBlob);
        attachment.setContentType('application/pdf');

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ toAddress.trim() });
        mail.setSubject(resolvedSubject);
        mail.setPlainTextBody(
            String.isBlank(message)
                ? 'Please find the attached clinical document.'
                : message.trim()
        );
        mail.setFileAttachments(new List<Messaging.EmailFileAttachment>{ attachment });
        mail.setSaveAsActivity(false);

        Messaging.SendEmailResult[] sendResults = Messaging.sendEmail(
            new List<Messaging.SingleEmailMessage>{ mail },
            false
        );
        if (sendResults != null && !sendResults.isEmpty() && sendResults[0].isSuccess()) {
            result.success = true;
            result.message = 'Document emailed successfully.';
            return result;
        }

        result.message = 'Unable to send email.';
        if (
            sendResults != null &&
            !sendResults.isEmpty() &&
            sendResults[0].getErrors() != null &&
            !sendResults[0].getErrors().isEmpty()
        ) {
            result.message = sendResults[0].getErrors()[0].getMessage();
        }
        return result;
    }

    private static PageReference buildPageReference(Id patientId, String docType, List<Id> recordIds) {
        if (patientId == null) {
            throw new AuraHandledException('Patient Id is required.');
        }
        String normalizedType = normalizeDocType(docType);
        if (normalizedType == null) {
            throw new AuraHandledException('Document type must be ChartSummary or Prescription.');
        }

        PageReference pageRef;
        if (normalizedType == DOC_PRESCRIPTION) {
            if (recordIds == null || recordIds.isEmpty()) {
                throw new AuraHandledException('Select at least one prescription to print.');
            }
            Integer ownedCount = [
                SELECT COUNT()
                FROM MedicationRequest__c
                WHERE Id IN :recordIds AND Patient__c = :patientId
            ];
            if (ownedCount == 0) {
                throw new AuraHandledException('No matching prescriptions found for this patient.');
            }
            pageRef = Page.PrescriptionPad;
            List<String> idTokens = new List<String>();
            for (Id recordId : recordIds) {
                if (recordId != null) {
                    idTokens.add(String.valueOf(recordId));
                }
            }
            pageRef.getParameters().put('ids', String.join(idTokens, ','));
        } else {
            pageRef = Page.PatientChartSummary;
        }
        pageRef.getParameters().put('id', String.valueOf(patientId));
        return pageRef;
    }

    private static String normalizeDocType(String docType) {
        if (String.isBlank(docType)) {
            return null;
        }
        String trimmed = docType.trim();
        if (trimmed.equalsIgnoreCase(DOC_CHART_SUMMARY)) {
            return DOC_CHART_SUMMARY;
        }
        if (trimmed.equalsIgnoreCase(DOC_PRESCRIPTION)) {
            return DOC_PRESCRIPTION;
        }
        return null;
    }

    private static String defaultSubject(String docType, Patient__c patient) {
        String first = patient.First_Name__c == null ? '' : patient.First_Name__c.trim();
        String last = patient.Last_Name__c == null ? '' : patient.Last_Name__c.trim();
        String name = (first + ' ' + last).trim();
        if (String.isBlank(name)) {
            name = 'Patient';
        }
        if (docType == DOC_PRESCRIPTION) {
            return 'Prescription — ' + name;
        }
        return 'Medical record — ' + name;
    }
}
