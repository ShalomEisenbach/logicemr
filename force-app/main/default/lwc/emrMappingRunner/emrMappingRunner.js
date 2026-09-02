import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getActiveMappings from '@salesforce/apex/MappingRunnerController.getActiveMappings';
import previewMapping from '@salesforce/apex/MappingRunnerController.previewMapping';
import runMapping from '@salesforce/apex/MappingRunnerController.runMapping';
import startBackfill from '@salesforce/apex/MappingRunnerController.startBackfill';

export default class EmrMappingRunner extends LightningElement {
    _mappingId;

    mappings = [];
    selectedMappingId = '';
    previewRecordId = '';
    runIdsText = '';
    previewResult;
    runSummary;
    backfillJobId;
    showBackfillConfirm = false;
    isLoading = false;
    isPreviewing = false;
    isRunning = false;
    isBackfilling = false;
    errorMessage;

    @api
    get mappingId() {
        return this._mappingId;
    }
    set mappingId(value) {
        this._mappingId = value;
        if (value) {
            this.selectedMappingId = value;
        }
    }

    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        const stateId = pageRef?.state?.c__mappingId || pageRef?.state?.c__recordId;
        if (stateId) {
            this._mappingId = stateId;
            this.selectedMappingId = stateId;
        }
    }

    connectedCallback() {
        this.loadMappings();
    }

    get mappingOptions() {
        return this.mappings.map((mapping) => ({
            label: `${mapping.name} (${mapping.sourceObject})`,
            value: mapping.id
        }));
    }

    get selectedMapping() {
        return this.mappings.find((mapping) => mapping.id === this.selectedMappingId);
    }

    get sourceObjectApiName() {
        return this.selectedMapping?.sourceObject || '';
    }

    get hasSourceObject() {
        return !!this.sourceObjectApiName;
    }

    get hasPreviewRows() {
        return this.previewResult?.rows && this.previewResult.rows.length > 0;
    }

    get previewErrors() {
        return this.previewResult?.summary?.errors || [];
    }

    get hasPreviewErrors() {
        return this.previewErrors.length > 0;
    }

    get previewOutcome() {
        if (!this.previewResult?.summary) {
            return '';
        }
        if (this.previewResult.summary.updated > 0) {
            return 'Would update an existing Patient.';
        }
        if (this.previewResult.summary.created > 0) {
            return 'Would create a Patient.';
        }
        return 'No Patient would be written.';
    }

    get runErrors() {
        return this.runSummary?.errors || [];
    }

    get hasRunSummary() {
        return !!this.runSummary;
    }

    get hasRunErrors() {
        return this.runErrors.length > 0;
    }

    get parsedRunIds() {
        return this.parseIds(this.runIdsText);
    }

    get isPreviewDisabled() {
        return this.isBusy || !this.selectedMappingId || !this.previewRecordId;
    }

    get isRunDisabled() {
        return this.isBusy || !this.selectedMappingId || this.parsedRunIds.length === 0;
    }

    get isBackfillDisabled() {
        return this.isBusy || !this.selectedMappingId;
    }

    get isBusy() {
        return this.isLoading || this.isPreviewing || this.isRunning || this.isBackfilling;
    }

    async loadMappings() {
        this.isLoading = true;
        try {
            this.mappings = (await getActiveMappings()) || [];
            if (this._mappingId) {
                this.selectedMappingId = this._mappingId;
            }
            this.errorMessage = undefined;
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleMappingChange(event) {
        this.selectedMappingId = event.detail.value;
        this.previewRecordId = '';
        this.runIdsText = '';
        this.previewResult = undefined;
        this.runSummary = undefined;
        this.backfillJobId = undefined;
        this.showBackfillConfirm = false;
        this.errorMessage = undefined;
    }

    handlePreviewIdChange(event) {
        this.previewRecordId = (event.detail.value || '').trim();
    }

    handlePreviewRecordPick(event) {
        const recordId = event.detail.recordId;
        if (recordId) {
            this.previewRecordId = recordId;
        }
    }

    handleRunIdsChange(event) {
        this.runIdsText = event.detail.value || '';
    }

    handleRunRecordPick(event) {
        const recordId = event.detail.recordId;
        if (!recordId) {
            return;
        }
        const ids = this.parseIds(this.runIdsText);
        if (!ids.includes(recordId)) {
            ids.push(recordId);
            this.runIdsText = ids.join('\n');
        }
    }

    async handlePreview() {
        if (this.isPreviewDisabled) {
            return;
        }
        this.isPreviewing = true;
        this.errorMessage = undefined;
        try {
            this.previewResult = await previewMapping({
                mappingDefinitionId: this.selectedMappingId,
                sourceRecordId: this.previewRecordId
            });
        } catch (error) {
            this.previewResult = undefined;
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isPreviewing = false;
        }
    }

    async handleRun() {
        if (this.isRunDisabled) {
            return;
        }
        this.isRunning = true;
        this.errorMessage = undefined;
        try {
            this.runSummary = await runMapping({
                mappingDefinitionId: this.selectedMappingId,
                sourceRecordIds: this.parsedRunIds
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Mapping run complete',
                    message: this.formatSummary(this.runSummary),
                    variant: this.runSummary.errors?.length ? 'warning' : 'success'
                })
            );
        } catch (error) {
            this.runSummary = undefined;
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isRunning = false;
        }
    }

    handleBackfillClick() {
        if (this.isBackfillDisabled) {
            return;
        }
        this.showBackfillConfirm = true;
        this.backfillJobId = undefined;
        this.errorMessage = undefined;
    }

    handleBackfillCancel() {
        this.showBackfillConfirm = false;
    }

    async handleBackfillConfirm() {
        if (this.isBackfillDisabled) {
            return;
        }
        this.isBackfilling = true;
        this.errorMessage = undefined;
        try {
            this.backfillJobId = await startBackfill({
                mappingDefinitionId: this.selectedMappingId
            });
            this.showBackfillConfirm = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Backfill queued',
                    message: 'Async Apex job ' + this.backfillJobId,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.backfillJobId = undefined;
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isBackfilling = false;
        }
    }

    parseIds(text) {
        if (!text) {
            return [];
        }
        const seen = new Set();
        const ids = [];
        text.split(/[\s,;]+/).forEach((part) => {
            const value = part.trim();
            if (value && !seen.has(value)) {
                seen.add(value);
                ids.push(value);
            }
        });
        return ids;
    }

    formatSummary(summary) {
        return (
            'Created ' +
            (summary.created || 0) +
            ', updated ' +
            (summary.updated || 0) +
            ', skipped ' +
            (summary.skipped || 0) +
            ', errors ' +
            (summary.errors ? summary.errors.length : 0)
        );
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to run the mapping.';
    }
}
