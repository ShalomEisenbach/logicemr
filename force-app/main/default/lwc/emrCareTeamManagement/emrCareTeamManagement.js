import { LightningElement, api } from 'lwc';
import getOrCreateCareTeam from '@salesforce/apex/CareTeamManagementController.getOrCreateCareTeam';
import addMember from '@salesforce/apex/CareTeamManagementController.addMember';
import deactivateMembers from '@salesforce/apex/CareTeamManagementController.deactivateMembers';
import removeMembers from '@salesforce/apex/CareTeamManagementController.removeMembers';
import MEMBER_OBJECT from '@salesforce/schema/CareTeamMember__c';
import PRACTITIONER_FIELD from '@salesforce/schema/CareTeamMember__c.Practitioner__c';
import ROLE_FIELD from '@salesforce/schema/CareTeamMember__c.Role__c';
import ACCESS_LEVEL_FIELD from '@salesforce/schema/CareTeamMember__c.Access_Level__c';

const DEACTIVATE = 'deactivate';
const REMOVE = 'remove';

export default class EmrCareTeamManagement extends LightningElement {
    _recordId;
    careTeamId;
    careTeamName;
    careTeamStatus;
    members;
    errorMessage;
    isLoading = false;
    isSaving = false;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.loadCareTeam();
        }
    }

    get memberObjectApiName() {
        return MEMBER_OBJECT.objectApiName;
    }

    get practitionerFieldApiName() {
        return PRACTITIONER_FIELD.fieldApiName;
    }

    get roleFieldApiName() {
        return ROLE_FIELD.fieldApiName;
    }

    get accessLevelFieldApiName() {
        return ACCESS_LEVEL_FIELD.fieldApiName;
    }

    get hasMembers() {
        return this.members && this.members.length > 0;
    }

    get showEmpty() {
        return this.members && this.members.length === 0 && !this.errorMessage;
    }

    get teamLabel() {
        if (!this.careTeamName) {
            return '';
        }
        return this.careTeamStatus
            ? `${this.careTeamName} · ${this.careTeamStatus}`
            : this.careTeamName;
    }

    get showForm() {
        return !!this.careTeamId && !this.isLoading;
    }

    get columns() {
        return [
            { label: 'Practitioner', fieldName: 'practitionerName' },
            { label: 'Role', fieldName: 'role' },
            { label: 'Access Level', fieldName: 'accessLevel' },
            { label: 'Active', fieldName: 'active', type: 'boolean' },
            {
                type: 'action',
                typeAttributes: {
                    rowActions: this.getRowActions.bind(this)
                }
            }
        ];
    }

    getRowActions(row, doneCallback) {
        doneCallback(this.actionsFor(row));
    }

    async loadCareTeam() {
        if (!this._recordId) {
            return;
        }
        this.isLoading = true;
        try {
            const view = await getOrCreateCareTeam({ patientId: this._recordId });
            this.applyView(view);
            this.errorMessage = undefined;
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    applyView(view) {
        this.careTeamId = view.careTeamId;
        this.careTeamName = view.name;
        this.careTeamStatus = view.status;
        this.members = view.members || [];
    }

    actionsFor(row) {
        const actions = [];
        if (row.active) {
            actions.push({ label: 'Deactivate', name: DEACTIVATE });
        }
        actions.push({ label: 'Remove', name: REMOVE });
        return actions;
    }

    handleAddSubmit(event) {
        event.preventDefault();
        const fields = event.detail.fields;
        this.saveMember(
            fields[PRACTITIONER_FIELD.fieldApiName],
            fields[ROLE_FIELD.fieldApiName],
            fields[ACCESS_LEVEL_FIELD.fieldApiName]
        );
    }

    async saveMember(practitionerId, role, accessLevel) {
        if (!practitionerId || this.isSaving) {
            return;
        }
        this.isSaving = true;
        try {
            await addMember({
                careTeamId: this.careTeamId,
                practitionerId,
                role,
                accessLevel
            });
            await this.loadCareTeam();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    async handleRowAction(event) {
        const memberId = event.detail.row.id;
        const actionName = event.detail.action.name;
        this.isSaving = true;
        try {
            if (actionName === DEACTIVATE) {
                await deactivateMembers({ memberIds: [memberId] });
            } else if (actionName === REMOVE) {
                await removeMembers({ memberIds: [memberId] });
            }
            await this.loadCareTeam();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to update the care team.';
    }
}
