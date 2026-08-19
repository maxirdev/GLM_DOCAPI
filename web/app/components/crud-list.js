function escapeMarkup(value) {
    return String(value === null || value === undefined ? '' : value).replace(/[&<>"']/g, function (character) {
        return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character];
    });
}

function environmentTypePill(type) {
    const normalizedType = String(type || '').toLowerCase();
    if (normalizedType === 'prod') { return '<span class="tag tag-produccion">Producción</span>'; }
    if (normalizedType === 'test') { return '<span class="tag tag-testing">Testing</span>'; }
    return '';
}

function actionButton(icon, title, action, clientId, environmentId) {
    const iconMarkup = icon === 'plus'
        ? '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>'
        : icon === 'edit'
            ? '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M17 3a2.85 2.85 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5z"/></svg>'
            : '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 6h18M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2m3 0v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6h14zM10 11v6M14 11v6"/></svg>';
    return '<button class="icon-button config-icon" type="button" title="' + escapeMarkup(title) + '" aria-label="' + escapeMarkup(title) + '" data-client-id="' + escapeMarkup(clientId) + '" data-environment-id="' + escapeMarkup(environmentId || '') + '" data-action="' + escapeMarkup(action) + '">' + iconMarkup + '</button>';
}

class GlmCrudList extends HTMLElement {
    constructor() {
        super();
        this.data = { clients: [], errors: [] };
        this.filter = '';
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

    render() {
        const clients = this.data.clients || [];
        const errors = this.data.errors || [];
        const normalizedFilter = this.filter.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
        const filteredClients = clients.filter(function (client) {
            const name = String(client.nombre || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
            const id = String(client.id || '').toLowerCase();
            return !normalizedFilter || name.indexOf(normalizedFilter) >= 0 || id.indexOf(normalizedFilter) >= 0;
        });
        let markup = errors.map(function (error) { return '<div class="config-error">' + escapeMarkup(error) + '</div>'; }).join('');
        markup += filteredClients.map(function (client) {
            const environments = client.ambientes || [];
            const types = environments.map(function (environment) { return String(environment.tipo || '').toLowerCase(); });
            const canAddEnvironment = !(types.indexOf('test') >= 0 && types.indexOf('prod') >= 0);
            const environmentsMarkup = environments.map(function (environment) {
                return '<div class="config-row config-environment"><span class="config-env-name"><strong>' + escapeMarkup(environment.nombre) + '</strong>' + environmentTypePill(environment.tipo) + '<small>' + escapeMarkup(environment.id) + ' | KB: ' + escapeMarkup(environment.kbPath) + '</small></span><span class="config-row-actions">' + actionButton('edit', 'Editar ambiente', 'edit-environment', client.id, environment.id) + actionButton('trash', 'Eliminar ambiente', 'delete-environment', client.id, environment.id) + '</span></div>';
            }).join('');
            const addEnvironment = canAddEnvironment ? actionButton('plus', 'Agregar ambiente', 'add-environment', client.id, '') : '';
            return '<section class="config-client"><div class="config-row config-client-heading"><span><strong>' + escapeMarkup(client.nombre) + '</strong><small>' + escapeMarkup(client.id) + ' | ' + escapeMarkup(client.packagename || 'Sin package name') + '</small></span><span class="config-row-actions">' + actionButton('edit', 'Editar cliente', 'edit-client', client.id, '') + actionButton('trash', 'Eliminar cliente', 'delete-client', client.id, '') + addEnvironment + '</span></div><div class="configuration-environments">' + (environmentsMarkup || '<div class="empty-state">No hay ambientes configurados.</div>') + '</div></section>';
        }).join('');
        this.innerHTML = markup || '<div class="empty-state">No hay clientes configurados.</div>';
    }
}

function registerCrudList() {
    if (!customElements.get('glm-crud-list')) {
        customElements.define('glm-crud-list', GlmCrudList);
    }
}

export { registerCrudList };
