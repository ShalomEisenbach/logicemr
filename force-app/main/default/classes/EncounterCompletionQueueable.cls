public with sharing class EncounterCompletionQueueable implements Queueable {
  private static final Integer BATCH_SIZE = 2;
  private List<Id> encounterIds;

  public EncounterCompletionQueueable(List<Id> encounterIds) {
    this.encounterIds = encounterIds == null
      ? new List<Id>()
      : new List<Id>(encounterIds);
  }

  public void execute(QueueableContext context) {
    List<Id> batch = new List<Id>();
    List<Id> remaining = new List<Id>();
    for (Integer i = 0; i < encounterIds.size(); i++) {
      if (i < BATCH_SIZE) {
        batch.add(encounterIds[i]);
      } else {
        remaining.add(encounterIds[i]);
      }
    }
    EncounterCompletionService.process(batch);
    if (!remaining.isEmpty()) {
      Boolean hasDepth =
        !AsyncInfo.hasMaxStackDepth() ||
        AsyncInfo.getCurrentQueueableStackDepth() <
        AsyncInfo.getMaximumQueueableStackDepth();
      if (
        Limits.getQueueableJobs() < Limits.getLimitQueueableJobs() && hasDepth
      ) {
        try {
          System.enqueueJob(new EncounterCompletionQueueable(remaining));
        } catch (System.AsyncException e) {
          EncounterCompletionService.markQueueUnavailable(remaining);
        }
      } else {
        EncounterCompletionService.markQueueUnavailable(remaining);
      }
    }
  }
}
