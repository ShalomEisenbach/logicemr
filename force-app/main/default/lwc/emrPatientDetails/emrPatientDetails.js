import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import NAME_FIELD from '@salesforce/schema/Patient__c.Name';
import LAST_NAME_FIELD from '@salesforce/schema/Patient__c.Last_Name__c';
import FIRST_NAME_FIELD from '@salesforce/schema/Patient__c.First_Name__c';
import DATE_OF_BIRTH_FIELD from '@salesforce/schema/Patient__c.Date_of_Birth__c';
import MRN_FIELD from '@salesforce/schema/Patient__c.MRN__c';
import SEX_AT_BIRTH_FIELD from '@salesforce/schema/Patient__c.Sex_at_Birth__c';
import PHONE_FIELD from '@salesforce/schema/Patient__c.Phone__c';
import EMAIL_FIELD from '@salesforce/schema/Patient__c.Email__c';
import SMS_OPT_IN_FIELD from '@salesforce/schema/Patient__c.SMS_Opt_In__c';
import CONTACT_FIELD from '@salesforce/schema/Patient__c.Contact__c';
import STREET_FIELD from '@salesforce/schema/Patient__c.Street__c';
import CITY_FIELD from '@salesforce/schema/Patient__c.City__c';
import STATE_FIELD from '@salesforce/schema/Patient__c.State__c';
import POSTAL_CODE_FIELD from '@salesforce/schema/Patient__c.Postal_Code__c';
import COUNTRY_FIELD from '@salesforce/schema/Patient__c.Country__c';
import STATUS_FIELD from '@salesforce/schema/Patient__c.Status__c';
import FHIR_ID_FIELD from '@salesforce/schema/Patient__c.FHIR_Id__c';
import SOURCE_SYSTEM_ID_FIELD from '@salesforce/schema/Patient__c.Source_System_Id__c';

export default class EmrPatientDetails extends LightningElement {
    @api recordId;

    patientObject = PATIENT_OBJECT;
    nameField = NAME_FIELD;
    editableFields = [
        LAST_NAME_FIELD,
        FIRST_NAME_FIELD,
        DATE_OF_BIRTH_FIELD,
        MRN_FIELD,
        SEX_AT_BIRTH_FIELD,
        PHONE_FIELD,
        EMAIL_FIELD,
        SMS_OPT_IN_FIELD,
        CONTACT_FIELD,
        STREET_FIELD,
        CITY_FIELD,
        STATE_FIELD,
        POSTAL_CODE_FIELD,
        COUNTRY_FIELD,
        STATUS_FIELD,
        FHIR_ID_FIELD,
        SOURCE_SYSTEM_ID_FIELD
    ];

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
