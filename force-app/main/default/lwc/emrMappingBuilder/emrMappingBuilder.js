import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import PATIENT_OBJECT from '@salesforce/schema/Patient__c';
import getSourceObjectOptions from '@salesforce/apex/MappingBuilderController.getSourceObjectOptions';
import getFields from '@salesforce/apex/MappingBuilderController.getFields';
import getMapping from '@salesforce/apex/MappingBuilderController.getMapping';
import saveMapping from '@salesforce/apex/MappingBuilderController.saveMapping';

const STEP_SOURCE = 'source';
const STEP_FIELDS = 'fields';
const STEP_MATCH = 'match';
const TX_DIRECT = 'Direct';
const TX_DEFAULT = 'Default Value';
const TX_DATE = 'Date Format';
const TX_PICKLIST = 'Picklist Value Map';
const TX_CONCAT = 'Concatenate';
const DEFAULT_MATCH_SUFFIX = 'Source_System_Id__c';

export default class EmrMappingBuilder extends LightningElement {
    _recordId;
    _mappingId;

    currentStep = STEP_SOURCE;
    mappingName = '';
    description = '';
    sourceObject = '';
    matchTargetField = '';
    active = true;

    sourceObjects = [];
    sourceFields = [];
    targetFields = [];
    rows = [];

    isLoading = false;
    isSaving = false;
    showValidation = false;
    errorMessage;
    loadedMappingId;
    nextRowKey = 1;
    nextValueMapKey = 1;

    transformationOptions = [
        { label: 'Direct', value: TX_DIRECT },
        { label: 'Default Value', value: TX_DEFAULT },
        { label: 'Trim', value: 'Trim' },
        { label: 'Uppercase', value: 'Uppercase' },
        { label: 'Lowercase', value: 'Lowercase' },
        { label: 'Date Format', value: TX_DATE },
        { label: 'Picklist Value Map', value: TX_PICKLIST },
        { label: 'Concatenate', value: TX_CONCAT }
    ];

    get targetObjectDisplay() {
        return `Patient (${PATIENT_OBJECT.objectApiName})`;
    }

    get sourceObjectOptions() {
        return this.sourceObjects.map((item) => ({
            label: `${item.label} (${item.apiName})`,
            value: item.apiName
        }));
    }

    get sourceFieldOptions() {
        return this.toFieldOptions(this.sourceFields);
    }

    get targetFieldOptions() {
        return this.toFieldOptions(this.targetFields);
    }

    get isStepSource() {
        return this.currentStep === STEP_SOURCE;
    }

    get isStepFields() {
        return this.currentStep === STEP_FIELDS;
    }

    get isStepMatch() {
        return this.currentStep === STEP_MATCH;
    }

    get showBack() {
        return !this.isStepSource;
    }

    get showNext() {
        return !this.isStepMatch;
    }

    get isNextDisabled() {
        return this.isLoading || this.isSaving;
    }

    get isSaveDisabled() {
        return this.isLoading || this.isSaving || !this.isFormValid();
    }

    get displayRows() {
        return this.rows.map((row) => this.decorateRow(row));
    }

    get nameError() {
        return this.showValidation && !this.mappingName ? 'Mapping name is required.' : '';
    }

    get sourceObjectError() {
        return this.showValidation && !this.sourceObject ? 'Source object is required.' : '';
    }

    get matchFieldError() {
        return this.isStepMatch && !this.matchTargetField ? 'Match target field is required.' : '';
    }

    get rowsError() {
        return this.showValidation && this.rows.length === 0 ? 'Add at least one field mapping.' : '';
    }

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.loadExistingMapping(value);
        }
    }

    @api
    get mappingId() {
        return this._mappingId;
    }
    set mappingId(value) {
        this._mappingId = value;
        if (value) {
            this.loadExistingMapping(value);
        }
    }

    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        const stateId = pageRef?.state?.c__mappingId || pageRef?.state?.c__recordId;
        if (stateId) {
            this.loadExistingMapping(stateId);
        }
    }

    connectedCallback() {
        this.initialize();
    }

    async initialize() {
        this.isLoading = true;
        try {
            if (this.rows.length === 0) {
                this.rows = [this.newRow()];
            }
            await Promise.all([this.loadSourceObjects(), this.loadTargetFields()]);
            this.applyDefaultMatchField();
            const existingId = this._recordId || this._mappingId;
            if (existingId) {
                await this.loadExistingMapping(existingId, false);
            }
            this.errorMessage = undefined;
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async loadSourceObjects() {
        this.sourceObjects = (await getSourceObjectOptions()) || [];
    }

    async loadTargetFields() {
        this.targetFields = (await getFields({ objectApiName: PATIENT_OBJECT.objectApiName })) || [];
        this.applyDefaultMatchField();
    }

    async loadSourceFields(objectApiName) {
        if (!objectApiName) {
            this.sourceFields = [];
            return;
        }
        this.sourceFields = (await getFields({ objectApiName })) || [];
    }

    async loadExistingMapping(mappingId, manageSpinner = true) {
        if (!mappingId || mappingId === this.loadedMappingId) {
            return;
        }
        this.loadedMappingId = mappingId;
        if (manageSpinner) {
            this.isLoading = true;
        }
        try {
            const payload = await getMapping({ mappingId });
            this.applyPayload(payload);
            await this.loadSourceFields(this.sourceObject);
            this.errorMessage = undefined;
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            if (manageSpinner) {
                this.isLoading = false;
            }
        }
    }

    applyPayload(payload) {
        const definition = payload.definition || {};
        this._recordId = definition.id;
        this.mappingName = definition.name || '';
        this.description = definition.description || '';
        this.sourceObject = definition.sourceObject || '';
        this.matchTargetField = definition.matchTargetField || '';
        this.active = definition.active !== false;
        this.rows =
            payload.rows && payload.rows.length > 0
                ? payload.rows.map((row) => this.rowFromPayload(row))
                : [this.newRow()];
        this.applyDefaultMatchField();
    }

    rowFromPayload(row) {
        const sourceFields = this.splitSourceFields(row.sourceField);
        return {
            key: `row-${this.nextRowKey++}`,
            id: row.id,
            sourceField: row.sourceField || '',
            sourceFields,
            targetField: row.targetField || '',
            transformationType: row.transformationType || TX_DIRECT,
            defaultValue: row.defaultValue || '',
            formatPattern: row.formatPattern || '',
            concatSeparator: row.concatSeparator || '',
            valueMaps:
                row.valueMaps && row.valueMaps.length > 0
                    ? row.valueMaps.map((valueMap) => this.valueMapFromPayload(valueMap))
                    : []
        };
    }

    valueMapFromPayload(valueMap) {
        return {
            key: `vm-${this.nextValueMapKey++}`,
            id: valueMap.id,
            sourceValue: valueMap.sourceValue || '',
            targetValue: valueMap.targetValue || ''
        };
    }

    newRow() {
        return {
            key: `row-${this.nextRowKey++}`,
            id: null,
            sourceField: '',
            sourceFields: [],
            targetField: '',
            transformationType: TX_DIRECT,
            defaultValue: '',
            formatPattern: '',
            concatSeparator: '',
            valueMaps: []
        };
    }

    newValueMap() {
        return {
            key: `vm-${this.nextValueMapKey++}`,
            id: null,
            sourceValue: '',
            targetValue: ''
        };
    }

    decorateRow(row) {
        const transform = row.transformationType || TX_DIRECT;
        const isDefaultValue = transform === TX_DEFAULT;
        const isDateFormat = transform === TX_DATE;
        const isConcatenate = transform === TX_CONCAT;
        const isPicklistMap = transform === TX_PICKLIST;
        return {
            ...row,
            isDefaultValue,
            isDateFormat,
            isConcatenate,
            isPicklistMap,
            showSourceField: !isDefaultValue && !isConcatenate,
            sourceFieldError: this.rowSourceFieldError(row),
            targetFieldError: this.showValidation && !row.targetField ? 'Target field is required.' : '',
            defaultValueError:
                this.showValidation && isDefaultValue && !row.defaultValue
                    ? 'Default value is required.'
                    : '',
            formatPatternError:
                this.showValidation && isDateFormat && !row.formatPattern
                    ? 'Format pattern is required.'
                    : '',
            concatFieldsError:
                this.showValidation && isConcatenate && (!row.sourceFields || row.sourceFields.length === 0)
                    ? 'Select at least one source field.'
                    : '',
            valueMapError:
                this.showValidation && isPicklistMap && !this.hasPopulatedValueMap(row)
                    ? 'Add at least one source and target value.'
                    : '',
            valueMaps: (row.valueMaps || []).map((valueMap) => ({
                ...valueMap,
                sourceValueError:
                    this.showValidation && isPicklistMap && !valueMap.sourceValue
                        ? 'Source value is required.'
                        : '',
                targetValueError:
                    this.showValidation && isPicklistMap && !valueMap.targetValue
                        ? 'Target value is required.'
                        : ''
            }))
        };
    }

    rowSourceFieldError(row) {
        const transform = row.transformationType || TX_DIRECT;
        if (!this.showValidation || transform === TX_DEFAULT || transform === TX_CONCAT) {
            return '';
        }
        return row.sourceField ? '' : 'Source field is required.';
    }

    toFieldOptions(fields) {
        return fields.map((field) => ({
            label: `${field.label} (${field.apiName})`,
            value: field.apiName
        }));
    }

    applyDefaultMatchField() {
        if (
            this.matchTargetField &&
            this.targetFields.some((field) => field.apiName === this.matchTargetField)
        ) {
            return;
        }
        if (this.matchTargetField) {
            const localName = this.matchTargetField.includes('__')
                ? this.matchTargetField.substring(this.matchTargetField.indexOf('__') + 2)
                : this.matchTargetField;
            const resolved = this.targetFields.find(
                (field) => field.apiName === this.matchTargetField || field.apiName.endsWith(localName)
            );
            if (resolved) {
                this.matchTargetField = resolved.apiName;
                return;
            }
        }
        const match = this.targetFields.find((field) => field.apiName.endsWith(DEFAULT_MATCH_SUFFIX));
        this.matchTargetField = match ? match.apiName : this.matchTargetField;
    }

    hasSourceStepValues() {
        return !!(this.mappingName && this.sourceObject);
    }

    areRowsValid() {
        return this.rows.length > 0 && this.rows.every((row) => this.isRowValid(row));
    }

    isFormValid() {
        return this.hasSourceStepValues() && !!this.matchTargetField && this.areRowsValid();
    }

    isRowValid(row) {
        if (!row.targetField) {
            return false;
        }
        const transform = row.transformationType || TX_DIRECT;
        if (transform === TX_DEFAULT) {
            return !!row.defaultValue;
        }
        if (transform === TX_CONCAT) {
            return row.sourceFields && row.sourceFields.length > 0;
        }
        if (!row.sourceField) {
            return false;
        }
        if (transform === TX_DATE) {
            return !!row.formatPattern;
        }
        if (transform === TX_PICKLIST) {
            return this.hasPopulatedValueMap(row);
        }
        return true;
    }

    hasPopulatedValueMap(row) {
        return (row.valueMaps || []).some((valueMap) => valueMap.sourceValue && valueMap.targetValue);
    }

    splitSourceFields(sourceField) {
        if (!sourceField) {
            return [];
        }
        return sourceField
            .split(',')
            .map((part) => part.trim())
            .filter((part) => part);
    }

    handleNameChange(event) {
        this.mappingName = event.detail.value;
    }

    handleDescriptionChange(event) {
        this.description = event.detail.value;
    }

    async handleSourceObjectChange(event) {
        this.sourceObject = event.detail.value;
        this.rows = this.rows.map((row) => ({
            ...row,
            sourceField: '',
            sourceFields: []
        }));
        this.errorMessage = undefined;
        try {
            await this.loadSourceFields(this.sourceObject);
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        }
    }

    handleMatchFieldChange(event) {
        this.matchTargetField = event.detail.value;
    }

    handleActiveChange(event) {
        this.active = event.target.checked;
    }

    handleRowFieldChange(event) {
        const key = event.currentTarget.dataset.rowKey;
        const field = event.currentTarget.dataset.field;
        const value = event.detail.value;
        this.rows = this.rows.map((row) => {
            if (row.key !== key) {
                return row;
            }
            const next = { ...row, [field]: value };
            if (field === 'transformationType') {
                return this.applyTransformDefaults(next);
            }
            return next;
        });
    }

    applyTransformDefaults(row) {
        const next = { ...row };
        if (next.transformationType === TX_PICKLIST && next.valueMaps.length === 0) {
            next.valueMaps = [this.newValueMap()];
        }
        if (next.transformationType === TX_CONCAT && next.sourceFields.length === 0) {
            next.sourceFields = this.splitSourceFields(next.sourceField);
        }
        if (next.transformationType !== TX_CONCAT && next.sourceFields.length > 0 && !next.sourceField) {
            next.sourceField = next.sourceFields[0];
        }
        return next;
    }

    handleConcatFieldsChange(event) {
        const key = event.currentTarget.dataset.rowKey;
        const selected = event.detail.value || [];
        this.rows = this.rows.map((row) =>
            row.key === key
                ? { ...row, sourceFields: selected, sourceField: selected.join(',') }
                : row
        );
    }

    handleValueMapChange(event) {
        const rowKey = event.currentTarget.dataset.rowKey;
        const valueMapKey = event.currentTarget.dataset.vmKey;
        const field = event.currentTarget.dataset.field;
        const value = event.detail.value;
        this.rows = this.rows.map((row) => {
            if (row.key !== rowKey) {
                return row;
            }
            return {
                ...row,
                valueMaps: row.valueMaps.map((valueMap) =>
                    valueMap.key === valueMapKey ? { ...valueMap, [field]: value } : valueMap
                )
            };
        });
    }

    handleAddRow() {
        this.rows = [...this.rows, this.newRow()];
    }

    handleRemoveRow(event) {
        const key = event.currentTarget.dataset.rowKey;
        const remaining = this.rows.filter((row) => row.key !== key);
        this.rows = remaining.length > 0 ? remaining : [this.newRow()];
    }

    handleAddValueMap(event) {
        const key = event.currentTarget.dataset.rowKey;
        this.rows = this.rows.map((row) =>
            row.key === key ? { ...row, valueMaps: [...row.valueMaps, this.newValueMap()] } : row
        );
    }

    handleRemoveValueMap(event) {
        const rowKey = event.currentTarget.dataset.rowKey;
        const valueMapKey = event.currentTarget.dataset.vmKey;
        this.rows = this.rows.map((row) => {
            if (row.key !== rowKey) {
                return row;
            }
            const remaining = row.valueMaps.filter((valueMap) => valueMap.key !== valueMapKey);
            return { ...row, valueMaps: remaining };
        });
    }

    handleNext() {
        this.showValidation = true;
        if (this.isStepSource && this.hasSourceStepValues()) {
            this.currentStep = STEP_FIELDS;
            this.showValidation = false;
            return;
        }
        if (this.isStepFields && this.areRowsValid()) {
            this.currentStep = STEP_MATCH;
            this.showValidation = false;
        }
    }

    handleBack() {
        this.showValidation = false;
        if (this.isStepMatch) {
            this.currentStep = STEP_FIELDS;
            return;
        }
        if (this.isStepFields) {
            this.currentStep = STEP_SOURCE;
        }
    }

    async handleSave() {
        this.showValidation = true;
        if (this.isSaveDisabled) {
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            const mappingId = await saveMapping({
                definition: {
                    id: this._recordId || this.loadedMappingId || null,
                    name: this.mappingName,
                    description: this.description,
                    sourceObject: this.sourceObject,
                    matchTargetField: this.matchTargetField,
                    active: this.active
                },
                rows: this.rows.map((row, index) => this.toSaveRow(row, index))
            });
            this._recordId = mappingId;
            this.loadedMappingId = undefined;
            await this.loadExistingMapping(mappingId, false);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Mapping saved',
                    message: 'The mapping definition was saved.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    toSaveRow(row, index) {
        const isConcatenate = row.transformationType === TX_CONCAT;
        return {
            id: row.id || null,
            sourceField: isConcatenate ? (row.sourceFields || []).join(',') : row.sourceField,
            targetField: row.targetField,
            transformationType: row.transformationType || TX_DIRECT,
            defaultValue: row.defaultValue,
            formatPattern: row.formatPattern,
            concatSeparator: row.concatSeparator,
            sortOrder: (index + 1) * 10,
            valueMaps: (row.valueMaps || [])
                .filter((valueMap) => valueMap.sourceValue || valueMap.targetValue)
                .map((valueMap) => ({
                    sourceValue: valueMap.sourceValue,
                    targetValue: valueMap.targetValue
                }))
        };
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to save the mapping.';
    }
}
