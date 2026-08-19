class GlmAppShell extends HTMLElement {
    connectedCallback() {
        this.classList.add('glm-app-shell');
        this.setAttribute('data-component', 'app-shell');
    }
}

function registerAppShell() {
    if (!customElements.get('glm-app-shell')) {
        customElements.define('glm-app-shell', GlmAppShell);
    }
}

export { registerAppShell };
