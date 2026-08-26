function escapeMarkup(value) {
    return String(value === null || value === undefined ? '' : value).replace(/[&<>"']/g, function (character) {
        return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character];
    });
}

function environmentTypePill(type) {
    const normalizedType = String(type || '').toLowerCase();
    if (normalizedType === 'prod') { return '<span class="tag tag-produccion">PROD</span>'; }
    if (normalizedType === 'test') { return '<span class="tag tag-testing">TEST</span>'; }
    return '';
}

function canonicalEnvironmentName(type, fallback) {
    const normalizedType = String(type || '').toLowerCase();
    if (normalizedType === 'prod') { return 'PROD'; }
    if (normalizedType === 'test') { return 'TEST'; }
    return String(fallback || '');
}

function actionButton(icon, title, action, clientId, environmentId, module) {
    const iconMarkup = icon === 'plus'
        ? '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>'
        : icon === 'edit'
            ? '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M17 3a2.85 2.85 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5z"/></svg>'
            : '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 6h18M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2m3 0v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6h14zM10 11v6M14 11v6"/></svg>';
    return '<button class="icon-button config-icon" type="button" title="' + escapeMarkup(title) + '" aria-label="' + escapeMarkup(title) + '" data-client-id="' + escapeMarkup(clientId) + '" data-environment-id="' + escapeMarkup(environmentId || '') + '" data-module="' + escapeMarkup(module || '') + '" data-action="' + escapeMarkup(action) + '">' + iconMarkup + '</button>';
}

function moduleLabel(module) {
    return String(module || '').toLowerCase() === 'erp' ? 'ERP' : 'Comercial';
}

function environmentDetails(environment) {
    const details = ['<small>' + escapeMarkup(environment.id) + ' | KB: ' + escapeMarkup(environment.kbPath) + '</small>'];
    if (String(environment.host || '').trim()) { details.push('<small>Host: ' + escapeMarkup(environment.host) + '</small>'); }
    if (String(environment.baseUrl || '').trim()) { details.push('<small>Base URL: ' + escapeMarkup(environment.baseUrl) + '</small>'); }
    return details.join('');
}

class GlmCrudList extends HTMLElement {
    constructor() {
        super();
        this.data = { clients: [], errors: [] };
        this.filter = '';
        this.moduleFilter = '';
    }

    connectedCallback() { this.render(); }

    set configuration(value) {
        this.data = value || { clients: [], errors: [] };
        this.render();
    }

    get configuration() { return this.data; }

    set searchValue(value) {
        this.filter = String(value || '');
        this.render();
    }

    set moduleValue(value) {
        this.moduleFilter = String(value || '').toLowerCase();
        this.render();
    }

    render() {
        const clients = this.data.clients || [];
        const errors = this.data.errors || [];
        const normalizedFilter = this.filter.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
        const filteredClients = clients.filter(function (client) {
            const name = String(client.nombre || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
            const id = String(client.id || '').toLowerCase();
            const moduleMatches = !this.moduleFilter || (client.ambientes || []).some(function (environment) {
                return String(environment.modulo || '').toLowerCase() === this.moduleFilter;
            }, this);
            return moduleMatches && (!normalizedFilter || name.indexOf(normalizedFilter) >= 0 || id.indexOf(normalizedFilter) >= 0);
        }, this);
        let markup = errors.map(function (error) { return '<div class="config-error">' + escapeMarkup(error) + '</div>'; }).join('');
        markup += filteredClients.map(function (client) {
            const environments = client.ambientes || [];
            const visibleEnvironments = this.moduleFilter ? environments.filter(function (environment) {
                return String(environment.modulo || '').toLowerCase() === this.moduleFilter;
            }, this) : environments;
            const packageNames = client.packagenames || {};
            const combinations = {};
            environments.forEach(function (environment) {
                combinations[String(environment.modulo || '').toLowerCase() + '|' + String(environment.tipo || '').toLowerCase()] = true;
            });
            const canAddEnvironment = environments.length < 4 && ['comercial', 'erp'].some(function (module) {
                return ['test', 'prod'].some(function (type) { return !combinations[module + '|' + type]; });
            });
            const addEnvironment = canAddEnvironment ? actionButton('plus', 'Agregar ambiente', 'add-environment', client.id, '', '') : '';
            const modules = ['comercial', 'erp'].filter(function (module) {
                return visibleEnvironments.some(function (environment) { return String(environment.modulo || '').toLowerCase() === module; });
            });
            const moduleMarkup = modules.map(function (module) {
                const moduleEnvironmentsMarkup = visibleEnvironments.filter(function (environment) {
                    return String(environment.modulo || '').toLowerCase() === module;
                }).map(function (environment) {
                    return '<div class="config-row config-environment"><span class="config-env-name"><strong>' + escapeMarkup(canonicalEnvironmentName(environment.tipo, environment.nombre)) + '</strong><span class="config-tags">' + environmentTypePill(environment.tipo) + '</span>' + environmentDetails(environment) + '</span><span class="config-row-actions">' + actionButton('edit', 'Editar ambiente', 'edit-environment', client.id, environment.id, environment.modulo) + actionButton('trash', 'Eliminar ambiente', 'delete-environment', client.id, environment.id, environment.modulo) + '</span></div>';
                }).join('');
                const packageName = String(packageNames[module] || '').trim();
                return '<div class="config-module"><div class="config-module-heading"><span><strong>' + moduleLabel(module) + '</strong><small>' + (packageName ? 'Package name: ' + escapeMarkup(packageName) : 'Sin package name') + '</small></span></div><div class="configuration-environments">' + moduleEnvironmentsMarkup + '</div></div>';
            }).join('');
            return '<section class="config-client"><div class="config-row config-client-heading"><span><strong>' + escapeMarkup(client.nombre) + '</strong><small>' + escapeMarkup(client.id) + '</small></span><span class="config-row-actions">' + actionButton('edit', 'Editar cliente', 'edit-client', client.id, '', '') + actionButton('trash', 'Eliminar cliente', 'delete-client', client.id, '', '') + addEnvironment + '</span></div>' + (moduleMarkup || '<div class="empty-state">No hay ambientes configurados.</div>') + '</section>';
        }, this).join('');
        this.innerHTML = markup || '<div class="empty-state">No hay clientes configurados.</div>';
    }
}

function registerCrudList() {
    if (!customElements.get('glm-crud-list')) {
        customElements.define('glm-crud-list', GlmCrudList);
    }
}

export { registerCrudList };
