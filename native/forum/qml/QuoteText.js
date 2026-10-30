.pragma library

// Presentation only: the signed, persisted body keeps its original quote syntax.
function segments(body) {
    var lines = body.replace(/\r\n/g, "\n").split("\n");
    var result = [], plain = [];
    function reference(line) {
        return /^>>[0-9a-f]{8,64}$/i.test(line);
    }
    function flush() {
        var text = plain.join("\n").replace(/^\n+|\n+$/g, "");
        if (text.length)
            result.push({reference: "", text: text});
        plain = [];
    }
    for (var i = 0; i < lines.length; ++i) {
        if (!reference(lines[i]) || i + 1 >= lines.length || !/^>($| )/.test(lines[i + 1])) {
            plain.push(lines[i]);
            continue;
        }
        flush();
        var label = lines[i], quoted = [];
        while (i + 1 < lines.length && /^>($| )/.test(lines[i + 1]))
            quoted.push(lines[++i].replace(/^> ?/, ""));
        result.push({reference: label, text: quoted.join("\n")});
    }
    // Leave ordinary posts exactly as written, including leading whitespace.
    if (!result.length)
        return [{reference: "", text: body}];
    flush();
    return result;
}
