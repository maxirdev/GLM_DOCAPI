function createConfigurationView() {
    const filterElement = document.getElementById('configuration-filter');
    const moduleFilterElement = document.getElementById('configuration-module-filter');
    const listElement = document.getElementById('configuration-list');
    return {
        getFilter: function () { return filterElement ? filterElement.value : ''; },
        getModuleFilter: function () { return moduleFilterElement ? moduleFilterElement.value : ''; },
        setConfiguration: function (configuration, errors, filter, moduleFilter) {
            if (!listElement) { return; }
            listElement.configuration = { clients: configuration || [], errors: errors || [] };
            listElement.searchValue = filter === undefined ? this.getFilter() : filter;
            listElement.moduleValue = moduleFilter === undefined ? this.getModuleFilter() : moduleFilter;
        }
    };
}

export { createConfigurationView };
