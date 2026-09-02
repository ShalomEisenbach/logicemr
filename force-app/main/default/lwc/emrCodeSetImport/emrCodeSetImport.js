import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCsvContent from '@salesforce/apex/CodeSetImportController.getCsvContent';
import importCodes from '@salesforce/apex/CodeSetImportController.importCodes';

const PREVIEW_LIMIT = 10;
const ERROR_LIMIT = 50;
const IMPORT_CHUNK_SIZE = 2000;
const HEADER_SYSTEM = 'code system';
const HEADER_CODE = 'code';
const HEADER_DISPLAY = 'display';

export default class EmrCodeSetImport extends LightningElement {
    parsedRows = [];
    previewRows = [];
    result;
    errorMessage;
    isLoading = false;
    isImporting = false;

    get isBusy() {
        return this.isLoading || this.isImporting;
    }

    get hasPreview() {
        return this.parsedRows.length > 0;
    }

    get isImportDisabled() {
        return this.isBusy || !this.hasPreview;
    }

    get previewSummary() {
        if (this.parsedRows.length <= PREVIEW_LIMIT) {
            return `${this.parsedRows.length} row(s) ready to import.`;
        }
        return `${this.parsedRows.length} row(s) ready to import. Showing the first ${PREVIEW_LIMIT}.`;
    }

    get hasResult() {
        return this.result != null;
    }

    get resultSummary() {
        if (!this.result) {
            return '';
        }
        return `Created ${this.result.created}, updated ${this.result.updated}, failed ${this.result.failed}.`;
    }

    get hasResultErrors() {
        return this.visibleErrors.length > 0;
    }

    get visibleErrors() {
        const errors = this.result?.errors || [];
        return errors.slice(0, ERROR_LIMIT).map((message, index) => ({
            key: `err-${index}`,
            message
        }));
    }

    get hiddenErrorCount() {
        const total = this.result?.errors?.length || 0;
        return total > ERROR_LIMIT ? total - ERROR_LIMIT : 0;
    }

    async handleUploadFinished(event) {
        const uploaded = event.detail.files || [];
        if (uploaded.length === 0) {
            this.errorMessage = 'No file was uploaded.';
            return;
        }
        this.isLoading = true;
        this.errorMessage = undefined;
        this.result = undefined;
        this.parsedRows = [];
        this.previewRows = [];
        try {
            const csvText = await getCsvContent({ contentDocumentId: uploaded[0].documentId });
            this.applyParsedRows(this.parseCsv(csvText));
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    applyParsedRows(rows) {
        if (rows.length === 0) {
            this.errorMessage = 'The CSV has a header but no data rows.';
            return;
        }
        this.parsedRows = rows;
        this.previewRows = rows.slice(0, PREVIEW_LIMIT).map((row, index) => ({
            ...row,
            key: `preview-${index}`
        }));
    }

    async handleImport() {
        if (this.isImportDisabled) {
            return;
        }
        this.isImporting = true;
        this.errorMessage = undefined;
        this.result = undefined;
        try {
            const aggregate = { created: 0, updated: 0, failed: 0, errors: [] };
            for (let i = 0; i < this.parsedRows.length; i += IMPORT_CHUNK_SIZE) {
                const chunk = this.parsedRows.slice(i, i + IMPORT_CHUNK_SIZE);
                const chunkResult = await importCodes({ rows: chunk });
                aggregate.created += chunkResult.created || 0;
                aggregate.updated += chunkResult.updated || 0;
                aggregate.failed += chunkResult.failed || 0;
                if (chunkResult.errors && chunkResult.errors.length) {
                    aggregate.errors.push(...chunkResult.errors);
                }
            }
            this.result = aggregate;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Code set import complete',
                    message: this.resultSummary,
                    variant: aggregate.failed > 0 ? 'warning' : 'success'
                })
            );
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isImporting = false;
        }
    }

    handleClear() {
        this.parsedRows = [];
        this.previewRows = [];
        this.result = undefined;
        this.errorMessage = undefined;
    }

    parseCsv(text) {
        if (!text) {
            throw new Error('The uploaded file is empty.');
        }
        const records = this.readCsvRecords(text);
        if (records.length === 0) {
            throw new Error('The uploaded file is empty.');
        }
        const headerIndex = this.buildHeaderIndex(records[0].values);
        if (headerIndex.system < 0 || headerIndex.code < 0 || headerIndex.display < 0) {
            throw new Error('CSV must include columns named Code System, Code, and Display.');
        }

        const rows = [];
        for (let i = 1; i < records.length; i++) {
            const record = records[i];
            rows.push({
                rowNumber: record.lineNumber,
                codeSystem: this.cell(record.values, headerIndex.system),
                code: this.cell(record.values, headerIndex.code),
                display: this.cell(record.values, headerIndex.display)
            });
        }
        return rows;
    }

    buildHeaderIndex(headerCells) {
        const index = { system: -1, code: -1, display: -1 };
        headerCells.forEach((cell, position) => {
            const normalized = this.normalizeHeader(cell);
            if (normalized === HEADER_SYSTEM || normalized === 'codesystem') {
                index.system = position;
            } else if (normalized === HEADER_CODE) {
                index.code = position;
            } else if (normalized === HEADER_DISPLAY) {
                index.display = position;
            }
        });
        return index;
    }

    normalizeHeader(value) {
        return (value || '').replace(/^\ufeff/, '').trim().toLowerCase().replace(/[\s_]+/g, ' ');
    }

    cell(values, index) {
        if (index < 0 || index >= values.length) {
            return '';
        }
        return values[index] == null ? '' : String(values[index]).trim();
    }

    readCsvRecords(text) {
        const source = text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;
        const records = [];
        let field = '';
        let row = [];
        let inQuotes = false;
        let lineNumber = 1;
        let rowStartLine = 1;

        const commitRow = () => {
            const empty = row.every((value) => !value || !String(value).trim());
            if (!empty) {
                records.push({ lineNumber: rowStartLine, values: row });
            }
            row = [];
            field = '';
        };

        for (let i = 0; i < source.length; i++) {
            const current = source[i];
            const next = source[i + 1];
            if (inQuotes) {
                if (current === '"') {
                    if (next === '"') {
                        field += '"';
                        i += 1;
                    } else {
                        inQuotes = false;
                    }
                } else {
                    if (current === '\n') {
                        lineNumber += 1;
                    }
                    field += current;
                }
            } else if (current === '"') {
                inQuotes = true;
            } else if (current === ',') {
                row.push(field);
                field = '';
            } else if (current === '\n') {
                row.push(field);
                commitRow();
                lineNumber += 1;
                rowStartLine = lineNumber;
            } else if (current === '\r') {
                if (next === '\n') {
                    continue;
                }
                row.push(field);
                commitRow();
                lineNumber += 1;
                rowStartLine = lineNumber;
            } else {
                field += current;
            }
        }
        if (field.length > 0 || row.length > 0) {
            row.push(field);
            commitRow();
        }
        return records;
    }

    reduceError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to import the code set.';
    }
}
