(function () {
    'use strict';

    var clientDropdown = null;
    var environmentDropdown = null;
    var currentJobId = null;
    var pollingTimer = null;
    var lastState = null;
    var endpointServices = [];
    var publishedDocuments = [];
    var contextLogs = [];
    var configurationSnapshot = null;
    var configurationData = { configuration: null, configHash: '', errores: [] };
    var activeTab = 'estado';
    var exportButton = document.getElementById('export-xpz');
    var updateServicesButton = document.getElementById('update-services');
    var exportFallback = document.getElementById('export-fallback');
    var selectedFallbackXpz = null;
    var operationResults = { exportar: null, generarPdf: null };
    var dismissedNoticeKeys = {};
    var exportConsoleVisible = false;
    var pdfConsoleVisible = false;
    var contextLocked = false;
    var environments = {};
    var persistedContextStorageKey = 'glm-panel-context:v1';
    var pendingPersistedContext = null;
    var pendingContextRestoreError = '';
    var contextResolutionPending = false;
    var pendingUi = { operation: '', controlId: '', pending: false };
    var contextActivationPending = false;
    var conflictingServerContext = null;
    var configurationModalOrigin = null;
    var configurationConfirmationAction = null;
    var documentationCurrentPage = 1;
    var documentationPageSize = 25;
    var documentationView = 'cards';

    function useServerApi() {
        return window.location.protocol === 'http:' && typeof window.fetch === 'function';
    }

    function escapeHtml(value) {
        return String(value || '').replace(/[&<>"']/g, function (character) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character];
        });
    }

    function getProperty(object, lowerName, upperName) {
        if (!object) { return ''; }
        return object[lowerName] !== undefined && object[lowerName] !== null ? object[lowerName] : (object[upperName] || '');
    }

    function normalize(value) {
        return String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
    }

    /* ============ CONTEXTO PERSISTIDO ============ */
    function isPersistedContextValid(context) {
        return Boolean(context && typeof context === 'object' &&
            typeof context.clienteId === 'string' && context.clienteId.trim() &&
            typeof context.ambienteId === 'string' && context.ambienteId.trim());
    }

    function readPersistedContext() {
        try {
            var serializedContext = window.localStorage.getItem(persistedContextStorageKey);
            if (!serializedContext) { return null; }
            var context = JSON.parse(serializedContext);
            if (isPersistedContextValid(context)) {
                return { clienteId: context.clienteId, ambienteId: context.ambienteId };
            }
        } catch (error) {
            /* Una clave dañada se trata igual que una estructura inválida. */
        }
        removePersistedContext();
        return null;
    }

    function savePersistedContext(context) {
        if (!isPersistedContextValid(context)) { return false; }
        try {
            window.localStorage.setItem(persistedContextStorageKey, JSON.stringify({
                clienteId: context.clienteId,
                ambienteId: context.ambienteId
            }));
            return true;
        } catch (error) {
            return false;
        }
    }

    function removePersistedContext() {
        try {
            window.localStorage.removeItem(persistedContextStorageKey);
        } catch (error) { }
    }

    function contextsMatch(firstContext, secondContext) {
        return Boolean(firstContext && secondContext &&
            firstContext.clienteId === getProperty(secondContext, 'clienteId', 'ClienteId') &&
            firstContext.ambienteId === getProperty(secondContext, 'ambienteId', 'AmbienteId'));
    }

    function contextExistsInServerList(context, contextList) {
        return Boolean(context && contextList.some(function (availableContext) {
            return availableContext.clienteId === context.clienteId && availableContext.ambienteId === context.ambienteId;
        }));
    }

    function svgIcon(name) {
        var icons = {
            pdf: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/><path d="M9 15h6M9 11h2M9 19h4"/></svg>',
            edit: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M17 3a2.85 2.85 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5z"/></svg>',
            trash: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 6h18M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2m3 0v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6h14zM10 11v6M14 11v6"/></svg>',
             plus: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>',
             info: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/></svg>',
             success: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="m8 12 2.5 2.5L16 9"/></svg>',
             warning: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m12 3 10 18H2L12 3z"/><path d="M12 9v4M12 17h.01"/></svg>',
             error: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="m9 9 6 6M15 9l-6 6"/></svg>',
             view: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12Z"/><circle cx="12" cy="12" r="2.5"/></svg>'
        };
        return icons[name] || '';
    }

    function pdfDownloadButton(pdfName) {
        return '<a class="pdf-download" href="/api/documentos/' + encodeURIComponent(pdfName) + '?download=1" download target="_blank" rel="noopener" title="Descargar PDF" aria-label="Descargar PDF">' + svgIcon('pdf') + '<span>PDF</span></a>';
    }

    function pdfFileName(serviceName) {
        var safeName = String(serviceName || 'documento').replace(/[<>:"/\\|?*\x00-\x1F]/g, '-').replace(/\s+/g, ' ').trim();
        return (safeName || 'documento') + '.pdf';
    }

    function pdfViewButton(pdfName, serviceName) {
        return '<button class="pdf-view" type="button" data-pdf-name="' + escapeHtml(pdfName) + '" data-service-name="' + escapeHtml(serviceName) + '" title="Abrir PDF" aria-label="Abrir PDF">' + svgIcon('pdf') + '<span>PDF</span></button>';
    }

    /* ============ TIPO DE AMBIENTE ============ */
    function clasificarTipo(tipo) {
        var t = String(tipo || '').trim().toLowerCase();
        return (t === 'test' || t === 'prod') ? t : null;
    }

    function nombreAmbienteCanonico(tipo, fallback) {
        var normalized = clasificarTipo(tipo);
        if (normalized === 'prod') { return 'PROD'; }
        if (normalized === 'test') { return 'TEST'; }
        return fallback || '';
    }

    function tipoInfo(tipo) {
        if (tipo === 'prod') { return { etiqueta: 'PROD', cls: 'tag-produccion' }; }
        if (tipo === 'test') { return { etiqueta: 'TEST', cls: 'tag-testing' }; }
        return { etiqueta: String(tipo || ''), cls: '' };
    }

    function tipoPill(tipo) {
        var t = clasificarTipo(tipo);
        if (!t) { return ''; }
        var info = tipoInfo(t);
        return '<span class="tag ' + info.cls + '">' + escapeHtml(info.etiqueta) + '</span>';
    }

    /* ============ ESTADOS EN ESPAÑOL ============ */
    function statusClass(status) {
        status = String(status || '').toUpperCase();
        if (['QUEUED', 'RUNNING', 'PROCESSING', 'EN PROCESO', 'EN_PROCESO'].indexOf(status) >= 0) { return 'badge-progress'; }
        if (['COMPLETED', 'COMPLETADO', 'OK', 'ACTIVO'].indexOf(status) >= 0) { return 'badge-ok'; }
        if (['PARTIAL', 'COMPLETADO PARCIALMENTE', 'WARNING', 'ADVERTENCIA', 'OBSOLETO', 'PENDIENTE', 'CANCELLED', 'CANCELADO', 'ABORTED', 'ABORTADO'].indexOf(status) >= 0) { return 'badge-warning'; }
        if (['FAILED', 'ERROR', 'ELIMINADO'].indexOf(status) >= 0) { return 'badge-danger'; }
        return 'badge-muted';
    }

    function statusLabel(status) {
        status = String(status || '').toUpperCase();
        if (['QUEUED', 'RUNNING', 'PROCESSING', 'EN PROCESO', 'EN_PROCESO'].indexOf(status) >= 0) { return 'En proceso'; }
        if (['COMPLETED', 'COMPLETADO'].indexOf(status) >= 0) { return 'Completado'; }
        if (['OK', 'ACTIVO'].indexOf(status) >= 0) { return 'Ok'; }
        if (['PARTIAL', 'COMPLETADO PARCIALMENTE', 'WARNING', 'ADVERTENCIA', 'OBSOLETO'].indexOf(status) >= 0) { return 'Advertencia'; }
        if (['FAILED', 'ERROR', 'ELIMINADO'].indexOf(status) >= 0) { return 'Error'; }
        if (['CANCELLED', 'CANCELADO', 'ABORTED', 'ABORTADO'].indexOf(status) >= 0) { return 'Cancelado'; }
        if (status === 'OMITIDO') { return 'Omitido'; }
        if (status === 'PENDIENTE') { return 'Pendiente'; }
        if (!status) { return 'Sin estado'; }
        return status;
    }

    function isEnProceso(status) {
        return ['QUEUED', 'RUNNING', 'PROCESSING', 'EN PROCESO', 'EN_PROCESO'].indexOf(String(status || '').toUpperCase()) >= 0;
    }

    function isError(status) {
        return ['FAILED', 'ERROR', 'ELIMINADO'].indexOf(String(status || '').toUpperCase()) >= 0;
    }

    function formatDateTime(value) {
        if (!value) { return ''; }
        var date = new Date(value);
        if (isNaN(date.getTime())) { return String(value); }
        function pad(number) { return String(number).padStart(2, '0'); }
        return date.getFullYear() + '-' + pad(date.getMonth() + 1) + '-' + pad(date.getDate()) + ' ' + pad(date.getHours()) + ':' + pad(date.getMinutes());
    }

    function statusBadge(status) {
        var label = statusLabel(status);
        var cls = statusClass(status);
        var spinner = isEnProceso(status) ? '<span class="spinner sm" aria-hidden="true"></span>' : '';
        return '<span class="badge ' + cls + '">' + spinner + escapeHtml(label) + '</span>';
    }

    /* ============ DROPDOWN PERSONALIZADO ============ */
    function createDropdown(config) {
        var trigger = document.getElementById(config.triggerId);
        var menu = document.getElementById(config.menuId);
        var labelEl = document.getElementById(config.labelId);
        var value = '';
        var disabled = false;
        var options = [];
        var onChange = null;

        function tagPills(tags, label) {
            if (!tags || !tags.length) { return ''; }
            return tags.map(function (t) {
                var info = tipoInfo(t);
                return info.etiqueta === label ? '' : tipoPill(t);
            }).join('');
        }

        function renderTrigger() {
            var selected = null;
            for (var i = 0; i < options.length; i++) { if (options[i].value === value) { selected = options[i]; break; } }
            if (selected) {
                labelEl.innerHTML = '<span class="dropdown-label-text">' + escapeHtml(selected.label) + '</span>' + tagPills(selected.tags, selected.label);
            } else {
                labelEl.textContent = config.placeholder || 'Seleccionar';
            }
            trigger.disabled = disabled;
            trigger.classList.toggle('is-empty', !selected);
        }

        function renderMenu() {
            var html = options.map(function (opt) {
                var active = opt.value === value ? ' is-active' : '';
                return '<button class="dropdown-option' + active + '" type="button" role="option" aria-selected="' + (opt.value === value ? 'true' : 'false') + '" data-value="' + escapeHtml(opt.value) + '"><span class="dropdown-option-label">' + escapeHtml(opt.label) + '</span>' + tagPills(opt.tags, opt.label) + '</button>';
            }).join('');
            menu.innerHTML = html || '<div class="dropdown-empty">Sin opciones</div>';
            menu.querySelectorAll('.dropdown-option').forEach(function (btn) {
                btn.addEventListener('click', function () {
                    setValue(btn.getAttribute('data-value'));
                    close();
                    if (onChange) { onChange(value); }
                });
            });
        }

        function close() {
            menu.hidden = true;
            trigger.setAttribute('aria-expanded', 'false');
        }

        function open() {
            if (disabled) { return; }
            menu.hidden = false;
            trigger.setAttribute('aria-expanded', 'true');
        }

        function setValue(newValue) {
            value = newValue;
            renderTrigger();
            renderMenu();
        }

        trigger.addEventListener('click', function (event) {
            event.stopPropagation();
            if (disabled) { return; }
            if (menu.hidden) { open(); } else { close(); }
        });
        document.addEventListener('click', function (event) {
            if (!trigger.contains(event.target) && !menu.contains(event.target)) { close(); }
        });

        var api = {
            setOptions: function (opts) {
                options = opts || [];
                var stillSelected = options.some(function (o) { return o.value === value; });
                if (!stillSelected) { value = ''; }
                renderTrigger();
                renderMenu();
            },
            get value() { return value; },
            set value(v) { setValue(v); },
            get disabled() { return disabled; },
            set disabled(d) { disabled = Boolean(d); renderTrigger(); close(); },
            setBusy: function (busy) {
                trigger.classList.toggle('loading', Boolean(busy));
                trigger.setAttribute('aria-busy', busy ? 'true' : 'false');
            },
            setOnChange: function (fn) { onChange = fn; }
        };
        renderTrigger();
        renderMenu();
        return api;
    }

    /* ============ CARGA DE CONTEXTOS ============ */
    function loadContextsFromServer() {
        if (!useServerApi()) { return; }
        fetch('/api/contextos', { cache: 'no-store' }).then(function (response) { return response.json(); }).then(function (payload) {
            if (!payload.ok) { return; }
            var clients = {};
            payload.data.contextos.forEach(function (context) {
                clients[context.clienteId] = clients[context.clienteId] || { name: context.clienteNombre, environments: [] };
                clients[context.clienteId].environments.push({ id: context.ambienteId, name: nombreAmbienteCanonico(context.ambienteTipo, context.ambienteNombre), tipo: context.ambienteTipo });
            });
            clientDropdown.setOptions(Object.keys(clients).map(function (clientId) {
                var tipos = [];
                clients[clientId].environments.forEach(function (e) { if (e.tipo && tipos.indexOf(e.tipo) < 0) { tipos.push(e.tipo); } });
                return { value: clientId, label: clients[clientId].name, tags: tipos };
            }));
            environments = Object.keys(clients).reduce(function (result, clientId) { result[clientId] = clients[clientId].environments; return result; }, {});
            var persistedContext = readPersistedContext();
            if (persistedContext && contextExistsInServerList(persistedContext, payload.data.contextos || [])) {
                pendingPersistedContext = persistedContext;
            } else if (persistedContext) {
                removePersistedContext();
                pendingContextRestoreError = 'No se pudo restaurar el contexto guardado porque el cliente o ambiente ya no existe.';
            }
            loadState();
        }).catch(function () { /* El esqueleto sigue funcionando sin servidor. */ });
    }

    function selectEnvironment() {
        var options = (environments[clientDropdown.value] || []).map(function (environment) {
            return { value: environment.id, label: nombreAmbienteCanonico(environment.tipo, environment.name), tags: [environment.tipo] };
        });
        environmentDropdown.setOptions(options);
        environmentDropdown.disabled = options.length === 0;
    }

    /* ============ BLOQUEO DE CONTEXTO ============ */
    function lockContext() {
        contextLocked = true;
        clientDropdown.disabled = true;
        environmentDropdown.disabled = true;
        document.getElementById('change-client').hidden = false;
        document.body.setAttribute('data-context', 'active');
    }

    function unlockContext() {
        contextLocked = false;
        clientDropdown.disabled = false;
        environmentDropdown.disabled = !clientDropdown.value;
        document.getElementById('change-client').hidden = true;
        document.body.setAttribute('data-context', 'none');
        document.getElementById('dashboard-title').textContent = 'Dashboard';
        document.getElementById('state-summary').innerHTML = '';
        document.getElementById('validation-list').innerHTML = '';
        if (window.panelViews) { window.panelViews.dashboard.clear(); window.panelViews.documentation.clearServices(); window.panelViews.logs.clear(); }
    }

    function clearContextDependentState() {
        lastState = null;
        endpointServices = [];
        contextLogs = [];
        selectedFallbackXpz = null;
        exportConsoleVisible = false;
        operationResults.exportar = null;
        document.getElementById('dashboard-title').textContent = 'Dashboard';
        document.getElementById('state-summary').innerHTML = '';
        document.getElementById('validation-list').innerHTML = '';
        renderDocumentation('');
        renderDocumentationServices('');
        renderLogs('todos');
        renderXpzList(null);
        updatePdfPanel(null);
        renderPdfXpzList(null);
        showExportFallback(false);
    }

    function setContextActivationBusy(isBusy) {
        pendingUi = {
            operation: isBusy ? 'ACTIVAR_CONTEXTO' : '',
            controlId: isBusy ? 'environment-dropdown-trigger' : '',
            pending: Boolean(isBusy)
        };
        clientDropdown.disabled = Boolean(isBusy) || contextLocked;
        environmentDropdown.disabled = Boolean(isBusy) || contextLocked || !clientDropdown.value;
        environmentDropdown.setBusy(Boolean(isBusy));
        document.getElementById('change-client').disabled = Boolean(isBusy);
        document.getElementById('change-client').hidden = Boolean(isBusy) || !contextLocked;
    }

    /* ============ NOTIFICACIONES GLOBALES ============ */
    function renderGlobalNotices() {
        var container = document.getElementById('global-notices');
        var notices = [];
        var state = lastState;
        if (state && state.configurationValid === false) {
            notices.push({ type: 'error', text: 'Configuración inválida. Corrige los errores desde Configuración. Las demás solapas están bloqueadas.' });
        } else if (!(state && state.context)) {
            notices.push({ type: 'info', text: 'Debe seleccionar contexto de Cliente y Ambiente' });
        }
        if (state && state.context) {
            var documentedServices = endpointServices.filter(function (service) { return service.pdf && service.pdf.disponible; });
            if (endpointServices.length && documentedServices.length === 0) {
                notices.push({ type: 'warn', text: 'No hay documentación publicada. Inicia el proceso de generación desde la solapa Generar PDF.', action: { label: 'Ir a Generar PDF', tab: 'endpoints' } });
            }
        }
        var work = state && state.work;
        if (work && (String(work.operacion || '').indexOf('EXPORTAR') >= 0 || String(work.operacion || '').indexOf('COMPLETAR') >= 0)) {
            var detail = formatDateTime(work.fin || work.inicio) + (work.error ? ' | ' + work.error : '');
            var visibleStatus = work.estadoVisible || work.estado;
            notices.push({ type: isError(visibleStatus) ? 'error' : 'ok', text: 'Último resultado: ' + visibleStatus + (detail ? ' — ' + detail : '') });
            var dashboardXpz = state.dashboard && state.dashboard.xpz;
            if (isError(visibleStatus) && dashboardXpz && !dashboardXpz.activo) {
                notices.push({ type: 'warn', text: 'No se produjo un XPZ válido. Puedes exportarlo manualmente y seleccionarlo desde Generar PDF.', action: { label: 'Ir a Generar PDF', tab: 'endpoints' } });
            }
        }
        container.innerHTML = notices.filter(function (notice) {
            return !dismissedNoticeKeys[notice.type + '|' + notice.text];
        }).map(function (notice) {
            var action = notice.action ? '<button type="button" class="notice-action" data-target-tab="' + escapeHtml(notice.action.tab) + '">' + escapeHtml(notice.action.label) + '</button>' : '';
            var iconType = notice.type === 'ok' ? 'success' : (notice.type === 'warn' ? 'warning' : notice.type);
            var key = notice.type + '|' + notice.text;
            return '<div class="notice notice-' + notice.type + '" data-notice-key="' + escapeHtml(key) + '"><span class="notice-icon" aria-hidden="true">' + svgIcon(iconType) + '</span><span class="notice-text">' + escapeHtml(notice.text) + '</span>' + action + '<button type="button" class="notice-close" aria-label="Cerrar mensaje">&times;</button></div>';
        }).join('');
        container.querySelectorAll('.notice-action').forEach(function (button) {
            button.addEventListener('click', function () { selectTab(button.getAttribute('data-target-tab')); });
        });
        container.querySelectorAll('.notice-close').forEach(function (button) {
            button.addEventListener('click', function () {
                var notice = button.closest('.notice');
                dismissedNoticeKeys[notice.getAttribute('data-notice-key')] = true;
                notice.classList.add('is-closing');
                window.setTimeout(function () { notice.remove(); }, 180);
            });
        });
    }

    /* ============ DASHBOARD ============ */
    function updatePdfPanel(xpz) {
        var message = document.getElementById('pdf-xpz-message');
        var actions = document.getElementById('pdf-actions');
        var hasActive = Boolean(xpz && xpz.activo);
        if (hasActive) {
            message.innerHTML = 'XPZ seleccionado: <span class="tag tag-selected">' + escapeHtml(xpz.activo.nombre) + '</span>';
        } else {
            message.textContent = 'Selecciona un XPZ del ambiente para generar los PDF.';
        }
        message.hidden = Boolean(currentJobId);
        document.getElementById('pdf-xpz-list').hidden = Boolean(currentJobId);
        actions.hidden = !hasActive;
        document.getElementById('generate-pdf').disabled = !hasActive || Boolean(currentJobId);
    }

    function selectPdfXpz(name, button) {
        if (!useServerApi() || currentJobId) { return; }
        document.querySelectorAll('.pdf-xpz-option').forEach(function (row) { row.classList.remove('is-selected'); });
        if (button) { button.closest('.pdf-xpz-option').classList.add('is-selected'); }
        fetch('/api/xpz/activar', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-Panel-Token': window.PANEL_TOKEN || '' },
            body: JSON.stringify({ nombre: name })
        }).then(function (response) { return response.json(); }).then(function (payload) {
            if (!payload.ok) { throw new Error(payload.error || 'No se pudo seleccionar el XPZ.'); }
            showToast('XPZ seleccionado.', 'ok');
            if (payload.jobId) {
                currentJobId = payload.jobId;
                setWorkBusy(true);
                pollWork();
            }
            loadState();
        }).catch(function (error) { showToast(error.message, 'err'); });
    }

    function renderPdfXpzList(xpz) {
        var list = document.getElementById('pdf-xpz-list');
        var candidates = (xpz && xpz.disponibles) || [];
        var activeName = xpz && xpz.activo ? xpz.activo.nombre : '';
        list.innerHTML = candidates.length ? candidates.map(function (candidate) {
            var recent = candidate.principal ? '<span class="tag tag-recent">RECIENTE</span>' : '';
            var processed = candidate.procesado ? '<span class="tag tag-processed">YA PROCESADO</span>' : '';
            var selected = (candidate.nombre === activeName || (!activeName && candidate.principal)) ? ' is-selected' : '';
            return '<div class="file-row pdf-xpz-option' + selected + '"><span class="pdf-xpz-meta"><strong>' + escapeHtml(candidate.nombre) + '</strong><span class="pdf-xpz-subtitle"><small>' + escapeHtml(formatDateTime(candidate.fecha)) + '</small>' + recent + processed + '</span></span><span class="pdf-xpz-actions"><button class="choose-pdf-xpz" type="button" data-xpz-name="' + escapeHtml(candidate.nombre) + '">Seleccionar</button></span></div>';
        }).join('') : '<div class="empty-state">No hay XPZ disponibles en este ambiente.</div>';
        list.querySelectorAll('.choose-pdf-xpz').forEach(function (button) {
            button.addEventListener('click', function () { selectPdfXpz(button.getAttribute('data-xpz-name'), button); });
        });
    }

    function renderDashboard(stateData) {
        var dashboard = stateData && stateData.dashboard;
        var summary = document.getElementById('state-summary');
        if (!dashboard || !dashboard.contexto) {
            summary.innerHTML = '';
            document.getElementById('validation-list').innerHTML = '';
            updatePdfPanel(null);
            renderPdfXpzList(null);
            return;
        }
        var context = dashboard.contexto;
        var clientName = getProperty(context, 'clienteNombre', 'ClienteNombre') || getProperty(context, 'clienteId', 'ClienteId');
        var environmentName = nombreAmbienteCanonico(getProperty(context, 'ambienteTipo', 'AmbienteTipo'), getProperty(context, 'ambienteNombre', 'AmbienteNombre')) || getProperty(context, 'ambienteId', 'AmbienteId');
        var environmentTipo = getProperty(context, 'ambienteTipo', 'AmbienteTipo');
        var documents = dashboard.documentos || {};
        var processing = dashboard.procesamiento || {};
        var validaciones = dashboard.validaciones || [];

        document.getElementById('dashboard-title').textContent = 'Dashboard ' + clientName + ' - ' + environmentName;

        var ultimaActualizacion = processing.ultimaActualizacion ? formatDateTime(processing.ultimaActualizacion) : 'No registrada';
        var items = [
            { label: 'Cliente', value: clientName },
            { label: 'Ambiente', value: environmentName, tag: environmentTipo },
            { label: 'Documentos', value: String(documents.total || 0) + ' PDF' },
            { label: 'Últ. actualización', value: ultimaActualizacion },
            { label: 'KB', value: getProperty(context, 'kbPath', 'KbPath') || 'No disponible' }
        ];
        summary.innerHTML = items.map(function (item) {
            var tag = item.tag ? ' · ' + item.tag : '';
            if (item.label === 'KB') {
                return '<glm-stat-card class="summary-item-kb" label="KB" value="' + escapeHtml(item.value) + '" detail="Ruta de la Knowledge Base"></glm-stat-card>';
            }
            return '<glm-stat-card label="' + escapeHtml(item.label) + '" value="' + escapeHtml(item.value) + '" detail="' + escapeHtml(tag.replace(/^ · /, '')) + '"></glm-stat-card>';
        }).join('');

        document.getElementById('validation-list').innerHTML = validaciones.map(function (item) {
            return '<div class="validation-item"><span class="v-name">' + escapeHtml(item.item) + '</span>' + statusBadge(item.estado) + '<span class="v-msg">' + escapeHtml(item.mensaje) + '</span></div>';
        }).join('');

        updateExportActions(processing, dashboard.xpz || {});
        var xpz = dashboard.xpz || {};
        updatePdfPanel(xpz);
        renderPdfXpzList(xpz);
    }

    function updateExportActions(processing, xpz) {
        var processed = Boolean(processing && processing.procesado);
        document.getElementById('export-state').textContent = processed ? 'PROCESADO' : 'SIN PROCESAR';
        document.getElementById('export-state').className = 'badge ' + (processed ? 'badge-ok' : 'badge-muted');
        exportButton.hidden = processed;
        updateServicesButton.hidden = !processed;
        document.getElementById('export-action-title').textContent = processed ? 'Actualizar servicios' : 'Exportar XPZ';
        document.getElementById('export-action-description').textContent = processed ? 'Obtiene el XPZ de la Knowledge Base o permite seleccionar uno existente del ambiente. No genera documentación.' : 'Genera un XPZ nuevo desde la Knowledge Base del ambiente activo.';
        if (selectedFallbackXpz) { document.getElementById('fallback-selected-actions').hidden = false; }
    }

    function updateGlobalWorkIndicator(work) {
        var jobOperation = document.getElementById('job-operation');
        if (jobOperation) {
            jobOperation.textContent = work && work.operacion ? String(work.operacion).replace(/_/g, ' ') : 'Trabajo en curso…';
        }
    }

    function applyTabAvailability(stateData) {
        var hasContext = Boolean(stateData && stateData.context);
        var configurationValid = !stateData || stateData.configurationValid !== false;
        document.querySelectorAll('.tab').forEach(function (tab) {
            var allowed = tab.dataset.tab === 'estado' || (hasContext && configurationValid);
            tab.disabled = !allowed;
            tab.setAttribute('aria-disabled', allowed ? 'false' : 'true');
        });
    }

    /* ============ ESTADO GLOBAL ============ */
    function loadState() {
        if (!useServerApi()) { return; }
        fetch('/api/estado', { cache: 'no-store' }).then(function (response) { return response.json(); }).then(function (payload) {
            if (!payload.ok) { return; }
            var serverContext = payload.data.context;
            if (contextResolutionPending) { return; }
            if (pendingPersistedContext && serverContext && !contextsMatch(pendingPersistedContext, serverContext)) {
                contextResolutionPending = true;
                conflictingServerContext = serverContext;
                showContextConflictModal(pendingPersistedContext, serverContext);
                return;
            }
            if (pendingPersistedContext && !serverContext) {
                clientDropdown.value = pendingPersistedContext.clienteId;
                selectEnvironment();
                environmentDropdown.value = pendingPersistedContext.ambienteId;
                pendingPersistedContext = null;
                activateContext();
                return;
            }
            lastState = payload.data;
            renderDashboard(payload.data);
            applyTabAvailability(payload.data);
            var restoredWork = payload.data.work;
            if (restoredWork && isEnProceso(restoredWork.estado)) {
                var restoredOperation = String(restoredWork.operacion || '');
                if (restoredOperation.indexOf('PDF') >= 0) {
                    pdfConsoleVisible = true;
                    document.getElementById('pdf-work-card').setAttribute('operation', 'generarPdf');
                } else if (restoredOperation.indexOf('EXPORTAR') >= 0 || restoredOperation.indexOf('COMPLETAR') >= 0 || restoredOperation.indexOf('VALIDAR') >= 0) {
                    exportConsoleVisible = true;
                    document.getElementById('export-work-card').setAttribute('operation', restoredOperation.indexOf('VALIDAR') >= 0 ? 'validarXpz' : 'exportar');
                }
            }
            renderWork(payload.data.work);
            handleWorkResult(payload.data.work);
            updateGlobalWorkIndicator(payload.data.work);
            var context = payload.data.context;
            if (context) {
                var clientId = getProperty(context, 'clienteId', 'ClienteId');
                var environmentId = getProperty(context, 'ambienteId', 'AmbienteId');
                if (clientDropdown.value !== clientId) { clientDropdown.value = clientId; selectEnvironment(); }
                if (environmentDropdown.value !== environmentId) { environmentDropdown.value = environmentId; }
                lockContext();
                setWorkBusy(false);
                loadXpz();
                loadContextArtifacts();
                if (payload.data.xpz && payload.data.xpz.activo) { loadServices(); } else { endpointServices = []; renderDocumentationServices(document.getElementById('documentation-filter').value); renderDocumentation(document.getElementById('documentation-filter').value); renderGlobalNotices(); }
            } else {
                unlockContext();
                setWorkBusy(false);
                renderGlobalNotices();
            }
            if (pendingContextRestoreError) {
                var restoreError = pendingContextRestoreError;
                pendingContextRestoreError = '';
                showContextRestoreError(restoreError);
            }
            if (payload.data.work && isEnProceso(payload.data.work.estado) && !currentJobId) {
                currentJobId = payload.data.work.id;
                setWorkBusy(true);
                pollWork();
            }
        }).catch(function () { /* El panel conserva su estado local si la API no responde. */ });
    }

    function handleWorkResult(work) {
        updateOperationResult(work);
        renderGlobalNotices();
        if (!work || (String(work.operacion || '').indexOf('EXPORTAR') < 0 && String(work.operacion || '').indexOf('COMPLETAR') < 0)) { return; }
        if (exportConsoleVisible && isError(work.estado)) { showExportFallback(true); loadXpz(); }
    }

    function updateOperationResult(work) {
        var key = getOperationKey(work);
        if (!key) { return; }
        if (key === 'exportar' && !exportConsoleVisible) { return; }
        var visibleStatus = work.estadoVisible || work.estado;
        var tagId = key === 'exportar' ? 'export-state' : 'pdf-generation-state';
        var tag = document.getElementById(tagId);
        if (tag) {
            tag.textContent = visibleStatus || 'SIN ACTIVIDAD';
            tag.className = 'badge ' + statusClass(visibleStatus);
        }
        renderOperationConsole(key);
    }

    /* ============ XPZ ============ */
    function renderXpzList(data) {
        var candidates = (data && data.xpz) || [];
        document.getElementById('fallback-xpz-list').innerHTML = candidates.length ? candidates.map(function (xpz) {
            var recent = xpz.principal ? '<span class="tag tag-recent">RECIENTE</span>' : '';
            var processed = xpz.procesado ? '<span class="tag tag-processed">YA PROCESADO</span>' : '';
            return '<div class="file-row xpz-option"><span class="xpz-meta"><strong>' + escapeHtml(xpz.nombre) + '</strong><span class="xpz-subtitle"><small>' + escapeHtml(new Date(xpz.fecha).toLocaleString('es-AR')) + '</small>' + recent + processed + '</span></span><span class="xpz-actions"><button class="choose-xpz" type="button" data-xpz-name="' + escapeHtml(xpz.nombre) + '">Seleccionar</button><button class="validate-xpz-option" type="button" data-xpz-name="' + escapeHtml(xpz.nombre) + '"><span class="btn-spinner" aria-hidden="true"></span><span class="label-idle">Validar XPZ</span><span class="label-busy">Validando…</span></button></span></div>';
        }).join('') : '<div class="empty-state">No hay XPZ disponibles en este ambiente.</div>';
        if (!candidates.length) { return; }
        document.querySelectorAll('.choose-xpz').forEach(function (button) {
            button.addEventListener('click', function () {
                selectedFallbackXpz = button.getAttribute('data-xpz-name');
                document.getElementById('fallback-selected-actions').hidden = false;
                document.querySelectorAll('.xpz-option').forEach(function (row) { row.classList.remove('is-selected'); });
                button.closest('.xpz-option').classList.add('is-selected');
            });
        });
        document.querySelectorAll('.validate-xpz-option').forEach(function (button) {
            button.addEventListener('click', function () { startValidation(button.getAttribute('data-xpz-name'), button); });
        });
    }

    function loadXpz() {
        if (!useServerApi() || !(clientDropdown.value && environmentDropdown.value)) {
            renderXpzList(null);
            return;
        }
        fetch('/api/xpz', { cache: 'no-store' }).then(function (response) { return response.json(); }).then(function (payload) {
            if (payload.ok) { renderXpzList(payload.data); }
        }).catch(function () { renderXpzList(null); });
    }

    function showExportFallback(show) {
        exportFallback.hidden = !show;
        if (!show) { selectedFallbackXpz = null; document.getElementById('fallback-selected-actions').hidden = true; }
    }

    function startExport(body, withConsole) {
        if (!useServerApi() || currentJobId) { return; }
        exportConsoleVisible = Boolean(withConsole);
        document.getElementById('export-work-card').setAttribute('operation', 'exportar');
        fetch('/api/exportar', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-Panel-Token': window.PANEL_TOKEN || '' },
            body: JSON.stringify(body || {})
        }).then(function (response) { return response.json(); }).then(function (payload) {
            if (!payload.ok) { throw new Error(payload.error || 'No se pudo iniciar la exportación.'); }
            currentJobId = payload.data.jobId;
            showExportFallback(false);
            setWorkBusy(true);
            showToast('Exportación iniciada.', 'info');
            pollWork();
        }).catch(function (error) { setButtonLoading(exportButton, false); setButtonLoading(updateServicesButton, false); setButtonLoading(document.getElementById('continue-operation'), false); showExportFallback(true); loadXpz(); showToast(error.message, 'err'); });
    }

    function abortOperation(jobId) {
        if (!useServerApi() || !currentJobId || String(currentJobId) !== String(jobId)) { return; }
        window.clearTimeout(pollingTimer);
        pollingTimer = null;
        fetch('/api/trabajos/' + encodeURIComponent(jobId) + '/cancelar', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-Panel-Token': window.PANEL_TOKEN || '' },
            body: '{}'
        }).then(function (response) { return response.json(); }).then(function (payload) {
            if (!payload.ok) { throw new Error(payload.error || 'No se pudo cancelar la operación.'); }
            renderWork(payload.data);
            handleWorkResult(payload.data);
            showToast('Operación cancelada. Se terminó el árbol de procesos.', 'warn');
            pollWork();
        }).catch(function (error) {
            showToast(error.message, 'err');
            pollWork();
        });
    }

    /* ============ SERVICIOS / DOCUMENTACIÓN ============ */
    function loadServices() {
        if (!useServerApi()) { return; }
        document.getElementById('documentation-loading').hidden = false;
        document.getElementById('documentation-empty').hidden = true;
        Promise.all([fetch('/api/servicios', { cache: 'no-store' }).then(function (response) { return response.json(); }), fetch('/api/documentos', { cache: 'no-store' }).then(function (response) { return response.json(); })]).then(function (responses) {
            document.getElementById('documentation-loading').hidden = true;
            var servicePayload = responses[0];
            var documentPayload = responses[1];
            if (servicePayload.ok) {
                endpointServices = servicePayload.data.servicios || [];
                publishedDocuments = (documentPayload.ok ? documentPayload.data.documentos : []) || [];
                var knownPdfNames = {};
                endpointServices.forEach(function (service) { if (service.pdf && service.pdf.nombre) { knownPdfNames[service.pdf.nombre] = true; } });
                publishedDocuments.filter(function (file) { return file.extension === '.pdf' && !knownPdfNames[file.nombre]; }).forEach(function (file) {
                    endpointServices.push({ nombre: file.servicioNombre || file.nombre.replace(/\.pdf$/i, ''), descripcion: file.descripcion || 'Documento publicado', fullyQualifiedName: '', endpoint: file.endpoint || '', estado: 'ACTIVO', version: file.version || null, versionDisponible: Boolean(file.version), fecha: file.modificado, pdf: { disponible: true, nombre: file.nombre } });
                });
                renderDocumentationServices(document.getElementById('documentation-filter').value);
                renderDocumentation(document.getElementById('documentation-filter').value);
                renderGlobalNotices();
            }
        }).catch(function () { document.getElementById('documentation-loading').hidden = true; endpointServices = []; publishedDocuments = []; renderDocumentationServices(document.getElementById('documentation-filter').value); renderDocumentation(document.getElementById('documentation-filter').value); });
    }

    function renderDocumentationServices(filter) {
        var normalizedFilter = normalize(filter);
        var filteredServices = endpointServices.filter(function (service) {
            var status = service.estado || '';
            return !normalizedFilter || normalize(service.nombre).indexOf(normalizedFilter) >= 0 || normalize(service.fullyQualifiedName).indexOf(normalizedFilter) >= 0 || normalize(status).indexOf(normalizedFilter) >= 0;
        });
        var availableDocuments = filteredServices.filter(function (service) { return service.pdf && service.pdf.disponible; }).length;
        document.getElementById('documentation-stats').innerHTML = '<glm-stat-card label="Servicios" value="' + filteredServices.length + '" detail="Coincidencias del inventario"></glm-stat-card><glm-stat-card label="Documentados" value="' + availableDocuments + '" detail="PDF disponibles"></glm-stat-card><glm-stat-card label="Sin documento" value="' + (filteredServices.length - availableDocuments) + '" detail="Requieren generación"></glm-stat-card>';
        var serviceList = document.getElementById('documentation-service-list');
        serviceList.hidden = true;
        serviceList.innerHTML = '';
    }

    function saveDocumentationPreferences() {
        if (!window.panelUiPreferences) { return; }
        var preferences = window.panelUiPreferences.read();
        preferences.views.documentacion = documentationView;
        preferences.pageSize.documentacion = documentationPageSize;
        preferences.filters.documentacion = document.getElementById('documentation-filter').value;
        window.panelUiPreferences.save(preferences);
        window.panelUiPreferences.current = preferences;
    }

    function renderDocumentation(filter) {
        var normalizedFilter = normalize(filter);
        var filteredServices = endpointServices.filter(function (service) {
            var status = service.estado || '';
            return !normalizedFilter || normalize(service.nombre).indexOf(normalizedFilter) >= 0 || normalize(service.fullyQualifiedName).indexOf(normalizedFilter) >= 0 || normalize(status).indexOf(normalizedFilter) >= 0;
        });
        var pdfServices = filteredServices.filter(function (service) { return service.pdf && service.pdf.disponible; });
        document.getElementById('documentation-empty').hidden = pdfServices.length > 0;
        var totalPages = Math.max(1, Math.ceil(pdfServices.length / documentationPageSize));
        documentationCurrentPage = Math.min(documentationCurrentPage, totalPages);
        var start = (documentationCurrentPage - 1) * documentationPageSize;
        var visiblePdfServices = pdfServices.slice(start, start + documentationPageSize);
        var pagination = document.getElementById('documentation-pagination');
        pagination.hidden = pdfServices.length <= documentationPageSize;
        document.getElementById('documentation-page-label').textContent = 'Página ' + documentationCurrentPage + ' de ' + totalPages;
        document.getElementById('documentation-previous-page').disabled = documentationCurrentPage <= 1;
        document.getElementById('documentation-next-page').disabled = documentationCurrentPage >= totalPages;
        document.getElementById('documentation-pdf-list').innerHTML = visiblePdfServices.map(function (service) {
            var pdfName = service.pdf.nombre;
            var date = service.fecha ? formatDateTime(service.fecha) : 'Sin fecha';
            var versionHeader = service.versionDisponible ? 'Versión ' + service.version : 'Sin versión';
            var observacionHtml = '';
            if (service.versionDisponible) {
                var revision = parseInt(String(service.version).split('.')[1], 10);
                if (!isNaN(revision) && revision >= 1 && service.observacion) {
                    observacionHtml = '<span class="doc-obs">' + escapeHtml(service.observacion) + '</span>';
                }
            }
            return '<div class="doc-row">' +
                '<span class="doc-meta"><span class="doc-name">' + escapeHtml(service.nombre) + '</span>' +
                '<span class="doc-desc">' + escapeHtml(service.descripcion) + ' · ' + escapeHtml(pdfName) + ' · ' + escapeHtml(date) + '</span></span>' +
                '<span class="doc-actions"><span class="doc-version">' + escapeHtml(versionHeader) + '</span>' + observacionHtml + pdfViewButton(pdfName, service.nombre) + '</span>' +
                '</div>';
        }).join('');
        document.getElementById('documentation-state').textContent = pdfServices.length + ' PDF';
        document.getElementById('documentation-state').className = 'badge ' + (pdfServices.length ? 'badge-ok' : 'badge-muted');
    }

    function showPdfViewer(pdfName, serviceName) {
        var dialog = document.getElementById('pdf-viewer-dialog');
        var frame = document.getElementById('pdf-viewer-frame');
        document.getElementById('pdf-viewer-title').textContent = serviceName || 'Documento PDF';
        frame.src = '/api/documentos/' + encodeURIComponent(pdfName) + '?view=1&v=' + Date.now() + '#toolbar=1&view=FitH';
        if (typeof dialog.showModal === 'function') { dialog.showModal(); }
        else { dialog.setAttribute('open', ''); }
    }

    function closePdfViewer() {
        var dialog = document.getElementById('pdf-viewer-dialog');
        var frame = document.getElementById('pdf-viewer-frame');
        if (dialog.open) { dialog.close(); }
        frame.src = 'about:blank';
    }

    /* ============ TRABAJO / CONSOLAS ============ */
    function setButtonLoading(button, loading) {
        if (!button) { return; }
        button.classList.toggle('loading', loading);
        button.disabled = loading;
    }

    function setWorkBusy(isBusy) {
        clientDropdown.disabled = isBusy || contextLocked;
        environmentDropdown.disabled = isBusy || contextLocked || !clientDropdown.value;
        document.getElementById('change-client').hidden = isBusy;
        exportButton.disabled = isBusy || !(clientDropdown.value && environmentDropdown.value);
        updateServicesButton.disabled = isBusy || !(clientDropdown.value && environmentDropdown.value);
        document.getElementById('generate-pdf').disabled = isBusy || !(lastState && lastState.xpz && lastState.xpz.activo);
        if (isBusy) { document.getElementById('documentation-running').hidden = false; }
        document.body.setAttribute('data-job', isBusy ? 'on' : 'off');
        document.getElementById('pdf-xpz-info').hidden = isBusy;
        document.getElementById('pdf-xpz-list').hidden = isBusy;
    }

    function getOperationKey(work) {
        var operation = String(work && work.operacion || '');
        if (operation.indexOf('PDF') >= 0) { return 'generarPdf'; }
        if (operation.indexOf('EXPORTAR') >= 0 || operation.indexOf('COMPLETAR') >= 0 || operation.indexOf('VALIDAR') >= 0) { return 'exportar'; }
        return '';
    }

    function renderOperationConsole(key) {
        var prefix = key === 'exportar' ? 'export' : 'pdf';
        var visible = key === 'exportar' ? exportConsoleVisible : pdfConsoleVisible;
        var card = document.getElementById(prefix + '-work-card');
        var work = operationResults[key];
        card.hidden = !visible;
        if (!visible) { return; }
        card.data = work;
    }

    function renderWork(work) {
        var key = getOperationKey(work);
        if (key) { operationResults[key] = work; }
        renderOperationConsole('exportar');
        renderOperationConsole('generarPdf');
    }

    function showPdfRunning(running) {
        document.getElementById('pdf-running').hidden = !running;
        document.getElementById('pdf-actions').hidden = running || !(lastState && lastState.xpz && lastState.xpz.activo);
    }

    function pollWork() {
        if (!currentJobId) { return; }
        fetch('/api/trabajos/' + encodeURIComponent(currentJobId), { cache: 'no-store' }).then(function (response) { return response.json(); }).then(function (payload) {
            if (!payload.ok) { throw new Error(payload.error || 'No se pudo consultar el trabajo.'); }
            var op = String(payload.data.operacion || '');
            renderWork(payload.data);
            handleWorkResult(payload.data);
            var isExportOp = op.indexOf('EXPORTAR') >= 0 || op.indexOf('COMPLETAR') >= 0;
            showPdfRunning(isEnProceso(payload.data.estado) && isExportOp);
            if (isEnProceso(payload.data.estado)) {
                if (op.indexOf('PDF') >= 0) { loadServices(); }
                pollingTimer = window.setTimeout(pollWork, 1500);
                return;
            }
            currentJobId = null;
            setWorkBusy(false);
            document.getElementById('documentation-running').hidden = true;
            showPdfRunning(false);
            setButtonLoading(exportButton, false);
            setButtonLoading(updateServicesButton, false);
            setButtonLoading(document.getElementById('generate-pdf'), false);
            setButtonLoading(document.getElementById('continue-operation'), false);
            document.getElementById('continue-operation').disabled = false;
            document.getElementById('abort-export').disabled = false;
            document.querySelectorAll('.validate-xpz-option').forEach(function (button) { setButtonLoading(button, false); button.disabled = false; });
            loadState();
            updateGlobalWorkIndicator(payload.data);
            var isExportOperation = op.indexOf('EXPORTAR') >= 0 || op.indexOf('COMPLETAR') >= 0 || op.indexOf('VALIDAR') >= 0;
            if (isExportOperation) { loadXpz(); }
            else { loadServices(); }
            renderDocumentation(document.getElementById('documentation-filter').value);
            var finalStatus = payload.data.estadoVisible || payload.data.estado;
            var finalMessage = 'Trabajo finalizado: ' + finalStatus + ' (' + payload.data.contextId + ').';
            if (payload.data.error) { finalMessage += ' ' + payload.data.error; }
            var normalizedFinalStatus = String(finalStatus || '').toUpperCase();
            var isWarningStatus = normalizedFinalStatus.indexOf('PARCIAL') >= 0 || ['CANCELADO', 'CANCELLED', 'ABORTED', 'ABORTADO', 'ADVERTENCIA'].indexOf(normalizedFinalStatus) >= 0;
            showToast(finalMessage, isError(finalStatus) ? 'err' : (isWarningStatus ? 'warn' : 'ok'));
        }).catch(function () {
            pollingTimer = window.setTimeout(pollWork, 2000);
        });
    }

    function startValidation(xpzName, button) {
        if (!useServerApi() || currentJobId || !(clientDropdown.value && environmentDropdown.value)) { return; }
        exportConsoleVisible = true;
        document.getElementById('export-work-card').setAttribute('operation', 'validarXpz');
        document.querySelectorAll('.validate-xpz-option').forEach(function (item) { item.disabled = true; });
        document.getElementById('continue-operation').disabled = true;
        document.getElementById('abort-export').disabled = true;
        setButtonLoading(button, true);
        fetch('/api/validar', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-Panel-Token': window.PANEL_TOKEN || '' },
            body: JSON.stringify(xpzName ? { nombre: xpzName } : {})
        }).then(function (response) { return response.json(); }).then(function (payload) {
            if (!payload.ok) { throw new Error(payload.error || 'No se pudo iniciar la validación.'); }
            currentJobId = payload.data.jobId;
            setWorkBusy(true);
            showToast('Trabajo iniciado: ' + currentJobId + '.', 'info');
            pollWork();
        }).catch(function (error) { setButtonLoading(button, false); document.querySelectorAll('.validate-xpz-option').forEach(function (item) { item.disabled = false; }); document.getElementById('continue-operation').disabled = false; document.getElementById('abort-export').disabled = false; showToast(error.message, 'err'); });
    }

    function startPdfGeneration() {
        document.getElementById('pdf-warning').hidden = false;
    }

    function confirmPdfGeneration() {
        if (!useServerApi() || currentJobId) { return; }
        var confirmButton = document.getElementById('confirm-pdf-generation');
        var dashboardXpz = lastState && lastState.dashboard && lastState.dashboard.xpz;
        var activeXpz = dashboardXpz && dashboardXpz.activo;
        var activeXpzHash = dashboardXpz && dashboardXpz.sha256;
        if (!activeXpz || !activeXpzHash) { showToast('No hay un XPZ activo confirmado.', 'err'); return; }
        pdfConsoleVisible = true;
        document.getElementById('pdf-work-card').setAttribute('operation', 'generarPdf');
        operationResults.generarPdf = null;
        document.getElementById('pdf-warning').hidden = true;
        setButtonLoading(confirmButton, true);
        renderOperationConsole('generarPdf');
        fetch('/api/generar-pdf', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Panel-Token': window.PANEL_TOKEN || '' }, body: JSON.stringify({ scope: 'BATCH', confirmRestart: true, xpz: { nombre: activeXpz.nombre, sha256: activeXpzHash } }) }).then(function (response) { return response.json(); }).then(function (payload) {
            if (!payload.ok) { throw new Error(payload.error || 'No se pudo iniciar la generación de PDF.'); }
            currentJobId = payload.data.jobId;
            setWorkBusy(true);
            setButtonLoading(document.getElementById('generate-pdf'), true);
            showToast('Generación de PDF iniciada.', 'info');
            pollWork();
        }).catch(function (error) {
            document.getElementById('pdf-warning').hidden = false;
            setButtonLoading(confirmButton, false);
            showToast(error.message, 'err');
        });
    }

    function showToast(message, type) {
        var toast = document.createElement('div');
        var iconType = type === 'ok' ? 'success' : (type === 'warn' ? 'warning' : type === 'err' ? 'error' : 'info');
        toast.className = 'toast toast-' + (type || 'info');
        toast.setAttribute('role', 'status');
        toast.setAttribute('aria-live', 'polite');
        toast.innerHTML = '<span class="toast-icon" aria-hidden="true">' + svgIcon(iconType) + '</span><span class="toast-message">' + escapeHtml(message) + '</span><button class="toast-close" type="button" aria-label="Cerrar mensaje">&times;</button><span class="toast-duration" aria-hidden="true"></span>';
        var timer;
        var dismiss = function () {
            if (toast.classList.contains('is-closing')) { return; }
            window.clearTimeout(timer);
            toast.classList.add('is-closing');
            window.setTimeout(function () { toast.remove(); }, 300);
        };
        toast.querySelector('.toast-close').addEventListener('click', dismiss);
        document.body.appendChild(toast);
        timer = window.setTimeout(dismiss, 4500);
    }

    function closeContextModal() {
        document.getElementById('context-modal').hidden = true;
    }

    function configureContextModal(message, showConflictActions) {
        document.getElementById('context-modal-message').textContent = message;
        document.getElementById('use-saved-context').hidden = !showConflictActions;
        document.getElementById('use-server-context').hidden = !showConflictActions;
        document.getElementById('context-modal').hidden = false;
    }

    function showContextRestoreError(message) {
        document.getElementById('context-modal-title').textContent = 'No se pudo restaurar el contexto';
        configureContextModal(message, false);
    }

    function showContextConflictModal(savedContext, serverContext) {
        document.getElementById('context-modal-title').textContent = 'Conflicto de contexto';
        configureContextModal('El contexto guardado en este navegador es distinto del contexto activo en el servidor. Elige cuál debe prevalecer.', true);
    }

    function useSavedContext() {
        if (!pendingPersistedContext) { return; }
        var savedContext = pendingPersistedContext;
        contextResolutionPending = false;
        conflictingServerContext = null;
        pendingPersistedContext = null;
        clientDropdown.value = savedContext.clienteId;
        selectEnvironment();
        environmentDropdown.value = savedContext.ambienteId;
        closeContextModal();
        activateContext();
    }

    function useServerContext() {
        if (!conflictingServerContext) { return; }
        var serverContext = conflictingServerContext;
        var serverContextIds = {
            clienteId: getProperty(serverContext, 'clienteId', 'ClienteId'),
            ambienteId: getProperty(serverContext, 'ambienteId', 'AmbienteId')
        };
        savePersistedContext(serverContextIds);
        contextResolutionPending = false;
        conflictingServerContext = null;
        pendingPersistedContext = null;
        clientDropdown.value = serverContextIds.clienteId;
        selectEnvironment();
        environmentDropdown.value = serverContextIds.ambienteId;
        closeContextModal();
        loadState();
    }

    /* ============ ACTIVAR CONTEXTO ============ */
    function activateContext() {
        var active = Boolean(clientDropdown.value && environmentDropdown.value);
        if (active && useServerApi() && !contextActivationPending) {
            clearContextDependentState();
            contextActivationPending = true;
            setContextActivationBusy(true);
            fetch('/api/contexto/activar', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-Panel-Token': window.PANEL_TOKEN || '' },
                body: JSON.stringify({ clienteId: clientDropdown.value, ambienteId: environmentDropdown.value })
            }).then(function (response) { return response.json(); }).then(function (payload) {
                if (payload.ok) {
                    savePersistedContext({ clienteId: clientDropdown.value, ambienteId: environmentDropdown.value });
                    lockContext();
                    contextActivationPending = false;
                    setContextActivationBusy(false);
                    setWorkBusy(false);
                    var selectedEnvironment = (environments[clientDropdown.value] || []).filter(function (item) { return item.id === environmentDropdown.value; })[0];
                    var activeEnvironmentType = payload.data.ambienteTipo || (selectedEnvironment && selectedEnvironment.tipo);
                    showToast('Contexto activo: ' + payload.data.clienteNombre + ' / ' + nombreAmbienteCanonico(activeEnvironmentType, payload.data.ambienteNombre), 'ok');
                    if (payload.data && payload.data.xpz && payload.data.xpz.activo) { loadServices(); } else { endpointServices = []; renderDocumentationServices(''); renderDocumentation(''); }
                    loadState();
                    if (payload.jobId) { currentJobId = payload.jobId; setWorkBusy(true); pollWork(); }
                } else {
                    removePersistedContext();
                    contextActivationPending = false;
                    setContextActivationBusy(false);
                    unlockContext();
                    showToast(payload.error || 'No se pudo activar el contexto.', 'err');
                }
            }).catch(function () {
                removePersistedContext();
                contextActivationPending = false;
                setContextActivationBusy(false);
                unlockContext();
                showToast('No se pudo activar el contexto.', 'err');
            });
        }
    }

    /* ============ LOGS ============ */
    function loadContextArtifacts() {
        if (!useServerApi() || !(clientDropdown.value && environmentDropdown.value)) { return; }
        fetch('/api/logs', { cache: 'no-store' }).then(function (response) { return response.json(); }).then(function (payload) {
            if (payload.ok) { contextLogs = payload.data.logs || []; renderLogs(document.getElementById('log-filter').value); }
        }).catch(function () { contextLogs = []; renderLogs('todos'); });
    }

    function classifyLog(file) {
        if (file.categoria) {
            var category = String(file.categoria).toLowerCase();
            if (category === 'info') { return 'ok'; }
            if (category === 'warning') { return 'advertencia'; }
            return category;
        }
        var name = normalize(file.nombre);
        if (name.indexOf('review') >= 0) { return 'review'; }
        if (name.indexOf('validacion') >= 0) { return 'validacion'; }
        return 'ok';
    }

    function logButton(file) {
        var label = classifyLog(file);
        return '<button class="file-row log-button" type="button" data-log-name="' + escapeHtml(file.nombre) + '"><span>' + escapeHtml(file.nombre) + '</span><small>' + escapeHtml(formatDateTime(file.modificado)) + ' | ' + escapeHtml(statusLabel(label)) + ' | ' + file.bytes + ' bytes</small></button>';
    }

    function renderLogs(filter) {
        var list = document.getElementById('log-list');
        var logs = contextLogs.filter(function (file) {
            var cat = classifyLog(file);
            return filter === 'todos' || cat === filter;
        });
        var grupos = { error: [], advertencia: [], ok: [] };
        logs.forEach(function (file) {
            var cat = classifyLog(file);
            (grupos[cat] = grupos[cat] || []).push(file);
        });
        var html = '';
        [['error', 'Errores'], ['advertencia', 'Advertencias'], ['ok', 'Ok']].forEach(function (grupo) {
            if (!grupos[grupo[0]].length) { return; }
            html += '<div class="log-group-title">' + grupo[1] + '</div>';
            html += grupos[grupo[0]].map(logButton).join('');
        });
        list.innerHTML = html || '<div class="empty-state">No hay logs disponibles para este filtro.</div>';
        list.querySelectorAll('.log-button').forEach(function (button) {
            button.addEventListener('click', function () { loadLogContent(button.getAttribute('data-log-name')); });
        });
    }

    function loadLogContent(name) {
        fetch('/api/logs/' + encodeURIComponent(name), { cache: 'no-store' }).then(function (response) { return response.text(); }).then(function (content) {
            var viewer = document.getElementById('log-viewer');
            viewer.hidden = false;
            viewer.textContent = content;
        }).catch(function (error) { showToast(error.message, 'err'); });
    }

    function loadReportContent(type) {
        var paths = { review: '/api/reportes/review-ultimo', validacion: '/api/reportes/validacion-ultima' };
        fetch(paths[type], { cache: 'no-store' }).then(function (response) { return response.json(); }).then(function (payload) {
            var viewer = document.getElementById('log-viewer');
            viewer.hidden = false;
            var reportContent = payload.ok && payload.data ? payload.data.contenido : null;
            if (typeof reportContent === 'string') {
                viewer.textContent = reportContent;
            } else if (reportContent && typeof reportContent === 'object') {
                viewer.textContent = JSON.stringify(reportContent, null, 2);
            } else {
                viewer.textContent = 'No hay contenido disponible.';
            }
        }).catch(function (error) { showToast(error.message, 'err'); });
    }

    /* ============ CONFIGURACIÓN ============ */
    function loadConfiguration() {
        if (!useServerApi()) { return; }
        fetch('/api/configuracion', { cache: 'no-store' }).then(function (response) { return response.json(); }).then(function (payload) {
            if (!payload.ok) { return; }
            configurationData.configuration = payload.data.configuracion;
            configurationData.configHash = payload.data.configHash || '';
            configurationData.errores = payload.data.errores || [];
            configurationSnapshot = payload.data.configuracion;
            renderConfigurationList();
        }).catch(function () { });
    }

    function iconButton(icon, title, action, clientId, environmentId) {
        return '<button class="icon-button config-icon" type="button" title="' + escapeHtml(title) + '" aria-label="' + escapeHtml(title) + '" data-client-id="' + escapeHtml(clientId) + '" data-environment-id="' + escapeHtml(environmentId || '') + '" data-action="' + escapeHtml(action) + '">' + svgIcon(icon) + '</button>';
    }

    function renderConfigurationList() {
        var configuration = configurationData.configuration;
        var configurationList = document.getElementById('configuration-list');
        if (window.panelViews) {
            window.panelViews.configuration.setConfiguration((configuration && configuration.clientes) || [], configurationData.errores || [], document.getElementById('configuration-filter').value);
        } else {
            configurationList.configuration = { clients: (configuration && configuration.clientes) || [], errors: configurationData.errores || [] };
            configurationList.searchValue = document.getElementById('configuration-filter').value;
        }
        bindConfigurationActions(configuration, configurationData.configHash);
    }

    function openConfigurationModal(values) {
        configurationModalOrigin = document.activeElement;
        document.getElementById('configuration-original-id').value = values.originalId || '';
        document.getElementById('configuration-client-id').value = values.clientId || '';
        document.getElementById('configuration-id').value = (values.id || '').toLowerCase();
        document.getElementById('configuration-id').disabled = Boolean(values.originalId);
        document.getElementById('configuration-name').value = values.name || '';
        document.getElementById('configuration-package').value = values.packageName || '';
        var exportProfileField = document.getElementById('configuration-export-profile-field');
        var exportProfile = values.geneXusExportProfile || (configurationData.configuration && configurationData.configuration.herramientas && configurationData.configuration.herramientas.geneXusExportProfile);
        setConfigurationExportProfile(exportProfile);
        var inferredEnvironment = getConfigurationEnvironmentDefaults(values.tipo);
        document.getElementById('configuration-environment-id').value = values.environmentId || (values.originalId ? values.originalId : inferredEnvironment.id);
        document.getElementById('configuration-environment-id').disabled = Boolean(values.environmentId && values.originalId);
        document.getElementById('configuration-kb-path').value = values.kbPath || '';
        var clientFields = document.getElementById('configuration-client-fields');
        var environmentFields = document.getElementById('configuration-environment-fields');
        var tipoRadios = document.querySelectorAll('input[name="configuration-tipo"]');
        var isEnvironment = Boolean(values.environment);
        var isNewClient = !isEnvironment && !values.originalId;
        clientFields.hidden = isEnvironment;
        exportProfileField.hidden = !isNewClient;
        environmentFields.hidden = !(isEnvironment || isNewClient);
        setConfigurationEnvironmentType(clasificarTipo(values.tipo) === 'prod' ? 'prod' : 'test');
        tipoRadios.forEach(function (radio) { radio.disabled = Boolean(values.tipoInmutable) || (Boolean(values.lockedTipo) && radio.value !== values.lockedTipo); });
        document.getElementById('configuration-environment-legend').textContent = values.originalId ? 'Editar ambiente' : 'Primer ambiente';
        document.getElementById('configuration-modal-title').textContent = values.environment ? (values.originalId ? 'Editar ambiente' : 'Agregar ambiente') : (values.originalId ? 'Editar cliente' : 'Agregar cliente');
        document.getElementById('configuration-modal-message').textContent = values.environment ? 'Completa los datos del ambiente.' : (values.originalId ? 'Actualiza los datos del cliente.' : 'El cliente y su primer ambiente se guardarán juntos.');
        document.getElementById('configuration-feedback').hidden = true;
        var modal = document.getElementById('configuration-modal');
        modal.hidden = false;
        focusFirstModalControl(modal);
    }

    function getConfigurationEnvironmentDefaults(tipo) {
        return clasificarTipo(tipo) === 'prod' ? { id: 'produccion', name: 'PROD' } : { id: 'testing', name: 'TEST' };
    }

    function getConfigurationEnvironmentType() {
        var selected = document.querySelector('input[name="configuration-tipo"]:checked');
        return selected ? selected.value : '';
    }

    function setConfigurationEnvironmentType(tipo) {
        document.querySelectorAll('input[name="configuration-tipo"]').forEach(function (radio) { radio.checked = radio.value === tipo; });
    }

    function normalizarPerfilExportacion(perfil) {
        return String(perfil || '').trim().toLowerCase() === 'evo3' ? 'Evo3' : 'Gx18';
    }

    function getConfigurationExportProfile() {
        var selected = document.querySelector('input[name="configuration-export-profile"]:checked');
        return selected ? selected.value : '';
    }

    function setConfigurationExportProfile(perfil) {
        var normalized = normalizarPerfilExportacion(perfil);
        document.querySelectorAll('input[name="configuration-export-profile"]').forEach(function (radio) { radio.checked = radio.value === normalized; });
    }

    function syncInferredConfigurationEnvironment() {
        var environmentId = document.getElementById('configuration-environment-id');
        if (environmentId.disabled) { return; }
        var defaults = getConfigurationEnvironmentDefaults(getConfigurationEnvironmentType());
        environmentId.value = defaults.id;
    }

    function focusFirstModalControl(modal) {
        var focusable = modal.querySelector('button:not([disabled]):not(.modal-close), input:not([disabled]), select:not([disabled]), textarea:not([disabled])');
        if (focusable) { window.setTimeout(function () { focusable.focus(); }, 0); }
    }

    function closeConfigurationModal() {
        document.getElementById('configuration-modal').hidden = true;
        if (configurationModalOrigin && typeof configurationModalOrigin.focus === 'function') { configurationModalOrigin.focus(); }
        configurationModalOrigin = null;
    }

    function openConfigurationConfirmation(message, action) {
        configurationModalOrigin = document.activeElement;
        configurationConfirmationAction = action;
        document.getElementById('configuration-confirm-message').textContent = message;
        document.getElementById('configuration-confirm-feedback').hidden = true;
        document.getElementById('confirm-configuration-delete').hidden = false;
        document.getElementById('cancel-configuration-delete').textContent = 'Cancelar';
        var modal = document.getElementById('configuration-confirm-modal');
        modal.hidden = false;
        focusFirstModalControl(modal);
    }

    function closeConfigurationConfirmation() {
        document.getElementById('configuration-confirm-modal').hidden = true;
        configurationConfirmationAction = null;
        if (configurationModalOrigin && typeof configurationModalOrigin.focus === 'function') { configurationModalOrigin.focus(); }
        configurationModalOrigin = null;
    }

    function showConfigurationFeedback(message, type) {
        var feedback = document.getElementById('configuration-feedback');
        feedback.textContent = message;
        feedback.className = 'modal-feedback modal-feedback-' + (type || 'error');
        feedback.hidden = false;
    }

    function showConfigurationRequestFeedback(elementId, message, type) {
        var feedback = document.getElementById(elementId || 'configuration-feedback');
        feedback.textContent = message;
        feedback.className = 'modal-feedback modal-feedback-' + (type || 'error');
        feedback.hidden = false;
    }

    function validateConfigurationForm(isEnvironment, isEditing) {
        var fields = isEnvironment ? [
            ['configuration-kb-path', 'El ambiente requiere una ruta de KB.']
        ] : [
            ['configuration-id', 'El cliente requiere un id.'],
            ['configuration-name', 'El cliente requiere un nombre.'],
            ['configuration-package', 'El cliente requiere packagename.']
        ];
        if (!isEnvironment && !isEditing) {
            fields = fields.concat([
                ['configuration-kb-path', 'El primer ambiente requiere una ruta de KB.']
            ]);
        }
        for (var fieldIndex = 0; fieldIndex < fields.length; fieldIndex++) {
            if (!document.getElementById(fields[fieldIndex][0]).value.trim()) {
                showConfigurationFeedback(fields[fieldIndex][1], 'error');
                document.getElementById(fields[fieldIndex][0]).focus();
                return false;
            }
        }
        return true;
    }

    function trapModalFocus(event, modal) {
        if (event.key === 'Escape') {
            if (!document.getElementById('configuration-modal').hidden) { closeConfigurationModal(); }
            if (!document.getElementById('configuration-confirm-modal').hidden) { closeConfigurationConfirmation(); }
            return;
        }
        if (event.key !== 'Tab' || modal.hidden) { return; }
        var focusable = Array.prototype.slice.call(modal.querySelectorAll('button:not([disabled]):not(.modal-close), input:not([disabled]), select:not([disabled]), textarea:not([disabled])'));
        if (!focusable.length) { return; }
        var first = focusable[0];
        var last = focusable[focusable.length - 1];
        if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
        else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    }

    function configurationRequest(url, method, body, feedbackElementId, successMessage) {
        return fetch(url, { method: method, headers: { 'Content-Type': 'application/json', 'X-Panel-Token': window.PANEL_TOKEN || '' }, body: JSON.stringify(body) }).then(function (response) { return response.json(); }).then(function (payload) {
            if (!payload.ok) { throw new Error(payload.error || 'No se pudo guardar la configuración.'); }
            showConfigurationRequestFeedback(feedbackElementId, successMessage || 'Configuración guardada correctamente.', 'success');
            if (feedbackElementId === 'configuration-confirm-feedback') {
                document.getElementById('confirm-configuration-delete').hidden = true;
                document.getElementById('cancel-configuration-delete').textContent = 'Cerrar';
                configurationConfirmationAction = null;
            }
            removePersistedContext();
            pendingPersistedContext = null;
            pendingContextRestoreError = '';
            contextResolutionPending = false;
            clearContextDependentState();
            unlockContext();
            clientDropdown.value = '';
            environmentDropdown.setOptions([]);
            environmentDropdown.value = '';
            loadConfiguration();
            loadContextsFromServer();
            return payload;
        }).catch(function (error) {
            showConfigurationRequestFeedback(feedbackElementId, error.message, 'error');
            throw error;
        });
    }

    function bindConfigurationActions(configuration, configHash) {
        function findClient(clientId) {
            return ((configuration && configuration.clientes) || []).filter(function (item) { return item.id === clientId; })[0];
        }
        document.querySelectorAll('[data-action="edit-client"]').forEach(function (button) {
            button.addEventListener('click', function () {
                var client = findClient(button.dataset.clientId);
                if (client) { openConfigurationModal({ originalId: client.id, id: client.id, name: client.nombre, packageName: client.packagename }); }
            });
        });
        document.querySelectorAll('[data-action="delete-client"]').forEach(function (button) {
            button.addEventListener('click', function () {
                openConfigurationConfirmation('¿Eliminar este cliente?', function () {
                    configurationRequest('/api/configuracion/clientes/' + encodeURIComponent(button.dataset.clientId), 'DELETE', { configHash: configHash, confirmDelete: true }, 'configuration-confirm-feedback', 'Cliente eliminado correctamente.').catch(function () { });
                });
            });
        });
        document.querySelectorAll('[data-action="add-environment"]').forEach(function (button) {
            button.addEventListener('click', function () {
                var client = findClient(button.dataset.clientId);
                if (!client) { return; }
                var tipos = (client.ambientes || []).map(function (e) { return clasificarTipo(e.tipo); });
                var lockedTipo = null;
                if (tipos.indexOf('test') >= 0 && tipos.indexOf('prod') < 0) { lockedTipo = 'prod'; }
                else if (tipos.indexOf('prod') >= 0 && tipos.indexOf('test') < 0) { lockedTipo = 'test'; }
                openConfigurationModal({ environment: true, originalId: '', id: '', name: '', kbPath: '', clientId: button.dataset.clientId, tipo: lockedTipo || 'test', lockedTipo: lockedTipo });
            });
        });
        document.querySelectorAll('[data-action="edit-environment"]').forEach(function (button) {
            button.addEventListener('click', function () {
                var client = findClient(button.dataset.clientId);
                var environment = client ? (client.ambientes || []).filter(function (item) { return item.id === button.dataset.environmentId; })[0] : null;
                if (environment) {
                    var environmentTypes = (client.ambientes || []).map(function (item) { return clasificarTipo(item.tipo); });
                    var hasBothEnvironmentTypes = environmentTypes.indexOf('test') >= 0 && environmentTypes.indexOf('prod') >= 0;
                    openConfigurationModal({ environment: true, originalId: environment.id, environmentId: environment.id, kbPath: environment.kbPath, clientId: client.id, tipo: environment.tipo, lockedTipo: null, tipoInmutable: hasBothEnvironmentTypes });
                }
            });
        });
        document.querySelectorAll('[data-action="delete-environment"]').forEach(function (button) {
            button.addEventListener('click', function () {
                openConfigurationConfirmation('¿Eliminar este ambiente?', function () {
                    configurationRequest('/api/configuracion/clientes/' + encodeURIComponent(button.dataset.clientId) + '/ambientes/' + encodeURIComponent(button.dataset.environmentId), 'DELETE', { configHash: configHash, confirmDelete: true }, 'configuration-confirm-feedback', 'Ambiente eliminado correctamente.').catch(function () { });
                });
            });
        });
    }

    /* ============ PESTAÑAS ============ */
    function selectTab(tabName) {
        activeTab = tabName;
        if (window.panelUiPreferences) {
            var tabPreferences = window.panelUiPreferences.read();
            tabPreferences.activeTab = tabName;
            window.panelUiPreferences.save(tabPreferences);
            window.panelUiPreferences.current = tabPreferences;
        }
        document.querySelectorAll('.tab').forEach(function (item) {
            item.classList.toggle('is-active', item.dataset.tab === tabName);
            item.setAttribute('aria-selected', item.dataset.tab === tabName ? 'true' : 'false');
        });
        document.querySelectorAll('.tab-panel').forEach(function (panel) {
            panel.classList.remove('is-active');
            panel.hidden = true;
            panel.setAttribute('aria-hidden', 'true');
        });
        var panel = document.getElementById('tab-' + tabName);
        if (panel) {
            panel.classList.add('is-active');
            panel.hidden = false;
            panel.setAttribute('aria-hidden', 'false');
        }
    }

    /* ============ EVENTOS ============ */
    function bindEvents() {
        document.addEventListener('operation-abort', function (event) {
            abortOperation(event.detail && event.detail.jobId);
        });
        document.addEventListener('operation-go-pdf', function () {
            selectTab('endpoints');
        });
        clientDropdown.setOnChange(function () {
            if (contextLocked) { return; }
            environmentDropdown.value = '';
            selectEnvironment();
        });
        environmentDropdown.setOnChange(function () { if (!contextLocked) { activateContext(); } });
        exportButton.addEventListener('click', function () { exportConsoleVisible = true; setButtonLoading(exportButton, true); startExport({}, true); });
        updateServicesButton.addEventListener('click', function () { exportConsoleVisible = true; setButtonLoading(updateServicesButton, true); startExport({}, true); });
        document.getElementById('continue-operation').addEventListener('click', function () {
            if (!selectedFallbackXpz) { showToast('Selecciona un XPZ para continuar.', 'warn'); return; }
            setButtonLoading(document.getElementById('continue-operation'), true);
            startExport({ modo: 'completar', nombre: selectedFallbackXpz }, exportConsoleVisible);
        });
        document.getElementById('abort-export').addEventListener('click', function () {
            showExportFallback(false);
            showToast('La exportación fue abortada.', 'err');
        });
        document.getElementById('change-client').addEventListener('click', function () {
            if (currentJobId) {
                showToast('No se puede cambiar el cliente mientras hay una operación en curso en el servidor.', 'err');
                return;
            }
            removePersistedContext();
            pendingPersistedContext = null;
            pendingContextRestoreError = '';
            contextResolutionPending = false;
            clearContextDependentState();
            unlockContext();
            selectEnvironment();
            renderGlobalNotices();
        });
        document.getElementById('documentation-filter').addEventListener('input', function () { documentationCurrentPage = 1; saveDocumentationPreferences(); loadServices(); });
        document.getElementById('documentation-page-size').addEventListener('change', function (event) { documentationPageSize = Number(event.target.value) || 25; documentationCurrentPage = 1; saveDocumentationPreferences(); loadServices(); });
        document.getElementById('documentation-previous-page').addEventListener('click', function () { if (documentationCurrentPage > 1) { documentationCurrentPage -= 1; loadServices(); } });
        document.getElementById('documentation-next-page').addEventListener('click', function () { documentationCurrentPage += 1; loadServices(); });
        document.getElementById('documentation-service-list').addEventListener('service-detail', function (event) { document.getElementById('documentation-detail-dialog').open(event.detail.service); });
        document.getElementById('documentation-pdf-list').addEventListener('click', function (event) {
            var button = event.target.closest('.pdf-view');
            if (button) { showPdfViewer(button.getAttribute('data-pdf-name'), button.getAttribute('data-service-name')); }
        });
        document.getElementById('close-pdf-viewer').addEventListener('click', closePdfViewer);
        document.getElementById('pdf-viewer-dialog').addEventListener('click', function (event) {
            if (event.target === event.currentTarget) { closePdfViewer(); }
        });
        document.getElementById('configuration-filter').addEventListener('input', renderConfigurationList);
        document.getElementById('generate-pdf').addEventListener('click', startPdfGeneration);
        document.getElementById('confirm-pdf-generation').addEventListener('click', confirmPdfGeneration);
        document.getElementById('cancel-pdf-generation').addEventListener('click', function () { document.getElementById('pdf-warning').hidden = true; });
        document.getElementById('log-filter').addEventListener('change', function (event) {
            var viewer = document.getElementById('log-viewer');
            viewer.hidden = true;
            viewer.textContent = '';
            renderLogs(event.target.value);
            if (window.panelUiPreferences) {
                var logPreferences = window.panelUiPreferences.read();
                logPreferences.filters.logs = event.target.value;
                window.panelUiPreferences.save(logPreferences);
                window.panelUiPreferences.current = logPreferences;
            }
        });
        document.getElementById('add-client').addEventListener('click', function () { openConfigurationModal({}); });
        document.getElementById('close-configuration-modal').addEventListener('click', closeConfigurationModal);
        document.getElementById('cancel-configuration').addEventListener('click', closeConfigurationModal);
        document.getElementById('close-configuration-confirm').addEventListener('click', closeConfigurationConfirmation);
        document.getElementById('cancel-configuration-delete').addEventListener('click', closeConfigurationConfirmation);
        document.getElementById('confirm-configuration-delete').addEventListener('click', function () {
            var action = configurationConfirmationAction;
            if (action) { action(); }
        });
        document.addEventListener('keydown', function (event) {
            trapModalFocus(event, document.getElementById('configuration-modal'));
            trapModalFocus(event, document.getElementById('configuration-confirm-modal'));
        });
        document.getElementById('close-context-modal').addEventListener('click', closeContextModal);
        document.getElementById('use-saved-context').addEventListener('click', useSavedContext);
        document.getElementById('use-server-context').addEventListener('click', useServerContext);
        document.getElementById('configuration-form').addEventListener('submit', function (event) {
            event.preventDefault();
            var originalId = document.getElementById('configuration-original-id').value;
            var clientId = document.getElementById('configuration-client-id').value;
            var id = document.getElementById('configuration-id').value.trim().toLowerCase();
            var name = document.getElementById('configuration-name').value.trim();
            var environmentType = getConfigurationEnvironmentType();
            syncInferredConfigurationEnvironment();
            var configHash = configurationData.configHash || '';
            if (!configHash) { showToast('No hay configuración vigente.', 'err'); return; }
            var isEnvironment = Boolean(clientId);
            var isEditing = Boolean(originalId);
            var url;
            var method;
            var body;
            if (isEnvironment) {
                url = '/api/configuracion/clientes/' + encodeURIComponent(clientId) + '/ambientes' + (isEditing ? '/' + encodeURIComponent(originalId) : '');
                method = isEditing ? 'PUT' : 'POST';
                body = { configHash: configHash, data: { tipo: environmentType, kbPath: document.getElementById('configuration-kb-path').value.trim() } };
            } else {
                url = '/api/configuracion/clientes' + (isEditing ? '/' + encodeURIComponent(originalId) : '');
                method = isEditing ? 'PUT' : 'POST';
                var existingClient = ((configurationSnapshot && configurationSnapshot.clientes) || []).filter(function (item) { return item.id === (clientId || originalId); })[0];
                var clientData = { id: id, nombre: name, packagename: document.getElementById('configuration-package').value.trim(), serviciosIgnorados: existingClient ? existingClient.serviciosIgnorados : [] };
                if (!isEditing) {
                    clientData.geneXusExportProfile = getConfigurationExportProfile();
                    clientData.ambientes = [{ tipo: environmentType, kbPath: document.getElementById('configuration-kb-path').value.trim() }];
                }
                body = { configHash: configHash, data: clientData };
            }
            if (!validateConfigurationForm(isEnvironment, isEditing)) { return; }
            configurationRequest(url, method, body).catch(function () { });
        });
        document.getElementById('configuration-id').addEventListener('input', function (event) { event.target.value = event.target.value.toLowerCase(); });
        document.querySelectorAll('input[name="configuration-tipo"]').forEach(function (radio) { radio.addEventListener('change', syncInferredConfigurationEnvironment); });
        document.getElementById('theme-toggle').addEventListener('click', function () {
            var nextTheme = document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
            document.documentElement.setAttribute('data-theme', nextTheme);
            if (window.panelUiPreferences) {
                var currentPreferences = window.panelUiPreferences.read();
                currentPreferences.theme = nextTheme;
                window.panelUiPreferences.save(currentPreferences);
                window.panelUiPreferences.current = currentPreferences;
            }
        });
        document.querySelectorAll('[data-target-tab]').forEach(function (button) {
            button.addEventListener('click', function () { selectTab(button.getAttribute('data-target-tab')); });
        });
        document.getElementById('configuration-toggle').addEventListener('click', function () { selectTab('configuracion'); });
        document.querySelectorAll('.tab').forEach(function (tab) {
            tab.addEventListener('click', function () { selectTab(tab.dataset.tab); });
        });
    }

    clientDropdown = createDropdown({ triggerId: 'client-dropdown-trigger', menuId: 'client-dropdown-menu', labelId: 'client-dropdown-label', placeholder: 'Seleccionar cliente' });
    environmentDropdown = createDropdown({ triggerId: 'environment-dropdown-trigger', menuId: 'environment-dropdown-menu', labelId: 'environment-dropdown-label', placeholder: 'Seleccionar ambiente' });
    environmentDropdown.disabled = true;

    if (window.panelUiPreferences) {
        var loadedDocumentationPreferences = window.panelUiPreferences.current || window.panelUiPreferences.read();
        documentationView = 'list';
        loadedDocumentationPreferences.views.documentacion = 'list';
        saveDocumentationPreferences();
        documentationPageSize = loadedDocumentationPreferences.pageSize.documentacion;
        document.getElementById('documentation-page-size').value = String(documentationPageSize);
        document.getElementById('documentation-filter').value = loadedDocumentationPreferences.filters.documentacion;
    }

    bindEvents();
    renderWork(null);
    renderGlobalNotices();
    selectTab((window.panelUiPreferences && window.panelUiPreferences.current && window.panelUiPreferences.current.activeTab) || 'estado');
    loadContextsFromServer();
    loadConfiguration();
}());
