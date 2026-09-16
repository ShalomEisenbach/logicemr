public without sharing class ClaimAcknowledgmentQueueable implements Queueable, Database.AllowsCallouts {
  private static final Integer MAX_RETRIES = 3;
  private static final Integer RETRY_DELAY_MINUTES = 5;
  private String transactionId;
  private Integer retryCount;

  public ClaimAcknowledgmentQueueable(String transactionId) {
    this(transactionId, 0);
  }

  private ClaimAcknowledgmentQueueable(
    String transactionId,
    Integer retryCount
  ) {
    this.transactionId = transactionId;
    this.retryCount = retryCount;
  }

  public void execute(QueueableContext context) {
    try {
      ClaimAcknowledgmentService.retrieveAndIngest(transactionId);
    } catch (Exception error) {
      if (!isRetryable(error) || retryCount >= MAX_RETRIES) {
        throw error;
      }
      System.enqueueJob(
        new ClaimAcknowledgmentQueueable(transactionId, retryCount + 1),
        RETRY_DELAY_MINUTES
      );
    }
  }

  @TestVisible
  private static Boolean isRetryable(Exception error) {
    if (error instanceof System.CalloutException) {
      return true;
    }
    String message = error.getMessage();
    return String.isNotBlank(message) &&
      (message.contains('HTTP 404') ||
      message.contains('HTTP 408') ||
      message.contains('HTTP 409') ||
      message.contains('HTTP 425') ||
      message.contains('HTTP 429') ||
      Pattern.matches('(?s).*HTTP 5[0-9]{2}.*', message));
  }
}
