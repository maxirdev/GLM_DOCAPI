import { panelApiClient } from './api-client.js';
import { panelState, resetContextState } from './state.js';
import {
    defaultUiPreferences,
    createDefaultUiPreferences,
    readUiPreferences,
    saveUiPreferences
} from './preferences.js';
import { escapeHtml, getProperty, normalize, renderTextList } from './render-utils.js';
import { registerBaseStateComponents } from './components/base-states.js';
import { registerServiceComponents } from './components/service-components.js';
import { registerOperationConsole } from './components/operation-console.js?v=20260820-pdf-oneclick-v6';
import { registerCrudList } from './components/crud-list.js';
import { createPanelViews } from './views/index.js';
import { registerAppShell } from './components/app-shell.js';

// El punto de entrada prepara servicios comunes antes de migrar cada vista.
window.panelApiClient = panelApiClient;
window.panelState = panelState;
window.resetPanelContextState = resetContextState;
window.panelUiPreferences = {
    defaults: defaultUiPreferences,
    createDefaults: createDefaultUiPreferences,
    read: readUiPreferences,
    save: saveUiPreferences
};
window.panelRenderUtils = { escapeHtml, getProperty, normalize, renderTextList };
registerBaseStateComponents();
registerServiceComponents();
registerOperationConsole();
registerCrudList();
registerAppShell();
window.panelViews = createPanelViews();

const loadedUiPreferences = readUiPreferences();
document.documentElement.setAttribute('data-theme', loadedUiPreferences.theme);
window.panelUiPreferences.current = loadedUiPreferences;

const legacyApplicationScript = document.createElement('script');
legacyApplicationScript.src = 'app.js?v=20260825-context-module-v1';
legacyApplicationScript.async = false;
document.body.appendChild(legacyApplicationScript);
