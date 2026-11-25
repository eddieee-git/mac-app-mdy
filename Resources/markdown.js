// Mdy — 외부 의존성 없는 GitHub 스타일(GFM) 마크다운 렌더러
(function (global) {
  'use strict';

  const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const safeUrl = (u) => (/^\s*(javascript|vbscript):/i.test(u) ? '#' : u.replace(/ /g, '%20'));
  const normRef = (s) => s.trim().replace(/\s+/g, ' ').toLowerCase();

  let refs = {};
  let slugCounts = {};
  let footnotes = {};
  let footnoteOrder = [];
  let headings = [];
  const TOC_TOKEN = '\u0003MDY-TOC\u0003';

  // [TOC] 자리에 넣을 목차
  function tocHtml() {
    if (!headings.length) return '';
    const min = Math.min(...headings.map((h) => h.level));
    let html = '';
    let depth = 0;
    for (const h of headings) {
      const d = h.level - min + 1;
      while (depth < d) { html += '<ul>'; depth++; }
      while (depth > d) { html += '</ul>'; depth--; }
      html += `<li><a href="#${esc(h.id)}">${h.html.replace(/<a\b[^>]*>|<\/a>/g, '')}</a></li>`;
    }
    while (depth-- > 0) html += '</ul>';
    return html;
  }

  // ---------------------------------------------------------------- inline

  const keep = (stash, html) => '\u0001' + (stash.push(html) - 1) + '\u0002';
  const BR = '(?:\\\\.|[^\\[\\]\\\\]|\\[(?:\\\\.|[^\\[\\]\\\\])*\\])*';
  const LINK_RE = new RegExp(
    '(!?)\\[(' + BR + ')\\]\\(\\s*(<[^>\\n]*>|(?:[^\\s()\\\\]|\\\\.|\\((?:[^\\s()\\\\]|\\\\.)*\\))*)' +
    '(?:\\s+("[^"]*"|\'[^\']*\'|\\([^)]*\\)))?\\s*\\)', 'g');
  const REF_LINK_RE = new RegExp('(!?)\\[(' + BR + ')\\](?:\\[([^\\]]*)\\])?', 'g');
  const HTML_TAG_RE = /<!--[\s\S]*?-->|<\/?[A-Za-z][A-Za-z0-9-]*(?:\s+[A-Za-z_:][\w:.-]*(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?)*\s*\/?>/g;

  function linkHtml(stash, bang, text, url, title) {
    const t = title ? ` title="${esc(title)}"` : '';
    if (bang) {
      const alt = text.replace(/[*_`~]|\u0001\d+\u0002/g, '');
      return keep(stash, `<img src="${esc(safeUrl(url))}" alt="${esc(alt)}"${t}>`);
    }
    return keep(stash, `<a href="${esc(safeUrl(url))}"${t}>${inlineCore(text, stash)}</a>`);
  }

  function inlineCore(src, stash) {
    let s = src;

    // 코드 스팬이 가장 우선
    s = s.replace(/(`+)(?!`)([\s\S]*?[^`])\1(?!`)/g, (m, ticks, code) => {
      code = code.replace(/\n/g, ' ');
      if (/^ [\s\S]* $/.test(code) && code.trim()) code = code.slice(1, -1);
      return keep(stash, '<code>' + esc(code) + '</code>');
    });

    // 인라인 수식 $...$ (앞뒤 공백이 없어야 하고, 닫는 $ 뒤에 숫자가 오면 안 됨: "$5 와 $10" 은 수식 아님)
    s = s.replace(/(?<!\\)\$(?=[^\s$])((?:\\.|[^$\\\n])+?)(?<=\S)\$(?!\d)/g, (m, tex) =>
      keep(stash, `<span class="math" data-tex="${esc(tex)}">${esc(tex)}</span>`));

    // 각주 참조 [^1]
    s = s.replace(/\[\^([^\]\s]+)\]/g, (m, id) => {
      const fn = footnotes[id];
      if (!fn) return m;
      if (!fn.n) { fn.n = footnoteOrder.push(id); }
      return keep(stash, `<sup class="footnote-ref"><a href="#fn-${esc(id)}" id="fnref-${esc(id)}">${fn.n}</a></sup>`);
    });

    // 자동 링크 <https://...>, <a@b.c>
    s = s.replace(/<((?:https?|ftp|mailto):[^\s<>]+)>/gi, (m, u) => keep(stash, `<a href="${esc(safeUrl(u))}">${esc(u)}</a>`));
    s = s.replace(/<([^\s<>@]+@[^\s<>@]+\.[^\s<>@]+)>/g, (m, u) => keep(stash, `<a href="mailto:${esc(u)}">${esc(u)}</a>`));

    // 인라인 HTML 은 그대로
    s = s.replace(HTML_TAG_RE, (m) => keep(stash, m));

    // 링크와 이미지
    s = s.replace(LINK_RE, (m, bang, text, url, title) => {
      url = url.replace(/^<|>$/g, '').replace(/\\(.)/g, '$1');
      title = title ? title.slice(1, -1) : '';
      return linkHtml(stash, bang, text, url, title);
    });
    s = s.replace(REF_LINK_RE, (m, bang, text, ref) => {
      const def = refs[normRef(ref || text)];
      if (!def) return m;
      return linkHtml(stash, bang, text, def.url, def.title);
    });

    // 줄바꿈과 이스케이프
    s = s.replace(/\\\n/g, () => keep(stash, '<br>') + '\n');
    s = s.replace(/ {2,}\n/g, () => keep(stash, '<br>') + '\n');
    s = s.replace(/\\([!"#$%&'()*+,\-./:;<=>?@[\\\]^_`{|}~])/g, (m, c) => keep(stash, esc(c)));

    s = esc(s);

    // 주소 자동 링크 (GFM)
    s = s.replace(/(^|[\s(（])((?:https?:\/\/|www\.)[^\s<\u0001]*[^\s<\u0001.,:;"')\]!?*_~])/g, (m, pre, u) => {
      const href = u.startsWith('www.') ? 'http://' + u : u;
      return pre + keep(stash, `<a href="${href}">${u}</a>`);
    });

    // 강조
    s = s.replace(/\*\*(?=[^\s*])([\s\S]*?[^\s])\*\*/g, '<strong>$1</strong>');
    s = s.replace(/(^|[^\p{L}\p{N}_])__(?=\S)([\s\S]*?\S)__(?![\p{L}\p{N}_])/gu, '$1<strong>$2</strong>');
    s = s.replace(/\*(?=[^\s*])([\s\S]*?[^\s*])\*/g, '<em>$1</em>');
    s = s.replace(/(^|[^\p{L}\p{N}_])_(?=[^\s_])([\s\S]*?[^\s_])_(?![\p{L}\p{N}_])/gu, '$1<em>$2</em>');
    s = s.replace(/~~(?=\S)([\s\S]*?\S)~~/g, '<del>$1</del>');
    s = s.replace(/==(?=\S)([^=\n]*?\S)==/g, '<mark>$1</mark>');

    return s;
  }

  function restore(s, stash) {
    for (let guard = 0; guard < 20 && /\u0001\d+\u0002/.test(s); guard++) {
      s = s.replace(/\u0001(\d+)\u0002/g, (m, i) => stash[+i]);
    }
    return s;
  }

  function inline(src) {
    const stash = [];
    return restore(inlineCore(src, stash), stash);
  }

  // ---------------------------------------------------------------- blocks

  const RE = {
    fence: /^( {0,3})(`{3,}|~{3,})[ \t]*([^`]*?)[ \t]*$/,
    fenceClose: /^ {0,3}(`{3,}|~{3,})[ \t]*$/,
    atx: /^ {0,3}(#{1,6})(?:[ \t]+|$)(.*?)(?:[ \t]+#+)?[ \t]*$/,
    hr: /^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$/,
    bq: /^ {0,3}> ?/,
    list: /^( {0,3})([-*+]|\d{1,9}[.)])([ \t]+|$)/,
    setext: /^ {0,3}(=+|-+)[ \t]*$/,
    tableSep: /^ {0,3}\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$/,
    html: /^ {0,3}(?:<(?:script|pre|style|textarea)[\s>]|<!--|<\/?(?:address|article|aside|blockquote|body|center|details|dialog|div|dl|dd|dt|fieldset|figcaption|figure|footer|form|h[1-6]|header|hr|iframe|li|main|nav|ol|p|picture|section|summary|table|tbody|td|tfoot|th|thead|tr|ul|video|audio|img|br|a)(?:[\s/>]|$))/i,
    mathBlock: /^ {0,3}\$\$(.*)$/,
    footnoteDef: /^ {0,3}\[\^([^\]\s]+)\]:[ \t]?(.*)$/,
    def: /^ {0,3}\[([^\]]+)\]:[ \t]*<?([^\s>]+)>?(?:[ \t]+(?:"([^"]*)"|'([^']*)'|\(([^)]*)\)))?[ \t]*$/,
  };

  function expandTabs(line) {
    return line.replace(/^[ \t]+/, (ws) => {
      let out = '';
      for (const ch of ws) out += ch === '\t' ? ' '.repeat(4 - (out.length % 4)) : ' ';
      return out;
    });
  }

  function splitRow(line) {
    let s = line.trim();
    if (s.startsWith('|')) s = s.slice(1);
    if (s.endsWith('|') && !s.endsWith('\\|')) s = s.slice(0, -1);
    const cells = [];
    let cur = '', ticks = 0;
    for (let i = 0; i < s.length; i++) {
      const ch = s[i];
      if (ch === '\\' && s[i + 1] === '|') { cur += '|'; i++; continue; }
      if (ch === '`') ticks ^= 1;
      if (ch === '|' && !ticks) { cells.push(cur.trim()); cur = ''; continue; }
      cur += ch;
    }
    cells.push(cur.trim());
    return cells;
  }

  function isTableStart(lines, i) {
    return i + 1 < lines.length && lines[i].includes('|') && lines[i + 1].includes('|') &&
      RE.tableSep.test(lines[i + 1]) && splitRow(lines[i]).length === splitRow(lines[i + 1]).length;
  }

  function interrupts(lines, i) {
    const c = lines[i];
    if (RE.atx.test(c) || RE.fence.test(c) || RE.hr.test(c) || RE.bq.test(c) || RE.mathBlock.test(c)) return true;
    const m = RE.list.exec(c);
    if (m && m[3] !== '' && (!/\d/.test(m[2]) || parseInt(m[2], 10) === 1)) return true;
    if (RE.html.test(c) && !/^ {0,3}<\/?(?:img|br|a)[\s/>]/i.test(c)) return true;
    return isTableStart(lines, i);
  }

  // 원본 줄 번호(0부터)를 HTML 에 남겨 편집기와 미리보기 위치를 서로 맞춥니다.
  const lineAttr = (s, e) => ` data-line="${s}" data-line-end="${e}"`;

  function heading(level, raw, s, e) {
    const html = inline(raw.trim());
    let slug = html.replace(/<[^>]+>/g, '').replace(/&[a-z#0-9]+;/gi, '').toLowerCase().trim()
      .replace(/[^\p{L}\p{N}\s_-]/gu, '').replace(/\s/g, '-');
    const count = slugCounts[slug] || 0;
    slugCounts[slug] = count + 1;
    if (count) slug += '-' + count;
    headings.push({ level, id: slug, html });
    return `<h${level} id="${esc(slug)}"${lineAttr(s, e)}>${html}</h${level}>`;
  }

  const ALERTS = { note: '참고', tip: '팁', important: '중요', warning: '경고', caution: '주의' };
  // 화면 글자 번역 (미리보기가 영어일 때 window.MdyStrings 를 넣어 줍니다)
  const t = (s) => (global.MdyStrings && global.MdyStrings[s]) || s;

  function blockquote(buf, nums, s, e) {
    const m = buf.length && /^\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*$/i.exec(buf[0]);
    if (m) {
      const kind = m[1].toLowerCase();
      return `<div class="markdown-alert markdown-alert-${kind}"${lineAttr(s, e)}><p class="markdown-alert-title">${t(ALERTS[kind])}</p>\n${blocks(buf.slice(1), nums.slice(1))}</div>`;
    }
    return `<blockquote${lineAttr(s, e)}>\n${blocks(buf, nums)}\n</blockquote>`;
  }

  function parseList(lines, nums, i) {
    const n = lines.length;
    const first = RE.list.exec(lines[i]);
    const ordered = /\d/.test(first[2]);
    const delim = ordered ? first[2].slice(-1) : first[2];
    const startNum = ordered ? parseInt(first[2], 10) : 1;
    const items = [];
    let loose = false;

    while (i < n) {
      const m = RE.list.exec(lines[i]);
      if (!m || RE.hr.test(lines[i])) break;
      const isOrd = /\d/.test(m[2]);
      if (isOrd !== ordered || (isOrd ? m[2].slice(-1) : m[2]) !== delim) break;

      let pad = m[3].length;
      if (pad === 0 || pad > 4) pad = 1;
      const ci = m[1].length + m[2].length + pad;
      const body = [lines[i].length >= ci ? lines[i].slice(ci) : ''];
      const bnums = [nums[i]];
      i++;

      let blank = false;
      while (i < n) {
        const c = lines[i];
        if (!c.trim()) { body.push(''); bnums.push(nums[i]); blank = true; i++; continue; }
        const indent = c.match(/^ */)[0].length;
        if (indent >= ci) { body.push(c.slice(ci)); bnums.push(nums[i]); blank = false; i++; continue; }
        if (blank || RE.list.test(c) || interrupts(lines, i)) break;
        body.push(c.trim()); bnums.push(nums[i]); i++;   // 느슨한 이어쓰기
      }

      let trailing = 0;
      while (body.length > 1 && !body[body.length - 1].trim()) { body.pop(); bnums.pop(); trailing++; }

      // 항목 안에서 (코드 블록 밖의) 빈 줄로 블록이 나뉘면 느슨한 목록
      let fence = false;
      for (let k = 1; k < body.length - 1; k++) {
        if (/^ {0,3}(`{3,}|~{3,})/.test(body[k])) fence = !fence;
        if (!fence && !body[k].trim() && body[k + 1].trim()) loose = true;
      }
      items.push({ body, bnums });

      if (trailing && i < n) {
        const nm = RE.list.exec(lines[i]);
        if (nm && /\d/.test(nm[2]) === ordered) loose = true;
      }
    }

    let hasTask = false;
    const lis = items.map(({ body, bnums }) => {
      const tm = /^\[([ xX])\](?:[ \t]+|$)/.exec(body[0]);
      let checkbox = '';
      if (tm) {
        hasTask = true;
        checkbox = `<input type="checkbox" disabled${tm[1] !== ' ' ? ' checked' : ''}> `;
        body[0] = body[0].slice(tm[0].length);
      }
      const attrs = (checkbox ? ' class="task-list-item"' : '') + lineAttr(bnums[0], bnums[bnums.length - 1]);
      return `<li${attrs}>${checkbox}${blocks(body, bnums, !loose)}</li>`;
    });

    const tag = ordered ? 'ol' : 'ul';
    const last = items[items.length - 1].bnums;
    const attrs = (ordered && startNum !== 1 ? ` start="${startNum}"` : '') +
      (hasTask ? ' class="contains-task-list"' : '') + lineAttr(items[0].bnums[0], last[last.length - 1]);
    return { html: `<${tag}${attrs}>\n${lis.join('\n')}\n</${tag}>`, next: i };
  }

  function blocks(lines, nums, tight) {
    const out = [];
    const n = lines.length;
    let i = 0;

    while (i < n) {
      const line = lines[i];
      const start = i;
      let m;

      if (!line.trim()) { i++; continue; }

      // 들여쓴 코드 블록
      if (/^ {4}/.test(line)) {
        const buf = [];
        let lastText = i;
        while (i < n && (/^ {4}/.test(lines[i]) || !lines[i].trim())) {
          if (lines[i].trim()) lastText = i;
          buf.push(lines[i].slice(4));
          i++;
        }
        buf.length = lastText - start + 1;
        i = lastText + 1;
        out.push(`<pre${lineAttr(nums[start], nums[lastText])}><code>${esc(buf.join('\n'))}</code></pre>`);
        continue;
      }

      // 펜스 코드 블록
      if ((m = RE.fence.exec(line))) {
        const indent = m[1].length, ch = m[2][0], len = m[2].length;
        const lang = m[3].split(/\s+/)[0];
        const strip = new RegExp('^ {0,' + indent + '}');
        const buf = [];
        i++;
        while (i < n) {
          const c = RE.fenceClose.exec(lines[i]);
          if (c && c[1][0] === ch && c[1].length >= len) { i++; break; }
          buf.push(lines[i].replace(strip, ''));
          i++;
        }
        const code = buf.join('\n');
        const at = lineAttr(nums[start], nums[i - 1]);
        const kind = lang.toLowerCase();
        if (kind === 'mermaid') {
          out.push(`<div class="mermaid"${at}>${esc(code)}</div>`);
        } else if (kind === 'math' || kind === 'latex' || kind === 'katex' || kind === 'tex') {
          out.push(`<div class="math-display" data-tex="${esc(code)}"${at}>${esc(code)}</div>`);
        } else {
          const cls = lang ? ` class="language-${esc(lang)}"` : '';
          const colored = global.CodeHighlight ? global.CodeHighlight.highlight(code, lang) : null;
          out.push(`<pre${at}><code${cls}>${colored ?? esc(code)}</code></pre>`);
        }
        continue;
      }

      // 수식 블록 $$ ... $$
      if ((m = RE.mathBlock.exec(line))) {
        let tex;
        const rest = m[1];
        if (rest.trim() && /\$\$\s*$/.test(rest)) {
          tex = rest.replace(/\$\$\s*$/, '');
          i++;
        } else {
          const buf = rest.trim() ? [rest] : [];
          i++;
          while (i < n) {
            if (/\$\$\s*$/.test(lines[i])) {
              const l = lines[i].replace(/\$\$\s*$/, '');
              if (l.trim()) buf.push(l);
              i++;
              break;
            }
            buf.push(lines[i]);
            i++;
          }
          tex = buf.join('\n');
        }
        out.push(`<div class="math-display" data-tex="${esc(tex.trim())}"${lineAttr(nums[start], nums[i - 1])}>${esc(tex.trim())}</div>`);
        continue;
      }

      if ((m = RE.atx.exec(line))) { out.push(heading(m[1].length, m[2], nums[i], nums[i])); i++; continue; }

      if (RE.hr.test(line)) { out.push(`<hr${lineAttr(nums[i], nums[i])}>`); i++; continue; }

      // 인용문
      if (RE.bq.test(line)) {
        const buf = [], bnums = [];
        while (i < n) {
          const c = lines[i];
          if (RE.bq.test(c)) { buf.push(c.replace(RE.bq, '')); bnums.push(nums[i]); i++; continue; }
          if (!c.trim()) break;
          if (buf.length && buf[buf.length - 1].trim() && !interrupts(lines, i)) { buf.push(c); bnums.push(nums[i]); i++; continue; }
          break;
        }
        out.push(blockquote(buf, bnums, nums[start], nums[i - 1]));
        continue;
      }

      if (RE.list.test(line)) {
        const r = parseList(lines, nums, i);
        out.push(r.html);
        i = r.next;
        continue;
      }

      // 표
      if (isTableStart(lines, i)) {
        const head = splitRow(line);
        const aligns = splitRow(lines[i + 1]).map((c) =>
          /^:-+:$/.test(c) ? 'center' : /^:/.test(c) ? 'left' : /:$/.test(c) ? 'right' : '');
        i += 2;
        const rows = [];
        while (i < n && lines[i].trim() && lines[i].includes('|') && !RE.bq.test(lines[i]) && !RE.fence.test(lines[i])) {
          rows.push({ cells: splitRow(lines[i]), line: nums[i] });
          i++;
        }
        const cell = (tag, text, k) => `<${tag}${aligns[k] ? ` style="text-align:${aligns[k]}"` : ''}>${inline(text || '')}</${tag}>`;
        const thead = `<tr${lineAttr(nums[start], nums[start + 1])}>` + head.map((c, k) => cell('th', c, k)).join('') + '</tr>';
        const tbody = rows.map((r) => `<tr${lineAttr(r.line, r.line)}>` + head.map((_, k) => cell('td', r.cells[k], k)).join('') + '</tr>').join('\n');
        out.push(`<table${lineAttr(nums[start], nums[i - 1])}>\n<thead>${thead}</thead>\n${rows.length ? `<tbody>\n${tbody}\n</tbody>\n` : ''}</table>`);
        continue;
      }

      // HTML 블록 (원본 그대로 두므로 줄 정보 없음)
      if (RE.html.test(line)) {
        const buf = [];
        const raw = /^ {0,3}<(script|pre|style|textarea)[\s>]/i.exec(line);
        if (/^ {0,3}<!--/.test(line)) {
          while (i < n) { buf.push(lines[i]); i++; if (buf[buf.length - 1].includes('-->')) break; }
        } else if (raw) {
          const close = new RegExp('</' + raw[1] + '>', 'i');
          while (i < n) { buf.push(lines[i]); i++; if (close.test(buf[buf.length - 1])) break; }
        } else {
          while (i < n && lines[i].trim()) { buf.push(lines[i]); i++; }
        }
        out.push(buf.join('\n'));
        continue;
      }

      // 문단 (+ Setext 제목)
      const buf = [line];
      let setext = 0;
      i++;
      while (i < n) {
        const c = lines[i];
        if (!c.trim()) break;
        if ((m = RE.setext.exec(c))) { setext = m[1][0] === '=' ? 1 : 2; i++; break; }
        if (interrupts(lines, i)) break;
        buf.push(c);
        i++;
      }
      const text = buf.map((l) => l.replace(/^ +/, '')).join('\n').replace(/\s+$/, '');
      if (!setext && /^\[\[?toc\]?\]$/i.test(text)) out.push(`<nav class="toc"${lineAttr(nums[start], nums[i - 1])}>${TOC_TOKEN}</nav>`);
      else if (setext) out.push(heading(setext, text, nums[start], nums[i - 1]));
      else out.push(tight ? inline(text) : `<p${lineAttr(nums[start], nums[i - 1])}>${inline(text)}</p>`);
    }

    return out.join('\n');
  }

  // ---------------------------------------------------------------- entry

  function render(src) {
    refs = {};
    slugCounts = {};
    headings = [];
    src = String(src || '').replace(/\r\n?/g, '\n').replace(/[\u0001\u0002]/g, '');

    // YAML 머리말
    let front = '';
    let offset = 0;
    const fm = /^---\n([\s\S]*?)\n(?:---|\.\.\.)[ \t]*(?:\n|$)/.exec(src);
    if (fm) {
      offset = (fm[0].match(/\n/g) || []).length;
      front = `<pre class="front-matter"${lineAttr(0, Math.max(0, offset - 1))}><code>${esc(fm[1])}</code></pre>\n`;
      src = src.slice(fm[0].length);
    }

    // 참조 링크·각주 정의 수집 (코드 블록 안은 제외)
    footnotes = {};
    footnoteOrder = [];
    let fence = null;
    const lines = [], nums = [];
    const all = src.split('\n').map(expandTabs);
    for (let k = 0; k < all.length; k++) {
      const l = all[k];
      const f = /^ {0,3}(`{3,}|~{3,})/.exec(l);
      if (f) {
        if (!fence) fence = f[1];
        else if (f[1][0] === fence[0] && f[1].length >= fence.length && RE.fenceClose.test(l)) fence = null;
      } else if (!fence) {
        const fd = RE.footnoteDef.exec(l);
        if (fd) {
          const body = [fd[2]], bnums = [k + offset];
          // 들여쓴 다음 줄(빈 줄 사이 포함)은 같은 각주
          while (k + 1 < all.length) {
            const next = all[k + 1];
            if (/^ {2,}\S/.test(next)) { body.push(next.replace(/^ {2,4}/, '')); bnums.push(k + 1 + offset); k++; continue; }
            if (!next.trim() && k + 2 < all.length && /^ {2,}\S/.test(all[k + 2])) { body.push(''); bnums.push(k + 1 + offset); k++; continue; }
            break;
          }
          if (!(fd[1] in footnotes)) footnotes[fd[1]] = { body, bnums, n: 0 };
          continue;
        }
        const d = RE.def.exec(l);
        if (d && !d[1].startsWith('^')) {
          const key = normRef(d[1]);
          if (!(key in refs)) refs[key] = { url: d[2], title: d[3] ?? d[4] ?? d[5] ?? '' };
          continue;
        }
      }
      lines.push(l);
      nums.push(k + offset);
    }

    let html = front + blocks(lines, nums, false);

    if (footnoteOrder.length) {
      // 각주 본문 안에서 새 각주가 참조될 수 있으므로 순서 배열이 늘어나는 동안 계속 돕니다.
      const items = [];
      for (let k = 0; k < footnoteOrder.length; k++) {
        const id = footnoteOrder[k];
        const fn = footnotes[id];
        const inner = blocks(fn.body, fn.bnums, true);
        const back = ` <a href="#fnref-${esc(id)}" class="footnote-back" aria-label="${t('본문으로')}">↩</a>`;
        items.push(`<li id="fn-${esc(id)}"${lineAttr(fn.bnums[0], fn.bnums[fn.bnums.length - 1])}>${inner}${back}</li>`);
      }
      html += `\n<section class="footnotes"><ol>\n${items.join('\n')}\n</ol></section>`;
    }
    if (html.includes(TOC_TOKEN)) html = html.split(TOC_TOKEN).join(tocHtml());
    return html;
  }

  global.Markdown = { render };
})(window);
