@IsTest
private class OrderEntryControllerTest {
    @IsTest
    static void createServiceOrdersInsertsLabAndImagingStampedToEncounter() {
        Encounter__c encounter = insertEncounter();
        Code_Reference__c labRef = insertCode('LOINC', '24323-8', 'Comprehensive metabolic panel');
        Code_Reference__c imagingRef = insertCode('CPT', '71046', 'Chest X-ray 2 views');
        OrderEntryController.ServiceOrderInput lab = serviceInput(
            'Lab',
            labRef.Code_System__c,
            labRef.Code__c,
            labRef.Display__c,
            'Routine',
            'Annual labs',
            labRef.Id
        );
        OrderEntryController.ServiceOrderInput imaging = serviceInput(
            'Imaging',
            imagingRef.Code_System__c,
            imagingRef.Code__c,
            imagingRef.Display__c,
            'STAT',
            'Cough',
            imagingRef.Id
        );

        Test.startTest();
        List<ServiceRequest__c> created = OrderEntryController.createServiceOrders(
            encounter.Id,
            new List<OrderEntryController.ServiceOrderInput>{ lab, imaging }
        );
        Test.stopTest();

        System.assertEquals(2, created.size(), 'Both service orders should insert in one call');
        Map<String, ServiceRequest__c> byCode = new Map<String, ServiceRequest__c>();
        for (ServiceRequest__c row : [
            SELECT
                Patient__c,
                Encounter__c,
                Category__c,
                Status__c,
                Service_Ref__c,
                Service_Code_System__c,
                Service_Code__c,
                Service_Display__c,
                Priority__c,
                Reason__c,
                Authored_On__c
            FROM ServiceRequest__c
            WHERE Encounter__c = :encounter.Id
        ]) {
            byCode.put(row.Service_Code__c, row);
            System.assertEquals(encounter.Patient__c, row.Patient__c, 'Patient must come from the encounter');
            System.assertEquals(encounter.Id, row.Encounter__c, 'Encounter must be stamped');
            System.assertEquals('Active', row.Status__c, 'New service request should be Active');
            System.assertNotEquals(null, row.Authored_On__c, 'Authored On should be stamped');
        }
        System.assertEquals('Lab', byCode.get('24323-8').Category__c, 'Lab category');
        System.assertEquals(labRef.Id, byCode.get('24323-8').Service_Ref__c, 'Lab lookup should point at the Code Reference');
        System.assertEquals(labRef.Code_System__c, byCode.get('24323-8').Service_Code_System__c, 'Lab LOINC');
        System.assertEquals(labRef.Display__c, byCode.get('24323-8').Service_Display__c, 'Lab snapshot should match the Code Reference');
        System.assertEquals(labRef.Code__c, byCode.get('24323-8').Service_Code__c, 'Lab snapshot code should match the Code Reference');
        System.assertEquals('Routine', byCode.get('24323-8').Priority__c, 'Lab priority');
        System.assertEquals('Annual labs', byCode.get('24323-8').Reason__c, 'Lab reason');
        System.assertEquals('Imaging', byCode.get('71046').Category__c, 'Imaging category');
        System.assertEquals(imagingRef.Id, byCode.get('71046').Service_Ref__c, 'Imaging lookup should point at the Code Reference');
        System.assertEquals(imagingRef.Code_System__c, byCode.get('71046').Service_Code_System__c, 'Imaging CPT');
        System.assertEquals(imagingRef.Code__c, byCode.get('71046').Service_Code__c, 'Imaging snapshot code should match the Code Reference');
        System.assertEquals(imagingRef.Display__c, byCode.get('71046').Service_Display__c, 'Imaging snapshot should match the Code Reference');
        System.assertEquals('STAT', byCode.get('71046').Priority__c, 'Imaging priority');
    }

    @IsTest
    static void createMedicationOrdersInsertsPrescriptionStampedToEncounter() {
        Encounter__c encounter = insertEncounter();
        Code_Reference__c lisinopril = insertCode('RxNorm', '197361', 'Lisinopril 10 MG Oral Tablet');
        Code_Reference__c statinRef = insertCode('RxNorm', '617318', 'Atorvastatin 40 MG Oral Tablet');
        OrderEntryController.MedicationOrderInput rx = new OrderEntryController.MedicationOrderInput();
        rx.codeSystem = lisinopril.Code_System__c;
        rx.code = lisinopril.Code__c;
        rx.display = lisinopril.Display__c;
        rx.codeReferenceId = lisinopril.Id;
        rx.dosageText = 'Take 1 tablet by mouth daily';
        rx.doseQuantity = 10;
        rx.doseUnit = 'mg';
        rx.frequency = 'Once daily';
        rx.route = 'Oral';
        OrderEntryController.MedicationOrderInput statin = medicationInput(
            statinRef.Code_System__c,
            statinRef.Code__c,
            statinRef.Display__c,
            statinRef.Id
        );

        Test.startTest();
        List<MedicationRequest__c> created = OrderEntryController.createMedicationOrders(
            encounter.Id,
            new List<OrderEntryController.MedicationOrderInput>{ rx, statin }
        );
        Test.stopTest();

        System.assertEquals(2, created.size(), 'Both prescriptions should insert in one call');
        MedicationRequest__c stored = [
            SELECT
                Patient__c,
                Encounter__c,
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
            WHERE Id = :created[0].Id
        ];
        System.assertEquals(encounter.Patient__c, stored.Patient__c, 'Patient must come from the encounter');
        System.assertEquals(encounter.Id, stored.Encounter__c, 'Encounter must be stamped');
        System.assertEquals('Active', stored.Status__c, 'New medication request should be Active');
        System.assertEquals('Order', stored.Intent__c, 'Intent should be Order');
        System.assertEquals(lisinopril.Id, stored.Medication_Ref__c, 'Lookup should point at the Code Reference');
        System.assertEquals(lisinopril.Code_System__c, stored.Medication_Code_System__c, 'Code system must be RxNorm');
        System.assertEquals(lisinopril.Code__c, stored.Medication_Code__c, 'Snapshot code should match the Code Reference');
        System.assertEquals(lisinopril.Display__c, stored.Medication_Display__c, 'Snapshot display should match the Code Reference');
        System.assertEquals('Take 1 tablet by mouth daily', stored.Dosage_Text__c, 'Dosage text should persist');
        System.assertEquals(10, stored.Dose_Quantity__c, 'Dose quantity should persist');
        System.assertEquals('mg', stored.Dose_Unit__c, 'Dose unit should persist');
        System.assertEquals('Once daily', stored.Frequency__c, 'Frequency should persist');
        System.assertEquals('Oral', stored.Route__c, 'Route should persist');
        System.assertNotEquals(null, stored.Authored_On__c, 'Authored On should be stamped');
    }

    @IsTest
    static void createServiceOrdersRejectsInvalidInputWithoutDml() {
        Patient__c patient = insertPatient('MRN-ORD-BAD');
        Encounter__c encounter = insertEncounter();
        Boolean nullIdThrew = false;
        Boolean unknownThrew = false;
        Boolean nullListThrew = false;
        Boolean emptyThrew = false;
        Boolean nullRowThrew = false;
        Boolean blankDisplayThrew = false;
        Boolean badCategoryThrew = false;
        Boolean badSystemThrew = false;

        Test.startTest();
        try {
            OrderEntryController.createServiceOrders(
                null,
                new List<OrderEntryController.ServiceOrderInput>{
                    serviceInput('Lab', 'LOINC', '24323-8', 'CMP', 'Routine', null)
                }
            );
        } catch (AuraHandledException e) {
            nullIdThrew = true;
        }
        try {
            OrderEntryController.createServiceOrders(
                patient.Id,
                new List<OrderEntryController.ServiceOrderInput>{
                    serviceInput('Lab', 'LOINC', '24323-8', 'CMP', 'Routine', null)
                }
            );
        } catch (AuraHandledException e) {
            unknownThrew = true;
        }
        try {
            OrderEntryController.createServiceOrders(encounter.Id, null);
        } catch (AuraHandledException e) {
            nullListThrew = true;
        }
        try {
            OrderEntryController.createServiceOrders(
                encounter.Id,
                new List<OrderEntryController.ServiceOrderInput>()
            );
        } catch (AuraHandledException e) {
            emptyThrew = true;
        }
        try {
            OrderEntryController.createServiceOrders(
                encounter.Id,
                new List<OrderEntryController.ServiceOrderInput>{ null }
            );
        } catch (AuraHandledException e) {
            nullRowThrew = true;
        }
        try {
            OrderEntryController.createServiceOrders(
                encounter.Id,
                new List<OrderEntryController.ServiceOrderInput>{
                    serviceInput('Lab', 'LOINC', '24323-8', '', 'Routine', null)
                }
            );
        } catch (AuraHandledException e) {
            blankDisplayThrew = true;
        }
        try {
            OrderEntryController.createServiceOrders(
                encounter.Id,
                new List<OrderEntryController.ServiceOrderInput>{
                    serviceInput('Procedure', 'CPT', '99213', 'Office visit', 'Routine', null)
                }
            );
        } catch (AuraHandledException e) {
            badCategoryThrew = true;
        }
        try {
            OrderEntryController.createServiceOrders(
                encounter.Id,
                new List<OrderEntryController.ServiceOrderInput>{
                    serviceInput('Referral', 'SNOMED', '3457005', 'Referral', 'Routine', null)
                }
            );
        } catch (AuraHandledException e) {
            badSystemThrew = true;
        }
        Test.stopTest();

        System.assertEquals(true, nullIdThrew, 'Null encounter Id should be rejected');
        System.assertEquals(true, unknownThrew, 'Non-encounter Id should be rejected');
        System.assertEquals(true, nullListThrew, 'Null service list should be rejected');
        System.assertEquals(true, emptyThrew, 'Empty service list should be rejected');
        System.assertEquals(true, nullRowThrew, 'Null service row should be rejected');
        System.assertEquals(true, blankDisplayThrew, 'Blank display should be rejected');
        System.assertEquals(true, badCategoryThrew, 'Procedure is not an order-entry category');
        System.assertEquals(true, badSystemThrew, 'SNOMED is not allowed for service orders');
        System.assertEquals(0, [SELECT COUNT() FROM ServiceRequest__c], 'Rejected saves must not insert rows');
    }

    @IsTest
    static void createMedicationOrdersRejectsInvalidInputWithoutDml() {
        Encounter__c encounter = insertEncounter();
        Boolean nullListThrew = false;
        Boolean emptyThrew = false;
        Boolean nullRowThrew = false;
        Boolean blankDisplayThrew = false;
        Boolean badSystemThrew = false;

        Test.startTest();
        try {
            OrderEntryController.createMedicationOrders(encounter.Id, null);
        } catch (AuraHandledException e) {
            nullListThrew = true;
        }
        try {
            OrderEntryController.createMedicationOrders(
                encounter.Id,
                new List<OrderEntryController.MedicationOrderInput>()
            );
        } catch (AuraHandledException e) {
            emptyThrew = true;
        }
        try {
            OrderEntryController.createMedicationOrders(
                encounter.Id,
                new List<OrderEntryController.MedicationOrderInput>{ null }
            );
        } catch (AuraHandledException e) {
            nullRowThrew = true;
        }
        try {
            OrderEntryController.createMedicationOrders(
                encounter.Id,
                new List<OrderEntryController.MedicationOrderInput>{ medicationInput('RxNorm', '197361', '', null) }
            );
        } catch (AuraHandledException e) {
            blankDisplayThrew = true;
        }
        try {
            OrderEntryController.createMedicationOrders(
                encounter.Id,
                new List<OrderEntryController.MedicationOrderInput>{
                    medicationInput('NDC', '0002-1433-80', 'Insulin', null)
                }
            );
        } catch (AuraHandledException e) {
            badSystemThrew = true;
        }
        Test.stopTest();

        System.assertEquals(true, nullListThrew, 'Null medication list should be rejected');
        System.assertEquals(true, emptyThrew, 'Empty medication list should be rejected');
        System.assertEquals(true, nullRowThrew, 'Null medication row should be rejected');
        System.assertEquals(true, blankDisplayThrew, 'Blank display should be rejected');
        System.assertEquals(true, badSystemThrew, 'Non-RxNorm code system should be rejected');
        System.assertEquals(0, [SELECT COUNT() FROM MedicationRequest__c], 'Rejected saves must not insert rows');
    }

    @IsTest
    static void createServiceOrdersAcceptsReferralWithCpt() {
        Encounter__c encounter = insertEncounter();

        Test.startTest();
        List<ServiceRequest__c> created = OrderEntryController.createServiceOrders(
            encounter.Id,
            new List<OrderEntryController.ServiceOrderInput>{
                serviceInput('Referral', 'CPT', '99241', 'Office consultation', 'Urgent', 'Cardiology')
            }
        );
        Test.stopTest();

        System.assertEquals(1, created.size(), 'Referral should insert');
        System.assertEquals('Referral', created[0].Category__c, 'Referral category');
        System.assertEquals('CPT', created[0].Service_Code_System__c, 'Referral CPT');
    }

    private static OrderEntryController.ServiceOrderInput serviceInput(
        String category,
        String codeSystem,
        String code,
        String display,
        String priority,
        String reason
    ) {
        return serviceInput(category, codeSystem, code, display, priority, reason, null);
    }

    private static OrderEntryController.ServiceOrderInput serviceInput(
        String category,
        String codeSystem,
        String code,
        String display,
        String priority,
        String reason,
        Id codeReferenceId
    ) {
        OrderEntryController.ServiceOrderInput input = new OrderEntryController.ServiceOrderInput();
        input.category = category;
        input.codeSystem = codeSystem;
        input.code = code;
        input.display = display;
        input.codeReferenceId = codeReferenceId;
        input.priority = priority;
        input.reason = reason;
        return input;
    }

    private static OrderEntryController.MedicationOrderInput medicationInput(
        String codeSystem,
        String code,
        String display,
        Id codeReferenceId
    ) {
        OrderEntryController.MedicationOrderInput input = new OrderEntryController.MedicationOrderInput();
        input.codeSystem = codeSystem;
        input.code = code;
        input.display = display;
        input.codeReferenceId = codeReferenceId;
        return input;
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

    private static Patient__c insertPatient(String mrn) {
        Patient__c patient = new Patient__c(MRN__c = mrn, Last_Name__c = 'Orders');
        insert patient;
        return patient;
    }

    private static Encounter__c insertEncounter() {
        Encounter__c encounter = new Encounter__c(
            Patient__c = insertPatient('MRN-ORD-' + String.valueOf(Math.abs(Crypto.getRandomInteger()))).Id,
            Status__c = 'In Progress',
            Class__c = 'Outpatient',
            Start__c = Datetime.newInstance(2024, 3, 1, 9, 0, 0)
        );
        insert encounter;
        return encounter;
    }
}
