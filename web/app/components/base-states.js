function getAttributeValue(element, name, fallback) {
    const value = element.getAttribute(name);
    return value === null ? fallback : value;
}

function escapeMarkup(value) {
    return String(value || '').replace(/[&<>"']/g, function (character) {
        return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character];
    });
}

class GlmLoadingState extends HTMLElement {
    connectedCallback() {
        this.setAttribute('role', 'status');
        this.setAttribute('aria-live', 'polite');
        this.render();
    }

    render() {
        const message = getAttributeValue(this, 'message', 'Cargando información...');
        const skeletonCount = Math.max(1, Number(getAttributeValue(this, 'skeletons', '3')) || 3);
        this.innerHTML = '<div class="component-state component-loading"><span class="component-spinner" aria-hidden="true"></span><span>' + escapeMarkup(message) + '</span><div class="component-skeletons" aria-hidden="true">' +
            new Array(skeletonCount).fill('<span class="component-skeleton"></span>').join('') + '</div></div>';
    }
}

class GlmEmptyState extends HTMLElement {
    connectedCallback() {
        this.setAttribute('role', 'status');
        this.render();
    }

    render() {
        const message = getAttributeValue(this, 'message', 'No hay información disponible.');
        this.innerHTML = '<div class="component-state component-empty"><strong>Sin resultados</strong><span>' + escapeMarkup(message) + '</span><slot></slot></div>';
    }
}

class GlmErrorState extends HTMLElement {
    connectedCallback() {
        this.setAttribute('role', 'alert');
        this.render();
    }

    render() {
        const message = getAttributeValue(this, 'message', 'No se pudo cargar la información.');
        const actionLabel = this.getAttribute('action-label');
        const action = actionLabel ? '<button type="button" class="component-state-action">' + escapeMarkup(actionLabel) + '</button>' : '';
        this.innerHTML = '<div class="component-state component-error"><strong>Ocurrió un error</strong><span>' + escapeMarkup(message) + '</span>' + action + '</div>';
        const actionButton = this.querySelector('.component-state-action');
        if (actionButton) {
            actionButton.addEventListener('click', () => this.dispatchEvent(new CustomEvent('retry', { bubbles: true })));
        }
    }
}

class GlmToast extends HTMLElement {
    connectedCallback() {
        this.setAttribute('role', 'status');
        this.setAttribute('aria-live', 'polite');
        this.render();
    }

    render() {
        const type = ['info', 'success', 'warning', 'error'].indexOf(getAttributeValue(this, 'type', 'info')) >= 0
            ? getAttributeValue(this, 'type', 'info')
            : 'info';
        const message = getAttributeValue(this, 'message', this.textContent.trim());
        this.className = 'component-toast component-toast-' + type;
        this.textContent = message;
    }
}

class GlmSpinner extends HTMLElement {
    connectedCallback() {
        this.setAttribute('role', 'status');
        this.setAttribute('aria-label', getAttributeValue(this, 'label', 'Cargando'));
        this.innerHTML = '<span class="component-spinner" aria-hidden="true"></span><span class="visually-hidden">' + this.getAttribute('aria-label') + '</span>';
    }
}

class GlmProgress extends HTMLElement {
    static get observedAttributes() { return ['value', 'max', 'label']; }

    connectedCallback() { this.render(); }

    attributeChangedCallback() {
        if (this.isConnected) { this.render(); }
    }

    render() {
        const maximum = Math.max(1, Number(getAttributeValue(this, 'max', '100')) || 100);
        const value = Math.min(maximum, Math.max(0, Number(getAttributeValue(this, 'value', '0')) || 0));
        const label = getAttributeValue(this, 'label', 'Progreso');
        this.setAttribute('role', 'progressbar');
        this.setAttribute('aria-label', label);
        this.setAttribute('aria-valuemin', '0');
        this.setAttribute('aria-valuemax', String(maximum));
        this.setAttribute('aria-valuenow', String(value));
        this.innerHTML = '<span class="component-progress-track"><span class="component-progress-value" style="width:' + ((value / maximum) * 100) + '%"></span></span>';
    }
}

function registerBaseStateComponents() {
    const components = {
        'glm-loading-state': GlmLoadingState,
        'glm-empty-state': GlmEmptyState,
        'glm-error-state': GlmErrorState,
        'glm-toast': GlmToast,
        'glm-spinner': GlmSpinner,
        'glm-progress': GlmProgress
    };
    Object.keys(components).forEach(function (name) {
        if (!customElements.get(name)) { customElements.define(name, components[name]); }
    });
}

export { registerBaseStateComponents };
