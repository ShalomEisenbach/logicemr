import { LightningElement, api } from 'lwc';

/**
 * Reusable SLDS modal dialog.
 *
 * Public API
 * - title (String): header text
 * - size (String, optional): 'small' | 'medium' | 'large' (default medium)
 * - close event: fired on X, Cancel, Escape, or backdrop click
 * - default slot: modal body
 * - footer slot: action buttons
 */
export default class EmrModal extends LightningElement {
    @api title;
    @api size = 'medium';

    connectedCallback() {
        this._boundKeydown = this.handleKeydown.bind(this);
        window.addEventListener('keydown', this._boundKeydown);
    }

    disconnectedCallback() {
        window.removeEventListener('keydown', this._boundKeydown);
    }

    get dialogClass() {
        const size = this.size || 'medium';
        const sizeClass =
            size === 'small'
                ? 'slds-modal_small'
                : size === 'large'
                  ? 'slds-modal_large'
                  : 'slds-modal_medium';
        return `slds-modal slds-fade-in-open ${sizeClass}`;
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleBackdropClick() {
        this.handleClose();
    }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            this.handleClose();
        }
    }

    stopPropagation(event) {
        event.stopPropagation();
    }
}
