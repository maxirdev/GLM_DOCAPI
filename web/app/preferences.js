const defaultUiPreferences = {
    theme: 'light',
    activeTab: 'estado',
    views: {
        documentacion: 'list',
        logs: 'list'
    },
    pageSize: {
        documentacion: 25
    },
    filters: {
        documentacion: '',
        logs: 'todos'
    }
};

const uiPreferencesStorageKey = 'glm-panel-ui:v1';
const validTabs = ['estado', 'exportar', 'endpoints', 'documentacion', 'logs', 'configuracion'];
const validViewModes = ['cards', 'list'];
const validLogFilters = ['todos', 'error', 'ok', 'advertencia', 'review', 'validacion'];
const validPageSizes = [25, 50, 100];

function createDefaultUiPreferences() {
    return {
        theme: defaultUiPreferences.theme,
        activeTab: defaultUiPreferences.activeTab,
        views: Object.assign({}, defaultUiPreferences.views),
        pageSize: Object.assign({}, defaultUiPreferences.pageSize),
        filters: Object.assign({}, defaultUiPreferences.filters)
    };
}

function isValidPreferences(preferences) {
    return Boolean(preferences && typeof preferences === 'object' &&
        (preferences.theme === 'light' || preferences.theme === 'dark') &&
        validTabs.indexOf(preferences.activeTab) >= 0 &&
        preferences.views && typeof preferences.views === 'object' &&
        validViewModes.indexOf(preferences.views.documentacion) >= 0 &&
        validViewModes.indexOf(preferences.views.logs) >= 0 &&
        preferences.pageSize && validPageSizes.indexOf(preferences.pageSize.documentacion) >= 0 &&
        preferences.filters && typeof preferences.filters === 'object' &&
        typeof preferences.filters.documentacion === 'string' &&
        validLogFilters.indexOf(preferences.filters.logs) >= 0);
}

function copyValidPreferences(preferences) {
    return {
        theme: preferences.theme,
        activeTab: preferences.activeTab,
        views: {
            documentacion: preferences.views.documentacion,
            logs: preferences.views.logs
        },
        pageSize: {
            documentacion: preferences.pageSize.documentacion
        },
        filters: {
            documentacion: preferences.filters.documentacion,
            logs: preferences.filters.logs
        }
    };
}

function readUiPreferences() {
    const fallbackPreferences = createDefaultUiPreferences();
    try {
        const serializedPreferences = window.localStorage.getItem(uiPreferencesStorageKey);
        if (!serializedPreferences) { return fallbackPreferences; }
        const parsedPreferences = JSON.parse(serializedPreferences);
        return isValidPreferences(parsedPreferences) ? copyValidPreferences(parsedPreferences) : fallbackPreferences;
    } catch (error) {
        return fallbackPreferences;
    }
}

function saveUiPreferences(preferences) {
    if (!isValidPreferences(preferences)) { return false; }
    try {
        window.localStorage.setItem(uiPreferencesStorageKey, JSON.stringify(copyValidPreferences(preferences)));
        return true;
    } catch (error) {
        return false;
    }
}

export {
    defaultUiPreferences,
    uiPreferencesStorageKey,
    createDefaultUiPreferences,
    isValidPreferences,
    readUiPreferences,
    saveUiPreferences
};
