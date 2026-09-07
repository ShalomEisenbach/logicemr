import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDocumentContext from '@salesforce/apex/ClinicalDocumentController.getDocumentContext';
import getDocumentUrl from '@salesforce/apex/ClinicalDocumentController.getDocumentUrl';
import sendDocument from '@salesforce/apex/ClinicalDocumentController.sendDocument';

const DOC_CHART = 'ChartSummary';
const DOC_RX = 'Prescription';

export default class EmrDocumentShare extends LightningElement {
    @api patientId;
    @api docType = DOC_CHART;
    @api recordIds = [];
    @api showPrint = false;
    @api showEmail = false;
    @api printLabel = 'Print';
    @api emailLabel = 'Email';
    @api compact = false;

    showEmailModal = false;
    toAddress = '';
    subject = '';
    message = '';
    errorMessage;
    isBusy = false;
    patientName = 'Patient';
    defaultEmail = '';
    _overrideRecordIds;

    @wire(getDocumentContext, { patientId: '$patientId' })
    wiredContext({ data, error }) {
        if (data) {
            this.defaultEmail = data.defaultEmail || '';
            this.patientName = data.patientName || 'Patient';
            if (!this.showEmailModal) {
                this.toAddress = this.defaultEmail;
                this.subject = this.defaultSubject;
            }
        } else if (error) {
            this.errorMessage = this.reduceError(error);
        }
    }

    get resolvedRecordIds() {
        return Array.isArray(this.recordIds) ? this.recordIds.filter((id) => !!id) : [];
    }

    get isPrescription() {
        return (this.docType || '').trim() === DOC_RX;
    }

    get defaultSubject() {
        const name = this.patientName || 'Patient';
        return this.isPrescription ? `Prescription — ${name}` : `Medical record — ${name}`;
    }

    get emailModalTitle() {
        return this.isPrescription ? 'Email prescription' : 'Email chart summary';
    }

    get canSend() {
        return !this.isBusy && !!(this.toAddress || '').trim();
    }

    get isSendDisabled() {
        return !this.canSend;
    }

    @api
    openEmail(recordIdsOverride) {
        if (Array.isArray(recordIdsOverride)) {
            this._overrideRecordIds = recordIdsOverride;
        } else {
            this._overrideRecordIds = undefined;
        }
        if (this.isPrescription && this.activeRecordIds.length === 0) {
            this.errorMessage = 'Select at least one prescription to email.';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Email prescription',
                    message: this.errorMessage,
                    variant: 'error'
                })
            );
            return;
        }
        this.toAddress = this.defaultEmail || '';
        this.subject = this.defaultSubject;
        this.message = '';
        this.errorMessage = undefined;
        this.showEmailModal = true;
    }

    @api
    async print(recordIdsOverride) {
        if (Array.isArray(recordIdsOverride)) {
            this._overrideRecordIds = recordIdsOverride;
        } else {
            this._overrideRecordIds = undefined;
        }
        await this.handlePrint();
    }

    get activeRecordIds() {
        if (Array.isArray(this._overrideRecordIds)) {
            return this._overrideRecordIds.filter((id) => !!id);
        }
        return this.resolvedRecordIds;
    }

    async handlePrint() {
        if (this.isBusy) {
            return;
        }
        if (this.isPrescription && this.activeRecordIds.length === 0) {
            this.errorMessage = 'Select at least one prescription to print.';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Print prescription',
                    message: this.errorMessage,
                    variant: 'error'
                })
            );
            return;
        }
        this.isBusy = true;
        this.errorMessage = undefined;
        try {
            const url = await getDocumentUrl({
                patientId: this.patientId,
                docType: this.docType,
                recordIds: this.activeRecordIds
            });
            window.open(url, '_blank');
        } catch (error) {
            this.errorMessage = this.reduceError(error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to open document',
                    message: this.errorMessage,
                    variant: 'error'
                })
            );
        } finally {
            this.isBusy = false;
            this._overrideRecordIds = undefined;
        }
    }

    handleOpenEmail() {
        this.openEmail();
    }

    handleCloseEmail() {
        this.showEmailModal = false;
        this.errorMessage = undefined;
        this._overrideRecordIds = undefined;
    }

    handleToChange(event) {
        this.toAddress = event.detail.value;
    }

    handleSubjectChange(event) {
        this.subject = event.detail.value;
    }

    handleMessageChange(event) {
        this.message = event.detail.value;
    }

    async handleSend() {
        if (!this.canSend) {
            this.errorMessage = 'A recipient email address is required.';
            return;
        }
        this.isBusy = true;
        this.errorMessage = undefined;
        try {
            const result = await sendDocument({
                patientId: this.patientId,
                docType: this.docType,
                recordIds: this.activeRecordIds,
                toAddress: this.toAddress,
                subject: this.subject,
                message: this.message
            });
            if (!result?.success) {
                this.errorMessage = result?.message || 'Unable to send email.';
                return;
            }
            this.showEmailModal = false;
            this._overrideRecordIds = undefined;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Email sent',
                    message: result.message || 'Document emailed successfully.',
                    variant: 'success'
                })
            );
            this.dispatchEvent(new CustomEvent('sent'));
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isBusy = false;
        }
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to share document.';
    }
}
