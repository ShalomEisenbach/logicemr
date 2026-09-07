@IsTest
private class ClinicalDocumentControllerTest {
    @IsTest
    static void getDocumentContextAndUrlForChartSummary() {
        Patient__c patient = insertPatient('MRN-CTRL-1', 'chart@example.com');

        Test.startTest();
        ClinicalDocumentController.DocumentContext context = ClinicalDocumentController.getDocumentContext(
            patient.Id
        );
        String defaultEmail = ClinicalDocumentController.getDefaultEmail(patient.Id);
        String url = ClinicalDocumentController.getDocumentUrl(
            patient.Id,
            ClinicalDocumentController.DOC_CHART_SUMMARY,
            null
        );
        Test.stopTest();

        System.assertEquals('chart@example.com', context.defaultEmail, 'Default email should load');
        System.assertEquals('Ada Patient', context.patientName, 'Patient name should load');
        System.assertEquals(defaultEmail, context.defaultEmail, 'getDefaultEmail should match context');
        System.assertNotEquals(null, url, 'Chart summary URL should be returned');
        System.assert(
            url.toLowerCase().contains('patientchartsummary'),
            'Chart summary URL should reference the VF page: ' + url
        );
        System.assert(url.contains(String.valueOf(patient.Id)), 'URL should include patient Id');
    }

    @IsTest
    static void getDocumentUrlForPrescriptionRequiresOwnedIds() {
        Patient__c patient = insertPatient('MRN-CTRL-2', 'rx@example.com');
        Patient__c other = insertPatient('MRN-CTRL-3', null);
        MedicationRequest__c own = insertRequest(patient.Id, 'Own Rx');
        MedicationRequest__c foreign = insertRequest(other.Id, 'Foreign Rx');

        Test.startTest();
        String url = ClinicalDocumentController.getDocumentUrl(
            patient.Id,
            ClinicalDocumentController.DOC_PRESCRIPTION,
            new List<Id>{ own.Id }
        );
        Boolean wrongPatientThrew = false;
        try {
            ClinicalDocumentController.getDocumentUrl(
                patient.Id,
                ClinicalDocumentController.DOC_PRESCRIPTION,
                new List<Id>{ foreign.Id }
            );
        } catch (AuraHandledException e) {
            wrongPatientThrew = true;
        }
        Boolean missingIdsThrew = false;
        try {
            ClinicalDocumentController.getDocumentUrl(
                patient.Id,
                ClinicalDocumentController.DOC_PRESCRIPTION,
                new List<Id>()
            );
        } catch (AuraHandledException e) {
            missingIdsThrew = true;
        }
        Test.stopTest();

        System.assertNotEquals(null, url, 'Prescription URL should be returned');
        System.assert(
            url.toLowerCase().contains('prescriptionpad'),
            'Prescription URL should reference the VF page: ' + url
        );
        System.assert(url.contains(String.valueOf(own.Id)), 'URL should include selected Rx Id');
        System.assertEquals(true, wrongPatientThrew, 'Foreign Rx Ids must be rejected');
        System.assertEquals(true, missingIdsThrew, 'Prescription URL requires selected Ids');
    }

    @IsTest
    static void sendDocumentEmailsChartAndPrescription() {
        Patient__c patient = insertPatient('MRN-CTRL-4', 'send@example.com');
        MedicationRequest__c rx = insertRequest(patient.Id, 'Email Rx');

        Test.startTest();
        ClinicalDocumentController.SendResult chartResult = ClinicalDocumentController.sendDocument(
            patient.Id,
            ClinicalDocumentController.DOC_CHART_SUMMARY,
            null,
            'override@example.com',
            'Custom chart subject',
            'Please review your chart.'
        );
        ClinicalDocumentController.SendResult rxResult = ClinicalDocumentController.sendDocument(
            patient.Id,
            ClinicalDocumentController.DOC_PRESCRIPTION,
            new List<Id>{ rx.Id },
            null,
            null,
            null
        );
        ClinicalDocumentController.SendResult blankTo = ClinicalDocumentController.sendDocument(
            patient.Id,
            ClinicalDocumentController.DOC_CHART_SUMMARY,
            null,
            '   ',
            null,
            null
        );
        ClinicalDocumentController.SendResult badType = ClinicalDocumentController.sendDocument(
            patient.Id,
            'Unknown',
            null,
            'ok@example.com',
            null,
            null
        );
        ClinicalDocumentController.SendResult wrongPatientRx = ClinicalDocumentController.sendDocument(
            patient.Id,
            ClinicalDocumentController.DOC_PRESCRIPTION,
            new List<Id>{ insertRequest(insertPatient('MRN-CTRL-5', null).Id, 'Other').Id },
            'ok@example.com',
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(true, chartResult.success, 'Chart email should succeed in tests');
        System.assertEquals(
            'Document emailed successfully.',
            chartResult.message,
            'Success message should be returned'
        );
        System.assertEquals(false, rxResult.success, 'Blank To address must fail for Rx email');
        System.assert(
            rxResult.message != null && rxResult.message.contains('recipient'),
            'Blank To should explain the required address'
        );
        System.assertEquals(false, blankTo.success, 'Whitespace To address must fail');
        System.assertEquals(false, badType.success, 'Unknown document type must fail');
        System.assertEquals(false, wrongPatientRx.success, 'Wrong-patient Rx Ids must fail');
    }

    @IsTest
    static void sendDocumentSucceedsForPrescriptionWithToOverride() {
        Patient__c patient = insertPatient('MRN-CTRL-6', 'default@example.com');
        MedicationRequest__c rx = insertRequest(patient.Id, 'Override Rx');

        Test.startTest();
        ClinicalDocumentController.SendResult result = ClinicalDocumentController.sendDocument(
            patient.Id,
            'prescription',
            new List<Id>{ rx.Id },
            'pharmacy@example.com',
            null,
            'Attached prescription'
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Prescription email should succeed with To override');
    }

    @IsTest
    static void validationCoversNullPatientAndMissingContext() {
        Patient__c doomed = insertPatient('MRN-CTRL-GONE', null);
        Id missingPatientId = doomed.Id;
        delete doomed;

        Patient__c nameless = new Patient__c(MRN__c = 'MRN-CTRL-NAMELESS');
        insert nameless;

        Test.startTest();
        ClinicalDocumentController.DocumentContext blankContext = ClinicalDocumentController.getDocumentContext(
            null
        );
        String blankEmail = ClinicalDocumentController.getDefaultEmail(null);
        ClinicalDocumentController.DocumentContext missingContext = ClinicalDocumentController.getDocumentContext(
            missingPatientId
        );
        ClinicalDocumentController.DocumentContext namelessContext = ClinicalDocumentController.getDocumentContext(
            nameless.Id
        );
        ClinicalDocumentController.SendResult nullPatient = ClinicalDocumentController.sendDocument(
            null,
            ClinicalDocumentController.DOC_CHART_SUMMARY,
            null,
            'ok@example.com',
            null,
            null
        );
        ClinicalDocumentController.SendResult missingPatient = ClinicalDocumentController.sendDocument(
            missingPatientId,
            ClinicalDocumentController.DOC_CHART_SUMMARY,
            null,
            'ok@example.com',
            null,
            null
        );
        ClinicalDocumentController.SendResult blankType = ClinicalDocumentController.sendDocument(
            nameless.Id,
            '   ',
            null,
            'ok@example.com',
            null,
            null
        );
        ClinicalDocumentController.SendResult defaultSubjectChart = ClinicalDocumentController.sendDocument(
            nameless.Id,
            ClinicalDocumentController.DOC_CHART_SUMMARY,
            null,
            'ok@example.com',
            null,
            null
        );
        Boolean badTypeThrew = false;
        try {
            ClinicalDocumentController.getDocumentUrl(nameless.Id, 'NotAType', null);
        } catch (AuraHandledException e) {
            badTypeThrew = true;
        }
        Boolean nullPatientUrlThrew = false;
        try {
            ClinicalDocumentController.getDocumentUrl(null, ClinicalDocumentController.DOC_CHART_SUMMARY, null);
        } catch (AuraHandledException e) {
            nullPatientUrlThrew = true;
        }
        Boolean blankTypeUrlThrew = false;
        try {
            ClinicalDocumentController.getDocumentUrl(nameless.Id, null, null);
        } catch (AuraHandledException e) {
            blankTypeUrlThrew = true;
        }
        ClinicalDocumentController.SendResult missingRx = ClinicalDocumentController.sendDocument(
            insertPatient('MRN-CTRL-8', 'a@example.com').Id,
            ClinicalDocumentController.DOC_PRESCRIPTION,
            new List<Id>(),
            'ok@example.com',
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(null, blankContext.defaultEmail, 'Null patient context has no email');
        System.assertEquals(null, blankEmail, 'Null patient default email is null');
        System.assertEquals(null, missingContext.patientName, 'Missing patient should return empty context');
        System.assertEquals('Patient', namelessContext.patientName, 'Blank name should fall back to Patient');
        System.assertEquals(false, nullPatient.success, 'Null patient send must fail');
        System.assertEquals(false, missingPatient.success, 'Missing patient send must fail');
        System.assertEquals('Patient not found.', missingPatient.message, 'Missing patient message');
        System.assertEquals(false, blankType.success, 'Blank doc type send must fail');
        System.assertEquals(true, defaultSubjectChart.success, 'Default subject chart email should succeed');
        System.assertEquals(true, badTypeThrew, 'Invalid doc type URL must throw');
        System.assertEquals(true, nullPatientUrlThrew, 'Null patient URL must throw');
        System.assertEquals(true, blankTypeUrlThrew, 'Blank doc type URL must throw');
        System.assertEquals(false, missingRx.success, 'Prescription send without Ids must fail');
    }

    private static Patient__c insertPatient(String mrn, String email) {
        Patient__c patient = new Patient__c(
            MRN__c = mrn,
            First_Name__c = 'Ada',
            Last_Name__c = 'Patient',
            Email__c = email
        );
        insert patient;
        return patient;
    }

    private static MedicationRequest__c insertRequest(Id patientId, String display) {
        MedicationRequest__c request = new MedicationRequest__c(
            Patient__c = patientId,
            Status__c = 'Active',
            Intent__c = 'Order',
            Medication_Code_System__c = 'RxNorm',
            Medication_Code__c = '197361',
            Medication_Display__c = display
        );
        insert request;
        return request;
    }
}
