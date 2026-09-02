trigger AppointmentTrigger on Appointment__c(before insert, before update) {
    NameFormatterHandler.format(Trigger.new);
}
