// audit-fanpage.js — chạy trong omp browser tool đã attach CDP :9222 (profile đã login FB).
// Dùng: attach browser -> goto facebook.com/8syncdev -> paste body này vào tab.evaluate (sau khi scroll).
// Trả về: post gần nhất, domain link ngoài (đã giải mã l.php?u=), có link news.8syncdev.com không, hashtag, ảnh.
//
// Cách chạy chuẩn (browser tool `run`):
//   for(let i=0;i<12;i++){await tab.evaluate(()=>window.scrollBy(0,2000));await new Promise(r=>setTimeout(r,1000));}
//   const res = await tab.evaluate(auditFanpage);  // (dán hàm dưới)
//   return res;

function auditFanpage() {
  const dec = (h) => {
    try {
      const u = new URL(h);
      if (u.pathname.includes('l.php')) return decodeURIComponent(u.searchParams.get('u') || '');
      return h;
    } catch (e) { return h; }
  };
  const all = [...document.querySelectorAll('a[href]')].map(a => dec(a.href));
  const own = [...new Set(all.filter(h => /8syncdev\.com/.test(h)).map(h => h.split('?')[0]))];
  const external = [...new Set(all
    .filter(h => /^https?:\/\//.test(h) && !/8syncdev\.com|facebook\.com|fbcdn|fb\.me/.test(h))
    .map(h => { try { return new URL(h).hostname; } catch (e) { return h; } }))];
  const hasNews = all.some(h => /news\.8syncdev/.test(h));
  const msgs = [...document.querySelectorAll('div[data-ad-comet-preview="message"],div[data-ad-preview="message"],div[dir="auto"]')]
    .map(d => d.innerText.trim()).filter(t => t.length > 60);
  const posts = [...new Set(msgs)].slice(0, 12);
  const tags = [...new Set((document.body.innerText.match(/#[\wÀ-ỹ]+/g) || []))].slice(0, 30);
  return {
    ownLinks: own,            // link về hệ sinh thái 8syncdev
    externalHosts: external,  // ⚠ link ra ngoài = mất traffic
    hasNewsLink: hasNews,     // ⚠ false = KHÔNG dùng workflow news.8syncdev.com
    hashtags: tags,           // đối chiếu SEO VN (§4c)
    posts,                    // nội dung để chấm nỗi đau/CTA/loại content
    articleCount: document.querySelectorAll('[role=article]').length,
  };
}

if (typeof module !== 'undefined') module.exports = { auditFanpage };
