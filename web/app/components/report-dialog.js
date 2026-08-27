const reportDescriptionMaximumGraphemes = 500;
const reportImageMaximumCount = 3;
const reportImageMaximumBytes = 5 * 1024 * 1024;
const reportImageMimeTypes = ['image/png', 'image/jpeg', 'image/webp'];

function readContextValue(context, lowerName, upperName) {
    if (!context) { return ''; }
    if (context[lowerName] !== undefined && context[lowerName] !== null) { return String(context[lowerName]); }
    if (context[upperName] !== undefined && context[upperName] !== null) { return String(context[upperName]); }
    return '';
}

function reportUnicodeCodePoints(text) {
    return Array.from(String(text || ''));
}

function isLegacyReportGraphemeExtend(codePoint) {
/*
    return /[\u0300-\u036f\u0483-\u0489\u0591-\u05bd\u05bf\u05c1\u05c2\u05c4\u05c5\u05c7\u0610-\u061a\u064b-\u065f\u0670\u06d6-\u06dc\u06df-\u06e4\u06e7-\u06e8\u06ea-\u06ed\u0711\u0730-\u074a\u07a6-\u07b0\u07eb-\u07f3\u0816-\u0819\u081b-\u0823\u0825-\u0827\u0829-\u082d\u0859-\u085f\u08d3-\u0903\u093a-\u093c\u093e-\u094f\u0951-\u0957\u0962-\u0963\u0981\u09bc\u09be-\u09c4\u09c7-\u09c8\u09cb-\u09cd\u09d7\u09e2-\u09e3\u0a01\u0a02\u0a3c\u0a3e-\u0a42\u0a47-\u0a48\u0a4b-\u0a4d\u0a51\u0a70-\u0a71\u0a75\u0a81\u0a82\u0abc\u0abe-\u0ac5\u0ac7-\u0ac9\u0acb-\u0acd\u0ae2-\u0ae3\u0b01\u0b3c\u0b3e-\u0b44\u0b47-\u0b48\u0b4b-\u0b4d\u0b56-\u0b57\u0b62-\u0b63\u0b82\u0bbe-\u0bc2\u0bc6-\u0bcd\u0bd7\u0c00-\u0c04\u0c3e-\u0c40\u0c46-\u0c48\u0c4a-\u0c4d\u0c55-\u0c56\u0c62-\u0c63\u0c81\u0cbc\u0cbe-\u0cc4\u0cc6-\u0cc8\u0cca-\u0ccd\u0cd5-\u0cd6\u0ce2-\u0ce3\u0d00-\u0d04\u0d3b\u0d3e-\u0d44\u0d46-\u0d4d\u0d57\u0d62-\u0d63\u0d81\u0dca\u0dcf-\u0dd4\u0dd6\u0dd8-\u0ddf\u0df2-\u0xdf3\u0e31\u0e34-\u0e3a\u0e47-\u0e4e\u0eb1\u0eb4-\u0ebc\u0ebe-\u0ebf\u0f18-\u0f19\u0f35\u0f37\u0f39\u0f3e-\u0f3f\u0f71-\u0f84\u0f86-\u0f87\u0f8d-\u0f97\u0f99-\u0fbc\u0fc6\u102d-\u1030\u1032-\u1037\u1039-\u103a\u103d-\u103e\u1058-\u1059\u105e-\u1060\u1062-\u1064\u1067-\u106d\u1071-\u1074\u1082\u1085-\u1086\u108d\u108f-\u109d\u135d-\u135f\u1712-\u1714\u1732-\u1734\u1752-\u1753\u1772-\u1773\u17b4-\u17d3\u17dd\u180b-\u180f\u1885-\u1886\u18a9\u1920-\u192b\u1930-\u193b\u1a17-\u1a1b\u1a55-\u1a5f\u1a65-\u1a7f\u1ab0-\u1aff\u1b00-\u1b04\u1b34\u1b35-\u1b43\u1b6b-\u1b73\u1b80-\u1b82\u1ba1-\u1ba1\u1ba8-\u1ba9\u1bac-\u1bad\u1be6-\u1bf3\u1c24-\u1c4c\u1c50-\u1c59\u1c5a-\u1c7d\u1cd0-\u1cf9\u1dc0-\u1dff\u200c\u20d0-\u20ff\u2cef-\u2cf1\u2de0-\u2dff\u302a-\u302f\ua66f-\ua67f\ua69e-\ua69f\ua6f0-\ua6f1\ua802\ua806\ua80b\ua823-\ua827\ua82c\ua880-\ua881\ua8b4-\ua8c5\ua8e0-\ua8f1\ua8ff-\ua909\ua926-\ua92f\ua947-\ua953\ua980\ua982\ua9b3\ua9b4-\ua9b5\ua9bc\ua9bd-\ua9c0\ua9c2-\ua9c5\ua9e5\ua9e6-\ua9ef\uaa29-\uaa2f\uaa31-\uaa32\uaa35-\uaa36\uaa43\uaa4c\uaa7b-\uaa7d\uaa7f-\uaaaf\uaab0-\uaab4\uaab7-\uaab8\uaabe-\uaabf\uaac1\uaac7-\uaac9\uaacb-\uaacd\uaae2-\uaaef\uaaf5\uab01-\uab06\uab09-\uab0e\uab11-\uab12\uab29\uab2b\uab2d-\uab2f\uab31-\uab33\uab35-\uab3e\uab41\uab43\uab44\uab47-\uab4f\uab51-\uab5b\uab60-\uab65\uabe3-\uabef\ufb1e\ufe00-\ufe0f\ufe20-\ufe2f\ufe4d-\ufe4f\uff9e-\uff9f\u{1f3fb}-\u{1f3ff}\u{e0020}-\u{e007f}]/u.test(codePoint);
}
*/
}

function isReportGraphemeExtend(codePoint) {
    const numericCodePoint = codePoint.codePointAt(0);
    if (numericCodePoint === 0x200c || /[\ufe00-\ufe0f]/u.test(codePoint) || (numericCodePoint >= 0x1f3fb && numericCodePoint <= 0x1f3ff) || (numericCodePoint >= 0xe0020 && numericCodePoint <= 0xe007f)) { return true; }
    return /^\p{Mark}$/u.test(codePoint);
}

function countReportGraphemes(text) {
    if (typeof Intl !== 'undefined' && Intl.Segmenter) {
        return Array.from(new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(String(text || ''))).length;
    }
    const codePoints = reportUnicodeCodePoints(text);
    let graphemeCount = 0;
    let codePointIndex = 0;
    while (codePointIndex < codePoints.length) {
        const currentCodePoint = codePoints[codePointIndex++].codePointAt(0);
        if (currentCodePoint === 0x0d && codePoints[codePointIndex] === '\n') { codePointIndex += 1; }
        if (currentCodePoint >= 0x1f1e6 && currentCodePoint <= 0x1f1ff && codePoints[codePointIndex] && codePoints[codePointIndex].codePointAt(0) >= 0x1f1e6 && codePoints[codePointIndex].codePointAt(0) <= 0x1f1ff) { codePointIndex += 1; }
        while (codePointIndex < codePoints.length) {
            const nextCodePoint = codePoints[codePointIndex];
            if (isReportGraphemeExtend(nextCodePoint)) { codePointIndex += 1; continue; }
            if (nextCodePoint === '\u200d') {
                codePointIndex += 1;
                if (codePointIndex < codePoints.length) { codePointIndex += 1; }
                continue;
            }
            break;
        }
        graphemeCount += 1;
    }
    return graphemeCount;
}

function reportTextElements(text) {
    if (typeof Intl !== 'undefined' && Intl.Segmenter) {
        return Array.from(new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(String(text || '')), function (segment) { return segment.segment; });
    }
    return Array.from(String(text || ''));
}

class GlmReportDialog extends HTMLElement {
    constructor() {
        super();
        this.availableContexts = [];
        this.activeContextValue = null;
        this.dialogOrigin = null;
        this.disabledValue = false;
        this.disabledReasonValue = '';
        this.reportFormState = {
            status: 'editing',
            category: 'error',
            clientId: '',
            module: '',
            environmentId: '',
            description: '',
            characterCount: 0,
            images: [],
            error: null
        };
    }

    connectedCallback() {
        this.render();
    }

    set contextOptions(value) {
        this.availableContexts = Array.isArray(value) ? value.slice() : [];
        if (this.isConnected) { this.refreshContextOptions(); }
    }

    get contextOptions() { return this.availableContexts.slice(); }

    set activeContext(value) {
        this.activeContextValue = value || null;
        if (this.isConnected) { this.applyActiveContext(); }
    }

    set disabled(value) {
        this.disabledValue = Boolean(value);
        if (this.isConnected) { this.updateDisabledState(); }
    }

    get disabled() { return this.disabledValue; }

    set disabledReason(value) {
        this.disabledReasonValue = String(value || '');
        if (this.isConnected) { this.updateDisabledState(); }
    }

    render() {
        this.innerHTML = '<dialog class="report-dialog" aria-labelledby="report-dialog-title">' +
            '<form class="report-form" novalidate>' +
                '<header class="report-dialog-header"><div><h2 id="report-dialog-title">Reportar un problema</h2></div><button type="button" class="dialog-close" data-report-action="close" aria-label="Cerrar">&times;</button></header>' +
                '<div class="report-dialog-error" data-report-error role="alert" hidden></div>' +
                '<div class="report-dialog-fields" data-report-form-fields>' +
                    '<label>Cliente<select data-report-field="clientId" required><option value="">Selecciona un cliente</option></select></label>' +
                    '<label>Módulo<select data-report-field="module" required disabled><option value="">Selecciona un módulo</option></select></label>' +
                    '<label>Ambiente<select data-report-field="environmentId" required disabled><option value="">Selecciona un ambiente</option></select></label>' +
                    '<label>Categoría<select data-report-field="category"><option value="error">Error</option><option value="sugerencia">Sugerencia</option></select></label>' +
                    '<label class="report-description-field">Descripción<textarea data-report-field="description" rows="6" maxlength="500" required aria-describedby="report-character-count"></textarea><span class="report-character-count" id="report-character-count" data-report-character-count aria-live="polite">0/500</span></label>' +
                    '<label class="report-image-field">Imágenes opcionales<input data-report-field="image" type="file" accept="image/png,image/jpeg,image/webp" multiple><span class="report-image-help" data-report-image-help>Hasta 3 imágenes PNG, JPEG o WebP. Máximo 5 MiB por imagen.</span></label>' +
                '</div>' +
                '<div class="report-dialog-actions" data-report-form-actions><button type="button" class="button secondary" data-report-action="close">Cancelar</button><button type="submit" class="button primary" data-report-action="submit">Enviar reporte</button></div>' +
            '</form>' +
            '<section class="report-success" data-report-success hidden tabindex="-1" aria-live="polite"><span class="report-success-icon" aria-hidden="true">✓</span><h2>El reporte se ha enviado con éxito</h2><button type="button" class="button primary" data-report-action="close">Cerrar</button></section>' +
        '</dialog>';

        this.dialogElement = this.querySelector('dialog');
        this.formElement = this.querySelector('.report-form');
        this.clientSelect = this.querySelector('[data-report-field="clientId"]');
        this.moduleSelect = this.querySelector('[data-report-field="module"]');
        this.environmentSelect = this.querySelector('[data-report-field="environmentId"]');
        this.categorySelect = this.querySelector('[data-report-field="category"]');
        this.descriptionElement = this.querySelector('[data-report-field="description"]');
        this.imageElement = this.querySelector('[data-report-field="image"]');
        this.errorElement = this.querySelector('[data-report-error]');
        this.characterCountElement = this.querySelector('[data-report-character-count]');
        this.successElement = this.querySelector('[data-report-success]');
        this.bindEvents();
        this.refreshContextOptions();
        this.updateDisabledState();
    }

    bindEvents() {
        this.formElement.addEventListener('submit', (event) => {
            event.preventDefault();
            this.submitForm();
        });
        this.clientSelect.addEventListener('change', () => {
            this.reportFormState.clientId = this.clientSelect.value;
            this.reportFormState.module = '';
            this.reportFormState.environmentId = '';
            this.refreshModuleOptions();
        });
        this.moduleSelect.addEventListener('change', () => {
            this.reportFormState.module = this.moduleSelect.value;
            this.reportFormState.environmentId = '';
            this.refreshEnvironmentOptions();
        });
        this.environmentSelect.addEventListener('change', () => { this.reportFormState.environmentId = this.environmentSelect.value; });
        this.categorySelect.addEventListener('change', () => { this.reportFormState.category = this.categorySelect.value; });
        this.descriptionElement.addEventListener('input', () => {
            const textElements = reportTextElements(this.descriptionElement.value);
            if (textElements.length > reportDescriptionMaximumGraphemes) {
                this.descriptionElement.value = textElements.slice(0, reportDescriptionMaximumGraphemes).join('');
            }
            this.reportFormState.description = this.descriptionElement.value;
            this.reportFormState.characterCount = countReportGraphemes(this.descriptionElement.value);
            this.characterCountElement.textContent = this.reportFormState.characterCount + '/' + reportDescriptionMaximumGraphemes;
            this.clearError();
        });
        this.imageElement.addEventListener('change', () => {
            const selectedFiles = Array.from(this.imageElement.files || []);
            const invalidFile = selectedFiles.find((file) => !reportImageMimeTypes.includes(file.type) || file.size > reportImageMaximumBytes);
            if (selectedFiles.length > reportImageMaximumCount || invalidFile) {
                this.reportFormState.images = [];
                this.imageElement.value = '';
                this.querySelector('[data-report-image-help]').textContent = 'Hasta 3 imágenes PNG, JPEG o WebP. Máximo 5 MiB por imagen.';
                this.setError(selectedFiles.length > reportImageMaximumCount ? 'Puedes adjuntar como máximo 3 imágenes.' : (invalidFile.size > reportImageMaximumBytes ? 'Una imagen supera el límite de 5 MiB.' : 'Las imágenes deben ser PNG, JPEG o WebP.'));
                return;
            }
            this.reportFormState.images = selectedFiles;
            this.clearError();
            this.querySelector('[data-report-image-help]').textContent = selectedFiles.length ? selectedFiles.map((file) => file.name).join(', ') : 'Hasta 3 imágenes PNG, JPEG o WebP. Máximo 5 MiB por imagen.';
        });
        this.querySelectorAll('[data-report-action="close"]').forEach((button) => button.addEventListener('click', () => this.close()));
        this.dialogElement.addEventListener('cancel', (event) => {
            if (event.target !== this.dialogElement) { return; }
            event.preventDefault();
            this.close();
        });
        this.dialogElement.addEventListener('keydown', (event) => this.trapFocus(event));
    }

    setOptions(selectElement, options, placeholder, selectedValue) {
        selectElement.innerHTML = '';
        const placeholderOption = document.createElement('option');
        placeholderOption.value = '';
        placeholderOption.textContent = placeholder;
        selectElement.appendChild(placeholderOption);
        options.forEach((option) => {
            const optionElement = document.createElement('option');
            optionElement.value = option.value;
            optionElement.textContent = option.label;
            selectElement.appendChild(optionElement);
        });
        selectElement.value = options.some((option) => option.value === selectedValue) ? selectedValue : '';
        selectElement.disabled = options.length === 0 || this.reportFormState.status === 'submitting';
    }

    getClients() {
        const clientsById = new Map();
        this.availableContexts.forEach((context) => {
            const clientId = readContextValue(context, 'clienteId', 'ClienteId');
            if (!clientId || clientsById.has(clientId)) { return; }
            clientsById.set(clientId, { value: clientId, label: readContextValue(context, 'clienteNombre', 'ClienteNombre') || clientId });
        });
        return Array.from(clientsById.values());
    }

    getModules(clientId) {
        const modulesById = new Map();
        this.availableContexts.filter((context) => readContextValue(context, 'clienteId', 'ClienteId') === clientId).forEach((context) => {
            const moduleId = readContextValue(context, 'modulo', 'Modulo');
            if (!moduleId || modulesById.has(moduleId)) { return; }
            modulesById.set(moduleId, { value: moduleId, label: readContextValue(context, 'moduloNombre', 'ModuloNombre') || (moduleId === 'erp' ? 'ERP' : 'Comercial') });
        });
        return Array.from(modulesById.values());
    }

    getEnvironments(clientId, moduleId) {
        return this.availableContexts.filter((context) => readContextValue(context, 'clienteId', 'ClienteId') === clientId && readContextValue(context, 'modulo', 'Modulo') === moduleId).map((context) => ({
            value: readContextValue(context, 'ambienteId', 'AmbienteId'),
            label: readContextValue(context, 'ambienteNombre', 'AmbienteNombre') || readContextValue(context, 'ambienteId', 'AmbienteId')
        }));
    }

    refreshContextOptions() {
        if (!this.clientSelect) { return; }
        const currentClient = this.reportFormState.clientId;
        this.setOptions(this.clientSelect, this.getClients(), 'Selecciona un cliente', currentClient);
        this.reportFormState.clientId = this.clientSelect.value;
        this.refreshModuleOptions();
        this.applyActiveContext();
    }

    refreshModuleOptions() {
        const currentModule = this.reportFormState.module;
        this.setOptions(this.moduleSelect, this.getModules(this.clientSelect.value), 'Selecciona un módulo', currentModule);
        this.reportFormState.module = this.moduleSelect.value;
        this.refreshEnvironmentOptions();
    }

    refreshEnvironmentOptions() {
        const currentEnvironment = this.reportFormState.environmentId;
        this.setOptions(this.environmentSelect, this.getEnvironments(this.clientSelect.value, this.moduleSelect.value), 'Selecciona un ambiente', currentEnvironment);
        this.reportFormState.environmentId = this.environmentSelect.value;
    }

    applyActiveContext() {
        if (!this.clientSelect || !this.activeContextValue) { return; }
        const clientId = readContextValue(this.activeContextValue, 'clienteId', 'ClienteId');
        const moduleId = readContextValue(this.activeContextValue, 'modulo', 'Modulo');
        const environmentId = readContextValue(this.activeContextValue, 'ambienteId', 'AmbienteId');
        if (!this.getClients().some((option) => option.value === clientId)) { return; }
        this.reportFormState.clientId = clientId;
        this.clientSelect.value = clientId;
        this.refreshModuleOptions();
        if (!this.getModules(clientId).some((option) => option.value === moduleId)) { return; }
        this.reportFormState.module = moduleId;
        this.moduleSelect.value = moduleId;
        this.refreshEnvironmentOptions();
        if (this.getEnvironments(clientId, moduleId).some((option) => option.value === environmentId)) {
            this.reportFormState.environmentId = environmentId;
            this.environmentSelect.value = environmentId;
        }
    }

    updateDisabledState() {
        const openButton = this.querySelector('[data-report-open]');
        if (openButton) {
            openButton.disabled = this.disabledValue;
            openButton.title = this.disabledValue ? this.disabledReasonValue : 'Reportar un error o enviar una sugerencia';
            openButton.setAttribute('aria-disabled', this.disabledValue ? 'true' : 'false');
        }
        if (this.dialogElement) {
            this.querySelectorAll('[data-report-field]').forEach((field) => { field.disabled = this.disabledValue || this.reportFormState.status === 'submitting'; });
        }
    }

    setError(message) {
        this.reportFormState.error = String(message || '');
        this.errorElement.textContent = this.reportFormState.error;
        this.errorElement.hidden = !this.reportFormState.error;
        this.reportFormState.status = 'error';
    }

    clearError() {
        if (!this.errorElement) { return; }
        this.reportFormState.error = null;
        this.errorElement.textContent = '';
        this.errorElement.hidden = true;
        if (this.reportFormState.status === 'error') { this.reportFormState.status = 'editing'; }
    }

    submitForm() {
        if (this.reportFormState.status === 'submitting' || this.disabledValue) { return; }
        const description = this.descriptionElement.value.trim();
        const characterCount = countReportGraphemes(description);
        if (!this.clientSelect.value || !this.moduleSelect.value || !this.environmentSelect.value) { this.setError('Selecciona un Cliente, Módulo y Ambiente válidos.'); return; }
        if (!description || characterCount > reportDescriptionMaximumGraphemes) { this.setError('La descripción debe contener entre 1 y 500 caracteres visibles.'); return; }
        this.reportFormState.description = description;
        this.reportFormState.characterCount = characterCount;
        this.reportFormState.category = this.categorySelect.value;
        this.reportFormState.clientId = this.clientSelect.value;
        this.reportFormState.module = this.moduleSelect.value;
        this.reportFormState.environmentId = this.environmentSelect.value;
        this.clearError();
        this.dispatchEvent(new CustomEvent('report-submit', {
            bubbles: true,
            detail: {
                category: this.reportFormState.category,
                context: { clientId: this.reportFormState.clientId, module: this.reportFormState.module, environmentId: this.reportFormState.environmentId },
                description,
                images: this.reportFormState.images.slice()
            }
        }));
    }

    setSubmitting(isSubmitting) {
        this.reportFormState.status = isSubmitting ? 'submitting' : 'editing';
        this.querySelectorAll('[data-report-field]').forEach((field) => { field.disabled = Boolean(isSubmitting) || this.disabledValue; });
        this.querySelector('[data-report-action="submit"]').disabled = Boolean(isSubmitting);
        this.querySelector('[data-report-action="submit"]').textContent = isSubmitting ? 'Enviando...' : 'Enviar reporte';
    }

    showSuccess() {
        this.reportFormState.status = 'success';
        this.querySelector('[data-report-form-fields]').hidden = true;
        this.querySelector('[data-report-form-actions]').hidden = true;
        this.formElement.hidden = true;
        this.successElement.hidden = false;
        this.successElement.focus();
    }

    open(origin) {
        if (this.disabledValue || !this.dialogElement || this.dialogElement.open) { return; }
        this.dialogOrigin = origin || document.activeElement;
        this.clearError();
        if (typeof this.dialogElement.showModal === 'function') { this.dialogElement.showModal(); } else { this.dialogElement.setAttribute('open', ''); }
        this.clientSelect.focus();
    }

    close() {
        if (!this.dialogElement) { return; }
        if (this.dialogElement.open && typeof this.dialogElement.close === 'function') { this.dialogElement.close(); } else { this.dialogElement.removeAttribute('open'); }
        this.reset();
        if (this.dialogOrigin && document.contains(this.dialogOrigin)) { this.dialogOrigin.focus(); }
        this.dialogOrigin = null;
        this.dispatchEvent(new CustomEvent('report-close', { bubbles: true }));
    }

    reset() {
        this.reportFormState = { status: 'editing', category: 'error', clientId: '', module: '', environmentId: '', description: '', characterCount: 0, images: [], error: null };
        if (!this.formElement) { return; }
        this.formElement.hidden = false;
        this.querySelector('[data-report-form-fields]').hidden = false;
        this.querySelector('[data-report-form-actions]').hidden = false;
        this.successElement.hidden = true;
        this.categorySelect.value = 'error';
        this.descriptionElement.value = '';
        this.imageElement.value = '';
        this.querySelector('[data-report-image-help]').textContent = 'Hasta 3 imágenes PNG, JPEG o WebP. Máximo 5 MiB por imagen.';
        this.characterCountElement.textContent = '0/500';
        this.clearError();
        this.refreshContextOptions();
    }

    trapFocus(event) {
        if (event.key !== 'Tab' || !this.dialogElement.open) { return; }
        const focusableElements = Array.from(this.dialogElement.querySelectorAll('button:not([disabled]), select:not([disabled]), textarea:not([disabled]), input:not([disabled])')).filter((element) => !element.closest('[hidden]'));
        if (!focusableElements.length) { return; }
        const firstFocusableElement = focusableElements[0];
        const lastFocusableElement = focusableElements[focusableElements.length - 1];
        if (event.shiftKey && document.activeElement === firstFocusableElement) { event.preventDefault(); lastFocusableElement.focus(); }
        if (!event.shiftKey && document.activeElement === lastFocusableElement) { event.preventDefault(); firstFocusableElement.focus(); }
    }
}

function registerReportDialog() {
    if (!customElements.get('glm-report-dialog')) { customElements.define('glm-report-dialog', GlmReportDialog); }
}

export { registerReportDialog, countReportGraphemes };
