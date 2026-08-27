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

function renderInlineMarkdown(value) {
    var escapedValue = escapeHtml(value);
    var inlinePattern = /`([^`\r\n]*)`|\*\*([^*\r\n]+)\*\*/g;
    var renderedParts = [];
    var lastMatchEnd = 0;
    var match;
    while ((match = inlinePattern.exec(escapedValue)) !== null) {
        renderedParts.push(escapedValue.slice(lastMatchEnd, match.index));
        if (match[1] !== undefined) {
            renderedParts.push('<code>' + match[1] + '</code>');
        } else {
            renderedParts.push('<strong>' + match[2] + '</strong>');
        }
        lastMatchEnd = inlinePattern.lastIndex;
    }
    renderedParts.push(escapedValue.slice(lastMatchEnd));
    return renderedParts.join('');
}

function renderMarkdown(markdown) {
    var normalizedMarkdown = String(markdown || '').replace(/\r\n?/g, '\n');
    var lines = normalizedMarkdown.split('\n');
    var renderedBlocks = [];
    var paragraphLines = [];
    var listItems = [];

    function flushParagraph() {
        if (!paragraphLines.length) { return; }
        renderedBlocks.push('<p>' + renderInlineMarkdown(paragraphLines.join(' ')) + '</p>');
        paragraphLines = [];
    }

    function flushList() {
        if (!listItems.length) { return; }
        renderedBlocks.push('<ul>' + listItems.map(function (item) {
            return '<li>' + renderInlineMarkdown(item) + '</li>';
        }).join('') + '</ul>');
        listItems = [];
    }

    lines.forEach(function (line) {
        var headingMatch = line.match(/^(#{1,3})\s+(.+?)\s*$/);
        var listMatch = line.match(/^\s*-\s+(.+?)\s*$/);
        if (!line.trim()) {
            flushParagraph();
            flushList();
        } else if (headingMatch) {
            flushParagraph();
            flushList();
            var headingLevel = headingMatch[1].length;
            renderedBlocks.push('<h' + headingLevel + '>' + renderInlineMarkdown(headingMatch[2]) + '</h' + headingLevel + '>');
        } else if (listMatch) {
            flushParagraph();
            listItems.push(listMatch[1]);
        } else {
            flushList();
            paragraphLines.push(line.trim());
        }
    });
    flushParagraph();
    flushList();
    return renderedBlocks.join('\n');
}

export { escapeHtml, getProperty, normalize, renderTextList, renderInlineMarkdown, renderMarkdown };
