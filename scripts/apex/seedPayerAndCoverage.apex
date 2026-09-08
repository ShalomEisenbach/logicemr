/**
 * Idempotent seed for Payer and Coverage.
 * Requires seedDemoData.apex. Re-run safe via Source_System_Id__c upsert.
 * Do not set Coverage Name — composed by NameFormatterHandler as
 * {Payer__r.Name} - {Member_Id__c}. Payer Name is a Text label — set it.
 *
 * Payer_Identifier__c values are public EDI / Stedi trading-partner IDs.
 */
new SeedRunner().run();

class SeedRunner {
    void run() {
        Map<String, Id> ptIds = loadIds(
            [
                SELECT Id, lfemr__Source_System_Id__c
                FROM lfemr__Patient__c
                WHERE lfemr__Source_System_Id__c LIKE 'seed-pt-%'
            ]
        );
        if (ptIds.size() < 10) {
            throw new AuraHandledException('Run scripts/apex/seedDemoData.apex first.');
        }

        Id maya = ptIds.get('seed-pt-maya-chen');
        Id liam = ptIds.get('seed-pt-liam-chen');
        Id sofia = ptIds.get('seed-pt-sofia-rivera');
        Id noah = ptIds.get('seed-pt-noah-rivera');
        Id james = ptIds.get('seed-pt-james-okonkwo');
        Id ava = ptIds.get('seed-pt-ava-thompson');
        Id ethan = ptIds.get('seed-pt-ethan-brooks');
        Id olivia = ptIds.get('seed-pt-olivia-kim');
        Id benjamin = ptIds.get('seed-pt-benjamin-alvarez');
        Id harper = ptIds.get('seed-pt-harper-nguyen');

        List<lfemr__Payer__c> payers = new List<lfemr__Payer__c>{
            newPayer('seed-payer-aetna', 'Aetna', 'Commercial', '60054', true),
            newPayer('seed-payer-uhc', 'UnitedHealthcare', 'Commercial', '87726', true),
            newPayer('seed-payer-cigna', 'Cigna', 'Commercial', '62308', true),
            newPayer('seed-payer-medicare', 'Medicare', 'Medicare', '00431', true),
            newPayer('seed-payer-medicaid', 'State Medicaid', 'Medicaid', '14163', true),
            newPayer('seed-payer-self-pay', 'Self-Pay', 'Self-Pay', 'SELFPAY', true),
            newPayer('seed-payer-legacy', 'Legacy Health Plan', 'Other', '99999', false)
        };
        upsert payers lfemr__Source_System_Id__c;

        Map<String, Id> payerIds = new Map<String, Id>();
        for (lfemr__Payer__c row : payers) {
            payerIds.put(row.lfemr__Source_System_Id__c, row.Id);
        }

        Id aetna = payerIds.get('seed-payer-aetna');
        Id uhc = payerIds.get('seed-payer-uhc');
        Id cigna = payerIds.get('seed-payer-cigna');
        Id medicare = payerIds.get('seed-payer-medicare');
        Id medicaid = payerIds.get('seed-payer-medicaid');
        Id selfPay = payerIds.get('seed-payer-self-pay');
        Id legacy = payerIds.get('seed-payer-legacy');

        List<lfemr__Coverage__c> coverages = new List<lfemr__Coverage__c>{
            // Maya Chen — commercial primary, pharmacy secondary, expired Cigna
            newCoverage(
                'seed-cov-maya-aetna',
                maya,
                aetna,
                'W123456789',
                'GRP-CHEN-100',
                'Aetna Gold PPO',
                'Medical',
                'Primary',
                'Self',
                'Maya Chen',
                'Active',
                Date.newInstance(2026, 1, 1),
                Date.newInstance(2026, 12, 31)
            ),
            newCoverage(
                'seed-cov-maya-uhc-rx',
                maya,
                uhc,
                'UHC-RX-44120',
                'GRP-CHEN-100',
                'UHC Pharmacy',
                'Pharmacy',
                'Secondary',
                'Self',
                'Maya Chen',
                'Active',
                Date.newInstance(2026, 1, 1),
                Date.newInstance(2026, 12, 31)
            ),
            newCoverage(
                'seed-cov-maya-cigna-old',
                maya,
                cigna,
                'CIG-88210',
                'GRP-OLD-88',
                'Cigna Open Access',
                'Medical',
                'Primary',
                'Self',
                'Maya Chen',
                'Inactive',
                Date.newInstance(2024, 1, 1),
                Date.newInstance(2025, 12, 31)
            ),
            // Liam Chen — dependent on Maya's Aetna
            newCoverage(
                'seed-cov-liam-aetna',
                liam,
                aetna,
                'W123456789-01',
                'GRP-CHEN-100',
                'Aetna Gold PPO',
                'Medical',
                'Primary',
                'Child',
                'Maya Chen',
                'Active',
                Date.newInstance(2026, 1, 1),
                Date.newInstance(2026, 12, 31)
            ),
            // Sofia Rivera — Medicare + commercial secondary
            newCoverage(
                'seed-cov-sofia-medicare',
                sofia,
                medicare,
                '1EG4-TE5-MK72',
                null,
                'Medicare Part B',
                'Medical',
                'Primary',
                'Self',
                'Sofia Rivera',
                'Active',
                Date.newInstance(2024, 11, 1),
                null
            ),
            newCoverage(
                'seed-cov-sofia-aetna',
                sofia,
                aetna,
                'W998877661',
                'GRP-RIVERA-22',
                'Aetna Medicare Supplement',
                'Medical',
                'Secondary',
                'Self',
                'Sofia Rivera',
                'Active',
                Date.newInstance(2025, 1, 1),
                Date.newInstance(2026, 12, 31)
            ),
            // Noah Rivera — Medicaid dependent
            newCoverage(
                'seed-cov-noah-medicaid',
                noah,
                medicaid,
                'MD-NOAH-0418',
                'MCD-NY-2026',
                'State Medicaid',
                'Medical',
                'Primary',
                'Child',
                'Sofia Rivera',
                'Active',
                Date.newInstance(2026, 4, 18),
                Date.newInstance(2026, 12, 31)
            ),
            // James Okonkwo — dual eligible
            newCoverage(
                'seed-cov-james-medicare',
                james,
                medicare,
                '3AB8-JK2-PL19',
                null,
                'Medicare Part A/B',
                'Medical',
                'Primary',
                'Self',
                'James Okonkwo',
                'Active',
                Date.newInstance(2013, 1, 1),
                null
            ),
            newCoverage(
                'seed-cov-james-medicaid',
                james,
                medicaid,
                'MD-JAMES-0109',
                'MCD-NY-2026',
                'State Medicaid',
                'Medical',
                'Secondary',
                'Self',
                'James Okonkwo',
                'Active',
                Date.newInstance(2026, 1, 1),
                Date.newInstance(2026, 12, 31)
            ),
            // Ava Thompson — inactive patient, inactive coverage
            newCoverage(
                'seed-cov-ava-aetna',
                ava,
                aetna,
                'W554433221',
                'GRP-THOMP-9',
                'Aetna Silver HMO',
                'Medical',
                'Primary',
                'Self',
                'Ava Thompson',
                'Inactive',
                Date.newInstance(2023, 6, 1),
                Date.newInstance(2025, 5, 31)
            ),
            // Ethan Brooks — Medicaid child
            newCoverage(
                'seed-cov-ethan-medicaid',
                ethan,
                medicaid,
                'MD-ETHAN-0815',
                'MCD-NY-2026',
                'State Medicaid',
                'Medical',
                'Primary',
                'Child',
                'Taylor Brooks',
                'Active',
                Date.newInstance(2025, 8, 15),
                Date.newInstance(2026, 12, 31)
            ),
            // Olivia Kim — medical + dental + draft vision
            newCoverage(
                'seed-cov-olivia-uhc',
                olivia,
                uhc,
                'UHC-OK-2001',
                'GRP-KIM-44',
                'UHC Choice Plus',
                'Medical',
                'Primary',
                'Self',
                'Olivia Kim',
                'Active',
                Date.newInstance(2026, 1, 1),
                Date.newInstance(2026, 12, 31)
            ),
            newCoverage(
                'seed-cov-olivia-cigna-dental',
                olivia,
                cigna,
                'CIG-DEN-2001',
                'GRP-KIM-44',
                'Cigna Dental PPO',
                'Dental',
                'Secondary',
                'Self',
                'Olivia Kim',
                'Active',
                Date.newInstance(2026, 1, 1),
                Date.newInstance(2026, 12, 31)
            ),
            newCoverage(
                'seed-cov-olivia-vision-draft',
                olivia,
                uhc,
                'UHC-VIS-2001',
                'GRP-KIM-44',
                'UHC Vision',
                'Vision',
                'Tertiary',
                'Self',
                'Olivia Kim',
                'Draft',
                Date.newInstance(2026, 10, 1),
                Date.newInstance(2027, 9, 30)
            ),
            // Benjamin Alvarez — commercial + expired self-pay
            newCoverage(
                'seed-cov-ben-cigna',
                benjamin,
                cigna,
                'CIG-BA-1963',
                'GRP-ALV-18',
                'Cigna Open Access Plus',
                'Medical',
                'Primary',
                'Self',
                'Benjamin Alvarez',
                'Active',
                Date.newInstance(2025, 7, 1),
                Date.newInstance(2026, 6, 30)
            ),
            newCoverage(
                'seed-cov-ben-self-pay',
                benjamin,
                selfPay,
                'SP-BA-1963',
                null,
                'Self-Pay',
                'Medical',
                'Secondary',
                'Self',
                'Benjamin Alvarez',
                'Inactive',
                Date.newInstance(2024, 1, 1),
                Date.newInstance(2025, 6, 30)
            ),
            // Harper Nguyen — dependent commercial; leftover inactive legacy
            newCoverage(
                'seed-cov-harper-uhc',
                harper,
                uhc,
                'UHC-HN-2010',
                'GRP-NGUYEN-8',
                'UHC Choice Plus',
                'Medical',
                'Primary',
                'Child',
                'Kim Nguyen',
                'Active',
                Date.newInstance(2026, 1, 1),
                Date.newInstance(2026, 12, 31)
            ),
            newCoverage(
                'seed-cov-harper-legacy',
                harper,
                legacy,
                'LEG-HN-2010',
                'GRP-OLD-01',
                'Legacy Pediatric',
                'Medical',
                'Primary',
                'Child',
                'Kim Nguyen',
                'Inactive',
                Date.newInstance(2022, 1, 1),
                Date.newInstance(2023, 12, 31)
            )
        };
        upsert coverages lfemr__Source_System_Id__c;

        System.debug('Seeded ' + payers.size() + ' payers, ' + coverages.size() + ' coverages.');
    }

    lfemr__Payer__c newPayer(
        String sourceId,
        String payerName,
        String payerType,
        String identifier,
        Boolean active
    ) {
        return new lfemr__Payer__c(
            Name = payerName,
            lfemr__Source_System_Id__c = sourceId,
            lfemr__FHIR_Id__c = sourceId,
            lfemr__Type__c = payerType,
            lfemr__Payer_Identifier__c = identifier,
            lfemr__Active__c = active
        );
    }

    lfemr__Coverage__c newCoverage(
        String sourceId,
        Id patientId,
        Id payerId,
        String memberId,
        String groupNumber,
        String planName,
        String coverageType,
        String priority,
        String relationship,
        String subscriberName,
        String status,
        Date startDate,
        Date endDate
    ) {
        return new lfemr__Coverage__c(
            lfemr__Source_System_Id__c = sourceId,
            lfemr__FHIR_Id__c = sourceId,
            lfemr__Patient__c = patientId,
            lfemr__Payer__c = payerId,
            lfemr__Member_Id__c = memberId,
            lfemr__Group_Number__c = groupNumber,
            lfemr__Plan_Name__c = planName,
            lfemr__Type__c = coverageType,
            lfemr__Priority__c = priority,
            lfemr__Relationship_to_Subscriber__c = relationship,
            lfemr__Subscriber_Name__c = subscriberName,
            lfemr__Status__c = status,
            lfemr__Effective_Start__c = startDate,
            lfemr__Effective_End__c = endDate
        );
    }

    Map<String, Id> loadIds(List<SObject> rows) {
        Map<String, Id> bySource = new Map<String, Id>();
        for (SObject row : rows) {
            bySource.put((String) row.get('lfemr__Source_System_Id__c'), row.Id);
        }
        return bySource;
    }
}
