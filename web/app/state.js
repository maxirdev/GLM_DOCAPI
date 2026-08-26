const panelState = {
    clientDropdown: null,
    moduleDropdown: null,
    environmentDropdown: null,
    currentJobId: null,
    pollingTimer: null,
    lastState: null,
    endpointServices: [],
    contextLogs: [],
    configurationSnapshot: null,
    configurationData: { configuration: null, configHash: '', errores: [] },
    activeTab: 'estado',
    operationResults: { exportar: null, generarPdf: null },
    contextLocked: false,
    environments: {},
    selectedFallbackXpz: null,
    contextActivationPending: false
};

function resetContextState() {
    panelState.lastState = null;
    panelState.endpointServices = [];
    panelState.contextLogs = [];
    panelState.selectedFallbackXpz = null;
    panelState.operationResults = { exportar: null, generarPdf: null };
}

export { panelState, resetContextState };
