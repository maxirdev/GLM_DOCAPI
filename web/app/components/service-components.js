function escapeMarkup(value) {
    return String(value === null || value === undefined ? '' : value).replace(/[&<>"']/g, function (character) {
        return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character];
    });
}

function getServiceValue(service, name, fallback) {
    return service && service[name] !== undefined && service[name] !== null ? service[name] : (fallback || '');
}

function serviceStatus(service) {
    return String(getServiceValue(service, 'estado', 'Sin estado'));
}

function serviceHasPdf(service) {
    return Boolean(service && service.pdf && service.pdf.disponible && service.pdf.nombre);
}

class GlmStatCard extends HTMLElement {
    static get observedAttributes() { return ['label', 'value', 'detail']; }

    connectedCallback() { this.render(); }

    attributeChangedCallback() {
        if (this.isConnected) { this.render(); }
    }

    render() {
        this.innerHTML = '<article class="component-stat-card example-stat"><span class="component-stat-label example-stat-label">' + escapeMarkup(this.getAttribute('label') || '') + '</span><strong class="component-stat-value example-stat-value">' + escapeMarkup(this.getAttribute('value') || '0') + '</strong><span class="component-stat-detail example-stat-note">' + escapeMarkup(this.getAttribute('detail') || '') + '</span></article>';
    }
}

class GlmServiceCard extends HTMLElement {
    constructor() {
        super();
        this.service = null;
        this.expanded = false;
    }

    connectedCallback() { this.render(); }

    set data(value) {
        this.service = value || null;
        this.render();
    }

    get data() { return this.service; }

    render() {
        const service = this.service || {};
        const fullyQualifiedName = getServiceValue(service, 'fullyQualifiedName', getServiceValue(service, 'nombre', 'Servicio'));
        const endpoint = getServiceValue(service, 'endpoint', 'Sin endpoint');
        const version = service.versionDisponible ? getServiceValue(service, 'version', 'Sin versión') : 'Sin versión';
        const generatedAt = service.fecha ? new Date(service.fecha).toLocaleDateString('es-AR') : 'Sin fecha de generación';
        const pdfAvailable = serviceHasPdf(service);
        const pdfLink = pdfAvailable
            ? '<a class="component-service-pdf" href="/api/documentos/' + encodeURIComponent(service.pdf.nombre) + '" download target="_blank" rel="noopener">Descargar PDF</a>'
            : '<span class="component-service-unavailable">PDF no disponible</span>';
        this.innerHTML = '<article class="component-service-card service-card' + (this.expanded ? ' is-expanded is-open' : '') + '"><button type="button" class="component-service-toggle service-summary" aria-expanded="' + (this.expanded ? 'true' : 'false') + '"><span class="service-summary-main"><strong class="service-name">' + escapeMarkup(getServiceValue(service, 'nombre', fullyQualifiedName)) + '</strong><small class="service-fqn">Versión ' + escapeMarkup(version) + '</small><span class="service-card-meta">Generado: ' + escapeMarkup(generatedAt) + ' · Versión ' + escapeMarkup(version) + '</span></span><span class="service-chevron" aria-hidden="true">⌄</span></button><div class="component-service-details service-details"' + (this.expanded ? '' : ' hidden') + '><dl><dt>FQN</dt><dd>' + escapeMarkup(fullyQualifiedName) + '</dd><dt>Endpoint</dt><dd>' + escapeMarkup(endpoint) + '</dd></dl><div class="component-service-actions service-actions"><button type="button" class="component-service-detail primary detail-button">Ver detalle documental</button>' + pdfLink + '</div></div></article>';
        this.querySelector('.component-service-toggle').addEventListener('click', () => {
            this.expanded = !this.expanded;
            this.render();
            this.dispatchEvent(new CustomEvent('service-expand', { bubbles: true, detail: { service: this.service, expanded: this.expanded } }));
        });
        this.querySelector('.component-service-detail').addEventListener('click', () => {
            this.dispatchEvent(new CustomEvent('service-detail', { bubbles: true, detail: { service: this.service } }));
        });
    }
}

class GlmDetailDialog extends HTMLElement {
    constructor() {
        super();
        this.service = null;
    }

    connectedCallback() {
        this.render();
        this.addEventListener('click', (event) => {
            if (event.target === this.querySelector('dialog')) { this.close(); }
        });
    }

    open(service) {
        this.service = service || null;
        this.render();
        const dialog = this.querySelector('dialog');
        if (dialog && typeof dialog.showModal === 'function') { dialog.showModal(); }
        else if (dialog) { dialog.setAttribute('open', ''); }
    }

    close() {
        const dialog = this.querySelector('dialog');
        if (dialog) { dialog.close(); }
        this.dispatchEvent(new CustomEvent('detail-close', { bubbles: true }));
    }

    render() {
        const service = this.service || {};
        const pdfAvailable = serviceHasPdf(service);
        const pdfLink = pdfAvailable
            ? '<a class="primary" href="/api/documentos/' + encodeURIComponent(service.pdf.nombre) + '" download target="_blank" rel="noopener">Descargar PDF</a>'
            : '';
        this.innerHTML = '<dialog class="component-detail-dialog example-dialog" aria-labelledby="component-detail-title"><div class="component-detail-heading example-dialog-header"><div><h2 id="component-detail-title">Detalle documental</h2><p>Información del endpoint seleccionado</p></div><button type="button" class="component-detail-close example-dialog-close" aria-label="Cerrar detalle">Cerrar</button></div><dl class="example-detail-list"><div><dt>FQN</dt><dd>' + escapeMarkup(getServiceValue(service, 'fullyQualifiedName', 'Sin FQN')) + '</dd></div><div><dt>Endpoint</dt><dd>' + escapeMarkup(getServiceValue(service, 'endpoint', 'Sin endpoint')) + '</dd></div><div><dt>Estado</dt><dd>' + escapeMarkup(serviceStatus(service)) + '</dd></div><div><dt>Versión</dt><dd>' + escapeMarkup(service.versionDisponible ? getServiceValue(service, 'version', 'Sin versión') : 'Sin versión') + '</dd></div><div><dt>Disponibilidad documental</dt><dd>' + (pdfAvailable ? 'PDF disponible' : 'PDF no disponible') + '</dd></div></dl><div class="component-detail-actions service-actions">' + pdfLink + '</div></dialog>';
        this.querySelector('.component-detail-close').addEventListener('click', () => this.close());
        this.querySelector('dialog').addEventListener('cancel', () => this.dispatchEvent(new CustomEvent('detail-close', { bubbles: true })));
    }
}

function registerServiceComponents() {
    const components = {
        'glm-stat-card': GlmStatCard,
        'glm-service-card': GlmServiceCard,
        'glm-detail-dialog': GlmDetailDialog
    };
    Object.keys(components).forEach(function (name) {
        if (!customElements.get(name)) { customElements.define(name, components[name]); }
    });
}

export { registerServiceComponents };
