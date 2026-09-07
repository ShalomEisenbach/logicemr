import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import { RefreshEvent } from 'lightning/refresh';
import getAppointments from '@salesforce/apex/AppointmentPanelController.getAppointments';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import APPOINTMENT_OBJECT from '@salesforce/schema/Appointment__c';
import PRACTITIONER_OBJECT from '@salesforce/schema/Practitioner__c';
import STATUS_FIELD from '@salesforce/schema/Appointment__c.Status__c';
import TYPE_FIELD from '@salesforce/schema/Appointment__c.Appointment_Type__c';
import START_FIELD from '@salesforce/schema/Appointment__c.Start__c';
import LOCATION_FIELD from '@salesforce/schema/Appointment__c.Location_Name__c';
import REASON_FIELD from '@salesforce/schema/Appointment__c.Reason__c';
import PRACTITIONER_FIELD from '@salesforce/schema/Appointment__c.Practitioner__c';
import PRAC_FIRST_NAME_FIELD from '@salesforce/schema/Practitioner__c.First_Name__c';
import PRAC_LAST_NAME_FIELD from '@salesforce/schema/Practitioner__c.Last_Name__c';
import { urlColumn, withRecordUrls, recordViewPageRef } from 'c/emrNavigationUtils';

const OPEN_APPOINTMENT = 'open';
const SEND_CONFIRMATION = 'send_confirmation';
const SEND_REMINDER = 'send_reminder';
const PRINT_APPOINTMENT = 'print';

export default class EmrAppointmentPanel extends NavigationMixin(LightningElement) {
    @api recordId;

    appointments;
    errorMessage;
    showScheduleForm = false;
    scheduleStarted = false;
    wiredAppointmentsResult;
    showNotifyModal = false;
    notifyAppointmentId;
    notifyMessageType = 'Confirmation';
    showPrintModal = false;
    printAppointmentId;

    get columns() {
        return [
            { label: 'Status', fieldName: STATUS_FIELD.fieldApiName },
            { label: 'Type', fieldName: TYPE_FIELD.fieldApiName },
            urlColumn('Start', 'recordUrl', 'startLabel'),
            urlColumn('Provider', 'providerUrl', 'providerName'),
            { label: 'Location', fieldName: LOCATION_FIELD.fieldApiName },
            { label: 'Reason', fieldName: REASON_FIELD.fieldApiName },
            {
                type: 'action',
                typeAttributes: {
                    rowActions: [
                        { label: 'Open', name: OPEN_APPOINTMENT },
                        { label: 'Send Confirmation', name: SEND_CONFIRMATION },
                        { label: 'Send Reminder', name: SEND_REMINDER },
                        { label: 'Print', name: PRINT_APPOINTMENT }
                    ]
                }
            }
        ];
    }

    @wire(getAppointments, { patientId: '$recordId' })
    wiredAppointments(result) {
        this.wiredAppointmentsResult = result;
        const { data, error } = result;
        if (data) {
            this.applyAppointments(data);
            this.errorMessage = undefined;
        } else if (error) {
            this.appointments = [];
            this.errorMessage = this.reduceError(error);
        }
    }

    renderedCallback() {
        if (!this.showScheduleForm || this.scheduleStarted) {
            return;
        }
        const booking = this.template.querySelector('c-emr-appointment-booking');
        if (booking?.beginForPatient) {
            booking.beginForPatient(this.recordId);
            this.scheduleStarted = true;
        }
    }

    async applyAppointments(data) {
        const withNames = data.map((row) => {
            const start = row[START_FIELD.fieldApiName];
            return {
                ...row,
                providerName: this.formatProvider(row),
                providerId: row[PRACTITIONER_FIELD.fieldApiName],
                startLabel: start ? this.formatStartLabel(start) : 'Appointment'
            };
        });
        const withAppointmentUrls = await withRecordUrls(
            this,
            withNames,
            APPOINTMENT_OBJECT.objectApiName,
            { labelField: 'startLabel', labelOutField: 'startLabel' }
        );
        this.appointments = await Promise.all(
            withAppointmentUrls.map(async (row) => {
                let providerUrl = '';
                if (row.providerId) {
                    try {
                        providerUrl = await this[NavigationMixin.GenerateUrl](
                            recordViewPageRef(row.providerId, PRACTITIONER_OBJECT.objectApiName)
                        );
                    } catch (e) {
                        providerUrl = '';
                    }
                }
                return { ...row, providerUrl };
            })
        );
    }

    formatStartLabel(value) {
        try {
            const date = new Date(value);
            if (Number.isNaN(date.getTime())) {
                return String(value);
            }
            return date.toLocaleString(undefined, {
                year: 'numeric',
                month: 'short',
                day: '2-digit',
                hour: '2-digit',
                minute: '2-digit'
            });
        } catch (e) {
            return String(value);
        }
    }

    get hasAppointments() {
        return this.appointments && this.appointments.length > 0;
    }

    get showEmpty() {
        return this.appointments && this.appointments.length === 0 && !this.errorMessage;
    }

    get appointmentCards() {
        return (this.appointments || []).map((row) => {
            const parts = [
                row[STATUS_FIELD.fieldApiName],
                row[TYPE_FIELD.fieldApiName],
                row.providerName,
                row[LOCATION_FIELD.fieldApiName]
            ].filter((part) => part);
            return {
                id: row.Id,
                title: row.startLabel || 'Appointment',
                meta: parts.join(' · '),
                objectApiName: APPOINTMENT_OBJECT.objectApiName
            };
        });
    }

    get notifyModalTitle() {
        return this.notifyMessageType === 'Reminder' ? 'Send reminder' : 'Send confirmation';
    }

    handleSchedule() {
        this.showScheduleForm = true;
        this.scheduleStarted = false;
        this.errorMessage = undefined;
    }

    handleCloseSchedule() {
        this.showScheduleForm = false;
        this.scheduleStarted = false;
        this.errorMessage = undefined;
    }

    async handleBooked() {
        this.handleCloseSchedule();
        if (this.wiredAppointmentsResult) {
            await refreshApex(this.wiredAppointmentsResult);
        }
        this.dispatchEvent(new RefreshEvent());
    }

    handleViewAll() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordRelationshipPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: PATIENT_OBJECT.objectApiName,
                relationshipApiName: this.appointmentsRelationshipApiName,
                actionName: 'view'
            }
        });
    }

    handleOpenCard(event) {
        this.handleRowAction({
            detail: {
                action: { name: OPEN_APPOINTMENT },
                row: { Id: event.currentTarget.dataset.id }
            }
        });
    }

    handleNotifyCard(event) {
        this.notifyAppointmentId = event.currentTarget.dataset.id;
        this.notifyMessageType = event.currentTarget.dataset.type || 'Confirmation';
        this.showNotifyModal = true;
    }

    handlePrintCard(event) {
        this.printAppointmentId = event.currentTarget.dataset.id;
        this.showPrintModal = true;
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const rowId = event.detail.row.Id;
        if (actionName === SEND_CONFIRMATION) {
            this.notifyAppointmentId = rowId;
            this.notifyMessageType = 'Confirmation';
            this.showNotifyModal = true;
            return;
        }
        if (actionName === SEND_REMINDER) {
            this.notifyAppointmentId = rowId;
            this.notifyMessageType = 'Reminder';
            this.showNotifyModal = true;
            return;
        }
        if (actionName === PRINT_APPOINTMENT) {
            this.printAppointmentId = rowId;
            this.showPrintModal = true;
            return;
        }
        if (actionName !== OPEN_APPOINTMENT) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: rowId,
                objectApiName: APPOINTMENT_OBJECT.objectApiName,
                actionName: 'view'
            }
        });
    }

    handleCloseNotify() {
        this.showNotifyModal = false;
        this.notifyAppointmentId = undefined;
    }

    handleNotifySent() {
        this.handleCloseNotify();
    }

    handleClosePrint() {
        this.showPrintModal = false;
        this.printAppointmentId = undefined;
    }

    get appointmentsRelationshipApiName() {
        const objectApiName = PATIENT_OBJECT.objectApiName;
        const parts = objectApiName.split('__');
        return parts.length === 3 ? `${parts[0]}__Appointments__r` : 'Appointments__r';
    }

    formatProvider(row) {
        const relationshipName = PRACTITIONER_FIELD.fieldApiName.replace(/__c$/, '__r');
        const practitioner = row[relationshipName];
        if (!practitioner) {
            return '';
        }
        const first = practitioner[PRAC_FIRST_NAME_FIELD.fieldApiName] || '';
        const last = practitioner[PRAC_LAST_NAME_FIELD.fieldApiName] || '';
        return `${first} ${last}`.trim();
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to load appointments.';
    }
}
