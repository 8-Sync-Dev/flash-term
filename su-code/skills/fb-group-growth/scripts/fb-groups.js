// fb-groups.js — helpers chạy TRONG omp browser tool (action:"run", name:"fb") sau khi
// attach profile browser CDP :9222 (đã login FB nick fb.com/8sync). KHÔNG chạy standalone.
//
// Tiền đề:
//   bash .../browser-profile-control/scripts/profile-browser.sh open linkedin "https://www.facebook.com/8sync"
//   omp browser: {"action":"open","name":"fb","app":{"cdp_url":"http://127.0.0.1:9222"}}
//   rồi paste file này làm `code` của {"action":"run","name":"fb"} và gọi hàm ở cuối.
//
// AN TOÀN: postToGroup mặc định dryRun=true (chỉ soạn, KHÔNG đăng). Đăng thật chỉ khi
// founder GO — rải giờ ≥20–30'/nhóm, nội dung tùy biến từng nhóm (tránh FB gắn cờ spam).

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ===== FORMAT (FB 2026 KHÔNG có rich-text native → Unicode toán học; VERIFIED render sạch cả tiếng Việt) =====
// NFD-decompose → bold/italic ký tự gốc A-Z/a-z/0-9 → dấu tổ hợp VN (ậ,ố,ì) tự gắn lại. đ/Đ không có bản đậm (giữ nguyên).
// Dùng VỪA PHẢI (screen-reader đọc kém nếu lạm dụng): chỉ tiêu đề + 2-3 cụm nhấn.
function _style(str, capBase, lowBase, digBase) {
  return str.normalize('NFD').replace(/[A-Za-z0-9]/g, (c) => {
    const n = c.charCodeAt(0);
    if (n >= 65 && n <= 90) return String.fromCodePoint(capBase + n - 65);
    if (n >= 97 && n <= 122) return String.fromCodePoint(lowBase + n - 97);
    if (digBase && n >= 48 && n <= 57) return String.fromCodePoint(digBase + n - 48);
    return c;
  });
}
const fmt = {
  bold: (s) => _style(s, 0x1D5D4, 0x1D5EE, 0x1D7EC),   // 𝗕𝗼𝗹𝗱 sans (heading/nhấn)
  ital: (s) => _style(s, 0x1D608, 0x1D622, 0),          // 𝘐𝘵𝘢𝘭𝘪𝘤 sans (quote)
  boldItal: (s) => _style(s, 0x1D63C, 0x1D656, 0x1D7EC),
  h1: (s) => '➤ ' + _style(s, 0x1D5D4, 0x1D5EE, 0x1D7EC),   // tiêu đề lớn
  h2: (s) => '▸ ' + _style(s, 0x1D5D4, 0x1D5EE, 0x1D7EC),   // tiêu đề phụ
  quote: (s) => '❝ ' + _style(s, 0x1D608, 0x1D622, 0) + ' ❞',
  bullet: (arr) => arr.map((x) => '• ' + x).join('\n'),
  num: (arr) => arr.map((x, i) => (i + 1) + '️⃣ ' + x).join('\n'),
  hr: '━━━━━━━━━━━',
};

// 1) Liệt kê nhóm đang tham gia (validate 2026-07-20: 40+ nhóm)
async function listMyGroups() {
  await tab.goto('https://www.facebook.com/groups/joins/?nav_source=tab', { waitUntil: 'domcontentloaded' });
  await sleep(4000);
  for (let i = 0; i < 8; i++) { await tab.evaluate(() => window.scrollBy(0, 2000)); await sleep(1000); }
  return await tab.evaluate(() => {
    const links = [...document.querySelectorAll('a[href*="/groups/"]')]
      .map((a) => ({ name: (a.innerText || '').replace(/\s+/g, ' ').trim(), url: a.href.split('?')[0] }))
      .filter((x) => x.name.length > 2 && /\/groups\/[^/]+\/?$/.test(x.url)
        && !/\/(feed|discover|joins)\/?$/.test(x.url));
    const seen = new Set(); const out = [];
    for (const l of links) { if (!seen.has(l.url)) { seen.add(l.url); out.push(l); } }
    return out;
  });
}

// 2) Đọc rule + chính sách link của 1 nhóm
async function readGroupRules(groupUrl) {
  const base = groupUrl.replace(/\/$/, '');
  await tab.goto(base + '/about', { waitUntil: 'domcontentloaded' });
  await sleep(3500);
  return await tab.evaluate(() => {
    const txt = (document.body.innerText || '').replace(/\s+/g, ' ');
    const rulesIdx = txt.search(/Quy định của nhóm|Group rules/i);
    const rules = rulesIdx >= 0 ? txt.slice(rulesIdx, rulesIdx + 1500) : '';
    const banLink = /không.{0,20}(link|liên kết)|no.{0,10}(external )?links?|không quảng cáo|no self.?promot/i.test(txt);
    const approval = /(duyệt bài|phê duyệt|post approval|admin.{0,10}approve)/i.test(txt);
    return { banLinkGuess: banLink, postApprovalGuess: approval, rulesText: rules.slice(0, 1200) };
  });
}

// 3) Tìm nhóm mới (VN keyword tiếng Việt / intl keyword tiếng Anh)
async function findMoreGroups(keyword) {
  await tab.goto('https://www.facebook.com/search/groups/?q=' + encodeURIComponent(keyword), { waitUntil: 'domcontentloaded' });
  await sleep(4000);
  for (let i = 0; i < 5; i++) { await tab.evaluate(() => window.scrollBy(0, 1800)); await sleep(1000); }
  return await tab.evaluate(() => {
    return [...document.querySelectorAll('a[href*="/groups/"]')]
      .map((a) => ({ name: (a.innerText || '').replace(/\s+/g, ' ').trim(), url: a.href.split('?')[0] }))
      .filter((x) => x.name.length > 3 && /\/groups\/[^/]+\/?$/.test(x.url))
      .slice(0, 25);
  });
}

// 4) Soạn bài FREE-SHARE (formatted). article={title,painHook,viSummary/enSummary,points:[],quote,valueLine,slug,url}
//    group={lang:'vi'|'en', linkPolicy:'body'|'image', tags:[], thankAdmin}
//    NHÓM NGOÀI = 100% FREE: KHÔNG CTA sản phẩm, KHÔNG câu comment, LINK trong body (nhóm siết → linkPolicy:'image' = ảnh chụp từ site).
function composeGroupPost(article, group) {
  const vi = group.lang !== 'en';
  if (!article.url && !article.slug) throw new Error('composeGroupPost: cần article.url/slug CỤ THỂ (/articles/<slug> hoặc /problem/<slug>) — KHÔNG homepage');
  const title = article.title ? fmt.h1(article.title) : '';                 // SEO: tiêu đề đậm keyword-rich
  const hook = article.painHook || (vi
    ? 'Mới học code hay bí chỗ bắt đầu? Mình để lại vài thứ free để luyện.'
    : 'Just starting out and stuck? Sharing some free stuff to practice.');
  const summary = vi ? (article.viSummary || '') : (article.enSummary || article.viSummary || '');
  const points = (article.points && article.points.length) ? fmt.bullet(article.points) : '';  // bullet: dwell-time
  const quote = article.quote ? fmt.quote(article.quote) : '';               // ❝ italic ❞
  const valueLine = article.valueLine || (vi ? 'Bản đầy đủ (free) ở đây:' : 'Full (free) here:');  // KHÔNG bán, chỉ trỏ đồ free
  const link = article.url || 'https://news.8syncdev.com/articles/' + (article.slug || '');
  const tags = (group.tags && group.tags.length) ? group.tags.join(' ') : '#8syncdev';  // brand LUÔN có
  const thanks = group.thankAdmin ? (vi ? 'Cảm ơn admin đã duyệt bài!' : 'Thanks admin for approving!') : '';
  // link LUÔN trong body (mn tự xem). Nhóm siết link → linkPolicy:'image' = đính ảnh chụp từ site, ghi nguồn thay link.
  const imageMode = group.linkPolicy === 'image';
  const linkOrNote = imageMode ? (vi ? '(Ảnh chụp từ chính site — nguồn: 8 Sync Dev / news.8syncdev.com)' : '(Screenshot from news.8syncdev.com — source: 8 Sync Dev)') : (valueLine + '\n' + link);
  const body = [thanks, title, hook, summary, points, quote, linkOrNote, tags].filter(Boolean).join('\n\n');
  return { body, comment: '', imageAttach: imageMode, lang: vi ? 'vi' : 'en', mode: group.mode || 'post', requiredTagNote: (group.tags && group.tags.length) ? 'nhóm cần tag: ' + group.tags.join(' ') : 'brand tag #8syncdev' };
}

// 5) postToGroup — MẶC ĐỊNH dryRun. Đăng thật: {dryRun:false}.
// VALIDATED 2026-07-20 (đã đăng thật fanpage + 2 nhóm): elementHandle.click()+type()
// (KHÔNG page.mouse.click toạ độ — screenshot downscale ~1.25× + không focus Lexical).
// Flow NHÓM: join nếu chưa member → composer "Bạn viết gì đi" → body handle type
// (link trong body → OG ảnh tự lên với nhóm dễ tính) → 1 nút "Đăng" → thường PENDING duyệt.
async function postToGroup(group, content, opts = {}) {
  const dryRun = opts.dryRun !== false; // default true — an toàn
  if (dryRun) return { dryRun: true, target: group.url, plan: content, note: 'DRY RUN — {dryRun:false} để đăng thật.' };
  await tab.goto(group.url, { waitUntil: 'domcontentloaded' }); await sleep(5000);
  page.removeAllListeners('dialog'); page.on('dialog', async (d) => { try { await d.accept(); } catch (e) {} });
  async function clickBtnText(re, minW) {
    const bs = await page.$$('[role=button]');
    for (const b of bs) { const t = ((await (await b.getProperty('innerText')).jsonValue()) || '').trim(); const bx = await b.boundingBox(); if (re.test(t) && bx && (!minW || bx.width > minW)) { await b.click(); return t; } }
    return '';
  }
  // 1) join nếu chưa là member
  const joinNeeded = await tab.evaluate(() => /Tham gia nhóm/.test(document.body.innerText) && !/Đã tham gia|Rời nhóm/.test(document.body.innerText));
  if (joinNeeded) { await clickBtnText(/^Tham gia nhóm$/); await sleep(5000); }
  // 2) mở composer (nhóm dùng "Bạn viết gì đi"; feed/page dùng "Bạn đang nghĩ gì")
  try { await tab.click('text/Bạn viết gì đi'); } catch (e) { try { await tab.click('text/Bạn đang nghĩ gì'); } catch (e2) {} }
  await sleep(3500);
  // 3) body: elementHandle click (focus) + type
  const hs = await page.$$('div[role=dialog] [role=textbox][contenteditable="true"]');
  let tb = null; for (const h of hs) { const b = await h.boundingBox(); if (b && b.height > 20) { tb = h; break; } }
  if (!tb) return { error: 'composer-body-not-found', target: group.url };
  await tb.click(); await sleep(500);
  await tb.type(content.body, { delay: 2 });
  await sleep(9000); // OG preview tự load nếu body có link
  // 4) Đăng (nhóm = 1 bước; fanpage = Tiếp→Đăng)
  let step = await clickBtnText(/^(Đăng|Tiếp)$/, 90); await sleep(4000);
  if (/Tiếp/i.test(step)) { await clickBtnText(/^Đăng$/, 90); await sleep(6000); } else { await sleep(3000); }
  // 5) trạng thái: pending duyệt vs live + permalink
  const st = await tab.evaluate(() => ({
    pending: /đang chờ phê duyệt|chờ quản trị viên phê duyệt|gửi bài viết cho quản trị/i.test(document.body.innerText),
    permalink: (document.querySelector('a[href*="/posts/"],a[href*="/permalink/"],a[href*="story_fbid"]') || {}).href || '',
  }));
  return { posted: true, target: group.url, pending: st.pending, permalink: (st.permalink || '').split('?')[0], commentLink: content.comment || '' };
}

// 6) batchPost — chạy nhiều nhóm từ PARAMS, rải giờ chống spam. items từ buildBatch().
//    opts.gapMs: cách nhau giữa 2 nhóm (mặc định 25 phút = 1500000). opts.dryRun mặc định true.
async function batchPost(items, opts = {}) {
  const gap = opts.gapMs != null ? opts.gapMs : 25 * 60 * 1000;
  const dryRun = opts.dryRun !== false;
  const results = [];
  for (let i = 0; i < items.length; i++) {
    const it = items[i];
    const r = await postToGroup({ url: it.url }, { body: it.body, comment: it.comment || '' }, { dryRun });
    results.push({ name: it.name || it.url, ...r });
    if (i < items.length - 1 && !dryRun) await sleep(gap); // rải giờ giữa các nhóm
  }
  return results;
}

// 7) buildBatch — từ PARAMS (nhóm + template) sinh danh sách bài, mỗi nhóm 1 bản khác hook.
//    groups: [{name,url,audience:'student'|'parent',tags:[],linkPolicy:'body'|'comment'}]
//    article: {viSummary, slug, painHook}. Trả items cho batchPost.
function buildBatch(groups, article) {
  return groups.map((g, idx) => {
    const c = composeGroupPost(article, { lang: 'vi', linkPolicy: g.linkPolicy || 'body', tags: g.tags || ['#8syncdev'], thankAdmin: g.thankAdmin });
    // đổi nhẹ hook theo index để tránh trùng lặp (FB phạt duplicate)
    const variants = ['', 'Chia sẻ nhẹ cho ai đang học: ', 'Tiện đây gửi mọi người: ', 'Một mẹo nhỏ: '];
    const body = (variants[idx % variants.length] || '') + c.body;
    return { name: g.name, url: g.url, body, comment: c.comment };
  });
}

// ==== PARAMS THẬT (thu hoạch 2026-07-20) — sửa ở đây rồi chạy batchPost ====
// Nhóm ĐÚNG KHÁCH + hashtag đầu vào riêng từng nhóm (audience + linkPolicy):
const GROUPS_STUDENT = [
  { name: 'Học LT cho người mới (Py/JS/C++) 11K', url: 'https://www.facebook.com/groups/2952419898364551', audience: 'student', tags: ['#8syncdev', '#hoclaptrinh', '#laptrinhchonguoimoi'], linkPolicy: 'body' },
  { name: 'Lập trình cơ bản 25K',                 url: 'https://www.facebook.com/groups/28techgroup',      audience: 'student', tags: ['#8syncdev', '#hoclaptrinh'],                        linkPolicy: 'body' },
  { name: 'C/C++ Python C# Java 12K',              url: 'https://www.facebook.com/groups/426381589699990',  audience: 'student', tags: ['#8syncdev', '#laptrinh'],                          linkPolicy: 'body' },
];
const GROUPS_PARENT = [
  { name: 'Cùng con học lập trình 2.4K', url: 'https://www.facebook.com/groups/cungconhoclaptrinh',  audience: 'parent', tags: ['#8syncdev', '#hoclaptrinhchotre'], linkPolicy: 'body', thankAdmin: true },
  { name: 'Giúp con học lập trình 1.2K', url: 'https://www.facebook.com/groups/giupconhoclaptrinh',  audience: 'parent', tags: ['#8syncdev', '#laptrinhchotreem'], linkPolicy: 'body', thankAdmin: true },
  { name: 'Học LT miễn phí cho trẻ 8.3K', url: 'https://www.facebook.com/groups/926339948372099',    audience: 'parent', tags: ['#8syncdev', '#tinhoctre'],       linkPolicy: 'body', thankAdmin: true },
];
// Bài do mình viết (article → composeGroupPost sinh body FREE-share). LINK PHẢI cụ thể (/problem/<slug> hoặc /articles/<slug>), KHÔNG homepage.
const ARTICLE_STUDENT = {
  title: 'Bài luyện code FREE có lời giải (Python/C++) — luyện tư duy',            // SEO
  painHook: 'Mới học lập trình, muốn luyện Python/C++ mà chưa biết bắt đầu từ đâu cho có lộ trình?',
  viSummary: 'Chia sẻ 1 bài luyện free (đề tiếng Việt, chấm tự động) + cả kho 1.000 bài từ cơ bản đến giải thuật để tự luyện, hợp ôn HSG/tin học trẻ lẫn tự học:',
  points: ['Đề tiếng Việt, ví dụ rõ ràng', 'Chấm tự động — biết ngay sai ở đâu', 'Từ dễ → khó (Python, C++, C, giải thuật)'],
  quote: 'Code mỗi ngày một ít, chắc gốc hơn cày lý thuyết.',
  valueLine: 'Làm thử bài này (free) ở đây:',
  // ⛔ LINK CỤ THỂ (KHÔNG homepage): đổi sang slug bài THẬT muốn share trước khi đăng.
  url: 'https://coding.8syncdev.com/problem/bit-lech-cam-bien-can-tho',
};
const ARTICLE_PARENT = {
  title: 'Bài luyện code MIỄN PHÍ cho con (đề tiếng Việt, có lời giải)',           // SEO
  painHook: 'Con muốn học lập trình mà chưa biết luyện ở đâu cho có lộ trình, khỏi học vẹt?',
  viSummary: 'Chia sẻ 1 bài luyện free cho bé (đề tiếng Việt, chấm tự động) + kho 1.000 bài từ dễ đến khó để con tự luyện mỗi ngày:',
  points: ['Đề tiếng Việt, con tự đọc hiểu', 'Chấm tự động, con biết sai ở đâu', 'Từ cơ bản → nâng cao (Python, C++)'],
  quote: 'Cho con luyện đều mỗi ngày, tư duy sẽ chắc.',
  valueLine: 'Cho bé làm thử bài này (free) ở đây:',
  // ⛔ LINK CỤ THỂ (KHÔNG homepage): đổi sang slug bài THẬT trước khi đăng.
  url: 'https://coding.8syncdev.com/problem/bit-lech-cam-bien-can-tho',
};

// ==== CHẠY (bỏ comment) — DRY RUN trước để soi body, rồi {dryRun:false} đăng thật, rải 25' ====
// return buildBatch(GROUPS_STUDENT, ARTICLE_STUDENT);                              // xem body sinh ra
// return await batchPost(buildBatch(GROUPS_STUDENT, ARTICLE_STUDENT), {dryRun:true});   // dry-run cả batch
// return await batchPost(buildBatch(GROUPS_STUDENT, ARTICLE_STUDENT), {dryRun:false, gapMs:25*60*1000}); // ĐĂNG THẬT
// return await batchPost(buildBatch(GROUPS_PARENT,  ARTICLE_PARENT),  {dryRun:false, gapMs:25*60*1000});
// Lẻ 1 nhóm: return await postToGroup({url:GROUPS_STUDENT[0].url}, {body:'...', comment:''}, {dryRun:false});
