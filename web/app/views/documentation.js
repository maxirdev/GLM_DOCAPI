function createDocumentationView() {
    const filterElement = document.getElementById('documentation-filter');
    const serviceListElement = document.getElementById('documentation-service-list');
    return {
        getFilter: function () { return filterElement ? filterElement.value : ''; },
        clearServices: function () {
            if (serviceListElement) { serviceListElement.innerHTML = ''; }
        },
        setFilter: function (filter) {
            if (filterElement) { filterElement.value = filter || ''; }
        }
    };
}

export { createDocumentationView };
