/**
 * Idempotent seed for fee schedules, effective-dated rates, and superbills.
 *
 * Requires the core clinical seeds, especially:
 *   seedCatalog.apex
 *   seedDemoData.apex
 *   seedClinicalConditions.apex
 *   seedClinicalNotesAndProcedures.apex
 *   seedPayerAndCoverage.apex
 *
 * Fee schedules are matched by their "LogicEMR Demo" names. Rates are matched
 * by schedule, code system, code, and effective start date. Superbill creation
 * uses ClaimReadinessController so diagnosis and rate snapshots follow the same
 * path as production claim preparation. Re-running refreshes four representative
 * unlocked claim scenarios while staying within anonymous Apex governor limits.
 */
new FeeScheduleAndSuperbillSeed().run();

class FeeScheduleAndSuperbillSeed {
    private final Date CURRENT_START = Date.newInstance(2026, 1, 1);
    private final Date HISTORICAL_START = Date.newInstance(2025, 1, 1);
    private final Date HISTORICAL_END = Date.newInstance(2025, 12, 31);

    void run() {
        Map<String, Id> payerIds = loadPayerIds();
        requireSeedPayers(payerIds);
        ensureBillingOrganization();

        List<lfemr__Fee_Schedule__c> schedules = buildSchedules(payerIds);
        saveSchedules(schedules);

        Map<String, Id> catalogIds = loadCatalogIds();
        List<FeeScheduleRateSpec> baseRates = baseRates();
        List<lfemr__Fee_Schedule_Rate__c> rates = buildRates(schedules, baseRates, catalogIds);
        saveRates(schedules, rates);

        Integer superbillCount = seedSuperbills();
        System.debug(
            'Seeded ' + schedules.size() + ' fee schedules, ' + rates.size() +
            ' effective-dated rates, and refreshed ' + superbillCount + ' superbills.'
        );
    }

    private Map<String, Id> loadPayerIds() {
        Map<String, Id> payerIds = new Map<String, Id>();
        for (lfemr__Payer__c row : [
            SELECT Id, lfemr__Source_System_Id__c
            FROM lfemr__Payer__c
            WHERE lfemr__Source_System_Id__c LIKE 'seed-payer-%'
        ]) {
            payerIds.put(row.lfemr__Source_System_Id__c, row.Id);
        }
        return payerIds;
    }

    private void requireSeedPayers(Map<String, Id> payerIds) {
        for (String sourceId : new List<String>{
            'seed-payer-aetna',
            'seed-payer-uhc',
            'seed-payer-cigna',
            'seed-payer-medicare',
            'seed-payer-medicaid'
        }) {
            if (!payerIds.containsKey(sourceId)) {
                throw new AuraHandledException(
                    'Run scripts/apex/seedPayerAndCoverage.apex first. Missing ' + sourceId + '.'
                );
            }
        }
    }

    private void ensureBillingOrganization() {
        List<lfemr__Organization__c> existing = [
            SELECT Id, lfemr__Taxonomy_Code__c
            FROM lfemr__Organization__c
            WHERE lfemr__Active__c = TRUE AND lfemr__Is_Default_Billing__c = TRUE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            if (String.isBlank(existing[0].lfemr__Taxonomy_Code__c)) {
                existing[0].lfemr__Taxonomy_Code__c = '261QP2300X';
                update existing[0];
            }
            return;
        }
        upsert new lfemr__Organization__c(
            Name = 'LogicEMR Demo Clinic',
            lfemr__Source_System_Id__c = 'seed-org-logicemr-demo-clinic',
            lfemr__FHIR_Id__c = 'seed-org-logicemr-demo-clinic',
            lfemr__NPI__c = '1888888875',
            lfemr__EIN__c = '12-3456789',
            lfemr__Taxonomy_Code__c = '261QP2300X',
            lfemr__Street__c = '100 Health Way',
            lfemr__City__c = 'New York',
            lfemr__State__c = 'NY',
            lfemr__Postal_Code__c = '10001',
            lfemr__Country__c = 'US',
            lfemr__Active__c = true,
            lfemr__Is_Default_Billing__c = true
        ) lfemr__Source_System_Id__c;
    }

    private List<lfemr__Fee_Schedule__c> buildSchedules(Map<String, Id> payerIds) {
        return new List<lfemr__Fee_Schedule__c>{
            schedule('LogicEMR Demo - Aetna 2026', 'Payer', payerIds.get('seed-payer-aetna'), 10),
            schedule('LogicEMR Demo - UnitedHealthcare 2026', 'Payer', payerIds.get('seed-payer-uhc'), 10),
            schedule('LogicEMR Demo - Cigna 2026', 'Payer', payerIds.get('seed-payer-cigna'), 10),
            schedule('LogicEMR Demo - Medicare 2026', 'Payer', payerIds.get('seed-payer-medicare'), 10),
            schedule('LogicEMR Demo - Medicaid 2026', 'Payer', payerIds.get('seed-payer-medicaid'), 10),
            schedule('LogicEMR Demo - Self-Pay 2026', 'Self-Pay', null, 20)
        };
    }

    private lfemr__Fee_Schedule__c schedule(String name, String type, Id payerId, Decimal priority) {
        return new lfemr__Fee_Schedule__c(
            Name = name,
            lfemr__Schedule_Type__c = type,
            lfemr__Payer__c = payerId,
            lfemr__Priority__c = priority,
            lfemr__Active__c = true
        );
    }

    private void saveSchedules(List<lfemr__Fee_Schedule__c> schedules) {
        Set<String> names = new Set<String>();
        for (lfemr__Fee_Schedule__c schedule : schedules) names.add(schedule.Name);

        Map<String, Id> existingIds = new Map<String, Id>();
        for (lfemr__Fee_Schedule__c existing : [
            SELECT Id, Name
            FROM lfemr__Fee_Schedule__c
            WHERE Name IN :names
        ]) {
            existingIds.put(existing.Name, existing.Id);
        }
        for (lfemr__Fee_Schedule__c schedule : schedules) {
            schedule.Id = existingIds.get(schedule.Name);
        }
        upsert schedules;
    }

    private Map<String, Id> loadCatalogIds() {
        Map<String, Id> catalogIds = new Map<String, Id>();
        for (lfemr__Code_Reference__c row : [
            SELECT Id, lfemr__Code_System__c, lfemr__Code__c
            FROM lfemr__Code_Reference__c
            WHERE lfemr__Active__c = TRUE
              AND lfemr__Code_System__c IN ('CPT', 'HCPCS')
        ]) {
            catalogIds.put(row.lfemr__Code_System__c + '|' + row.lfemr__Code__c, row.Id);
        }
        return catalogIds;
    }

    private List<FeeScheduleRateSpec> baseRates() {
        return new List<FeeScheduleRateSpec>{
            new FeeScheduleRateSpec('CPT', '99213', 'Office visit, established patient, low MDM', 135),
            new FeeScheduleRateSpec('CPT', '99214', 'Office visit, established patient, moderate MDM', 195),
            new FeeScheduleRateSpec('CPT', '99393', 'Preventive visit, established patient, age 5-11', 165),
            new FeeScheduleRateSpec('CPT', '93000', 'Electrocardiogram, complete', 95),
            new FeeScheduleRateSpec('CPT', '93306', 'Echocardiogram, complete', 520),
            new FeeScheduleRateSpec('CPT', '73502', 'X-ray hip, 2 or 3 views', 145),
            new FeeScheduleRateSpec('CPT', '27236', 'Open treatment of femoral neck fracture', 2450),
            new FeeScheduleRateSpec('CPT', '47562', 'Laparoscopic cholecystectomy', 1850),
            new FeeScheduleRateSpec('CPT', '94010', 'Spirometry', 85),
            new FeeScheduleRateSpec('CPT', '90834', 'Psychotherapy, 45 minutes', 165),
            new FeeScheduleRateSpec('HCPCS', 'J1885', 'Ketorolac tromethamine, per 15 mg', 18)
        };
    }

    private List<lfemr__Fee_Schedule_Rate__c> buildRates(
        List<lfemr__Fee_Schedule__c> schedules,
        List<FeeScheduleRateSpec> baseRates,
        Map<String, Id> catalogIds
    ) {
        List<lfemr__Fee_Schedule_Rate__c> rates = new List<lfemr__Fee_Schedule_Rate__c>();
        for (lfemr__Fee_Schedule__c schedule : schedules) {
            Decimal multiplier = multiplierFor(schedule.Name);
            for (FeeScheduleRateSpec spec : baseRates) {
                rates.add(rate(schedule.Id, spec, catalogIds, CURRENT_START, null, multiplier));
            }

            // One prior-period row per schedule makes effective-date behavior visible.
            FeeScheduleRateSpec historical = baseRates[3]; // CPT 93000
            rates.add(
                rate(schedule.Id, historical, catalogIds, HISTORICAL_START, HISTORICAL_END, multiplier * 0.94)
            );
        }
        return rates;
    }

    private Decimal multiplierFor(String scheduleName) {
        if (scheduleName.contains('Medicaid')) return 0.62;
        if (scheduleName.contains('Medicare')) return 0.75;
        if (scheduleName.contains('Cigna')) return 0.95;
        if (scheduleName.contains('UnitedHealthcare')) return 0.98;
        if (scheduleName.contains('Self-Pay')) return 1.15;
        return 1.00;
    }

    private lfemr__Fee_Schedule_Rate__c rate(
        Id scheduleId,
        FeeScheduleRateSpec spec,
        Map<String, Id> catalogIds,
        Date effectiveStart,
        Date effectiveEnd,
        Decimal multiplier
    ) {
        return new lfemr__Fee_Schedule_Rate__c(
            lfemr__Fee_Schedule__c = scheduleId,
            lfemr__Procedure_Code_System__c = spec.codeSystem,
            lfemr__Procedure_Code__c = spec.code,
            lfemr__Procedure_Display__c = spec.display,
            lfemr__Procedure_Ref__c = catalogIds.get(spec.codeSystem + '|' + spec.code),
            lfemr__Rate_Amount__c = (spec.baseAmount * multiplier).setScale(2),
            lfemr__Effective_Start__c = effectiveStart,
            lfemr__Effective_End__c = effectiveEnd,
            lfemr__Active__c = true
        );
    }

    private void saveRates(
        List<lfemr__Fee_Schedule__c> schedules,
        List<lfemr__Fee_Schedule_Rate__c> rates
    ) {
        Set<Id> scheduleIds = new Map<Id, lfemr__Fee_Schedule__c>(schedules).keySet();
        Map<String, Id> existingIds = new Map<String, Id>();
        for (lfemr__Fee_Schedule_Rate__c existing : [
            SELECT Id, lfemr__Fee_Schedule__c, lfemr__Procedure_Code_System__c,
                   lfemr__Procedure_Code__c, lfemr__Effective_Start__c
            FROM lfemr__Fee_Schedule_Rate__c
            WHERE lfemr__Fee_Schedule__c IN :scheduleIds
        ]) {
            existingIds.put(rateKey(existing), existing.Id);
        }
        for (lfemr__Fee_Schedule_Rate__c rate : rates) {
            rate.Id = existingIds.get(rateKey(rate));
        }
        upsert rates;
    }

    private String rateKey(lfemr__Fee_Schedule_Rate__c rate) {
        return String.valueOf(rate.lfemr__Fee_Schedule__c) + '|' +
            rate.lfemr__Procedure_Code_System__c + '|' + rate.lfemr__Procedure_Code__c + '|' +
            String.valueOf(rate.lfemr__Effective_Start__c);
    }

    private Integer seedSuperbills() {
        Set<String> claimEncounterKeys = new Set<String>{
            'seed-enc-maya-finished-ed',
            'seed-enc-liam-well',
            'seed-enc-james-ed',
            'seed-enc-olivia-virtual'
        };
        List<lfemr__Encounter__c> encounters = [
            SELECT Id
            FROM lfemr__Encounter__c
            WHERE lfemr__Status__c = 'Finished'
              AND lfemr__Source_System_Id__c IN :claimEncounterKeys
            ORDER BY lfemr__Start__c ASC
        ];
        if (encounters.size() != claimEncounterKeys.size()) {
            throw new AuraHandledException(
                'Run scripts/apex/seedDemoData.apex first. Expected four claim-ready demo encounters.'
            );
        }
        for (lfemr__Encounter__c encounter : encounters) {
            ClaimReadinessController.prepareForFinishedEncounter(encounter.Id);
        }
        return encounters.size();
    }

}

class FeeScheduleRateSpec {
    String codeSystem;
    String code;
    String display;
    Decimal baseAmount;

    FeeScheduleRateSpec(String codeSystem, String code, String display, Decimal baseAmount) {
        this.codeSystem = codeSystem;
        this.code = code;
        this.display = display;
        this.baseAmount = baseAmount;
    }
}
