(function () {
    'use strict';

    var fixture = JSON.parse(document.getElementById('panel-fixture').textContent);
    var clientSelect = document.getElementById('client-select');
    var environmentSelect = document.getElementById('environment-select');
    var currentJobId = null;
    var pollingTimer = null;
    var regenerateButton = document.getElementById('regenerate-endpoints');
    var environments = {
        trunk: [{ id: 'testing', name: 'Testing' }],
        lps: [{ id: 'prue', name: 'Testing' }, { id: 'prod', name: 'PROD' }]
    };

    function useServerApi() {
        return window.location.protocol === 'http:' && typeof window.fetch === 'function';
    }

    function loadContextsFromServer() {
        if (!useServerApi()) { return; }
        fetch('/api/contextos', { cache: 'no-store' }).then(function (response) { return response.json(); }).then(function (payload) {
            if (!payload.ok) { return; }
            var clients = {};
            payload.data.contextos.forEach(function (context) {
                clients[context.clienteId] = clients[context.clienteId] || { name: context.clienteNombre, environments: [] };
                clients[context.clienteId].environments.push({ id: context.ambienteId, name: context.ambienteNombre });
            });
            clientSelect.innerHTML = '<option value="">Seleccionar cliente</option>' + Object.keys(clients).map(function (clientId) {
                return '<option value="' + clientId + '">' + clients[clientId].name + '</option>';
            }).join('');
            environments = Object.keys(clients).reduce(function (result, clientId) { result[clientId] = clients[clientId].environments; return result; }, {});
        }).catch(function () { /* El esqueleto sigue funcionando sin servidor. */ });
    }

    function normalize(value) {
        return String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
    }

    function renderEndpoints(filter) {
        var normalizedFilter = normalize(filter);
        var rows = fixture.endpoints.filter(function (endpoint) {
            return !normalizedFilter || normalize(endpoint.nombre).indexOf(normalizedFilter) >= 0 || normalize(endpoint.descripcion).indexOf(normalizedFilter) >= 0;
        });
        document.getElementById('endpoint-table').innerHTML = rows.map(function (endpoint) {
            return '<tr><td>' + escapeHtml(endpoint.nombre) + '</td><td>' + escapeHtml(endpoint.descripcion) + '</td><td><code>' + escapeHtml(endpoint.proceso) + '</code></td><td><code>' + escapeHtml(endpoint.endpoint) + '</code></td></tr>';
        }).join('') || '<tr><td colspan="4" class="table-empty">No hay endpoints que coincidan con el filtro.</td></tr>';
    }

    function renderInventoryState(inventoryState) {
        var inventory = inventoryState && inventoryState.inventario;
        if (inventory) {
            fixture = inventory;
            document.getElementById('endpoint-count').textContent = inventory.meta.totalConfirmed + ' CONFIRMADOS';
            document.getElementById('inventory-meta').textContent = 'XPZ: ' + inventory.meta.xpz + ' | Generado: ' + new Date(inventory.meta.generatedAt).toLocaleString('es-AR');
            renderEndpoints(document.getElementById('endpoint-filter').value);
        } else {
            document.getElementById('endpoint-count').textContent = 'SIN INVENTARIO';
            document.getElementById('inventory-meta').textContent = inventoryState && inventoryState.motivo ? inventoryState.motivo : 'El inventario todavía no fue generado.';
        }
        regenerateButton.disabled = !useServerApi() || Boolean(currentJobId) || !(inventoryState && (!inventoryState.vigente || !inventoryState.disponible));
        if (inventoryState && inventoryState.obsoleto) {
            document.getElementById('inventory-meta').textContent = 'OBSOLETO: ' + inventoryState.motivo;
        }
    }

    function loadEndpointInventory() {
        if (!useServerApi()) { return; }
        fetch('/api/endpoints', { cache: 'no-store' }).then(function (response) { return response.json(); }).then(function (payload) {
            if (payload.ok) { renderInventoryState(payload.data); }
        }).catch(function () { /* La vista conserva el fixture local. */ });
    }

    function renderFileList(elementId, files, emptyMessage, basePath) {
        var element = document.getElementById(elementId);
        if (!files || files.length === 0) { element.innerHTML = '<div class="empty-state">' + emptyMessage + '</div>'; return; }
        element.innerHTML = files.map(function (file) {
            return '<a class="file-row" href="' + basePath + encodeURIComponent(file.nombre) + '" target="_blank" rel="noopener"><span>' + escapeHtml(file.nombre) + '</span><small>' + file.extension + ' | ' + file.bytes + ' bytes</small></a>';
        }).join('');
    }

    function loadContextArtifacts() {
        if (!useServerApi() || !(clientSelect.value && environmentSelect.value)) { return; }
        fetch('/api/documentos', { cache: 'no-store' }).then(function (response) { return response.json(); }).then(function (payload) {
            if (payload.ok) { renderFileList('document-list', payload.data.documentos, 'No hay documentos publicados en este contexto.', '/api/documentos/'); }
        }).catch(function () { });
        fetch('/api/logs', { cache: 'no-store' }).then(function (response) { return response.json(); }).then(function (payload) {
            if (payload.ok) { renderFileList('log-list', payload.data.logs, 'No hay logs disponibles para este contexto.', '/api/logs/'); }
        }).catch(function () { });
    }

    function loadConfiguration() {
        if (!useServerApi()) { return; }
        fetch('/api/configuracion', { cache: 'no-store' }).then(function (response) { return response.json(); }).then(function (payload) {
            if (!payload.ok) { return; }
            var configuration = payload.data.configuracion;
            var errors = payload.data.errores || [];
            var clients = (configuration && configuration.clientes) || [];
            var html = errors.map(function (error) { return '<div class="config-error">' + escapeHtml(error) + '</div>'; }).join('');
            html += clients.map(function (client) {
                return '<div class="config-row"><strong>' + escapeHtml(client.nombre) + '</strong><span>' + escapeHtml(client.id) + ' | ' + ((client.ambientes || []).length) + ' ambiente(s)</span></div>';
            }).join('');
            document.getElementById('configuration-list').innerHTML = html || '<div class="empty-state">No hay clientes configurados.</div>';
        }).catch(function () { });
    }

    function escapeHtml(value) {
        return String(value || '').replace(/[&<>"']/g, function (character) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character];
        });
    }

    function selectEnvironment() {
        var options = environments[clientSelect.value] || [];
        environmentSelect.innerHTML = '<option value="">Seleccionar ambiente</option>' + options.map(function (environment) {
            return '<option value="' + environment.id + '">' + environment.name + '</option>';
        }).join('');
        environmentSelect.disabled = options.length === 0;
    }

    function activateContext() {
        var active = Boolean(clientSelect.value && environmentSelect.value);
        document.getElementById('context-badge').textContent = active ? 'CONTEXTO SELECCIONADO' : 'SIN CONTEXTO';
        document.getElementById('context-badge').className = active ? 'badge badge-ok' : 'badge badge-muted';
        document.getElementById('state-empty').textContent = active ? 'Preflight pendiente: el servidor validará este contexto al activarlo.' : 'Selecciona un cliente y un ambiente para comenzar.';
        document.getElementById('validate-xpz').disabled = !active || Boolean(currentJobId);
        if (active && useServerApi()) {
            fetch('/api/contexto/activar', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-Panel-Token': window.PANEL_TOKEN || '' },
                body: JSON.stringify({ clienteId: clientSelect.value, ambienteId: environmentSelect.value })
            }).then(function (response) { return response.json(); }).then(function (payload) {
                if (payload.ok) {
                    document.getElementById('state-empty').textContent = 'Contexto activo: ' + payload.data.contextId + '.';
                    loadEndpointInventory();
                    loadContextArtifacts();
                    if (payload.jobId) { currentJobId = payload.jobId; setWorkBusy(true); pollWork(); }
                }
            }).catch(function () { document.getElementById('state-empty').textContent = 'No se pudo activar el contexto.'; });
        }
    }

    function setWorkBusy(isBusy) {
        clientSelect.disabled = isBusy;
        environmentSelect.disabled = isBusy || !clientSelect.value;
        document.getElementById('validate-xpz').disabled = isBusy || !(clientSelect.value && environmentSelect.value);
    }

    function showToast(message) {
        var toast = document.createElement('div');
        toast.className = 'toast';
        toast.setAttribute('role', 'status');
        toast.textContent = message;
        document.body.appendChild(toast);
        window.setTimeout(function () { toast.remove(); }, 4500);
    }

    function renderWork(work) {
        var card = document.getElementById('work-card');
        if (!work) { card.hidden = true; return; }
        card.hidden = false;
        document.getElementById('work-status').textContent = work.estado;
        document.getElementById('work-description').textContent = work.operacion + ' | ' + work.contextId;
        document.getElementById('work-progress').style.width = work.progreso && work.progreso.porcentaje !== null ? work.progreso.porcentaje + '%' : '42%';
        document.getElementById('work-lines').textContent = (work.ultimasLineas || []).join('\n');
    }

    function pollWork() {
        if (!currentJobId) { return; }
        fetch('/api/trabajos/' + encodeURIComponent(currentJobId), { cache: 'no-store' }).then(function (response) { return response.json(); }).then(function (payload) {
            if (!payload.ok) { throw new Error(payload.error || 'No se pudo consultar el trabajo.'); }
            renderWork(payload.data);
            if (['QUEUED', 'RUNNING'].indexOf(payload.data.estado) >= 0) {
                pollingTimer = window.setTimeout(pollWork, 1500);
                return;
            }
            currentJobId = null;
            setWorkBusy(false);
            loadEndpointInventory();
            showToast('Validación finalizada: ' + payload.data.estado + ' (' + payload.data.contextId + ').');
        }).catch(function () {
            pollingTimer = window.setTimeout(pollWork, 2000);
        });
    }

    function startValidation() {
        if (!useServerApi() || currentJobId || !(clientSelect.value && environmentSelect.value)) { return; }
        fetch('/api/validar', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-Panel-Token': window.PANEL_TOKEN || '' },
            body: '{}'
        }).then(function (response) { return response.json(); }).then(function (payload) {
            if (!payload.ok) { throw new Error(payload.error || 'No se pudo iniciar la validación.'); }
            currentJobId = payload.data.jobId;
            setWorkBusy(true);
            showToast('Trabajo iniciado: ' + currentJobId + '.');
            pollWork();
        }).catch(function (error) { showToast(error.message); });
    }

    function regenerateEndpoints() {
        if (!useServerApi() || currentJobId) { return; }
        fetch('/api/endpoints/regenerar', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-Panel-Token': window.PANEL_TOKEN || '' },
            body: '{}'
        }).then(function (response) { return response.json(); }).then(function (payload) {
            if (!payload.ok) { throw new Error(payload.error || 'No se pudo regenerar el inventario.'); }
            currentJobId = payload.data.jobId;
            setWorkBusy(true);
            showToast('Regeneración de endpoints iniciada.');
            pollWork();
        }).catch(function (error) { showToast(error.message); });
    }

    clientSelect.addEventListener('change', function () { selectEnvironment(); activateContext(); });
    environmentSelect.addEventListener('change', activateContext);
    document.getElementById('validate-xpz').addEventListener('click', startValidation);
    regenerateButton.addEventListener('click', regenerateEndpoints);
    document.getElementById('endpoint-filter').addEventListener('input', function (event) { renderEndpoints(event.target.value); });
    document.getElementById('theme-toggle').addEventListener('click', function () {
        var nextTheme = document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
        document.documentElement.setAttribute('data-theme', nextTheme);
        try { localStorage.setItem('panel-theme', nextTheme); } catch (error) { /* Persistencia opcional. */ }
    });
    document.querySelectorAll('.tab').forEach(function (tab) {
        tab.addEventListener('click', function () {
            document.querySelectorAll('.tab').forEach(function (item) { item.classList.remove('is-active'); item.setAttribute('aria-selected', 'false'); });
            document.querySelectorAll('.tab-panel').forEach(function (panel) { panel.classList.remove('is-active'); panel.hidden = true; });
            tab.classList.add('is-active');
            tab.setAttribute('aria-selected', 'true');
            var panel = document.getElementById('tab-' + tab.dataset.tab);
            panel.classList.add('is-active');
            panel.hidden = false;
        });
    });
    try { document.documentElement.setAttribute('data-theme', localStorage.getItem('panel-theme') || 'light'); } catch (error) { /* Tema predeterminado. */ }
    document.getElementById('inventory-meta').textContent = 'XPZ: ' + fixture.meta.xpz + ' | Generado: ' + new Date(fixture.meta.generatedAt).toLocaleString('es-AR');
    renderEndpoints('');
    loadContextsFromServer();
    loadConfiguration();
}());
