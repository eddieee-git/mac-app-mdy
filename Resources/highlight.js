// Mdy — 외부 의존성 없는 가벼운 코드 문법 색칠기
(function (global) {
  'use strict';

  const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const words = (list) => new RegExp('\\b(?:' + list.trim().split(/\s+/).join('|') + ')\\b', 'y');

  const C_COMMENT = [['comment', /\/\/[^\n]*/y], ['comment', /\/\*[\s\S]*?(?:\*\/|$)/y]];
  const HASH_COMMENT = [['comment', /#[^\n]*/y]];
  const DQ = ['string', /"(?:\\[\s\S]|[^"\\\n])*"?/y];
  const SQ = ['string', /'(?:\\[\s\S]|[^'\\\n])*'?/y];
  const BT = ['string', /`(?:\\[\s\S]|[^`\\])*`?/y];
  const NUM = ['number', /\b(?:0[xX][\da-fA-F_]+|0[bB][01_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)[a-zA-Z]*\b/y];
  const TYPE = ['type', /\b[A-Z][A-Za-z0-9_]*\b/y];
  const FN = ['fn', /\b[a-zA-Z_][\w]*(?=\s*\()/y];
  const LIT = ['literal', words('true false null nil undefined None True False NULL self this super')];

  function cLike(keywords, extra = []) {
    return [...C_COMMENT, ...extra, DQ, SQ, NUM, ['keyword', words(keywords)], LIT, TYPE, FN];
  }

  const LANGS = {};
  const define = (names, rules) => names.split(' ').forEach((n) => { LANGS[n] = rules; });

  define('js javascript jsx mjs cjs ts typescript tsx', cLike(
    'async await break case catch class const continue debugger default delete do else export extends finally for from function get if import in instanceof let new of return set static switch throw try typeof var void while with yield interface type enum implements private protected public readonly declare namespace abstract as satisfies keyof',
    [BT, ['regex', /\/(?![*/])(?:\\.|\[(?:\\.|[^\]\n])*\]|[^/\\\n])+\/[gimsuyd]*(?=\s*[.,;)\]}\n]|$)/y]]));
  define('swift', cLike(
    'actor associatedtype async await break case catch class continue default defer do else enum extension fallthrough fileprivate final for func guard if import in init inout internal is let mutating nonisolated open operator override private protocol public repeat rethrows return some any static struct subscript switch throw throws try typealias var weak where while lazy unowned convenience required dynamic',
    [['attr', /@\w+/y], ['string', /"""[\s\S]*?(?:"""|$)/y]]));
  define('java kotlin kt scala groovy', cLike(
    'abstract assert break case catch class const continue default do else enum extends final finally for goto if implements import instanceof interface native new package private protected public return static strictfp super switch synchronized throw throws transient try void volatile while fun val var when object companion data sealed override open internal lateinit suspend in is as by init',
    [['attr', /@\w+/y]]));
  define('c h cpp c++ cc hpp cxx objc objective-c', cLike(
    'auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while class namespace template typename public private protected virtual override using new delete try catch throw nullptr constexpr bool',
    [['meta', /#\s*\w+[^\n]*/y]]));
  define('cs csharp c#', cLike(
    'abstract as async await base bool break byte case catch char checked class const continue decimal default delegate do double else enum event explicit extern finally fixed float for foreach goto if implicit in int interface internal is lock long namespace new object operator out override params private protected public readonly ref return sbyte sealed short sizeof static string struct switch throw try typeof uint ulong unchecked unsafe ushort using var virtual void volatile while record init get set',
    [['attr', /\[[A-Z]\w*(?:\([^)]*\))?\]/y]]));
  define('go golang', cLike(
    'break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var', [BT]));
  define('rust rs', cLike(
    'as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return Self static struct super trait type unsafe use where while',
    [['attr', /#!?\[[^\]]*\]/y], ['fn', /\b\w+!/y]]));
  define('php', cLike(
    'abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty enddeclare endfor endforeach endif endswitch endwhile extends final finally fn for foreach function global goto if implements include instanceof insteadof interface isset list match namespace new or print private protected public readonly require return static switch throw trait try unset use var while yield',
    [...HASH_COMMENT, ['variable', /\$\w+/y]]));
  define('py python', [
    ...HASH_COMMENT,
    ['string', /[rbfuRBFU]{0,2}"""[\s\S]*?(?:"""|$)/y], ['string', /[rbfuRBFU]{0,2}'''[\s\S]*?(?:'''|$)/y],
    ['string', /[rbfuRBFU]{0,2}"(?:\\.|[^"\\\n])*"?/y], ['string', /[rbfuRBFU]{0,2}'(?:\\.|[^'\\\n])*'?/y],
    ['attr', /@[\w.]+/y], NUM,
    ['keyword', words('and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case')],
    LIT, TYPE, FN,
  ]);
  define('rb ruby', [
    ...HASH_COMMENT, DQ, SQ, ['string', /:\w+/y], ['variable', /@{1,2}\w+/y], NUM,
    ['keyword', words('alias and begin break case class def defined do else elsif end ensure for if in module next not or redo rescue retry return then undef unless until when while yield require attr_accessor attr_reader')],
    LIT, TYPE, FN,
  ]);
  define('sh bash zsh shell console fish', [
    ...HASH_COMMENT, DQ, SQ, ['variable', /\$(?:\{[^}]*\}|\w+|[@#?$!*0-9])/y],
    ['keyword', words('if then else elif fi for while until do done case esac in function return export local readonly unset source alias exit set shift trap')],
    ['fn', /^\s*[\w./-]+(?=\s|$)/my], ['attr', /\s--?[\w-]+/y], NUM,
  ]);
  define('json jsonc json5', [
    ...C_COMMENT, ['prop', /"(?:\\.|[^"\\\n])*"(?=\s*:)/y], DQ, NUM, LIT,
  ]);
  define('yaml yml', [
    ...HASH_COMMENT, ['prop', /^[ \t-]*[\w.\-"' ]+?(?=:(?:\s|$))/my], DQ, SQ, NUM,
    ['literal', words('true false null yes no on off')], ['meta', /^---|^\.\.\./my], ['attr', /[&*!][\w-]+/y],
  ]);
  define('toml ini cfg conf properties', [
    ...HASH_COMMENT, ['comment', /;[^\n]*/y], ['meta', /^\s*\[[^\]\n]*\]/my], ['prop', /^\s*[\w.\-"]+(?=\s*=)/my], DQ, SQ, NUM, LIT,
  ]);
  define('html xml svg vue plist xhtml', [
    ['comment', /<!--[\s\S]*?(?:-->|$)/y], ['meta', /<![^>]*>|<\?[\s\S]*?\?>/y],
    ['tag', /<\/?[\w:.-]+/y], ['attr', /\s[\w:@.-]+(?==)/y], DQ, SQ, ['tag', /\/?>/y],
    ['string', /&[\w#]+;/y],
  ]);
  define('css scss sass less', [
    ['comment', /\/\*[\s\S]*?(?:\*\/|$)/y], ['comment', /\/\/[^\n]*/y], DQ, SQ,
    ['keyword', /@[\w-]+/y], ['prop', /[\w-]+(?=\s*:(?!:))/y], ['number', /#[\da-fA-F]{3,8}\b/y],
    ['number', /-?\d*\.?\d+(?:px|em|rem|%|vh|vw|s|ms|deg|fr|pt)?\b/y], ['variable', /[$@][\w-]+|--[\w-]+/y],
    ['tag', /[.#][\w-]+/y], ['fn', /[\w-]+(?=\()/y],
  ]);
  define('sql mysql postgres postgresql sqlite', [
    ['comment', /--[^\n]*/y], ['comment', /\/\*[\s\S]*?(?:\*\/|$)/y], SQ, DQ, NUM,
    ['keyword', new RegExp('\\b(?:' + 'select from where and or not insert into values update set delete create table drop alter add column primary key foreign references index view join inner left right outer full on as group by order having limit offset union all distinct case when then else end is null in like between exists default unique constraint begin commit rollback returning with asc desc count sum avg min max'.split(' ').join('|') + ')\\b', 'iy')],
    FN,
  ]);
  define('diff patch', [
    ['meta', /^@@[^\n]*/my], ['added', /^\+[^\n]*/my], ['deleted', /^-[^\n]*/my], ['comment', /^(?:diff|index|---|\+\+\+)[^\n]*/my],
  ]);
  define('dockerfile docker', [
    ...HASH_COMMENT, DQ, SQ, ['keyword', /^\s*(?:FROM|RUN|CMD|LABEL|EXPOSE|ENV|ADD|COPY|ENTRYPOINT|VOLUME|USER|WORKDIR|ARG|ONBUILD|STOPSIGNAL|HEALTHCHECK|SHELL|AS)\b/imy],
    ['variable', /\$\{?\w+\}?/y],
  ]);
  define('makefile make', [
    ...HASH_COMMENT, ['fn', /^[\w.%/-]+(?=\s*:)/my], ['variable', /\$[({][^)}]*[)}]|\$\w/y], DQ, SQ,
  ]);

  function highlight(code, lang) {
    const rules = LANGS[String(lang || '').toLowerCase()];
    if (!rules) return null;
    let out = '';
    let plain = '';
    let i = 0;
    const flush = () => { if (plain) { out += esc(plain); plain = ''; } };
    while (i < code.length) {
      let matched = false;
      for (const [cls, re] of rules) {
        re.lastIndex = i;
        const m = re.exec(code);
        if (m && m[0].length) {
          flush();
          out += `<span class="tok-${cls}">${esc(m[0])}</span>`;
          i += m[0].length;
          matched = true;
          break;
        }
      }
      if (!matched) {
        const w = /[\w$]+|\s+|[\s\S]/y;
        w.lastIndex = i;
        const m = w.exec(code);
        plain += m[0];
        i += m[0].length;
      }
    }
    flush();
    return out;
  }

  global.CodeHighlight = { highlight, languages: Object.keys(LANGS) };
})(typeof window !== 'undefined' ? window : globalThis);
