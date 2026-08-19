const panelApiClient = {
    request: async function (url, options) {
        const requestOptions = Object.assign({ cache: 'no-store' }, options || {});
        const response = await window.fetch(url, requestOptions);
        const contentType = response.headers.get('content-type') || '';
        const payload = contentType.indexOf('application/json') >= 0
            ? await response.json()
            : await response.text();

        if (!response.ok || (payload && typeof payload === 'object' && payload.ok === false)) {
            const message = payload && typeof payload === 'object' && payload.error
                ? payload.error
                : 'La solicitud al servidor no se pudo completar.';
            throw new Error(message);
        }
        return payload;
    },

    get: function (url) {
        return this.request(url);
    },

    sendJson: function (url, method, body) {
        return this.request(url, {
            method: method,
            headers: {
                'Content-Type': 'application/json',
                'X-Panel-Token': window.PANEL_TOKEN || ''
            },
            body: JSON.stringify(body || {})
        });
    },

    downloadUrl: function (documentName) {
        return '/api/documentos/' + encodeURIComponent(documentName);
    }
};

export { panelApiClient };
