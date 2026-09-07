import { createElement } from 'lwc';
import EmrAppointmentPrint from 'c/emrAppointmentPrint';
import getPrintPayload from '@salesforce/apex/AppointmentCommunicationController.getPrintPayload';
import logPrint from '@salesforce/apex/AppointmentCommunicationController.logPrint';

jest.mock(
    '@salesforce/apex/AppointmentCommunicationController.getPrintPayload',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return {
            default: createApexTestWireAdapter(jest.fn())
        };
    },
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/AppointmentCommunicationController.logPrint',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

describe('c-emr-appointment-print', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders slip fields and logs print', async () => {
        logPrint.mockResolvedValue({ success: true, sentCount: 1, message: 'Print logged.' });
        const printSpy = jest.spyOn(window, 'print').mockImplementation(() => {});

        const element = createElement('c-emr-appointment-print', { is: EmrAppointmentPrint });
        element.appointmentId = 'a0A000000000001';
        document.body.appendChild(element);

        getPrintPayload.emit({
            appointmentId: 'a0A000000000001',
            patientId: 'a0B000000000001',
            patientName: 'Chen, Maya',
            mrn: 'MRN-1',
            startTime: '2026-09-10T15:00:00.000Z',
            endTime: '2026-09-10T15:30:00.000Z',
            practitionerName: 'Ada Lopez',
            locationName: 'Clinic A',
            appointmentType: 'Checkup',
            reason: 'Annual',
            status: 'Booked'
        });
        await Promise.resolve();

        const slip = element.shadowRoot.querySelector('.slip');
        expect(slip).not.toBeNull();
        expect(element.shadowRoot.textContent).toContain('Chen, Maya');

        const printButton = element.shadowRoot.querySelector('lightning-button');
        printButton.click();
        await Promise.resolve();
        await Promise.resolve();

        expect(logPrint).toHaveBeenCalledWith({ appointmentId: 'a0A000000000001' });
        expect(printSpy).toHaveBeenCalled();
        printSpy.mockRestore();
    });
});
