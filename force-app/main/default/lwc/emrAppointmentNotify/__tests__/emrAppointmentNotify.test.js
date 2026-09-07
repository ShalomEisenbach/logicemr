import { createElement } from 'lwc';
import EmrAppointmentNotify from 'c/emrAppointmentNotify';
import getChannelAvailability from '@salesforce/apex/AppointmentCommunicationController.getChannelAvailability';
import sendConfirmation from '@salesforce/apex/AppointmentCommunicationController.sendConfirmation';

jest.mock(
    '@salesforce/apex/AppointmentCommunicationController.getChannelAvailability',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return {
            default: createApexTestWireAdapter(jest.fn())
        };
    },
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/AppointmentCommunicationController.sendConfirmation',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/AppointmentCommunicationController.sendReminder',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

describe('c-emr-appointment-notify', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders channel checkboxes from availability and sends confirmation', async () => {
        sendConfirmation.mockResolvedValue({
            success: true,
            message: 'Sent 1, skipped 0, failed 0.',
            sentCount: 1,
            skippedCount: 0,
            failedCount: 0
        });

        const element = createElement('c-emr-appointment-notify', { is: EmrAppointmentNotify });
        element.appointmentId = 'a0A000000000001';
        element.messageType = 'Confirmation';
        document.body.appendChild(element);

        getChannelAvailability.emit({
            emailAvailable: true,
            smsAvailable: true,
            canSend: true,
            emailRecipient: 'a@example.com',
            smsRecipient: '555-0100'
        });
        await Promise.resolve();

        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        expect(inputs.length).toBe(2);

        const sendButton = [...element.shadowRoot.querySelectorAll('lightning-button')].find(
            (btn) => btn.label === 'Send'
        );
        expect(sendButton).toBeTruthy();
        sendButton.click();
        await Promise.resolve();
        await Promise.resolve();

        expect(sendConfirmation).toHaveBeenCalled();
    });
});
