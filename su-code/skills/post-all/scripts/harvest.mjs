#!/usr/bin/env node
// harvest.mjs — thu hoạch + XẾP HẠNG nguyên liệu content cho skill `post-all`.
//
// VÌ SAO CÓ FILE NÀY: trước đây việc "lên bài" bắt đầu bằng mở feed đọc bằng mắt rồi chọn
// cảm tính. Hai hậu quả đã xảy ra thật: (1) đăng lại bài đã có trong sổ cái
// (data/social-ledger.ndjson) → Facebook phạt duplicate; (2) chọn bài không dính gì tới
// chủ đề brand nên bài chết. File này biến bước chọn thành một con số tra được.
//
// KHÔNG thêm dependency: chỉ `fetch` toàn cục + regex + `node:child_process`.
// KHÔNG parse XML bằng thư viện — regex là đủ cho feed/sitemap dạng phẳng của news site.
//
//   node harvest.mjs news [--limit N] [--json]
//   node harvest.mjs ex   [--limit N] [--json] [--difficulty easy|medium|hard|expert]
//   node harvest.mjs yt   [--limit N] [--json]
//   node harvest.mjs plan --days 30 [--start YYYY-MM-DD] [--json]
//
// Mọi lỗi mạng/nguồn đều DỪNG HẲN (exit ≠ 0) và in tiếng Việt. Cố ý không có đường
// "trả bảng rỗng coi như xong" — bảng rỗng trông y hệt thành công và đã từng lừa được người đọc.

import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..', '..', '..', '..');

// ===== NGUỒN THẬT (verify live 2026-08-02) ==================================================
const NEWS_FEED = 'https://news.8syncdev.com/feed.xml';          // 30 item mới nhất
const NEWS_SITEMAP = 'https://news.8syncdev.com/sitemap.xml';    // 148 loc, 60 permalink /vi/articles/
const NEWS_ARTICLE = 'https://news.8syncdev.com/vi/articles/';   // bản /en/ là cùng bài, tiếng Anh
const EX_API = 'https://coding.8syncdev.com/api/exercises';      // { exercises: [{slug,titleVi,difficulty}] } — 1000 bài
const EX_PROBLEM = 'https://coding.8syncdev.com/problem/';
const EX_OG = (slug) => `${EX_PROBLEM}${slug}/opengraph-image`;

// YouTube = ĐÍCH của phễu (doctrine founder 2026-08-02), KHÔNG phải nguồn nguyên liệu.
// Kênh duy nhất: @Dev8Sync (2.490 người đăng ký · 313 video, đo live 2026-08-02).
// Handle @8syncdev trên YouTube KHÔNG tồn tại (404) — đừng sinh link tới nó.
const YT_CHANNEL_ID = 'UCMWzM6NOoVvr9484XBSJEjg';
const YT_CHANNEL = 'https://www.youtube.com/@Dev8Sync';
const YT_FEED = `https://www.youtube.com/feeds/videos.xml?channel_id=${YT_CHANNEL_ID}`; // 15 video mới nhất
const YT_WATCH = 'https://www.youtube.com/watch?v=';

const LEDGER_CLI = path.join(REPO, '8syncdev-org-skills', 'skills', 'org-social-ops', 'scripts', 'post-ledger.js');

// ===== THANG ĐIỂM ===========================================================================
// Ba thành phần, cộng lại. Tất cả đều ĐO ĐƯỢC từ dữ liệu có sẵn — không có hệ số cảm tính nào
// dựa trên "độ hay" của bài.
const W_FRESH = 50;      // độ mới: tuyến tính, bài đúng hôm nay = 50, bài ≥ FRESH_DAYS ngày = 0
const FRESH_DAYS = 30;
const W_TOPIC_CAP = 40;  // trần điểm khớp chủ đề (cộng dồn theo nhóm từ khoá, không nhân đôi trong 1 nhóm)
const P_POSTED = -60;    // đã có trong sổ cái → phạt nặng hơn mọi điểm cộng cộng lại của 1 nhóm

// Từ khoá chủ đề lõi. LẤY TỪ ĐÂU (không phải nghĩ ra):
//   agent_ide  ← products.md §6 ZUS AI IDE (agent, autonomy, Tauri/Rust, workbench)
//   career     ← products.md §7 định vị + mkt-playbook.md §4b kho nỗi đau (junior thừa, AI ăn việc,
//                bằng cấp ≠ việc làm, portfolio > GPA)
//   dsa        ← products.md §2 coding "The Breach" (1.000 bài DSA)
//   perf       ← products.md §6 (installer 22.3 MB, nhẹ ~9× VS Code — brand bán bằng số hiệu năng)
//   security   ← products.md §5 news category `security`
//   lang       ← products.md §3 lộ trình course (Java, Fullstack JS, .NET, DevOps) + §6 core Rust
//   learn      ← products.md §3 course 1-kèm-1 + triết lý "Dạy bạn học, không dạy bạn copy"
//   ai_ml      ← products.md §5 news (tóm tắt AI) + §3 lộ trình AI/ML
const BRAND_TOPICS = [
  { key: 'agent_ide', w: 12, terms: ['ai ide', 'ide', 'coding agent', 'ai agent', 'agentic', 'agent', 'copilot', 'cursor', 'claude code', 'vs code', 'vscode', 'editor', 'tauri', 'autocomplete'] },
  { key: 'career', w: 12, terms: ['senior', 'junior', 'fresher', 'intern', 'thực tập', 'tuyển dụng', 'hiring', 'recruit', 'jobs', 'job', 'việc làm', 'phỏng vấn', 'interview', 'career', 'nghề', 'layoff', 'sa thải', 'lương', 'salary', 'portfolio', 'entry-level'] },
  { key: 'dsa', w: 10, terms: ['thuật toán', 'algorithm', 'dsa', 'data structure', 'cấu trúc dữ liệu', 'leetcode', 'big o', 'độ phức tạp', 'linked list', 'pointer', 'graph', 'dynamic programming', 'quy hoạch động', 'recursion', 'đệ quy'] },
  { key: 'learn', w: 10, terms: ['học', 'dạy', 'tutorial', 'guide', 'hướng dẫn', 'khoá học', 'khóa học', 'course', 'mentor', 'lộ trình', 'roadmap', 'beginner', 'người mới', 'cheat sheet', 'explained'] },
  { key: 'perf', w: 8, terms: ['hiệu năng', 'performance', 'tối ưu', 'optimize', 'optimization', 'latency', 'throughput', 'benchmark', 'memory', 'bộ nhớ', 'cache', 'gpu', 'quantization', 'nhanh hơn', 'faster'] },
  { key: 'security', w: 8, terms: ['bảo mật', 'security', 'vulnerability', 'lỗ hổng', 'cve', 'exploit', 'malware', 'auth', 'oauth', 'mã hoá', 'encryption', 'cisa', 'tấn công'] },
  { key: 'lang', w: 8, terms: ['rust', 'golang', 'go', 'python', 'javascript', 'typescript', 'java', 'c++', 'node.js', 'react', 'next.js', 'flutter', 'dart', '.net', 'kotlin', 'swift'] },
  { key: 'ai_ml', w: 8, terms: ['ai', 'trí tuệ nhân tạo', 'machine learning', 'học máy', 'neural', 'llm', 'model', 'mô hình', 'training', 'inference', 'embedding', 'fine-tune', 'rag', 'prompt'] },
];

// Tỉ lệ 4 share : 2 bài học : 1 product (org-core/mkt-playbook.md §2), rải theo bản đồ ngày §4:
// T2–T4 top-funnel, T5–T6 bán, T7–CN demo. §4 chia thô 3:2:2 nên slot T5 kéo về `share` để
// đúng 4:2:1 — tỉ lệ §2 là luật, bản đồ ngày §4 chỉ là gợi ý "đơn giản cho team".
const WEEK_KIND = ['product', 'share', 'share', 'share', 'share', 'bài học', 'bài học']; // CN,T2,T3,T4,T5,T6,T7
const WEEKDAY_VI = ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'];
// Bậc khó bài tập theo vai trò phễu: share = cửa vào phải dễ; bài học = chứng minh chất
// lượng dạy nên vừa sức; product = khoe sức mạnh nền tảng.
const KIND_DIFF = { share: ['easy'], 'bài học': ['medium', 'hard'], product: ['hard', 'expert'] };

// ===== TIỆN ÍCH =============================================================================

class Fail extends Error {}
const fail = (msg) => { throw new Fail(msg); };

function args(argv) {
  const o = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const t = argv[i];
    if (!t.startsWith('--')) { o._.push(t); continue; }
    const k = t.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith('--')) o[k] = true;
    else { o[k] = next; i++; }
  }
  return o;
}

async function getText(url, what) {
  let res;
  try {
    res = await fetch(url, { signal: AbortSignal.timeout(25000), headers: { 'user-agent': '8syncdev-post-all-harvest' } });
  } catch (e) {
    const why = e?.name === 'TimeoutError' ? 'quá 25 giây không phản hồi' : (e?.cause?.code || e?.message || String(e));
    fail(`không tải được ${what}\n  URL: ${url}\n  Lý do: ${why}\n  Kiểm tra mạng rồi chạy lại — KHÔNG có bảng nào được in vì không có dữ liệu thật.`);
  }
  if (!res.ok) fail(`${what} trả HTTP ${res.status} ${res.statusText}\n  URL: ${url}\n  Nguồn đang lỗi, đừng lên plan bằng dữ liệu thiếu.`);
  const body = await res.text();
  if (!body.trim()) fail(`${what} trả về rỗng\n  URL: ${url}`);
  return body;
}

const unent = (s) => String(s)
  .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
  .replace(/&lt;/g, '<').replace(/&gt;/g, '>')
  .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&apos;/g, "'")
  .replace(/&amp;/g, '&')
  .replace(/[\u200b-\u200f\u2060\ufeff]/g, '')   // zero-width: có thật trong title feed, phá mọi phép so khớp
  .trim();

const tagOf = (xml, tag) => {
  const m = xml.match(new RegExp(`<${tag}(?:\\s[^>]*)?>([\\s\\S]*?)</${tag}>`));
  return m ? unent(m[1]) : '';
};

const deaccent = (s) => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/đ/g, 'd').replace(/Đ/g, 'D');
const slugify = (s) => deaccent(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
const alnum = (s) => deaccent(s).toLowerCase().replace(/[^a-z0-9]+/g, '');

// ===== SỔ CÁI ===============================================================================
// Spawn `node post-ledger.js list --json` thay vì require: post-ledger.js là CommonJS và mở
// sqlite khi load. Gọi qua CLI giữ đúng một cửa vào sổ cái, và nếu sổ hỏng thì hỏng ở đó,
// không kéo theo tiến trình này.
function ledgerUrls() {
  const r = spawnSync(process.execPath, [LEDGER_CLI, 'list', '--limit', '1000000', '--json'], {
    cwd: REPO, encoding: 'utf8', timeout: 30000,
  });
  if (r.error) fail(`không chạy được sổ cái post-ledger.js\n  ${r.error.message}\n  Không có sổ thì không biết bài nào đã đăng — dừng, đừng chấm điểm mù.`);
  if (r.status !== 0) fail(`post-ledger.js list thoát mã ${r.status}\n  ${(r.stderr || '').trim()}`);
  let rows;
  try { rows = JSON.parse(r.stdout); } catch { fail(`post-ledger.js list --json trả về thứ không phải JSON:\n  ${r.stdout.slice(0, 200)}`); }
  const set = new Set();
  for (const row of rows) {
    const u = (row.source_url || '').trim();
    if (u) set.add(u.replace(/\/+$/, ''));
  }
  return set;
}

// ===== NEWS =================================================================================

// Feed cho tín hiệu (title/pubDate/description); sitemap cho PERMALINK 8sync.
// Cố ý ghép hai nguồn: <link> trong feed là URL nguồn GỐC (together.ai, medium…), đăng cái đó
// là đẩy traffic cho người khác. Link phải đăng luôn là /vi/articles/<slug> của mình.
function indexSitemap(xml) {
  const locs = [...xml.matchAll(/<loc>\s*([^<\s]+)\s*<\/loc>/g)].map((m) => unent(m[1]))
    .filter((u) => u.includes('/vi/articles/'));
  if (!locs.length) fail(`sitemap không có permalink /vi/articles/ nào\n  URL: ${NEWS_SITEMAP}\n  Cấu trúc site đã đổi — sửa harvest.mjs trước khi lên plan.`);
  const exact = new Map();
  const loose = new Map();
  for (const loc of locs) {
    const slug = loc.split('/').pop();
    const base = slug.replace(/-[a-z0-9]{7,12}$/, '');   // slug = <slugify(title)>-<id ngắn>
    if (!exact.has(base)) exact.set(base, loc);
    const key = alnum(base);                              // site đôi khi để `--` (space + dấu gạch gốc)
    if (!loose.has(key)) loose.set(key, loc);
  }
  return { exact, loose, count: locs.length };
}

function scoreTopics(text) {
  const hay = ` ${deaccent(text).toLowerCase()} `;
  const hits = [];
  let raw = 0;
  for (const g of BRAND_TOPICS) {
    const hit = g.terms.some((t) => {
      const needle = deaccent(t).toLowerCase().replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      return new RegExp(`(?<![a-z0-9])${needle}(?![a-z0-9])`, 'u').test(hay);
    });
    if (hit) { raw += g.w; hits.push(g.key); }
  }
  return { topic: Math.min(raw, W_TOPIC_CAP), topics: hits, topicRaw: raw };
}

async function harvestNews() {
  const [feedXml, smXml] = await Promise.all([
    getText(NEWS_FEED, 'RSS news.8syncdev.com'),
    getText(NEWS_SITEMAP, 'sitemap news.8syncdev.com'),
  ]);
  const sm = indexSitemap(smXml);
  const posted = ledgerUrls();

  const raw = feedXml.match(/<item>[\s\S]*?<\/item>/g) || [];
  if (!raw.length) fail(`RSS không có <item> nào\n  URL: ${NEWS_FEED}\n  Feed đang rỗng hoặc đổi cấu trúc.`);

  const now = Date.now();
  const out = [];
  for (const it of raw) {
    const title = tagOf(it, 'title');
    if (!title) continue;
    const description = tagOf(it, 'description');
    const pubDate = tagOf(it, 'pubDate');
    const ts = Date.parse(pubDate);
    const ageDays = Number.isNaN(ts) ? FRESH_DAYS : (now - ts) / 86400000;
    const fresh = Math.round(W_FRESH * Math.max(0, 1 - Math.max(0, ageDays) / FRESH_DAYS) * 10) / 10;

    const base = slugify(title);
    const permalink = sm.exact.get(base) || sm.loose.get(alnum(base)) || null;
    const { topic, topics, topicRaw } = scoreTopics(`${title} ${description}`);
    const isPosted = !!permalink && posted.has(permalink.replace(/\/+$/, ''));
    const postedPenalty = isPosted ? P_POSTED : 0;

    out.push({
      title,
      permalink,
      sourceLink: tagOf(it, 'link'),
      guid: tagOf(it, 'guid'),
      pubDate,
      ageDays: Math.round(ageDays * 10) / 10,
      fresh,
      topic,
      topicRaw,
      topics,
      posted: isPosted,
      postedPenalty,
      score: Math.round((fresh + topic + postedPenalty) * 10) / 10,
      description,
    });
  }
  out.sort((a, b) => b.score - a.score || a.ageDays - b.ageDays);
  out.forEach((x, i) => { x.rank = i + 1; });
  return { items: out, ledgerSize: posted.size, sitemapArticles: sm.count };
}

// ===== EXERCISES ============================================================================

async function harvestEx() {
  const body = await getText(EX_API, 'API bài tập coding.8syncdev.com');
  let j;
  try { j = JSON.parse(body); } catch { fail(`API bài tập trả về thứ không phải JSON\n  URL: ${EX_API}\n  ${body.slice(0, 200)}`); }
  const list = Array.isArray(j?.exercises) ? j.exercises : null;
  if (!list || !list.length) fail(`API bài tập không có mảng \`exercises\`\n  URL: ${EX_API}\n  Nhận được các khoá: ${Object.keys(j || {}).join(', ') || '(rỗng)'}`);
  const posted = ledgerUrls();
  return list.map((e) => {
    const url = `${EX_PROBLEM}${e.slug}`;
    return {
      slug: e.slug,
      titleVi: e.titleVi,
      difficulty: e.difficulty,
      url,
      ogImage: EX_OG(e.slug),
      posted: posted.has(url),
    };
  });
}

// ===== YOUTUBE (ĐÍCH, không phải nguồn) =====================================================

async function harvestYt() {
  const xml = await getText(YT_FEED, 'RSS kênh YouTube @Dev8Sync');
  const entries = xml.match(/<entry>[\s\S]*?<\/entry>/g) || [];
  if (!entries.length) fail(`RSS kênh YouTube không có <entry> nào\n  URL: ${YT_FEED}\n  Không có video thật thì không gắn được đích YouTube cho bài — dừng.`);
  return entries.map((e) => {
    const id = (e.match(/<yt:videoId>([^<]+)<\/yt:videoId>/) || [])[1] || '';
    const title = tagOf(e, 'title');
    const published = tagOf(e, 'published');
    return { videoId: id, title, published, url: `${YT_WATCH}${id}`, tokens: new Set(alnum(title).length ? deaccent(title).toLowerCase().match(/[a-z0-9]{3,}/g) || [] : []) };
  }).filter((v) => v.videoId);
}

// Ghép video liên quan nhất theo số token trùng. Không có token nào trùng thì xoay vòng —
// doctrine 2026-08-02: KHÔNG ngày nào được thiếu link YouTube, nên fallback phải luôn ra link thật.
function pickVideo(videos, text, dayIndex) {
  const want = new Set(deaccent(text).toLowerCase().match(/[a-z0-9]{4,}/g) || []);
  let best = null;
  let bestN = 0;
  for (const v of videos) {
    let n = 0;
    for (const t of v.tokens) if (want.has(t)) n++;
    if (n > bestN) { bestN = n; best = v; }
  }
  const v = best || videos[dayIndex % videos.length];
  return { videoId: v.videoId, title: v.title, url: v.url, matchedTokens: bestN, matched: !!best };
}

// ===== PLAN =================================================================================

function ymd(d) { return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`; }

async function buildPlan({ days, start }) {
  if (!Number.isInteger(days) || days < 1) fail('`--days` phải là số nguyên ≥ 1.');
  if (days > 31) fail(`--days ${days} vượt trần 31.\n  Plan chỉ được dài 1 THÁNG: feed news thay mới mỗi ngày, lên lịch xa hơn là bịa nguyên liệu chưa tồn tại.`);
  const startDate = start ? new Date(`${start}T00:00:00Z`) : new Date(`${ymd(new Date())}T00:00:00Z`);
  if (Number.isNaN(startDate.getTime())) fail(`--start "${start}" không phải ngày hợp lệ (cần YYYY-MM-DD).`);

  const [{ items }, exercises, videos] = await Promise.all([harvestNews(), harvestEx(), harvestYt()]);

  const newsPool = items.filter((n) => !n.posted && n.permalink);
  if (newsPool.length < days) {
    fail(`chỉ còn ${newsPool.length} bài news dùng được (chưa đăng + có permalink) trong feed ${items.length} item, không đủ cho ${days} ngày.\n`
      + `  Cách xử lý: giảm --days xuống ${newsPool.length}, hoặc chạy lại sau khi feed cập nhật (cron news chạy mỗi ngày).\n`
      + '  Cố ý KHÔNG tái dùng bài đã đăng — đó chính là lỗi bị Facebook phạt duplicate.');
  }

  const exPool = {};
  for (const d of ['easy', 'medium', 'hard', 'expert']) exPool[d] = exercises.filter((e) => e.difficulty === d && !e.posted);
  const exCursor = { easy: 0, medium: 0, hard: 0, expert: 0 };
  const takeEx = (kind, i) => {
    for (const d of KIND_DIFF[kind]) {
      const pool = exPool[d];
      if (pool && pool.length) {
        // Bước nhảy nguyên tố qua danh sách 1.000 bài: tránh 30 ngày toàn bài nằm cạnh nhau
        // trong cùng một chương (API trả theo thứ tự cố định).
        const idx = (exCursor[d]++ * 37 + i) % pool.length;
        return pool[idx];
      }
    }
    fail(`hết bài tập chưa đăng cho loại "${kind}" (bậc ${KIND_DIFF[kind].join('/')}).`);
    return null;
  };

  const plan = [];
  for (let i = 0; i < days; i++) {
    const d = new Date(startDate.getTime() + i * 86400000);
    const dow = d.getUTCDay();
    const kind = WEEK_KIND[dow];
    const news = newsPool[i];
    const ex = takeEx(kind, i);
    const yt = pickVideo(videos, `${news.title} ${ex.titleVi}`, i);
    plan.push({
      day: i + 1,
      date: ymd(d),
      weekday: WEEKDAY_VI[dow],
      kind,
      news: { title: news.title, url: news.permalink, score: news.score, topics: news.topics, pubDate: news.pubDate },
      exercise: { slug: ex.slug, titleVi: ex.titleVi, difficulty: ex.difficulty, url: ex.url, ogImage: ex.ogImage },
      youtube: { channel: YT_CHANNEL, videoId: yt.videoId, title: yt.title, url: yt.url, matched: yt.matched },
    });
  }
  return plan;
}

// ===== IN RA ================================================================================

const cut = (s, n) => (s.length <= n ? s : `${s.slice(0, n - 1)}…`);
const pad = (s, n) => cut(String(s), n).padEnd(n);

function printNews(res, limit) {
  const rows = res.items.slice(0, limit);
  console.log(`news.8syncdev.com — ${res.items.length} bài trong feed · ${res.sitemapArticles} permalink trong sitemap · sổ cái có ${res.ledgerSize} link đã đăng`);
  console.log(`điểm = mới (0–${W_FRESH}, tuyến tính ${FRESH_DAYS} ngày) + chủ đề (0–${W_TOPIC_CAP}, org-core/products.md) + sổ cái (${P_POSTED} nếu đã đăng)`);
  console.log('');
  console.log(`${pad('#', 3)} ${pad('điểm', 6)} ${pad('mới', 5)} ${pad('chủ đề', 7)} ${pad('sổ', 4)} ${pad('nhóm khớp', 26)} ${pad('tiêu đề', 58)} link`);
  console.log('-'.repeat(150));
  for (const r of rows) {
    console.log(`${pad(r.rank, 3)} ${pad(r.score, 6)} ${pad(r.fresh, 5)} ${pad(r.topic, 7)} ${pad(r.postedPenalty || '·', 4)} ${pad(r.topics.join(',') || '(không)', 26)} ${pad(r.title, 58)} ${r.permalink || '⚠ CHƯA CÓ PERMALINK — không đăng'}`);
  }
  const noLink = res.items.filter((x) => !x.permalink).length;
  const dup = res.items.filter((x) => x.posted).length;
  console.log('');
  console.log(`đã đăng (bị trừ ${P_POSTED}): ${dup} · thiếu permalink: ${noLink}`);
}

function printEx(rows, limit) {
  const shown = rows.slice(0, limit);
  const byDiff = {};
  for (const e of rows) byDiff[e.difficulty] = (byDiff[e.difficulty] || 0) + 1;
  console.log(`coding.8syncdev.com — ${rows.length} bài tập · ${Object.entries(byDiff).map(([k, v]) => `${k} ${v}`).join(' · ')}`);
  console.log('');
  console.log(`${pad('#', 3)} ${pad('bậc', 8)} ${pad('slug', 44)} ${pad('tên tiếng Việt', 40)} sổ`);
  console.log('-'.repeat(110));
  shown.forEach((e, i) => {
    console.log(`${pad(i + 1, 3)} ${pad(e.difficulty, 8)} ${pad(e.slug, 44)} ${pad(e.titleVi, 40)} ${e.posted ? 'ĐÃ ĐĂNG' : '·'}`);
  });
}

function printYt(rows, limit) {
  console.log(`${YT_CHANNEL} — ${rows.length} video mới nhất qua RSS kênh (đích của phễu, không phải nguồn)`);
  console.log('');
  rows.slice(0, limit).forEach((v, i) => {
    console.log(`${pad(i + 1, 3)} ${pad(v.published.slice(0, 10), 11)} ${pad(v.title, 82)} ${v.url}`);
  });
}

function printPlan(plan) {
  const c = {};
  for (const d of plan) c[d.kind] = (c[d.kind] || 0) + 1;
  console.log(`Nguyên liệu ${plan.length} ngày · ${plan[0].date} → ${plan[plan.length - 1].date}`);
  console.log(`tỉ lệ: ${Object.entries(c).map(([k, v]) => `${k} ${v}`).join(' · ')} (chuẩn 4 share : 2 bài học : 1 product mỗi tuần — mkt-playbook §2)`);
  console.log('');
  console.log(`${pad('#', 3)} ${pad('ngày', 11)} ${pad('thứ', 4)} ${pad('loại', 8)} ${pad('news (điểm)', 52)} ${pad('bài tập', 34)} đích YouTube`);
  console.log('-'.repeat(190));
  for (const d of plan) {
    console.log(`${pad(d.day, 3)} ${pad(d.date, 11)} ${pad(d.weekday, 4)} ${pad(d.kind, 8)} ${pad(`${d.news.title} (${d.news.score})`, 52)} ${pad(`${d.exercise.titleVi} [${d.exercise.difficulty}]`, 34)} ${d.youtube.url}`);
  }
  const missing = plan.filter((d) => !d.youtube.url).length;
  console.log('');
  console.log(`ngày thiếu link YouTube: ${missing} (phải là 0 — doctrine 2026-08-02: YouTube là đích, mọi bài phải có 1 đường về @Dev8Sync)`);
  console.log('Link trong comment #1 xếp theo thứ tự: YouTube → news → coding.');
}

// ===== MAIN =================================================================================

const USAGE = `harvest.mjs — thu hoạch + xếp hạng nguyên liệu content (skill post-all)

  news [--limit N] [--json]                    xếp hạng bài news theo điểm nóng
  ex   [--limit N] [--json] [--difficulty D]   danh sách bài tập coding
  yt   [--limit N] [--json]                    video mới nhất của @Dev8Sync (ĐÍCH của phễu)
  plan --days N [--start YYYY-MM-DD] [--json]  bảng nguyên liệu N ngày (trần 31 = 1 tháng)`;

async function main(argvRaw) {
  const cmd = argvRaw[0];
  const o = args(argvRaw.slice(1));
  if (!cmd || cmd === '--help' || cmd === '-h') { console.log(USAGE); return 0; }
  const limit = o.limit ? Number(o.limit) : 20;
  if (o.limit && (!Number.isFinite(limit) || limit < 1)) fail(`--limit "${o.limit}" không phải số dương.`);

  if (cmd === 'news') {
    const res = await harvestNews();
    if (o.json) console.log(JSON.stringify(res.items.slice(0, limit)));
    else printNews(res, limit);
    return 0;
  }
  if (cmd === 'ex') {
    let rows = await harvestEx();
    if (typeof o.difficulty === 'string') {
      rows = rows.filter((e) => e.difficulty === o.difficulty);
      if (!rows.length) fail(`không có bài tập nào bậc "${o.difficulty}" (hợp lệ: easy, medium, hard, expert).`);
    }
    if (o.json) console.log(JSON.stringify(rows.slice(0, limit)));
    else printEx(rows, limit);
    return 0;
  }
  if (cmd === 'yt') {
    const rows = await harvestYt();
    if (o.json) console.log(JSON.stringify(rows.slice(0, limit).map(({ tokens, ...v }) => v)));
    else printYt(rows, limit);
    return 0;
  }
  if (cmd === 'plan') {
    const plan = await buildPlan({ days: Number(o.days ?? 30), start: typeof o.start === 'string' ? o.start : null });
    if (o.json) console.log(JSON.stringify(plan));
    else printPlan(plan);
    return 0;
  }

  console.error(`lệnh lạ: ${cmd}\n\n${USAGE}`);
  return 2;
}

try {
  process.exitCode = await main(process.argv.slice(2));
} catch (e) {
  if (e instanceof Fail) console.error(`LỖI: ${e.message}`);
  else console.error(`LỖI KHÔNG LƯỜNG TRƯỚC: ${e?.stack || e}`);
  process.exitCode = 1;
}
