// linkedin-scrape.snippet.js — chạy TRONG omp browser tool (action:"run"), KHÔNG chạy standalone.
// Tiền đề: browser attach vào profile LinkedIn đã đăng nhập của repo:
//   bash writter-ai/skills/linkedin-cv-sync/scripts/linkedin-browser.sh open
//   -> browser tool: {"action":"open","name":"li","app":{"cdp_url":"http://127.0.0.1:9222"}}
// Sau đó paste toàn bộ file này làm `code` của {"action":"run","name":"li","timeout":900}.
// Kết quả ghi ra /tmp/jobscan/linkedin.json (code chạy với full Node access).
// Tùy biến: sửa object `searches` (key = category hint cho build_digest.py, value = keywords đã URL-encode).

const fs = require('fs');

async function scrapeSearch(url) {
  await tab.goto(url, { waitUntil: 'domcontentloaded' });
  await new Promise(r => setTimeout(r, 3500));
  // list lazy-load: cuộn pane kết quả (KHÔNG phải window) tới khi số card đứng yên
  let prev = 0;
  for (let i = 0; i < 15; i++) {
    const n = await tab.evaluate(() => {
      const li = document.querySelector('li[data-occludable-job-id]');
      if (!li) return 0;
      let el = li.parentElement;
      while (el && el.scrollHeight <= el.clientHeight + 10) el = el.parentElement;
      if (el) el.scrollBy(0, 800); else window.scrollBy(0, 800);
      return document.querySelectorAll('li[data-occludable-job-id]').length;
    });
    await new Promise(r => setTimeout(r, 900));
    if (n === prev && i > 4) break;
    prev = n;
  }
  return await tab.evaluate(() => {
    return [...document.querySelectorAll('li[data-occludable-job-id]')].map(c => {
      const a = c.querySelector('a[href*="/jobs/view/"]');
      const title = (c.querySelector('.job-card-list__title--link strong, .artdeco-entity-lockup__title') || a)?.innerText?.trim();
      const company = c.querySelector('.artdeco-entity-lockup__subtitle')?.innerText?.trim();
      const loc = c.querySelector('.artdeco-entity-lockup__caption li, .job-card-container__metadata-wrapper li')?.innerText?.trim();
      return { title, company, loc, href: a ? a.href.split('?')[0] : '' };
    }).filter(j => j.title && j.href);
  });
}

// f_WT=2 = Remote · f_TPR=r2592000 = 30 ngày gần nhất
const base = 'https://www.linkedin.com/jobs/search/?f_WT=2&location=Worldwide&f_TPR=r2592000&keywords=';
const searches = {
  ai: 'AI%20Engineer%20LLM',
  ml: 'Machine%20Learning%20Engineer',
  fullstack: 'Full%20Stack%20Engineer%20TypeScript%20Next.js',
  web: 'Web%20Developer%20React',
  mobile: 'React%20Native%20OR%20Flutter%20Mobile%20Developer',
  game: 'Game%20Developer%20Unity',
  gameart: 'Game%20Artist%202D%203D',
  design: 'UI%20UX%20Designer',
  art: 'Digital%20Artist%20Illustrator',
  cn: '%E8%BF%9C%E7%A8%8B%20%E5%B7%A5%E7%A8%8B%E5%B8%88',   // 远程 工程师
  cndev: '%E8%BF%9C%E7%A8%8B%20%E5%BC%80%E5%8F%91',          // 远程 开发
};

const all = {};
for (const [k, q] of Object.entries(searches)) {
  try { all[k] = await scrapeSearch(base + q); } catch (e) { all[k] = []; }
}
fs.mkdirSync('/tmp/jobscan', { recursive: true });
fs.writeFileSync('/tmp/jobscan/linkedin.json', JSON.stringify(all, null, 1));
return Object.fromEntries(Object.entries(all).map(([k, v]) => [k, v.length]));
