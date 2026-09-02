import { NavigationMixin } from 'lightning/navigation';

/**
 * Shared navigation helpers for EMR datatables and record links.
 */

/**
 * @param {string} recordId
 * @param {string} objectApiName
 * @returns {{ type: string, attributes: object }}
 */
export function recordViewPageRef(recordId, objectApiName) {
    return {
        type: 'standard__recordPage',
        attributes: {
            recordId,
            objectApiName,
            actionName: 'view'
        }
    };
}

/**
 * lightning-datatable column config for a clickable record name.
 * @param {string} label column header
 * @param {string} urlField field holding the generated URL
 * @param {string} labelField field holding the display label
 * @returns {object}
 */
export function urlColumn(label, urlField, labelField) {
    return {
        label,
        fieldName: urlField,
        type: 'url',
        typeAttributes: {
            label: { fieldName: labelField },
            target: '_self'
        },
        wrapText: true
    };
}

/**
 * Attach generated record URLs onto rows for datatable url columns.
 * Host component must extend NavigationMixin.
 *
 * @param {object} component host with NavigationMixin
 * @param {Array<object>} rows
 * @param {string} objectApiName
 * @param {object} [options]
 * @param {string} [options.idField='Id']
 * @param {string} [options.urlField='recordUrl']
 * @param {string} [options.labelField] source label field to copy
 * @param {string} [options.labelOutField='recordLabel'] output label field
 * @returns {Promise<Array<object>>}
 */
export async function withRecordUrls(component, rows, objectApiName, options = {}) {
    const idField = options.idField || 'Id';
    const urlField = options.urlField || 'recordUrl';
    const labelField = options.labelField;
    const labelOutField = options.labelOutField || 'recordLabel';

    if (!rows || !rows.length || !component || !objectApiName) {
        return rows || [];
    }

    return Promise.all(
        rows.map(async (row) => {
            const recordId = row[idField];
            let url = '';
            if (recordId) {
                try {
                    url = await component[NavigationMixin.GenerateUrl](
                        recordViewPageRef(recordId, objectApiName)
                    );
                } catch (e) {
                    url = '';
                }
            }
            const next = { ...row, [urlField]: url || '' };
            if (labelField) {
                next[labelOutField] = row[labelField] || '';
            }
            return next;
        })
    );
}
