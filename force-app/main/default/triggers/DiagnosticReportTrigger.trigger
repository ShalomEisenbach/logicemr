trigger DiagnosticReportTrigger on DiagnosticReport__c(before insert, before update) {
    NameFormatterHandler.format(Trigger.new);
}
