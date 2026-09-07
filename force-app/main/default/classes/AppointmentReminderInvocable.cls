global with sharing class AppointmentReminderInvocable {
    public static final String JOB_NAME = 'LogicEMR Appointment Reminders';
    public static final String DEFAULT_CRON = '0 0 * * * ?';

    @InvocableMethod(
        label='Schedule Appointment Reminders'
        description='Schedules the hourly LogicEMR appointment reminder job if it is not already scheduled.'
        category='LogicEMR'
    )
    global static List<Result> scheduleReminders(List<Request> requests) {
        List<Result> results = new List<Result>();
        Request request = requests != null && !requests.isEmpty() ? requests[0] : new Request();
        Result result = new Result();
        results.add(result);
        try {
            String cron = String.isNotBlank(request.cronExpression) ? request.cronExpression : DEFAULT_CRON;
            List<CronTrigger> existing = [
                SELECT Id, CronJobDetail.Name
                FROM CronTrigger
                WHERE CronJobDetail.Name = :JOB_NAME
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                result.success = true;
                result.jobId = existing[0].Id;
                result.message = 'Reminder job is already scheduled.';
                return results;
            }
            result.jobId = System.schedule(JOB_NAME, cron, new AppointmentReminderSchedulable());
            result.success = true;
            result.message = 'Reminder job scheduled.';
        } catch (Exception e) {
            result.success = false;
            result.message = e.getMessage();
        }
        return results;
    }

    global class Request {
        @InvocableVariable(label='Cron Expression' description='Optional cron; defaults to hourly at minute 0.')
        global String cronExpression;
    }

    global class Result {
        @InvocableVariable
        global Boolean success;
        @InvocableVariable
        global String jobId;
        @InvocableVariable
        global String message;
    }
}
