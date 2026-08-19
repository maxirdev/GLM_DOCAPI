function createLogsView() {
    const filterElement = document.getElementById('log-filter');
    const listElement = document.getElementById('log-list');
    return {
        getFilter: function () { return filterElement ? filterElement.value : 'todos'; },
        clear: function () {
            if (listElement) { listElement.innerHTML = '<div class="empty-state">No hay logs disponibles para este contexto.</div>'; }
        }
    };
}

export { createLogsView };
