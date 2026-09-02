import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getData from '@salesforce/apex/FlowsheetController.getData';
import OBSERVATION_OBJECT from '@salesforce/schema/Observation__c';
import { recordViewPageRef } from 'c/emrNavigationUtils';

const CATEGORY_VITALS = 'Vitals';
const CATEGORY_LABS = 'Labs';

export default class EmrFlowsheet extends NavigationMixin(LightningElement) {
    @api recordId;

    category = CATEGORY_VITALS;
    dateRange = '7d';
    columns = [];
    rows = [];
    truncated = false;
    totalObservationCount = 0;
    errorMessage;
    wiredResult;

    dateRangeOptions = [
        { label: 'Last 24 hours', value: '24h' },
        { label: 'Last 7 days', value: '7d' },
        { label: 'Last 30 days', value: '30d' },
        { label: 'Last 90 days', value: '90d' },
        { label: 'Last year', value: '1y' },
        { label: 'All time', value: 'all' }
    ];

    get observationObjectApiName() {
        return OBSERVATION_OBJECT.objectApiName;
    }

    @wire(getData, {
        patientId: '$recordId',
        category: '$category',
        dateRange: '$dateRange'
    })
    wiredFlowsheet(result) {
        this.wiredResult = result;
        const { data, error } = result;
        if (data) {
            this.columns = data.columns || [];
            this.applyRows(data.rows || [], this.columns);
            this.truncated = data.truncated === true;
            this.totalObservationCount = data.totalObservationCount || 0;
            this.errorMessage = undefined;
        } else if (error) {
            this.columns = [];
            this.rows = [];
            this.truncated = false;
            this.totalObservationCount = 0;
            this.errorMessage = this.reduceError(error);
        }
    }

    async applyRows(sourceRows, columns) {
        const pivoted = this.pivotRows(sourceRows, columns);
        this.rows = await Promise.all(
            pivoted.map(async (row) => ({
                ...row,
                cells: await Promise.all(row.cells.map((cell) => this.withCellUrl(cell)))
            }))
        );
    }

    async withCellUrl(cell) {
        if (!cell.observationId) {
            return cell;
        }
        try {
            const url = await this[NavigationMixin.GenerateUrl](
                recordViewPageRef(cell.observationId, OBSERVATION_OBJECT.objectApiName)
            );
            return { ...cell, url: url || '' };
        } catch (e) {
            return cell;
        }
    }

    get isLoading() {
        return !this.wiredResult || (this.wiredResult.data === undefined && !this.wiredResult.error);
    }

    get hasGrid() {
        return this.rows.length > 0 && this.columns.length > 0;
    }

    get showEmpty() {
        return !this.isLoading && !this.errorMessage && !this.hasGrid;
    }

    get emptyMessage() {
        return this.category === CATEGORY_LABS
            ? 'No laboratory results in this date range.'
            : 'No vital signs in this date range.';
    }

    get largeStateMessage() {
        return `Showing the ${this.columns.length} most recent time points (${this.totalObservationCount} observations). Narrow the date range for a complete view.`;
    }

    get vitalsVariant() {
        return this.category === CATEGORY_VITALS ? 'brand' : 'neutral';
    }

    get labsVariant() {
        return this.category === CATEGORY_LABS ? 'brand' : 'neutral';
    }

    handleVitals() {
        this.category = CATEGORY_VITALS;
    }

    handleLabs() {
        this.category = CATEGORY_LABS;
    }

    handleDateRange(event) {
        this.dateRange = event.detail.value;
    }

    pivotRows(sourceRows, columns) {
        return sourceRows.map((row) => {
            const byColumn = new Map();
            (row.cells || []).forEach((cell) => {
                if (cell?.columnKey) {
                    byColumn.set(cell.columnKey, cell);
                }
            });
            return {
                key: row.key,
                display: row.display,
                code: row.code,
                cells: columns.map((column) => this.toCellView(byColumn.get(column.key), column.key))
            };
        });
    }

    toCellView(cell, columnKey) {
        const interpretation = cell?.interpretation;
        const value = cell?.value;
        const unit = cell?.unit;
        const observationId = cell?.observationId;
        return {
            key: `${columnKey}-${observationId || 'empty'}`,
            value,
            unit,
            interpretation,
            observationId,
            hasValue: value !== null && value !== undefined && value !== '',
            className: this.cellClass(interpretation),
            title: interpretation || '',
            url: ''
        };
    }

    cellClass(interpretation) {
        const key = interpretation ? interpretation.toLowerCase() : '';
        if (key === 'critical') {
            return 'cell cell-critical';
        }
        if (key === 'high') {
            return 'cell cell-high';
        }
        if (key === 'low') {
            return 'cell cell-low';
        }
        return 'cell';
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to load the flowsheet.';
    }
}
