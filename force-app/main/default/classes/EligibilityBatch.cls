public with sharing class EligibilityBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful, Schedulable {
    public static final Integer DEFAULT_LOOKAHEAD_DAYS = 7;
    public static final Integer DEFAULT_BATCH_SIZE = 1;
    private static final Set<String> UPCOMING_STATUSES = new Set<String>{ 'Proposed', 'Booked', 'Arrived' };

    @TestVisible
    public static String lastSummary;

    @TestVisible
    Integer lookaheadDays;

    private Integer processedCount = 0;
    private Integer failedCount = 0;

    public EligibilityBatch() {
        this(DEFAULT_LOOKAHEAD_DAYS);
    }

    public EligibilityBatch(Integer lookaheadDays) {
        this.lookaheadDays = lookaheadDays == null || lookaheadDays < 1
            ? DEFAULT_LOOKAHEAD_DAYS
            : lookaheadDays;
    }

    public static Id run() {
        return run(DEFAULT_LOOKAHEAD_DAYS);
    }

    public static Id run(Integer lookaheadDays) {
        return Database.executeBatch(new EligibilityBatch(lookaheadDays), DEFAULT_BATCH_SIZE);
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        Datetime windowStart = Datetime.now();
        Datetime windowEnd = windowStart.addDays(lookaheadDays);
        return Database.getQueryLocator(
            [
                SELECT Id, Patient__c
                FROM Coverage__c
                WHERE
                    Status__c = 'Active'
                    AND Patient__c IN (
                        SELECT Patient__c
                        FROM Appointment__c
                        WHERE
                            Start__c >= :windowStart
                            AND Start__c <= :windowEnd
                            AND Status__c IN :UPCOMING_STATUSES
                    )
            ]
        );
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        // Batch size is 1 so each coverage is its own transaction (callout then DML).
        for (SObject row : scope) {
            Coverage__c coverage = (Coverage__c) row;
            try {
                EligibilityService.runCheck(coverage.Patient__c, coverage.Id, null);
                processedCount++;
            } catch (Exception e) {
                failedCount++;
            }
        }
    }

    public void finish(Database.BatchableContext context) {
        lastSummary = 'Eligibility re-verify processed=' + processedCount + ', failed=' + failedCount;
    }

    public void execute(SchedulableContext context) {
        Database.executeBatch(new EligibilityBatch(lookaheadDays), DEFAULT_BATCH_SIZE);
    }
}
