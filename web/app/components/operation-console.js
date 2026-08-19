function escapeMarkup(value) {
    return String(value === null || value === undefined ? '' : value).replace(/[&<>"']/g, function (character) {
        return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character];
    });
}

function isOperationRunning(status) {
    return ['QUEUED', 'RUNNING', 'PROCESSING', 'EN PROCESO', 'EN_PROCESO'].indexOf(String(status || '').toUpperCase()) >= 0;
}

function operationStatusClass(status) {
    const normalizedStatus = String(status || '').toUpperCase();
    if (isOperationRunning(normalizedStatus)) { return 'badge-progress'; }
    if (['COMPLETED', 'COMPLETADO', 'OK', 'ACTIVO'].indexOf(normalizedStatus) >= 0) { return 'badge-ok'; }
    if (['PARTIAL', 'COMPLETADO PARCIALMENTE', 'WARNING', 'ADVERTENCIA', 'PENDIENTE'].indexOf(normalizedStatus) >= 0) { return 'badge-warning'; }
    if (['FAILED', 'ERROR', 'ELIMINADO', 'ABORTED', 'ABORTADO'].indexOf(normalizedStatus) >= 0) { return 'badge-danger'; }
    return 'badge-muted';
}

function inferOperationProgress(operation, status, lines) {
    if (!isOperationRunning(status)) { return 100; }
    const text = lines.join(' ').toUpperCase();
    const stages = [
        { terms: ['VALIDANDO', 'VALIDACION', 'VALIDACIÓN'], value: 18 },
        { terms: ['EXPORTANDO', 'EXPORTACION', 'EXPORTACIÓN'], value: 30 },
        { terms: ['ANALIZANDO', 'ANALISIS', 'ANÁLISIS'], value: 45 },
        { terms: ['COMPLETANDO', 'COMPLETAR'], value: 55 },
        { terms: ['GENERANDO', 'GENERACION', 'GENERACIÓN'], value: 68 },
        { terms: ['PUBLICANDO', 'PUBLICACION', 'PUBLICACIÓN'], value: 84 },
        { terms: ['FINALIZANDO', 'FINALIZACION', 'FINALIZACIÓN'], value: 94 }
    ];
    let progress = Math.min(88, 8 + (lines.length * 3));
    stages.forEach(function (stage) {
        if (stage.terms.some(function (term) { return text.indexOf(term) >= 0; })) { progress = Math.max(progress, stage.value); }
    });
    if (String(operation).indexOf('VALIDAR') >= 0 && text.indexOf('XPZ') >= 0) { progress = Math.max(progress, 35); }
    return progress;
}

class GlmOperationConsole extends HTMLElement {
    constructor() {
        super();
        this.work = null;
    }

    connectedCallback() { this.render(); }

    set data(value) {
        this.work = value || null;
        this.render();
    }

    get data() { return this.work; }

    render() {
        const operationKey = this.getAttribute('operation') || 'operacion';
        const operationTitle = operationKey === 'generarPdf' ? 'Generar PDF' : (operationKey === 'validarXpz' ? 'Validar XPZ' : 'Exportar');
        const work = this.work;
        this.className = 'work-card operation-console example-console';
        this.setAttribute('role', 'status');
        this.setAttribute('aria-live', 'polite');
        if (!work) {
            this.innerHTML = '<div class="work-card-heading example-console-header"><strong>' + operationTitle + '</strong><span class="badge badge-muted">SIN ACTIVIDAD</span></div><div class="console-body"><p>La operación mostrará aquí su progreso y salida.</p><glm-progress value="0" label="Progreso de la operación"></glm-progress><pre></pre></div>';
            return;
        }
        const visibleStatus = work.estadoVisible || work.estado || 'SIN ESTADO';
        const lines = Array.isArray(work.ultimasLineas) ? work.ultimasLineas.join('\n') : '';
        const outputLines = lines ? lines.split('\n') : [];
        const rawPercentage = work.progreso && work.progreso.porcentaje !== null && work.progreso.porcentaje !== undefined
            ? work.progreso.porcentaje
            : inferOperationProgress(work.operacion || operationTitle, visibleStatus, outputLines);
        const percentage = Math.min(100, Math.max(0, Number(rawPercentage) || 0));
        const runningSpinner = isOperationRunning(visibleStatus) ? '<span class="spinner sm" aria-hidden="true"></span> ' : '';
        const contextId = escapeMarkup(work.contextId || 'el contexto activo');
        const errorMessage = work.error || work.mensaje || '';
        const output = lines || (errorMessage ? 'La operación finalizó sin salida adicional.' : 'Esperando salida de la operación...');
        const errorHtml = errorMessage ? '<p class="console-error-message"><strong>Error:</strong> ' + escapeMarkup(errorMessage) + '</p>' : '';
        this.innerHTML = '<div class="work-card-heading example-console-header"><strong>' + operationTitle + '</strong><span class="badge ' + operationStatusClass(visibleStatus) + '">' + runningSpinner + escapeMarkup(visibleStatus) + '</span></div><div class="console-body"><p>' + escapeMarkup(work.operacion || operationTitle) + ' del contexto <strong>' + contextId + '</strong></p>' + errorHtml + '<p class="console-progress-label">Progreso: ' + escapeMarkup(percentage) + '%</p><glm-progress value="' + escapeMarkup(percentage) + '" label="Progreso de la operación"></glm-progress><pre aria-live="polite">' + escapeMarkup(output) + '</pre></div>';
    }
}

function registerOperationConsole() {
    if (!customElements.get('glm-operation-console')) {
        customElements.define('glm-operation-console', GlmOperationConsole);
    }
}

export { registerOperationConsole };
