public with sharing class ClaimSubmissionQueueable implements Queueable, Database.AllowsCallouts {
    private Id submissionId;
    private ClaimSubmissionConfig config;

    public ClaimSubmissionQueueable(Id submissionId, ClaimSubmissionConfig config) {
        this.submissionId = submissionId;
        this.config = config;
    }

    public void execute(QueueableContext context) {
        ClaimSubmissionService.process(submissionId, config);
    }
}
