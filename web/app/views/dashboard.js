function createDashboardView() {
    const titleElement = document.getElementById('dashboard-title');
    const summaryElement = document.getElementById('state-summary');
    const validationElement = document.getElementById('validation-list');
    return {
        clear: function () {
            if (titleElement) { titleElement.textContent = 'Dashboard'; }
            if (summaryElement) { summaryElement.innerHTML = ''; }
            if (validationElement) { validationElement.innerHTML = ''; }
        },
        setTitle: function (title) {
            if (titleElement) { titleElement.textContent = title || 'Dashboard'; }
        }
    };
}

export { createDashboardView };
