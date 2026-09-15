import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';

export default class EmrPatientDetails extends LightningElement {
    @api recordId;

    patientObject = PATIENT_OBJECT;

    handleSuccess() {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Patient updated',
                message: 'Patient details were saved.',
                variant: 'success'
            })
        );
    }
}
