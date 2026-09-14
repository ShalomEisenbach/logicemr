Id patientId = 'a03hm000001kKGAAA2';
Id appointmentId = 'a0Mhm0000009V4bEAE';
Id encounterId = 'a02hm000000wfSbAAI';
Id coverageId = 'a0Shm000000HIJtEAO';

Patient__c patient = [
	SELECT Name, MRN__c, First_Name__c, Last_Name__c, Status__c
	FROM Patient__c
	WHERE Id = : patientId
];
Appointment__c appt = [
	SELECT Name, Status__c, Encounter__c, Practitioner__c, Practitioner__r.Name, Start__c
	FROM Appointment__c
	WHERE Id = : appointmentId
];
Encounter__c enc = [
	SELECT Name, Status__c
	FROM Encounter__c
	WHERE Id = : encounterId
];
Integer dx = [SELECT COUNT() FROM EncounterDiagnosis__c WHERE Encounter__c = : encounterId];
Integer orders = [SELECT COUNT() FROM ServiceRequest__c WHERE Encounter__c = : encounterId];
ClinicalNote__c note = [
	SELECT Status__c, Signed_Date__c
	FROM ClinicalNote__c
	WHERE Encounter__c = : encounterId
	    LIMIT 1
];
Coverage__c cov = [
	SELECT Status__c, Member_Id__c, Payer__r.Name, Payer__r.Payer_Identifier__c
	FROM Coverage__c
	WHERE Id = : coverageId
];
Eligibility_Check__c check = [
	SELECT Status__c, Error_Message__c
	FROM Eligibility_Check__c
	WHERE Coverage__c = : coverageId
	    ORDER BY CreatedDate DESC
	    LIMIT 1
];

System.debug('VERIFY patient=' + patient.Name + ' mrn=' + patient.MRN__c);
System.debug('VERIFY appointment=' + appt.Name + ' status=' + appt.Status__c + ' practitioner=' + appt.Practitioner__r.Name + ' start=' + appt.Start__c);
System.debug('VERIFY encounter=' + enc.Name + ' status=' + enc.Status__c);
System.debug('VERIFY diagnoses=' + dx + ' orders=' + orders + ' note=' + note.Status__c);
System.debug('VERIFY coverage=' + cov.Payer__r.Name + ' payerId=' + cov.Payer__r.Payer_Identifier__c);
System.debug('VERIFY eligibility=' + check.Status__c + ' error=' + check.Error_Message__c);

ProviderHomeController.HomePayload home = ProviderHomeController.getHome();

Boolean homeHasAppt = false;

for (Appointment__c row : home.lists.todaysAppointments) {
	if (row.Id == appointmentId) {
		homeHasAppt = true;
	}
}

Boolean homeHasEnc = false;

for (Encounter__c row : home.lists.todaysEncounters) {
	if (row.Id == encounterId) {
		homeHasEnc = true;
	}
}

System.debug('VERIFY home todaysAppointments=' + home.metrics.todaysAppointments
             + ' homeHasAppt=' + homeHasAppt
             + ' homeHasEnc=' + homeHasEnc
             + ' openEncounters=' + home.metrics.openEncounters);