function createConfigurationView() {
    const filterElement = document.getElementById('configuration-filter');
    const listElement = document.getElementById('configuration-list');
    return {
        getFilter: function () { return filterElement ? filterElement.value : ''; },
        setConfiguration: function (configuration, errors, filter) {
            if (!listElement) { return; }
            listElement.configuration = { clients: configuration || [], errors: errors || [] };
            listElement.searchValue = filter === undefined ? this.getFilter() : filter;
        }
    };
}

export { createConfigurationView };
