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
    if (['PARTIAL', 'COMPLETADO PARCIALMENTE', 'WARNING', 'ADVERTENCIA', 'PENDIENTE', 'CANCELLED', 'CANCELADO', 'ABORTED', 'ABORTADO'].indexOf(normalizedStatus) >= 0) { return 'badge-warning'; }
    if (['FAILED', 'ERROR', 'ELIMINADO'].indexOf(normalizedStatus) >= 0) { return 'badge-danger'; }
    return 'badge-muted';
}

function inferOperationProgress(operation, status, lines) {
    if (!isOperationRunning(status)) { return 100; }
    const text = lines.join(' ').toUpperCase();
    const operationName = String(operation || '').toUpperCase();
    const isExport = operationName.indexOf('EXPORTAR') >= 0;
    const isComplete = operationName.indexOf('COMPLETAR') >= 0;
    const isPdf = operationName.indexOf('PDF') >= 0;
    const cycleMatches = lines.join('\n').match(/ciclo\s+(\d+)\s+de\s+(\d+)/ig) || [];
    let progress = isComplete ? 4 : (isExport ? 2 : 4);

    if (isExport && text.indexOf('[1/4]') >= 0) {
        const phaseMatches = lines.join('\n').match(/\[(\d+)\/5\]/g) || [];
        const phase = phaseMatches.length ? Number((phaseMatches[phaseMatches.length - 1].match(/\d+/) || ['1'])[0]) : 1;
        progress = Math.max(progress, 4 + (Math.min(phase, 5) * 10));
    }

    if ((isExport || isComplete) && cycleMatches.length) {
        const lastCycle = cycleMatches[cycleMatches.length - 1].match(/(\d+)\s+de\s+(\d+)/i);
        const cycle = lastCycle ? Number(lastCycle[1]) : 1;
        const totalCycles = lastCycle ? Number(lastCycle[2]) : 5;
        const cycleWidth = isExport ? 45 : 82;
        const cycleStart = isExport ? 48 : 10;
        const cycleProgress = cycleStart + ((Math.max(0, cycle - 1) / Math.max(1, totalCycles)) * cycleWidth);
        const isSelective = text.indexOf('EXPORTANDO COMPLEMENTO') >= 0;
        progress = Math.max(progress, cycleProgress + (isSelective ? cycleWidth / Math.max(1, totalCycles) * 0.45 : 0));
    }

    if (isPdf) {
        const stages = [
            { terms: ['VALIDANDO', 'VALIDACION', 'VALIDACIÓN'], value: 12 },
            { terms: ['REGENERACION', 'REGENERACIÓN', 'ANALIZANDO', 'ANALISIS', 'ANÁLISIS'], value: 28 },
            { terms: ['MARKDOWN', 'GENERANDO DOCUMENTACION'], value: 56 },
            { terms: ['GENERANDO DOCUMENTOS PDF', 'GENERANDO PDF'], value: 78 },
            { terms: ['PUBLICANDO', 'PUBLICACION', 'PUBLICACIÓN'], value: 90 },
            { terms: ['FINALIZANDO', 'FINALIZACION', 'FINALIZACIÓN', 'ACTUALIZACION COMPLETADA'], value: 96 }
        ];
        stages.forEach(function (stage) {
            if (stage.terms.some(function (term) { return text.indexOf(term) >= 0; })) { progress = Math.max(progress, stage.value); }
        });
    }

    if (text.indexOf('ERROR') >= 0 || text.indexOf('FATAL') >= 0 || text.indexOf('EXCEPTION') >= 0) { return Math.min(99, Math.max(progress, 96)); }
    return Math.min(96, Math.max(progress, 8));
}

function outputLineClass(line) {
    const normalizedLine = String(line || '').toUpperCase();
    if (/^\s*\[\d+\/\d+\]/.test(normalizedLine)) { return 'console-line-step'; }
    if (/ERROR\b|FATAL\b|EXCEPTION\b|MSB\d{4}\b/.test(normalizedLine)) { return 'console-line-error'; }
    if (/ADVERTENCIA|WARNING/.test(normalizedLine)) { return 'console-line-warning'; }
    if (/RESULTADO:\s*OK|COMPLETADO|GENERADO CORRECTAMENTE|PUBLICADO/.test(normalizedLine)) { return 'console-line-success'; }
    if (/^TARGET |^ALCANCE |^LOG |^COMPLEMENTO DE SALIDA:/.test(normalizedLine)) { return 'console-line-meta'; }
    return '';
}

function formatConsoleOutput(output) {
    return String(output || '').split(/\r?\n/).map(function (line) {
        const className = outputLineClass(line);
        const classAttribute = className ? ' class="console-output-line ' + className + '"' : ' class="console-output-line"';
        return '<span' + classAttribute + '>' + (line ? escapeMarkup(line) : '&nbsp;') + '</span>';
    }).join('\n');
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

    captureConsolePosition() {
        const consoleBody = this.querySelector('.console-body');
        if (!consoleBody) {
            return { followEnd: true, scrollTop: 0 };
        }

        const distanceToEnd = consoleBody.scrollHeight - consoleBody.scrollTop - consoleBody.clientHeight;
        return {
            followEnd: distanceToEnd <= 24,
            scrollTop: consoleBody.scrollTop
        };
    }

    restoreConsolePosition(position) {
        const consoleBody = this.querySelector('.console-body');
        if (!consoleBody) { return; }

        const maxScrollTop = Math.max(0, consoleBody.scrollHeight - consoleBody.clientHeight);
        if (position.followEnd) {
            consoleBody.scrollTop = maxScrollTop;
        } else {
            consoleBody.scrollTop = Math.min(position.scrollTop, maxScrollTop);
        }
    }

    render() {
        const consolePosition = this.captureConsolePosition();
        const operationKey = this.getAttribute('operation') || 'operacion';
        const work = this.work;
        const workOperation = String(work && work.operacion || '').toUpperCase();
        const isPdfOperation = operationKey === 'generarPdf' || workOperation.indexOf('PDF') >= 0;
        const operationTitle = isPdfOperation ? 'Generando PDF' : (operationKey === 'validarXpz' ? 'Validar XPZ' : 'Exportar XPZ');
        this.className = 'work-card operation-console example-console';
        this.setAttribute('role', 'status');
        this.setAttribute('aria-live', 'polite');
        if (!work) {
            this.innerHTML = '<div class="work-card-heading example-console-header"><div class="example-console-header-main"><strong>' + operationTitle + '</strong><span class="badge badge-muted">SIN ACTIVIDAD</span></div><div class="example-console-progress"><div class="example-console-progress-label"><span>Progreso total</span><strong>0%</strong></div><glm-progress value="0" label="Progreso total de la operación"></glm-progress></div></div><div class="console-body"><p>La operación mostrará aquí su progreso y salida.</p><pre></pre></div>';
            this.restoreConsolePosition(consolePosition);
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
        const warningState = operationStatusClass(visibleStatus) === 'badge-warning';
        const successState = operationKey === 'exportar' && operationStatusClass(visibleStatus) === 'badge-ok';
        const errorHtml = errorMessage ? '<p class="' + (warningState ? 'console-warning-message' : 'console-error-message') + '"><strong>' + (warningState ? 'Advertencia:' : 'Error:') + '</strong> ' + escapeMarkup(errorMessage) + '</p>' : '';
        const successHtml = successState ? '<div class="console-success-message"><strong>Éxito:</strong> el XPZ está listo para avanzar con la generación de PDF.<button type="button" class="console-pdf-button" data-operation-go-pdf="true">Ir a Generar PDF</button></div>' : '';
        const progressClass = operationStatusClass(visibleStatus) === 'badge-danger' ? ' console-progress-error' : (operationStatusClass(visibleStatus) === 'badge-warning' ? ' console-progress-warning' : '');
        const header = '<div class="work-card-heading example-console-header"><div class="example-console-header-main"><strong>' + operationTitle + '</strong><span class="badge ' + operationStatusClass(visibleStatus) + '">' + runningSpinner + escapeMarkup(visibleStatus) + '</span></div><div class="example-console-progress"><div class="example-console-progress-label"><span>Progreso total</span><strong>' + escapeMarkup(percentage) + '%</strong></div><glm-progress class="' + progressClass.trim() + '" value="' + escapeMarkup(percentage) + '" label="Progreso total de la operación"></glm-progress></div></div>';
        const abortHtml = isOperationRunning(visibleStatus) && work.id
            ? '<div class="console-actions"><button type="button" class="console-abort-button" data-operation-abort="true">Abortar operación</button></div>'
            : '';
        this.innerHTML = header + '<div class="console-body"><p>' + escapeMarkup(work.operacion || operationTitle) + ' del contexto <strong>' + contextId + '</strong></p>' + errorHtml + successHtml + '<pre aria-live="polite">' + formatConsoleOutput(output) + '</pre></div>' + abortHtml;
        const abortButton = this.querySelector('[data-operation-abort]');
        if (abortButton) {
            abortButton.addEventListener('click', () => {
                if (!window.confirm('¿Confirmas abortar la operación? Se terminarán la consola y todos sus procesos descendientes.')) { return; }
                abortButton.disabled = true;
                abortButton.textContent = 'Cancelando…';
                this.dispatchEvent(new CustomEvent('operation-abort', { bubbles: true, detail: { jobId: work.id } }));
            });
        }
        const pdfButton = this.querySelector('[data-operation-go-pdf]');
        if (pdfButton) {
            pdfButton.addEventListener('click', () => this.dispatchEvent(new CustomEvent('operation-go-pdf', { bubbles: true })));
        }
        this.restoreConsolePosition(consolePosition);
    }
}

function registerOperationConsole() {
    if (!customElements.get('glm-operation-console')) {
        customElements.define('glm-operation-console', GlmOperationConsole);
    }
}

export { registerOperationConsole };
