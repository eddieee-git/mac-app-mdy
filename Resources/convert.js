// Mdy — 웹·문서 앱에서 복사한 HTML 을 마크다운으로 바꾸는 변환기
(function (global) {
  'use strict';

  const BLOCK = new Set(['P', 'DIV', 'SECTION', 'ARTICLE', 'HEADER', 'FOOTER', 'MAIN', 'ASIDE', 'NAV', 'FIGURE',
    'FIGCAPTION', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'UL', 'OL', 'LI', 'BLOCKQUOTE', 'PRE', 'TABLE', 'HR', 'DL',
    'DT', 'DD', 'ADDRESS', 'DETAILS', 'SUMMARY', 'CENTER']);
  const SKIP = new Set(['SCRIPT', 'STYLE', 'META', 'LINK', 'TITLE', 'HEAD', 'NOSCRIPT', 'TEMPLATE', 'BUTTON']);
  const BLOCK_SELECTOR = Array.from(BLOCK).join(',');

  const isBlock = (el) => el.nodeType === 1 && BLOCK.has(el.tagName);
  const weight = (el) => {
    const w = el.style && el.style.fontWeight;
    if (!w) return null;
    if (w === 'bold' || w === 'bolder') return 700;
    if (w === 'normal' || w === 'lighter') return 400;
    return parseInt(w, 10) || null;
  };

  function wrap(marker, text, close = marker) {
    const m = /^(\s*)([\s\S]*?)(\s*)$/.exec(text);
    if (!m[2]) return text;
    return m[1] + marker + m[2] + close + m[3];
  }

  function escapeText(t) {
    return t.replace(/([\\`*])/g, '\\$1').replace(/^(\s*)([#>+-]|\d+\.)(?=\s)/, '$1\\$2');
  }

  function inline(node) {
    let out = '';
    for (const child of node.childNodes) {
      if (child.nodeType === 3) { out += escapeText(child.nodeValue.replace(/\s+/g, ' ')); continue; }
      if (child.nodeType !== 1 || SKIP.has(child.tagName)) continue;
      const el = child;
      const tag = el.tagName;
      if (isBlock(el)) { out += '\n' + inline(el) + '\n'; continue; }
      let inner;
      switch (tag) {
        case 'BR': out += '  \n'; break;
        case 'B': case 'STRONG':
          inner = inline(el);
          out += weight(el) !== null && weight(el) < 600 ? inner : wrap('**', inner);
          break;
        case 'I': case 'EM': case 'CITE': case 'DFN': out += wrap('*', inline(el)); break;
        case 'S': case 'DEL': case 'STRIKE': out += wrap('~~', inline(el)); break;
        case 'MARK': out += wrap('==', inline(el)); break;
        case 'CODE': case 'KBD': case 'SAMP': case 'TT': {
          const code = el.textContent.replace(/\s+/g, ' ');
          const ticks = code.includes('`') ? '``' : '`';
          out += code ? ticks + (ticks === '``' ? ' ' + code + ' ' : code) + ticks : '';
          break;
        }
        case 'A': {
          const href = el.getAttribute('href') || '';
          inner = inline(el).trim();
          if (!href || /^\s*javascript:/i.test(href) || href.startsWith('#')) { out += inner; break; }
          out += inner && inner !== href ? `[${inner}](${href.replace(/ /g, '%20')})` : `<${href}>`;
          break;
        }
        case 'IMG': {
          const src = el.getAttribute('src') || '';
          if (src && !src.startsWith('data:')) out += `![${(el.getAttribute('alt') || '').replace(/[\[\]]/g, '')}](${src.replace(/ /g, '%20')})`;
          break;
        }
        case 'INPUT': break;
        default: {
          inner = inline(el);
          const w = weight(el);
          if (w !== null && w >= 600) inner = wrap('**', inner);
          if (el.style && el.style.fontStyle === 'italic') inner = wrap('*', inner);
          if (el.style && /line-through/.test(el.style.textDecoration || '')) inner = wrap('~~', inner);
          out += inner;
        }
      }
    }
    return out;
  }

  const cleanInline = (s) => s.replace(/[ \t]+\n/g, (m) => (m.startsWith('  ') ? '  \n' : '\n'))
    .replace(/\n{2,}/g, '\n').replace(/^[ \t]+|[ \t]+$/g, '').replace(/ {2,}(?!\n)/g, ' ');

  function list(el, depth) {
    const ordered = el.tagName === 'OL';
    let n = parseInt(el.getAttribute('start') || '1', 10) || 1;
    const lines = [];
    for (const li of el.children) {
      if (li.tagName !== 'LI') continue;
      const marker = ordered ? `${n++}.` : '-';
      const pad = ' '.repeat(marker.length + 1);
      const box = li.querySelector(':scope > input[type=checkbox], :scope > p > input[type=checkbox]');
      const task = box ? (box.checked || box.hasAttribute('checked') ? '[x] ' : '[ ] ') : '';
      const textParts = [];
      const nested = [];
      for (const child of li.childNodes) {
        if (child.nodeType === 1 && (child.tagName === 'UL' || child.tagName === 'OL')) nested.push(list(child, depth + 1));
        else if (child.nodeType === 1 && isBlock(child) && child.tagName !== 'P' && child.tagName !== 'DIV') nested.push(blocks(child));
        else {
          const holder = document.createElement('span');
          holder.appendChild(child.cloneNode(true));
          textParts.push(inline(holder));
        }
      }
      const text = cleanInline(textParts.join(' ')).replace(/^\s+|\s+$/g, '').replace(/\n+/g, '\n').replace(/\n/g, '\n' + pad);
      lines.push(marker + ' ' + task + text);
      for (const sub of nested) lines.push(sub.split('\n').map((l) => (l ? pad + l : l)).join('\n'));
    }
    return lines.join('\n');
  }

  function table(el) {
    const rows = Array.from(el.querySelectorAll('tr')).map((tr) =>
      Array.from(tr.children).filter((c) => c.tagName === 'TD' || c.tagName === 'TH')
        .map((c) => cleanInline(inline(c)).replace(/\n/g, ' ').replace(/\|/g, '\\|')));
    if (!rows.length) return '';
    const cols = Math.max(...rows.map((r) => r.length));
    const fill = (r) => r.concat(Array(cols - r.length).fill(''));
    const line = (r) => '| ' + fill(r).join(' | ') + ' |';
    return [line(rows[0]), '|' + ' --- |'.repeat(cols), ...rows.slice(1).map(line)].join('\n');
  }

  function blocks(root) {
    const out = [];
    let para = '';
    const flush = () => {
      const t = cleanInline(para);
      if (t.trim()) out.push(t);
      para = '';
    };
    for (const child of root.childNodes) {
      if (child.nodeType === 3) { para += escapeText(child.nodeValue.replace(/\s+/g, ' ')); continue; }
      if (child.nodeType !== 1 || SKIP.has(child.tagName)) continue;
      const el = child;
      // 구글 문서처럼 굵게(b) 안에 문단이 통째로 들어 있는 경우
      if (!isBlock(el) && el.querySelector(BLOCK_SELECTOR)) { flush(); const inner = blocks(el); if (inner) out.push(inner); continue; }
      if (!isBlock(el)) {
        const holder = document.createElement('span');
        holder.appendChild(el.cloneNode(true));
        para += inline(holder);
        continue;
      }
      flush();
      const tag = el.tagName;
      if (/^H[1-6]$/.test(tag)) {
        const text = cleanInline(inline(el)).replace(/\n/g, ' ').replace(/^\*\*([\s\S]*)\*\*$/, '$1');
        if (text) out.push('#'.repeat(+tag[1]) + ' ' + text);
      } else if (tag === 'UL' || tag === 'OL') {
        out.push(list(el, 0));
      } else if (tag === 'BLOCKQUOTE') {
        const inner = blocks(el);
        if (inner) out.push(inner.split('\n').map((l) => (l ? '> ' + l : '>')).join('\n'));
      } else if (tag === 'PRE') {
        const codeEl = el.querySelector('code');
        const lang = ((codeEl && codeEl.className) || el.className || '').match(/(?:language|lang)-([\w#+-]+)/);
        const code = el.textContent.replace(/\n$/, '');
        const fence = code.includes('```') ? '~~~' : '```';
        out.push(fence + (lang ? lang[1] : '') + '\n' + code + '\n' + fence);
      } else if (tag === 'TABLE') {
        const t = table(el);
        if (t) out.push(t);
      } else if (tag === 'HR') {
        out.push('---');
      } else {
        const inner = blocks(el);
        if (inner) out.push(inner);
      }
    }
    flush();
    return out.join('\n\n');
  }

  function htmlToMarkdown(html) {
    const doc = new DOMParser().parseFromString(String(html), 'text/html');
    doc.querySelectorAll('script, style, meta, link, title, noscript, template').forEach((el) => el.remove());
    return blocks(doc.body).replace(/\n{3,}/g, '\n\n').replace(/[ \t]+$/gm, (m) => (m === '  ' ? m : '')).trim();
  }

  global.MdyConvert = { htmlToMarkdown };
})(window);
