// lark-base-ops — reusable Lark Base (Bitable) browser-control helpers.
// Runs inside the omp `browser` tool `run` context (Node, puppeteer). NOT sandboxed.
// Built on browser-profile-control: a logged-in Chromium profile on CDP :9222.
//
// Usage (inside a browser `run` cell):
//   const H = require('<repo>/8syncdev-org-skills/skills/lark-base-ops/scripts/lark-helpers.js');
//   const page = await H.attachBase(browser, '<baseUrl>');
//   await H.openTable(page, 'MKT_01 Lịch nội dung');
//   await H.openAddForm(page);
//   const rep = await H.addRecord(page, { text:{Content:'...'}, date:{Deadline:'20/07/2026'},
//       select:{'Loại content':'Bài học'}, link:{'Kênh đăng':'TikTok'}, member:{'Người phụ trách':['Hoàng Quyên']} });
//
// GOLDEN RULE (org): NEVER delete a base/table/record/field. Only ADD or UPDATE. No delete op here by design.
//
// Interaction model: Lark card-form fields activate on a COORDINATE click in the value zone
// (raw <input> handles are not directly clickable). Blur by clicking the record title —
// NEVER press Escape inside the form (Escape closes the whole panel).

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function attachBase(browser, baseUrl, opts = {}) {
  const recentName = opts.recentName || '8 SYNC DEV';
  const pages = await browser.pages();
  let page = pages.find((p) => baseUrl && p.url().includes(baseUrl.split('?')[0]));
  if (!page) {
    page = pages.find((p) => p.url().includes('/base/')) || (await browser.newPage());
    if (baseUrl) { try { await page.goto(baseUrl, { waitUntil: 'domcontentloaded' }); } catch (e) {} }
  }
  await page.bringToFront();
  await sleep(4000);
  const notFound = await page.evaluate(() => /doesn't exist|not found|không tìm/i.test(document.body.innerText));
  if (notFound) {
    await page.goto(new URL('/drive/home/', baseUrl).href, { waitUntil: 'domcontentloaded' });
    await sleep(6000);
    const info = await page.evaluate((nm) => {
      const els = [...document.querySelectorAll('*')].filter((e) => (e.innerText || '').trim().startsWith(nm) && e.children.length <= 3);
      if (!els.length) return null;
      const r = els[els.length - 1].getBoundingClientRect();
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    }, recentName);
    if (info) { await page.mouse.click(info.x, info.y, { clickCount: 2, delay: 60 }); await sleep(8000); }
    const np = (await browser.pages()).find((p) => p.url().includes('/base/'));
    if (np) { page = np; await page.bringToFront(); await sleep(3000); }
  }
  return page;
}

async function listTables(page) {
  return page.evaluate(() => {
    const items = [...document.querySelectorAll('[class*=table-tab__item-name],[class*=tab__item-name]')]
      .map((e) => (e.innerText || '').trim()).filter(Boolean);
    return [...new Set(items)];
  });
}

async function openTable(page, name) {
  const c = await page.evaluate((nm) => {
    const els = [...document.querySelectorAll('[class*=table-tab__item-name],[class*=tab__item-name]')]
      .filter((e) => (e.innerText || '').trim() === nm);
    if (!els.length) return null;
    const r = els[0].getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  }, name);
  if (!c) throw new Error('table not found: ' + name);
  await page.mouse.click(c.x, c.y);
  await sleep(4000);
  return true;
}

async function formOpen(page) {
  return page.evaluate(() => !!document.querySelector('[class*=card-field-editor]'));
}

async function openAddForm(page) {
  if (await formOpen(page)) return true;
  const b = await page.evaluate(() => {
    const el = [...document.querySelectorAll('*')].find((e) => e.children.length <= 2 && /^\+?\s*Add Record$/.test((e.innerText || '').trim()));
    if (!el) return null; const r = el.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  if (!b) throw new Error('Add Record button not found');
  await page.mouse.click(b.x, b.y);
  await sleep(2500);
  return formOpen(page);
}

// Coordinate of the value zone of a field row (right portion), by label prefix.
async function rowValueXY(page, label, frac = 0.6) {
  const c = await page.evaluate((lbl, fr) => {
    const rows = [...document.querySelectorAll('[class*=card-field-editor]')];
    const r = rows.find((x) => (x.innerText || '').trim().startsWith(lbl));
    if (!r) return null;
    r.scrollIntoView({ block: 'center' });
    const b = r.getBoundingClientRect();
    return { x: b.x + b.width * fr, y: b.y + b.height / 2 };
  }, label, frac);
  return c;
}

// Blur the active field by clicking the record title (safe; Escape would close the panel).
async function blur(page) {
  const t = await page.evaluate(() => {
    const el = [...document.querySelectorAll('*')].find((e) => /^(Untitled record|Bản ghi)/.test((e.innerText || '').trim()) && e.children.length <= 2);
    if (el) { const r = el.getBoundingClientRect(); return { x: r.x + 40, y: r.y + r.height / 2 }; }
    return { x: 1200, y: 130 };
  });
  await page.mouse.click(t.x, t.y);
  await sleep(250);
}

async function fillText(page, label, val) {
  const c = await rowValueXY(page, label);
  if (!c) throw new Error('row not found');
  await page.mouse.click(c.x, c.y);
  await sleep(250);
  await page.keyboard.down('Control'); await page.keyboard.press('KeyA'); await page.keyboard.up('Control');
  await sleep(80);
  await page.keyboard.type(String(val), { delay: 4 });
  await sleep(150);
  await blur(page);
}

async function fillDate(page, label, val) {
  const c = await rowValueXY(page, label);
  if (!c) throw new Error('row not found');
  await page.mouse.click(c.x, c.y);
  await sleep(300);
  await page.keyboard.type(String(val), { delay: 20 }); // DD/MM/YYYY
  await sleep(300);
  await blur(page); // NOT Escape (would close the form)
}

async function fillSelect(page, label, val) {
  const c = await rowValueXY(page, label);
  if (!c) throw new Error('row not found');
  await page.mouse.click(c.x, c.y);
  await sleep(400);
  await page.keyboard.type(String(val), { delay: 15 });
  await sleep(800);
  const picked = await page.evaluate((v) => {
    const opts = [...document.querySelectorAll('[class*=option],[role=option],[class*=select-item],[class*=dropdown] li')]
      .filter((e) => (e.innerText || '').trim());
    let t = opts.find((e) => (e.innerText || '').trim() === v)
      || opts.find((e) => /add|thêm|create|tạo/i.test(e.innerText || '') && (e.innerText || '').includes(v))
      || opts.find((e) => (e.innerText || '').trim().includes(v));
    if (!t) return false; const r = t.getBoundingClientRect(); window.__lk = { x: r.x + Math.min(30, r.width / 2), y: r.y + r.height / 2 }; return true;
  }, String(val));
  if (picked) { const p = await page.evaluate(() => window.__lk); await page.mouse.click(p.x, p.y); await sleep(400); }
  await blur(page);
  return picked;
}

// Link-record picker is a CANVAS grid (record text NOT in DOM). Select by COORDINATE.
// DIM_Kênh rows are fixed order Facebook/Tiktok/Youtube -> map name to row-y. Unknown
// values fall back to: type into the DOM Search input to filter, then click row-0.
// Checkbox column x≈298; data rows at y 283/316/347 (modal is fixed & centered).
const LINK_ROW_Y = { facebook: 283, tiktok: 316, youtube: 347 };
async function fillLink(page, label, val, opts = {}) {
  const c = await rowValueXY(page, label);
  if (!c) throw new Error('row not found');
  await page.mouse.click(c.x, c.y);
  await sleep(1600);
  const modal = await page.evaluate(() => /Linked to/.test(document.body.innerText));
  if (!modal) throw new Error('link modal not opened');
  const rowY = opts.rowY || LINK_ROW_Y[String(val).toLowerCase()];
  const cbx = opts.cbx || 298;
  if (rowY) {
    await page.mouse.click(cbx, rowY);
  } else {
    await page.evaluate(() => { const i = [...document.querySelectorAll('input')].find((x) => { const r = x.getBoundingClientRect(); return r.width > 200 && r.y < 320; }); if (i) i.focus(); });
    await page.keyboard.type(String(val), { delay: 20 }); await sleep(1100);
    await page.mouse.click(cbx, 283);
  }
  await sleep(600);
  const sel = await page.evaluate(() => { const m = document.body.innerText.match(/Selected:\s*(\d+)/); return m ? +m[1] : 0; });
  const conf = await page.evaluate(() => {
    const b = [...document.querySelectorAll('button,[role=button]')].find((e) => /^(Confirm|Xác nhận)$/i.test((e.innerText || '').trim()));
    if (!b) return null; const r = b.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  if (conf) { await page.mouse.click(conf.x, conf.y); await sleep(1000); }
  return sel > 0;
}

async function fillMember(page, label, vals) {
  const first = await rowValueXY(page, label);
  if (!first) throw new Error('row not found');
  for (const v of [].concat(vals)) {
    const c = await rowValueXY(page, label);
    await page.mouse.click(c.x, c.y);
    await sleep(400);
    await page.keyboard.type(String(v), { delay: 20 });
    await sleep(900);
    const picked = await page.evaluate((name) => {
      const opts = [...document.querySelectorAll('[class*=member],[class*=option],[role=option],[class*=user-item],[class*=dropdown] li')]
        .filter((e) => (e.innerText || '').includes(name));
      if (!opts[0]) return false; const r = opts[0].getBoundingClientRect(); window.__lk = { x: r.x + Math.min(30, r.width / 2), y: r.y + r.height / 2 }; return true;
    }, String(v));
    if (picked) { const p = await page.evaluate(() => window.__lk); await page.mouse.click(p.x, p.y); await sleep(400); }
  }
  await blur(page);
}

async function setCheckbox(page, label, on = true) {
  const cur = await page.evaluate((lbl) => {
    const rows = [...document.querySelectorAll('[class*=card-field-editor]')];
    const r = rows.find((x) => (x.innerText || '').trim().startsWith(lbl));
    if (!r) return { found: false };
    const b = r.querySelector('input[type=checkbox],[role=checkbox]');
    const checked = b ? (b.checked || b.getAttribute('aria-checked') === 'true') : false;
    const rr = (b || r).getBoundingClientRect();
    return { found: true, checked, x: rr.x + 8, y: rr.y + rr.height / 2 };
  }, label);
  if (!cur.found) throw new Error('row not found');
  if (cur.checked !== on) { await page.mouse.click(cur.x, cur.y); await sleep(200); }
}

async function submitForm(page) {
  const b = await page.evaluate(() => {
    const el = [...document.querySelectorAll('button,[role=button]')].find((e) => /^(Submit|Gửi|Lưu)$/i.test((e.innerText || '').trim()));
    if (!el) return null; const r = el.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  if (!b) throw new Error('Submit button not found');
  await page.mouse.click(b.x, b.y);
  await sleep(2200);
  return true;
}

// Tick "Add more records after submission" so the form stays open blank after each Submit.
async function setAddMore(page, on = true) {
  const st = await page.evaluate(() => {
    const el = [...document.querySelectorAll('*')].find((e) => e.children.length <= 3 && /Add more records after submission/i.test((e.innerText || '').trim()));
    if (!el) return null;
    const box = el.querySelector('input[type=checkbox],[role=checkbox]') || el.parentElement.querySelector('input[type=checkbox],[role=checkbox]');
    const checked = box ? (box.checked || box.getAttribute('aria-checked') === 'true') : false;
    const t = box || el; const r = t.getBoundingClientRect();
    return { checked, x: r.x + (box ? r.width / 2 : 8), y: r.y + r.height / 2 };
  });
  if (st && st.checked !== on) { await page.mouse.click(st.x, st.y); await sleep(300); }
  return !!st;
}

async function addRecord(page, spec, { submit = true } = {}) {
  const rep = { ok: [], fail: [] };
  const run = async (fn, k) => { try { await fn(); rep.ok.push(k); } catch (e) { rep.fail.push(k + ':' + e.message); } };
  for (const [k, v] of Object.entries(spec.text || {})) await run(() => fillText(page, k, v), 'text.' + k);
  for (const [k, v] of Object.entries(spec.date || {})) await run(() => fillDate(page, k, v), 'date.' + k);
  for (const [k, v] of Object.entries(spec.select || {})) await run(async () => { const ok = await fillSelect(page, k, v); if (!ok) throw new Error('option not matched'); }, 'select.' + k);
  for (const [k, v] of Object.entries(spec.link || {})) await run(async () => { const ok = await fillLink(page, k, v); if (!ok) throw new Error('record not matched'); }, 'link.' + k);
  for (const [k, v] of Object.entries(spec.member || {})) await run(() => fillMember(page, k, v), 'member.' + k);
  for (const [k, v] of Object.entries(spec.checkbox || {})) await run(() => setCheckbox(page, k, v), 'checkbox.' + k);
  if (submit) await run(() => submitForm(page), 'submit');
  return rep;
}

module.exports = {
  sleep, attachBase, listTables, openTable, formOpen, openAddForm, rowValueXY, blur,
  fillText, fillDate, fillSelect, fillLink, fillMember, setCheckbox, setAddMore, submitForm, addRecord,
};
