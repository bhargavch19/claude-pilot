import yaml from 'js-yaml';

const FRONTMATTER = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?/;

export class TddParseError extends Error {
  constructor(message) {
    super(message);
    this.name = 'TddParseError';
  }
}

export function parseTdd(source, file = '<unknown>') {
  // Windows editors write a UTF-8 BOM by default. It sits before the opening
  // `---`, so the frontmatter regex missed it and the file was quarantined as
  // "missing YAML frontmatter" — an error naming the wrong cause, sending the
  // author to inspect frontmatter that was correct all along. Only a leading
  // U+FEFF is a byte-order mark; one appearing later in the document is
  // content and is left alone.
  const text = source.charCodeAt(0) === 0xfeff ? source.slice(1) : source;

  const m = FRONTMATTER.exec(text);
  if (!m) throw new TddParseError(`${file}: missing YAML frontmatter`);

  let data;
  try {
    data = yaml.load(m[1]) ?? {};
  } catch (e) {
    throw new TddParseError(`${file}: ${e.message}`);
  }

  if (typeof data !== 'object' || Array.isArray(data)) {
    throw new TddParseError(`${file}: frontmatter must be a mapping`);
  }

  return { data, body: text.slice(m[0].length) };
}

export function serializeTdd({ data, body }) {
  // js-yaml's dump() always emits LF-terminated lines, so the frontmatter
  // block is LF regardless of the source. To avoid emitting a file with
  // mixed line endings (LF delimiters/frontmatter, CRLF body), serialize
  // output is deliberately normalised to LF throughout, even when the
  // in-memory `body` was read from a CRLF-authored source.
  const front = yaml.dump(data, { lineWidth: -1, noRefs: true });
  const normalizedBody = body.replace(/\r\n/g, '\n');
  return `---\n${front}---\n${normalizedBody}`;
}
