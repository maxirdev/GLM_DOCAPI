function escapeHtml(value) {
    return String(value || '').replace(/[&<>"']/g, function (character) {
        return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character];
    });
}

function getProperty(object, lowerName, upperName) {
    if (!object) { return ''; }
    return object[lowerName] !== undefined && object[lowerName] !== null
        ? object[lowerName]
        : (object[upperName] || '');
}

function normalize(value) {
    return String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
}

function renderTextList(items, emptyMessage) {
    if (!items || !items.length) { return '<p class="empty-state">' + escapeHtml(emptyMessage || 'Sin datos.') + '</p>'; }
    return items.map(function (item) { return '<span>' + escapeHtml(item) + '</span>'; }).join('');
}

export { escapeHtml, getProperty, normalize, renderTextList };
