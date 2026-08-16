#!/usr/bin/env node
// news-ideas.js — AUTO đọc API backend news.8syncdev.com (public, KHÔNG auth)
// → chấm liên quan tới khán giả "học lập trình VN" → phân loại 2 vế → xuất idea
// card (share-kiến-thức / mkt-sale) + phễu + CTA + nỗi đau + LINK NGƯỢC news.
//
// Vì sao API (không phải feed.xml)? Backend cron bài mới mỗi ngày, có:
//   • rank=latest (mới nhất) · rank=hot (hot nhất) · rankings?period (top kỳ)
//   • category (9 danh mục — dùng categories HỌC THUẬT là dễ làm content nhất)
//   • viSummary (tóm tắt tiếng Việt AI SẴN) · imageUrl (ảnh OG) · whyRead · score
// → nguồn content vô tận, đã tóm tắt VN, chỉ việc chọn góc + link ngược.
//
// Đích cuối: bán tutorial (giáo viên có học viên). Share xây traffic/uy tín (TOP)
// → coding (luyện free) → tutorial (DOANH THU). News = kho content gốc.
//
// Chạy:  node scripts/news-ideas.js [options]
//   --n N            số idea xuất (mặc định 8)
//   --rank hot|latest  xếp theo hot / mới (mặc định hot)
//   --category SLUG  1 danh mục: ai-ml|frontend|backend|devops|security|mobile|opensource|career|other
//   --all            duyệt HẾT categories học thuật, xuất NHÓM THEO DANH MỤC (dễ lên lịch)
//   --period 7d|30d|all   dùng bảng xếp hạng (rankings) thay feed
//   --json           in JSON thay vì markdown
//
// KHÔNG bịa: chỉ dùng bài THẬT từ API. Hook/CTA là GỢI Ý; người viết bám nỗi đau
// thật (mkt-playbook §4b) + LUÔN link ngược news.8syncdev.com/articles/<slug>.

const SITE = process.env.NEWS_SITE || 'https://news.8syncdev.com';
const API = process.env.NEWS_API || `${SITE}/api/backend/news/news`;

// Danh mục HỌC THUẬT (map thẳng sang chủ đề dạy) — bỏ "other". `career`/`security`
// hook nỗi đau mạnh (top funnel); `frontend`/`backend`/`ai-ml`… = lát cắt dạy.
const ACADEMIC = ['ai-ml', 'frontend', 'backend', 'devops', 'security', 'mobile', 'opensource', 'career'];
const CAT_LABEL = {
  'ai-ml': 'AI / ML', frontend: 'Frontend', backend: 'Backend', devops: 'DevOps & Cloud',
  mobile: 'Mobile', security: 'Security', opensource: 'Open Source', career: 'Sự nghiệp', other: 'Khác',
};
// Góc dạy gợi ý theo danh mục (định vị trường code) — người viết tuỳ biến.
const CAT_ANGLE = {
  'ai-ml': 'Định vị "kỹ sư vận hành AI/RAG" — bắt trend, dẫn về học nền tảng.',
  frontend: 'Lát cắt React/Next.js/UI — dạy nhanh 1 kỹ thuật, mời học 1-1.',
  backend: 'API/Go/database/thuật toán — chứng minh chất lượng mentor.',
  devops: 'Docker/K8s/CI-CD — kỹ năng "được tuyển", gắn lộ trình.',
  security: 'NỖI ĐAU bảo mật (breach/lỗ hổng) — cảnh tỉnh → dạy làm đúng.',
  mobile: 'Flutter/mobile — sản phẩm chạy được → portfolio.',
  opensource: 'Đọc source thật → chuẩn kỹ sư (khác copy-paste).',
  career: 'NỖI ĐAU nghề (bằng cấp ≠ việc làm, AI thay copy-paste) → mời luyện.',
};

// ── taxonomy phụ: chấm thêm nỗi đau/nghề trên (title + viSummary) để chọn vế ──
const KW = {
  pain: { w: 3, terms: ['junior', 'fail', 'mistake', 'sai lầm', 'tuyển', 'hiring', 'interview', 'phỏng vấn', 'lương', 'salary', 'job', 'việc làm', 'career', 'nghề', 'layoff', 'sa thải', 'breach', 'ddos', 'attack', 'tấn công', 'lỗ hổng', 'vulnerability'] },
  learn: { w: 2, terms: ['guide', 'tutorial', 'how to', 'cách', 'học', 'walkthrough', 'step-by-step', 'từng bước', 'explained', 'giải thích', 'khóa học', 'course', 'lộ trình', 'algorithm', 'thuật toán', 'data structure', 'cấu trúc dữ liệu'] },
  tool: { w: 2, terms: ['ide', 'editor', 'vs code', 'vscode', 'công cụ', 'framework mới', 'ra mắt', 'release', 'launch', 'v1.0', 'open-source', 'library'] },
  noise: { w: -20, terms: ['casino', 'kiếm tiền', 'earning app', 'apk download', 'lottery', 'xổ số', 'betting', 'cá cược', 'crypto pump', 'road trip'] },
};

function scoreText(t) {
  const s = (t || '').toLowerCase();
  const hits = {};
  let score = 0;
  for (const [grp, { w, terms }] of Object.entries(KW)) {
    let n = 0;
    for (const term of terms) if (s.includes(term)) n++;
    if (n) { hits[grp] = n; score += n * w; }
  }
  return { score, hits };
}

// ── 2 vế: share-kiến-thức (TOP) vs mkt-sale (bài học/product) ──
function classify(cat, hits) {
  const pain = hits.pain || 0, learn = hits.learn || 0, tool = hits.tool || 0;
  if (cat === 'security' || cat === 'career' || pain >= 2) {
    return { loai: 'share', pillar: 'share-kiến-thức', cua_vao: 'news→coding', cta: 'tutorial (học bài bản 1-1)', goc: CAT_ANGLE[cat] || 'Xoáy nỗi đau nghề → giá trị free → mời luyện.' };
  }
  if (tool >= 2 && learn < 2) {
    return { loai: 'product', pillar: 'mkt-sale', cua_vao: 'demo công cụ → ZUS', cta: 'ZUS (AI IDE) / coding', goc: 'Gắn công cụ mới với ZUS AI IDE — demo tính năng, kết quả.' };
  }
  if (learn >= 1 || ['frontend', 'backend', 'ai-ml', 'devops', 'mobile'].includes(cat)) {
    return { loai: 'bài học', pillar: 'mkt-sale', cua_vao: 'tutorial (lát cắt bài giảng)', cta: 'coding (1.000 bài free) + tutorial', goc: CAT_ANGLE[cat] || 'Trích 1 kỹ thuật → dạy nhanh → mời học 1-1.' };
  }
  return { loai: 'share', pillar: 'share-kiến-thức', cua_vao: 'news→coding', cta: 'coding (luyện thử)', goc: CAT_ANGLE[cat] || 'Chia sẻ free, quảng cáo ẩn (giá trị + brand).' };
}

async function api(path) {
  const res = await fetch(`${API}${path}`, { headers: { accept: 'application/json' } });
  if (!res.ok) throw new Error(`API ${path} -> ${res.status}`);
  return res.json();
}
const getFeed = (qs) => api(`/feed${qs}`).then((d) => d.articles || []);
const getRankings = (period) => api(`/rankings?period=${period}`).then((d) => d.articles || []);
const getCategories = () => api('/categories').then((d) => d.categories || []);

function enrich(a) {
  const summary = a.viSummary || a.description || '';
  const { score: kwScore, hits } = scoreText(`${a.title} ${summary}`);
  const cls = classify(a.category, hits);
  return {
    title: a.title,
    slug: a.slug,
    category: a.category || 'other',
    catLabel: CAT_LABEL[a.category] || 'Khác',
    summary,
    whyRead: a.whyRead || '',
    upvotes: a.upvotes || 0,
    backendScore: a.score || 0,
    kwScore,
    linkBack: `${SITE}/articles/${a.slug}`, // ⬅ LINK NGƯỢC (OG image tự hiện trên FB)
    source: a.url,                          // nguồn gốc — chỉ ghi chú, KHÔNG đăng thay link ngược
    image: a.imageUrl || '',
    ...cls,
  };
}

function card(x, i) {
  const L = [];
  L.push(`### ${i}. ${x.title}  \`${x.loai}\` · ${x.pillar} · [${x.catLabel}] · ▲${x.upvotes}`);
  L.push(`- **Tóm tắt (VN, từ news):** ${x.summary.slice(0, 240)}`);
  if (x.whyRead) L.push(`- **Vì sao đáng đọc:** ${x.whyRead.slice(0, 160)}`);
  L.push(`- **Góc content:** ${x.goc}`);
  L.push(`- **Phễu:** cửa vào ${x.cua_vao} → CTA **${x.cta}**`);
  L.push(`- **🔗 Link ngược (đăng cái này):** ${x.linkBack}`);
  L.push(`- _Nguồn gốc (chỉ ghi chú): ${x.source}_`);
  return L.join('\n');
}

async function main() {
  const argv = process.argv.slice(2);
  const opt = (k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d; };
  const n = parseInt(opt('--n', '8'), 10);
  const rank = opt('--rank', 'hot');
  const category = opt('--category', null);
  const period = opt('--period', null);
  const all = argv.includes('--all');
  const json = argv.includes('--json');
  const today = new Date().toISOString().slice(0, 10);

  const header = `> Đích: bán tutorial (GV có học viên). Mỗi bài PHẢI **link ngược ${SITE}/articles/<slug>** (OG image tự hiện) + mở bằng **nỗi đau thật** (mkt-playbook §4b) + **CTA phễu**. Tóm tắt VN lấy sẵn từ API.`;

  // ── --all: nhóm theo danh mục học thuật (dễ lên lịch tháng) ──
  if (all) {
    const cats = await getCategories();
    const active = cats.filter((c) => ACADEMIC.includes(c.slug)).sort((a, b) => b.count - a.count);
    const out = {};
    for (const c of active) {
      const arts = await getFeed(`?category=${c.slug}&rank=${rank}&limit=${Math.max(n, 4)}`);
      out[c.slug] = arts.map(enrich).filter((x) => (x.kwScore || 0) > -10).slice(0, n);
    }
    if (json) { console.log(JSON.stringify({ date: today, mode: 'all', rank, categories: out }, null, 2)); return; }
    console.log(`# Ý tưởng content theo DANH MỤC HỌC THUẬT — ${today} (rank=${rank})`);
    console.log(`_Nguồn: API ${SITE} · ${active.length} danh mục · lấy top ${n}/danh mục._\n`);
    console.log(header + '\n');
    for (const c of active) {
      console.log(`## ${CAT_LABEL[c.slug]}  (\`${c.slug}\` · ${c.count} bài trong kho · trang: ${SITE}/danh-muc/${c.slug})`);
      console.log(`_Góc dạy: ${CAT_ANGLE[c.slug]}_\n`);
      out[c.slug].forEach((x, i) => console.log(card(x, i + 1) + '\n'));
    }
    return;
  }

  // ── 1 luồng: category | rankings(period) | feed(rank) ──
  let arts;
  let src;
  if (period) { arts = await getRankings(period); src = `rankings period=${period}`; }
  else if (category) { arts = await getFeed(`?category=${category}&rank=${rank}&limit=${Math.max(n * 2, 20)}`); src = `category=${category} rank=${rank}`; }
  else { arts = await getFeed(`?rank=${rank}&limit=${Math.max(n * 2, 20)}`); src = `feed rank=${rank}`; }

  const ranked = arts.map(enrich)
    .filter((x) => (x.kwScore || 0) > -10)
    .sort((a, b) => (b.upvotes + b.kwScore * 3) - (a.upvotes + a.kwScore * 3))
    .slice(0, n);

  if (json) { console.log(JSON.stringify({ date: today, src, ideas: ranked }, null, 2)); return; }
  console.log(`# Ý tưởng content từ news.8syncdev.com — ${today}`);
  console.log(`_Nguồn: API ${SITE} · ${src} · ${arts.length} bài → top ${ranked.length}._\n`);
  console.log(header + '\n');
  ranked.forEach((x, i) => console.log(card(x, i + 1) + '\n'));
}

main().catch((e) => { console.error(e); process.exit(1); });
