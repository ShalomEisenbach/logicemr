trigger AppointmentTrigger on Appointment__c(before insert, before update, after insert, after update) {
    if (Trigger.isBefore) {
        NameFormatterHandler.format(Trigger.new);
        if (Trigger.isUpdate) {
            AppointmentCommunicationHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
        }
    }
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            AppointmentCommunicationHandler.afterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            AppointmentCommunicationHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}
