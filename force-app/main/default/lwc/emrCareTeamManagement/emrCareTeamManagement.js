import { LightningElement, api } from 'lwc';
import getOrCreateCareTeam from '@salesforce/apex/CareTeamManagementController.getOrCreateCareTeam';
import addMember from '@salesforce/apex/CareTeamManagementController.addMember';
import deactivateMembers from '@salesforce/apex/CareTeamManagementController.deactivateMembers';
import removeMembers from '@salesforce/apex/CareTeamManagementController.removeMembers';
import CARE_TEAM_OBJECT from '@salesforce/schema/CareTeam__c';
import PRACTITIONER_OBJECT from '@salesforce/schema/Practitioner__c';

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
    showAddForm = false;
    practitionerId;
    role = 'Attending';
    accessLevel = 'Read';

    roleOptions = [
        { label: 'Attending', value: 'Attending' },
        { label: 'Consulting', value: 'Consulting' },
        { label: 'Nurse', value: 'Nurse' },
        { label: 'Care Coordinator', value: 'Care Coordinator' },
        { label: 'Other', value: 'Other' }
    ];

    accessLevelOptions = [
        { label: 'Read', value: 'Read' },
        { label: 'Edit', value: 'Edit' }
    ];

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

    get careTeamObjectApiName() {
        return CARE_TEAM_OBJECT.objectApiName;
    }

    get practitionerObjectApiName() {
        return PRACTITIONER_OBJECT.objectApiName;
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

    get memberCards() {
        return (this.members || []).map((row) => {
            const active = !!row.active;
            return {
                id: row.id,
                practitionerId: row.practitionerId,
                title: row.practitionerName || 'Member',
                role: row.role || 'Role not set',
                accessLabel: row.accessLevel ? `${row.accessLevel} access` : 'Access not set',
                statusLabel: active ? 'Active' : 'Inactive',
                statusClass: active ? 'tile-status tile-status_active' : 'tile-status tile-status_inactive',
                canDeactivate: active,
                objectApiName: PRACTITIONER_OBJECT.objectApiName
            };
        });
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

    handleToggleAdd() {
        this.showAddForm = true;
        this.errorMessage = undefined;
        this.resetAddForm();
    }

    handleCloseAdd() {
        this.showAddForm = false;
        this.errorMessage = undefined;
        this.resetAddForm();
    }

    resetAddForm() {
        this.practitionerId = undefined;
        this.role = 'Attending';
        this.accessLevel = 'Read';
    }

    handlePractitionerChange(event) {
        this.practitionerId = event.detail.recordId;
        this.errorMessage = undefined;
    }

    handleRoleChange(event) {
        this.role = event.detail.value;
    }

    handleAccessLevelChange(event) {
        this.accessLevel = event.detail.value;
    }

    handleAddClick() {
        if (!this.practitionerId) {
            this.errorMessage = 'Select a practitioner.';
            return;
        }
        this.saveMember(this.practitionerId, this.role, this.accessLevel);
    }

    async saveMember(practitionerId, role, accessLevel) {
        if (!practitionerId || this.isSaving) {
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            await addMember({
                careTeamId: this.careTeamId,
                practitionerId,
                role,
                accessLevel
            });
            this.showAddForm = false;
            this.resetAddForm();
            await this.loadCareTeam();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    handleMemberCardAction(event) {
        this.handleRowAction({
            detail: {
                action: { name: event.currentTarget.dataset.action },
                row: { id: event.currentTarget.dataset.id }
            }
        });
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
