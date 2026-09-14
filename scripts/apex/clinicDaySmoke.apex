String stamp = String.valueOf(Datetime.now().getTime());
String mrn = 'SMOKE-' + stamp;

System.debug('CLINIC_DAY_SMOKE start mrn=' + mrn);

PatientRegistrationController.PatientDemographics demo = new PatientRegistrationController.PatientDemographics();
demo.mrn = mrn;
demo.firstName = 'Smoke';
demo.lastName = 'Visit' + stamp.right(6);
demo.dateOfBirth = Date.newInstance(1988, 4, 12);
demo.sexAtBirth = 'Female';
demo.phone = '5550101999';
demo.email = 'smoke.visit+' + stamp + '@example.com';
demo.smsOptIn = true;
demo.status = 'Active';
demo.street = '1 Smoke St';
demo.city = 'Boston';
demo.state = 'MA';
demo.postalCode = '02108';
demo.country = 'US';

PatientRegistrationController.RegistrationResult registered = PatientRegistrationController.registerPatient(demo);

if (registered.patient == null) {
	throw new IllegalArgumentException('Register failed: duplicates found ' + registered.duplicates.size());
}

Id patientId = registered.patient.Id;

System.debug('PASS register patientId=' + patientId);

Slot__c slot = [
	SELECT Id, Start__c
	FROM Slot__c
	WHERE Status__c = 'Free' AND Schedule__r.Practitioner__r.User__c = : UserInfo.getUserId()
	    ORDER BY Start__c ASC
	    LIMIT 1
];

AppointmentCalendarController.ActionResult booked = AppointmentCalendarController.bookAppointment(
	patientId,
	slot.Id,
	'Walk-in',
	'Clinic-day smoke test'
	);

if (booked == null || booked.appointmentId == null) {
	throw new IllegalArgumentException('Book failed: ' + (booked == null ? 'null' : booked.reason));
}

Id appointmentId = booked.appointmentId;

System.debug('PASS book appointmentId=' + appointmentId + ' slotId=' + slot.Id);

AppointmentCalendarController.ActionResult arrived = AppointmentCalendarController.arriveAppointment(appointmentId);

if (arrived == null || arrived.encounterId == null) {
	throw new IllegalArgumentException('Arrive failed: ' + (arrived == null ? 'null' : arrived.reason));
}

Id encounterId = arrived.encounterId;

System.debug('PASS arrive encounterId=' + encounterId);

EncounterDiagnosis__c dx = EncounterWorkspaceController.addDiagnosis(
	encounterId,
	'ICD-10',
	'J06.9',
	'Acute upper respiratory infection, unspecified',
	null,
	'Principal',
	1
	);

System.debug('PASS diagnosis encounterDiagnosisId=' + dx.Id);

OrderEntryController.ServiceOrderInput orderInput = new OrderEntryController.ServiceOrderInput();
orderInput.category = 'Lab';
orderInput.codeSystem = 'CPT';
orderInput.code = '85025';
orderInput.display = 'Complete CBC with auto differential WBC';
orderInput.priority = 'Routine';
orderInput.reason = 'Clinic-day smoke test';

List<ServiceRequest__c> orders = OrderEntryController.createServiceOrders(
	encounterId,
	new List<OrderEntryController.ServiceOrderInput> { orderInput }
	);

System.debug('PASS order serviceRequestId=' + orders[0].Id);

NoteEditorController.NoteEditorState signed = NoteEditorController.signNote(
	encounterId,
	null,
	'Progress Note',
	'Clinic-day smoke test. URI symptoms. CBC ordered. Follow up as needed.'
	);
System.debug('PASS sign noteId=' + signed.noteId + ' status=' + signed.status);

Payer__c aetna = [
	SELECT Id, Payer_Identifier__c
	FROM Payer__c
	WHERE Name = 'Aetna'
	    LIMIT 1
];
Coverage__c coverage = CoveragePanelController.saveCoverage(
	null,
	patientId,
	aetna.Id,
	'SMOKE' + stamp.right(8),
	'GRP100',
	'Aetna PPO',
	'Medical',
	'Self',
	'Smoke Visit',
	'Active',
	Date.today().addYears(-1),
	Date.today().addYears(1),
	'Primary'
	);

System.debug('PASS coverage coverageId=' + coverage.Id + ' payerId=' + aetna.Payer_Identifier__c);

EncounterWorkspaceController.transitionStatus(encounterId, 'In Progress');
System.debug('PASS encounter In Progress');

System.debug('CLINIC_DAY_SMOKE_IDS patient=' + patientId
             + ' appointment=' + appointmentId
             + ' encounter=' + encounterId
             + ' coverage=' + coverage.Id);