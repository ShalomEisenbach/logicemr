Id patientId = 'a03hm000001kKGAAA2';
Datetime startOfDay = Datetime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0));
Datetime startOfNextDay = startOfDay.addDays(1);

Slot__c slot = [
	SELECT Id, Start__c
	FROM Slot__c
	WHERE
	Status__c = 'Free'
	    AND Schedule__r.Practitioner__r.User__c = : UserInfo.getUserId()
	    AND Start__c >= : startOfDay
	    AND Start__c < : startOfNextDay
	    ORDER BY Start__c ASC
	    LIMIT 1
];

AppointmentCalendarController.ActionResult booked = AppointmentCalendarController.bookAppointment(
	patientId,
	slot.Id,
	'Follow-up',
	'Same-day Home worklist check'
	);
AppointmentCalendarController.ActionResult arrived = AppointmentCalendarController.arriveAppointment(
	booked.appointmentId
	);

ProviderHomeController.HomePayload home = ProviderHomeController.getHome();

Boolean homeHasAppt = false;

for (Appointment__c row : home.lists.todaysAppointments) {
	if (row.Id == booked.appointmentId) {
		homeHasAppt = true;
	}
}

System.debug('TODAY_SLOT start=' + slot.Start__c
             + ' appointment=' + booked.appointmentId
             + ' encounter=' + arrived.encounterId
             + ' homeHasAppt=' + homeHasAppt
             + ' todaysAppointments=' + home.metrics.todaysAppointments);