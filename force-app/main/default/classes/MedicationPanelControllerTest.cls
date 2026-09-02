@IsTest
private class MedicationPanelControllerTest {
    @IsTest
    static void getMedicationsReturnsActiveOrdersAndReportedStatements() {
        Patient__c patient = insertPatient('MRN-MED-1');
        Patient__c other = insertPatient('MRN-MED-2');

        MedicationRequest__c activeOrder = insertRequest(
            patient.Id,
            'Active',
            'RxNorm',
            '197361',
            'Lisinopril 10 MG Oral Tablet'
        );
        insertRequest(patient.Id, 'Stopped', 'RxNorm', '314076', 'Lisinopril 20 MG Oral Tablet');
        insertRequest(other.Id, 'Active', 'RxNorm', '617318', 'Atorvastatin 40 MG Oral Tablet');

        MedicationStatement__c reported = insertStatement(
            patient.Id,
            'Active',
            'Patient Reported',
            'RxNorm',
            '198440',
            'Acetaminophen 325 MG Oral Tablet'
        );
        insertStatement(
            patient.Id,
            'Stopped',
            'Patient Reported',
            'RxNorm',
            '310965',
            'Ibuprofen 200 MG Oral Tablet'
        );
        insertStatement(
            other.Id,
            'Active',
            'Patient Reported',
            'RxNorm',
            '308971',
            'Aspirin 81 MG Oral Tablet'
        );

        Test.startTest();
        MedicationPanelController.MedicationPanelView view = MedicationPanelController.getMedications(
            patient.Id
        );
        MedicationPanelController.MedicationPanelView blank = MedicationPanelController.getMedications(
            null
        );
        Test.stopTest();

        System.assertEquals(1, view.activeOrders.size(), 'Only this patient\'s active orders');
        System.assertEquals(activeOrder.Id, view.activeOrders[0].Id, 'Active order Id should match');
        System.assertEquals(
            '197361',
            view.activeOrders[0].Medication_Code__c,
            'Order coding code should be queried'
        );
        System.assertEquals(
            'RxNorm',
            view.activeOrders[0].Medication_Code_System__c,
            'Order coding system should be queried'
        );
        System.assertEquals(1, view.reportedMedications.size(), 'Only this patient\'s reported meds');
        System.assertEquals(
            reported.Id,
            view.reportedMedications[0].Id,
            'Reported statement Id should match'
        );
        System.assertEquals(
            'Patient Reported',
            view.reportedMedications[0].Source__c,
            'Statement source should be queried'
        );
        System.assertEquals(0, blank.activeOrders.size(), 'Null patient should return no orders');
        System.assertEquals(
            0,
            blank.reportedMedications.size(),
            'Null patient should return no reported meds'
        );
    }

    @IsTest
    static void addMedicationPersistsRxNormCodingAsActiveOrder() {
        Patient__c patient = insertPatient('MRN-MED-3');
        Code_Reference__c codeRef = insertCode('RxNorm', '617318', 'Atorvastatin 40 MG Oral Tablet');

        Test.startTest();
        MedicationRequest__c created = MedicationPanelController.addMedication(
            patient.Id,
            codeRef.Code_System__c,
            codeRef.Code__c,
            codeRef.Display__c,
            codeRef.Id,
            'Take 1 tablet by mouth daily',
            10,
            'mg',
            'Once daily',
            'Oral',
            'Order',
            'Active',
            null
        );
        Test.stopTest();

        MedicationRequest__c stored = [
            SELECT
                Patient__c,
                Status__c,
                Intent__c,
                Medication_Ref__c,
                Medication_Code_System__c,
                Medication_Code__c,
                Medication_Display__c,
                Dosage_Text__c,
                Dose_Quantity__c,
                Dose_Unit__c,
                Frequency__c,
                Route__c,
                Authored_On__c
            FROM MedicationRequest__c
            WHERE Id = :created.Id
        ];
        System.assertEquals(patient.Id, stored.Patient__c, 'Order should belong to the patient');
        System.assertEquals('Active', stored.Status__c, 'New order should be Active');
        System.assertEquals('Order', stored.Intent__c, 'New row should be an order');
        System.assertEquals(codeRef.Id, stored.Medication_Ref__c, 'Lookup should point at the Code Reference');
        System.assertEquals(codeRef.Code_System__c, stored.Medication_Code_System__c, 'Code system should persist');
        System.assertEquals(codeRef.Code__c, stored.Medication_Code__c, 'Snapshot code should match the Code Reference');
        System.assertEquals(
            codeRef.Display__c,
            stored.Medication_Display__c,
            'Snapshot display should match the Code Reference'
        );
        System.assertEquals('Take 1 tablet by mouth daily', stored.Dosage_Text__c, 'Dosage text should persist');
        System.assertEquals(10, stored.Dose_Quantity__c, 'Dose quantity should persist');
        System.assertEquals('mg', stored.Dose_Unit__c, 'Dose unit should persist');
        System.assertEquals('Once daily', stored.Frequency__c, 'Frequency should persist');
        System.assertEquals('Oral', stored.Route__c, 'Route should persist');
        System.assertNotEquals(null, stored.Authored_On__c, 'Add should stamp authored on');
    }

    @IsTest
    static void addMedicationRejectsBlankPatientDisplayOrWrongSystem() {
        Patient__c patient = insertPatient('MRN-MED-4');
        Boolean missingPatient = false;
        Boolean missingDisplay = false;
        Boolean wrongSystem = false;

        Test.startTest();
        try {
            MedicationPanelController.addMedication(
                null,
                'RxNorm',
                '197361',
                'Lisinopril',
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null
            );
        } catch (AuraHandledException e) {
            missingPatient = true;
        }
        try {
            MedicationPanelController.addMedication(
                patient.Id,
                'RxNorm',
                '197361',
                '',
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null
            );
        } catch (AuraHandledException e) {
            missingDisplay = true;
        }
        try {
            MedicationPanelController.addMedication(
                patient.Id,
                'SNOMED',
                '387517004',
                'Paracetamol',
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null
            );
        } catch (AuraHandledException e) {
            wrongSystem = true;
        }
        Test.stopTest();

        System.assertEquals(true, missingPatient, 'Blank patient Id should be rejected');
        System.assertEquals(true, missingDisplay, 'Blank display should be rejected');
        System.assertEquals(true, wrongSystem, 'Non-RxNorm system should be rejected');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM MedicationRequest__c WHERE Patient__c = :patient.Id],
            'Rejected adds must not insert rows'
        );
    }

    @IsTest
    static void renewAndDiscontinueUpdateOrderStatusInBulk() {
        Patient__c patient = insertPatient('MRN-MED-5');
        MedicationRequest__c first = insertRequest(
            patient.Id,
            'Active',
            'RxNorm',
            '197361',
            'Lisinopril 10 MG Oral Tablet'
        );
        MedicationRequest__c second = insertRequest(
            patient.Id,
            'On Hold',
            'RxNorm',
            '617318',
            'Atorvastatin 40 MG Oral Tablet'
        );
        MedicationRequest__c alreadyStopped = insertRequest(
            patient.Id,
            'Stopped',
            'RxNorm',
            '310965',
            'Ibuprofen 200 MG Oral Tablet'
        );

        Test.startTest();
        MedicationPanelController.renewOrders(null);
        MedicationPanelController.renewOrders(new List<Id>());
        MedicationPanelController.renewOrders(new List<Id>{ second.Id });
        MedicationPanelController.discontinueOrders(null);
        MedicationPanelController.discontinueOrders(new List<Id>());
        MedicationPanelController.discontinueOrders(
            new List<Id>{ first.Id, alreadyStopped.Id }
        );
        Test.stopTest();

        Map<Id, MedicationRequest__c> stored = new Map<Id, MedicationRequest__c>(
            [
                SELECT Status__c, Authored_On__c
                FROM MedicationRequest__c
                WHERE Id IN :new List<Id>{ first.Id, second.Id, alreadyStopped.Id }
            ]
        );
        System.assertEquals(
            'Stopped',
            stored.get(first.Id).Status__c,
            'Active order should discontinue to Stopped'
        );
        System.assertEquals(
            'Active',
            stored.get(second.Id).Status__c,
            'On Hold order should renew to Active'
        );
        System.assertNotEquals(
            null,
            stored.get(second.Id).Authored_On__c,
            'Renew should stamp authored on'
        );
        System.assertEquals(
            'Stopped',
            stored.get(alreadyStopped.Id).Status__c,
            'Already stopped order should stay Stopped'
        );
        System.assertEquals(
            1,
            MedicationPanelController.getMedications(patient.Id).activeOrders.size(),
            'Only the renewed order should remain active'
        );
        System.assertEquals(
            second.Id,
            MedicationPanelController.getMedications(patient.Id).activeOrders[0].Id,
            'Renewed order should be the remaining active row'
        );
    }

    @IsTest
    static void deleteOrdersAndReportedMedicationsRemoveRows() {
        Patient__c patient = insertPatient('MRN-MED-6');
        MedicationRequest__c order = insertRequest(
            patient.Id,
            'Active',
            'RxNorm',
            '197361',
            'Lisinopril 10 MG Oral Tablet'
        );
        MedicationStatement__c reported = insertStatement(
            patient.Id,
            'Active',
            'Patient Reported',
            'RxNorm',
            '310965',
            'Ibuprofen 200 MG Oral Tablet'
        );

        Test.startTest();
        MedicationPanelController.deleteOrders(null);
        MedicationPanelController.deleteOrders(new List<Id>());
        MedicationPanelController.deleteReportedMedications(null);
        MedicationPanelController.deleteReportedMedications(new List<Id>());
        MedicationPanelController.deleteOrders(new List<Id>{ order.Id });
        MedicationPanelController.deleteReportedMedications(new List<Id>{ reported.Id });
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM MedicationRequest__c WHERE Id = :order.Id],
            'Order should be deleted'
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM MedicationStatement__c WHERE Id = :reported.Id],
            'Reported medication should be deleted'
        );
    }

    private static Patient__c insertPatient(String mrn) {
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'Medications');
        insert patient;
        return patient;
    }

    private static MedicationRequest__c insertRequest(
        Id patientId,
        String status,
        String codeSystem,
        String code,
        String display
    ) {
        MedicationRequest__c request = new MedicationRequest__c(
            Patient__c = patientId,
            Status__c = status,
            Intent__c = 'Order',
            Medication_Code_System__c = codeSystem,
            Medication_Code__c = code,
            Medication_Display__c = display
        );
        insert request;
        return request;
    }

    private static MedicationStatement__c insertStatement(
        Id patientId,
        String status,
        String source,
        String codeSystem,
        String code,
        String display
    ) {
        MedicationStatement__c statement = new MedicationStatement__c(
            Patient__c = patientId,
            Status__c = status,
            Source__c = source,
            Medication_Code_System__c = codeSystem,
            Medication_Code__c = code,
            Medication_Display__c = display
        );
        insert statement;
        return statement;
    }

    private static Code_Reference__c insertCode(String codeSystem, String code, String display) {
        Code_Reference__c row = new Code_Reference__c(
            Name = display.left(80),
            Code_System__c = codeSystem,
            Code__c = code,
            Display__c = display,
            Active__c = true
        );
        insert row;
        return row;
    }
}
