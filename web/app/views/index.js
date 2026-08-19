import { createDashboardView } from './dashboard.js';
import { createDocumentationView } from './documentation.js';
import { createLogsView } from './logs.js';
import { createConfigurationView } from './configuration.js';

function createPanelViews() {
    return {
        dashboard: createDashboardView(),
        documentation: createDocumentationView(),
        logs: createLogsView(),
        configuration: createConfigurationView()
    };
}

export { createPanelViews };
