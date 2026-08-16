// lark-review-digest — scan team tables' records for comments & @mentions and
// build a review digest. Runs INSIDE the omp `browser` run context (has `page`).
// Depends on lark-base-ops read helpers (scanTableComments et al).
//
// Usage (browser `run` cell):
//   const R = require('<repo>/8syncdev-org-skills/skills/lark-review-digest/scripts/review-digest.js');
//   const page = await R.H.attachBase(browser, '<BASE_URL>');
//   const results = await R.scanAll(page, R.allTables());        // all teams
//   const md = R.toMarkdown(results, { me: 'Anh Tú' });
//   require('fs').writeFileSync('/tmp/lark-review.md', md);

const path = require('path');
const H = require(path.join(__dirname, '..', '..', 'lark-base-ops', 'scripts', 'lark-helpers.js'));

// Team WORK tables only — exclude folder headers, DIM_* dimensions, dashboards, onboarding.
const TEAM_TABLES = {
  DEV: ['ZUS IDE', 'mind0', 'AcoLeads', '8syncdev Monorepo', 'IELTS (Ezen)', 'DEV_02 Kho thông tin sản phẩm'],
  MKT: ['MKT_01 Lịch nội dung', 'MKT_02 Kho ý tưởng', 'MKT_03 Kho tài sản', 'MKT_04 Chiến dịch quảng cáo',
        'MKT_05 Nhật ký QC theo ngày', 'MKT_06 Traffic & Funnel', 'MKT_07 SEO Keywords', 'MKT_08 Lead / CRM'],
  EDU: ['EDU_01 Giáo viên', 'EDU_02 Lớp học', 'EDU_03 Ca dạy', 'EDU_04 Học viên', 'EDU_05 Ngân hàng bài tập',
        'GV_Task giáo viên cần làm'],
  OPS: ['OPS_01 Yêu cầu chéo'],
};

// Flatten to [{team, name}]. Pass e.g. ['DEV'] to scope; empty = all teams.
function allTables(teams) {
  const t = teams && teams.length ? teams : Object.keys(TEAM_TABLES);
  return t.flatMap((k) => (TEAM_TABLES[k] || []).map((name) => ({ team: k, name })));
}

// Scan a list of {team,name}. Returns [{team, table, walked, withComments, error?}].
async function scanAll(page, tables, opts = {}) {
  const results = [];
  for (const { team, name } of tables) {
    try {
      let ok = await H.openTable(page, name);
      if (!ok) { await H.sleep(900); ok = await H.openTable(page, name); }
      if (!ok) { results.push({ team, table: name, walked: 0, withComments: [], error: 'openTable: switch not verified' }); continue; }
      const r = await H.scanTableComments(page, opts);
      results.push({ team, table: name, walked: r.walked, withComments: r.withComments });
    } catch (e) {
      results.push({ team, table: name, walked: 0, withComments: [], error: e.message });
    }
  }
  return results;
}

// Build the review digest markdown. `me` = display name used for the mention section.
function toMarkdown(results, opts = {}) {
  const me = opts.me || 'Anh Tú';
  const now = new Date().toISOString().slice(0, 16).replace('T', ' ');
  const flat = [];
  for (const r of results) for (const rec of r.withComments) flat.push({ team: r.team, table: r.table, ...rec });
  const mentions = flat.filter((x) => x.mentionsMe);
  const rest = flat.filter((x) => !x.mentionsMe);
  const errs = results.filter((r) => r.error);

  const fmtComment = (c) => c.split('\n').map((l) => l.trim()).filter(Boolean).join(' — ');
  const fmtRec = (x) => {
    const head = `- **${x.title || '(no title)'}** · \`${x.table}\``
      + `${x.assignee ? ` · 👤 ${x.assignee}` : ''}${x.status ? ` · _${x.status}_` : ''}`;
    const cs = x.comments.map((c) => `  - 💬 ${fmtComment(c)}`);
    return [head, ...cs].join('\n');
  };

  const L = [];
  L.push('# Lark review digest — comments & @mentions');
  L.push(`> Scan **${now}** · base "8 SYNC DEV Workspace" · ${results.length} bảng · `
    + `**${flat.length}** record có comment · 🔔 **${mentions.length}** tag @${me}`
    + `${errs.length ? ` · ⚠️ ${errs.length} bảng lỗi` : ''}`);
  L.push('');
  L.push(`## 🔔 Tag @${me} — cần xem / trả lời (${mentions.length})`);
  L.push(mentions.length ? mentions.map(fmtRec).join('\n') : '_Không có._');
  L.push('');
  L.push(`## 💬 Comment khác của team (${rest.length})`);
  L.push(rest.length ? rest.map(fmtRec).join('\n') : '_Không có._');
  L.push('');
  L.push('## 📋 Coverage (record đã quét / có comment)');
  L.push('| Bảng | Team | Quét | Comment |');
  L.push('|---|:--:|--:|--:|');
  for (const r of results) {
    L.push(`| ${r.table} | ${r.team} | ${r.walked}${r.error ? ' ⚠️' : ''} | ${r.withComments.length} |`);
  }
  if (errs.length) {
    L.push('');
    L.push('### ⚠️ Bảng lỗi (scan lại thủ công)');
    for (const e of errs) L.push(`- \`${e.table}\` — ${e.error}`);
  }
  return L.join('\n');
}

module.exports = { TEAM_TABLES, allTables, scanAll, toMarkdown, H };
