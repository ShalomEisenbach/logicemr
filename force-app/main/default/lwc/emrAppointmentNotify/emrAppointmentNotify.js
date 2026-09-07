import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getChannelAvailability from '@salesforce/apex/AppointmentCommunicationController.getChannelAvailability';
import sendConfirmation from '@salesforce/apex/AppointmentCommunicationController.sendConfirmation';
import sendReminder from '@salesforce/apex/AppointmentCommunicationController.sendReminder';

export default class EmrAppointmentNotify extends LightningElement {
    @api appointmentId;
    @api messageType = 'Confirmation';

    emailAvailable = false;
    smsAvailable = false;
    canSend = false;
    sendEmail = true;
    sendSms = false;
    emailRecipient;
    smsRecipient;
    errorMessage;
    isBusy = false;

    @wire(getChannelAvailability, { appointmentId: '$appointmentId' })
    wiredAvailability({ data, error }) {
        if (data) {
            this.emailAvailable = data.emailAvailable === true;
            this.smsAvailable = data.smsAvailable === true;
            this.canSend = data.canSend === true;
            this.emailRecipient = data.emailRecipient;
            this.smsRecipient = data.smsRecipient;
            this.sendEmail = this.emailAvailable;
            this.sendSms = this.smsAvailable && !this.emailAvailable;
            this.errorMessage = undefined;
            if (!this.canSend) {
                this.errorMessage = 'You do not have permission to send appointment notifications.';
            } else if (!this.emailAvailable && !this.smsAvailable) {
                this.errorMessage =
                    'No eligible channels. Add a patient email, or enable SMS with opt-in and Twilio config.';
            }
        } else if (error) {
            this.errorMessage = this.reduceError(error);
        }
    }

    get title() {
        return this.messageType === 'Reminder' ? 'Send reminder' : 'Send confirmation';
    }

    get emailLabel() {
        return this.emailRecipient ? `Email (${this.emailRecipient})` : 'Email';
    }

    get smsLabel() {
        return this.smsRecipient ? `SMS (${this.smsRecipient})` : 'SMS';
    }

    get isSendDisabled() {
        return this.isBusy || !this.canSend || (!this.sendEmail && !this.sendSms);
    }

    handleEmailChange(event) {
        this.sendEmail = event.target.checked === true;
    }

    handleSmsChange(event) {
        this.sendSms = event.target.checked === true;
    }

    async handleSend() {
        if (this.isSendDisabled || !this.appointmentId) {
            return;
        }
        const channels = [];
        if (this.sendEmail) {
            channels.push('Email');
        }
        if (this.sendSms) {
            channels.push('SMS');
        }
        this.isBusy = true;
        try {
            const sendFn = this.messageType === 'Reminder' ? sendReminder : sendConfirmation;
            const result = await sendFn({ appointmentId: this.appointmentId, channels });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: this.title,
                    message: result?.message || 'Notification sent.',
                    variant: result?.success === false ? 'warning' : 'success'
                })
            );
            this.dispatchEvent(
                new CustomEvent('sent', {
                    detail: { result, messageType: this.messageType }
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Send failed',
                    message: this.reduceError(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isBusy = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to send notification.';
    }
}
