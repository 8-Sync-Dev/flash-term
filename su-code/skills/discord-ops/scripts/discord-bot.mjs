#!/usr/bin/env node
// discord-bot.mjs — bot Discord Gateway viết bằng Node thuần (KHÔNG discord.js).
//
// VÌ SAO KHÔNG DÙNG discord.js:
//   Repo này có luật không thêm dependency npm. Node 26 đã có sẵn `WebSocket` và `fetch`
//   toàn cục — đủ để nói chuyện với Gateway v10 (JSON) và REST v10. Toàn bộ thứ ta cần là
//   4 opcode (HELLO/HEARTBEAT/IDENTIFY/DISPATCH) + 3 opcode phục hồi (RESUME/RECONNECT/
//   INVALID_SESSION). Kéo cả thư viện về để dùng 7 opcode là gánh nợ bảo trì, không phải
//   tiện lợi.
//
// LUẬT TOKEN (bất biến):
//   Token CHỈ đọc từ biến môi trường `DISCORD_BOT_TOKEN`. Không hardcode, không đọc từ file
//   trong repo, không in ra log. Mọi dòng ra stdout/stderr đi qua `redact()` — nếu token lỡ
//   nằm trong chuỗi lỗi Discord trả về thì nó bị thay bằng `••••<4 ký tự cuối>`.
//
// LUẬT TRẢ LỜI (brand):
//   Bot chỉ nói những câu đã duyệt trong `references/brand-answers.md`. Không sinh chữ mới,
//   không gọi LLM. Dưới ngưỡng khớp thì IM LẶNG — trả lời sai brand tốn uy tín hơn nhiều so
//   với việc không trả lời.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_ANSWERS = path.join(HERE, '..', 'references', 'brand-answers.md');

const GATEWAY_URL = 'wss://gateway.discord.gg/?v=10&encoding=json';
const API = 'https://discord.com/api/v10';

// GUILDS(1<<0) | GUILD_MESSAGES(1<<9) | MESSAGE_CONTENT(1<<15) = 33281.
// MESSAGE_CONTENT là privileged intent: phải bật trong Developer Portal, không bật thì
// `content` về rỗng và bot im lặng vĩnh viễn (xem cảnh báo trong `onDispatch`).
export const INTENTS = (1 << 0) | (1 << 9) | (1 << 15);

export const MIN_SCORE = 2;            // dưới ngưỡng này thì im lặng
export const FLOOD_WINDOW_MS = 60_000; // cùng 1 user hỏi lại trong 60s → bỏ qua
const MAX_MESSAGE = 2000;              // trần độ dài 1 message của Discord

// ── Chuẩn hoá tiếng Việt ──────────────────────────────────────────────────────
// Bỏ dấu để "cài zus lỗi" và "cai zus loi" là một. Bỏ code block/URL/mention TRƯỚC khi bỏ
// dấu câu, nếu không `<@123>` vỡ thành token "123" và link biến thành một nắm token rác.
export function normalize(input) {
  let t = String(input ?? '');
  t = t.replace(/```[\s\S]*?```/g, ' ').replace(/`[^`\n]*`/g, ' ');
  t = t.replace(/https?:\/\/\S+/gi, ' ');
  t = t.replace(/<[^>\n]{1,64}>/g, ' ');
  t = t.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/đ/g, 'd');
  return t.replace(/[^a-z0-9\s]+/g, ' ').replace(/\s+/g, ' ').trim();
}

export function tokenize(input) {
  const n = normalize(input);
  return n ? n.split(' ') : [];
}

// ── Kho câu trả lời ───────────────────────────────────────────────────────────
// Định dạng: mỗi mục là `## <chủ đề>`, dòng `keywords: a, b c, d` rồi phần thân.
// Mục không có `keywords:` bị bỏ qua — đó là phần văn xuôi hướng dẫn cho người đọc file.
export function parseAnswers(md) {
  const out = [];
  const blocks = String(md).split(/^##\s+/m).slice(1);
  for (const block of blocks) {
    const lines = block.split(/\r?\n/);
    const topic = (lines.shift() || '').trim();
    let keywords = null;
    const bodyLines = [];
    for (const line of lines) {
      const kw = line.match(/^\s*keywords:\s*(.*)$/i);
      if (kw && keywords === null) { keywords = kw[1]; continue; }
      if (/^\s*<!--/.test(line)) continue;
      bodyLines.push(line);
    }
    if (keywords === null) continue;
    const body = bodyLines.join('\n').trim();
    if (!body) continue;
    const parsedKeywords = keywords
      .split(',')
      .map((k) => ({ raw: k.trim(), tokens: tokenize(k) }))
      .filter((k) => k.tokens.length > 0);
    if (!parsedKeywords.length) continue;
    out.push({ topic, keywords: parsedKeywords, body });
  }
  return out;
}

export function loadAnswers(file = DEFAULT_ANSWERS) {
  let md;
  try {
    md = fs.readFileSync(file, 'utf8');
  } catch {
    throw new AppError(`Không đọc được kho câu trả lời: ${file}\n`
      + 'Kiểm tra lại đường dẫn, hoặc truyền --answers <file>.');
  }
  const entries = parseAnswers(md);
  if (!entries.length) {
    throw new AppError(`Kho câu trả lời rỗng: ${file}\n`
      + 'Mỗi mục phải có tiêu đề "## <chủ đề>", một dòng "keywords: ..." và phần thân.');
  }
  return entries;
}

// Khớp câu hỏi với kho. Một keyword nhiều từ chỉ tính là khớp khi ĐỦ MỌI từ của nó xuất
// hiện trong câu hỏi (không cần đúng thứ tự) — điểm bằng số từ. Nhờ vậy cụm dài thắng cụm
// ngắn: "cài zus lỗi" về mục "Lỗi khi cài ZUS" (khớp `lỗi cài` + `zus lỗi` = 4 điểm) chứ
// không về mục "ZUS AI IDE là gì" (chỉ khớp `zus` = 1 điểm).
// Hệ quả cố ý của ngưỡng 2: một từ đơn lẻ ("zus", "cv", "spam") KHÔNG đủ để bot mở miệng.
export function matchAnswer(question, entries, opts = {}) {
  const minScore = opts.minScore ?? MIN_SCORE;
  const qTokens = new Set(tokenize(question));
  if (!qTokens.size) return null;
  let best = null;
  for (const entry of entries) {
    let score = 0;
    const hits = [];
    for (const kw of entry.keywords) {
      if (kw.tokens.every((t) => qTokens.has(t))) { score += kw.tokens.length; hits.push(kw.raw); }
    }
    if (!score) continue;
    if (!best || score > best.score || (score === best.score && hits.length > best.hits.length)) {
      best = { topic: entry.topic, body: entry.body, score, hits };
    }
  }
  if (!best || best.score < minScore) return null;
  return best;
}

// ── Che token ─────────────────────────────────────────────────────────────────
export function maskToken(token) {
  const t = String(token ?? '');
  if (!t) return '(rỗng)';
  return t.length <= 4 ? '••••' : `••••${t.slice(-4)}`;
}

// Thay MỌI lần xuất hiện của token trong một chuỗi bằng bản đã che. Dùng cho toàn bộ log:
// Discord trả nguyên token trong vài thông điệp lỗi, và log thì ai cũng đọc được.
export function redact(text, token = process.env.DISCORD_BOT_TOKEN) {
  const s = typeof text === 'string' ? text : String(text);
  return token ? s.split(token).join(maskToken(token)) : s;
}

const inspect = (x) => { try { return JSON.stringify(x); } catch { return String(x); } };
const log = (...a) => console.log(a.map((x) => redact(typeof x === 'string' ? x : inspect(x))).join(' '));
const warn = (...a) => console.error(a.map((x) => redact(typeof x === 'string' ? x : inspect(x))).join(' '));

// Lỗi "đã lường trước" — in một câu tiếng Việt rồi thoát, KHÔNG in stack trace.
class AppError extends Error {
  constructor(message, code = 1) { super(message); this.name = 'AppError'; this.exitCode = code; }
}

function requireToken() {
  const token = (process.env.DISCORD_BOT_TOKEN || '').trim();
  if (!token) {
    throw new AppError(
      'Thiếu biến môi trường DISCORD_BOT_TOKEN — bot không có gì để đăng nhập.\n'
      + '\n'
      + 'Cách lấy token (làm 1 lần, ~2 phút):\n'
      + '  1. Vào https://discord.com/developers/applications → New Application (tên: 8 Sync Dev Bot).\n'
      + '  2. Tab Bot → Reset Token → Copy. Token chỉ hiện MỘT lần; copy hụt thì reset lại.\n'
      + '  3. Cùng tab Bot, bật Privileged Gateway Intents → MESSAGE CONTENT INTENT (bắt buộc;\n'
      + '     không bật thì bot nhận được message nhưng nội dung rỗng).\n'
      + '  4. Tab OAuth2 → URL Generator → scope `bot` + quyền View Channels, Send Messages,\n'
      + '     Read Message History → mở link đó, mời bot vào server 8 Sync Forum.\n'
      + "  5. Chạy:  export DISCORD_BOT_TOKEN='<token vừa copy>'\n"
      + '\n'
      + 'KHÔNG dán token vào file trong repo, không commit, không gửi qua chat.',
      2,
    );
  }
  return token;
}

// ── REST ──────────────────────────────────────────────────────────────────────
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function rest(token, method, endpoint, body) {
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(API + endpoint, {
      method,
      headers: {
        authorization: `Bot ${token}`,
        'content-type': 'application/json',
        'user-agent': 'DiscordBot (https://8syncdev.com, 1.0) 8sync-discord-ops',
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (res.status === 429 || res.status >= 500) {
      if (attempt >= 3) throw new AppError(`Discord từ chối ${method} ${endpoint} (HTTP ${res.status}) sau 4 lần thử.`);
      let waitMs = 1000 * 2 ** attempt;
      if (res.status === 429) {
        const j = await res.json().catch(() => null);
        if (j && typeof j.retry_after === 'number') waitMs = Math.ceil(j.retry_after * 1000) + 250;
        warn(`[rate-limit] chờ ${waitMs}ms rồi thử lại ${method} ${endpoint}`);
      }
      await sleep(waitMs);
      continue;
    }
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      const hint = res.status === 401 ? ' — token sai hoặc đã bị reset.'
        : res.status === 403 ? ' — bot không có quyền ở kênh này (cần View Channels + Send Messages).'
          : res.status === 404 ? ' — sai channel id, hoặc bot chưa được mời vào server đó.' : '';
      throw new AppError(`Discord trả HTTP ${res.status} cho ${method} ${endpoint}${hint}\n${redact(text, token).slice(0, 400)}`);
    }
    return res.status === 204 ? null : res.json();
  }
}

// Cắt theo ranh giới dòng để không xé đôi câu; chỉ cắt cứng khi một dòng dài hơn trần.
export function chunkMessage(text, limit = MAX_MESSAGE) {
  const chunks = [];
  let buf = '';
  for (const line of String(text).split('\n')) {
    let rest = line;
    while (rest.length > limit) {
      if (buf) { chunks.push(buf); buf = ''; }
      chunks.push(rest.slice(0, limit));
      rest = rest.slice(limit);
    }
    const candidate = buf ? `${buf}\n${rest}` : rest;
    if (candidate.length > limit) { chunks.push(buf); buf = rest; } else { buf = candidate; }
  }
  if (buf.trim()) chunks.push(buf);
  return chunks.filter((c) => c.trim().length);
}

async function sendMessage(token, channelId, content) {
  const parts = chunkMessage(content);
  const ids = [];
  for (const part of parts) {
    const msg = await rest(token, 'POST', `/channels/${channelId}/messages`, {
      content: part,
      allowed_mentions: { parse: [] }, // không @everyone/@role dù kho câu trả lời có lỡ chứa
    });
    ids.push(msg?.id);
    if (parts.length > 1) await sleep(400);
  }
  return ids;
}

// ── Gateway ───────────────────────────────────────────────────────────────────
class GatewayClient {
  constructor({ token, onDispatch }) {
    this.token = token;
    this.onDispatch = onDispatch;
    this.ws = null;
    this.seq = null;
    this.sessionId = null;
    this.resumeUrl = null;
    this.heartbeatTimer = null;
    this.heartbeatJitter = null;
    this.missedAcks = 0;
    this.attempt = 0;
    this.stopped = false;
    this.wantResume = false;
  }

  connect(resume = false) {
    if (this.stopped) return;
    const url = resume && this.resumeUrl ? `${this.resumeUrl}?v=10&encoding=json` : GATEWAY_URL;
    const ws = new WebSocket(url);
    this.ws = ws;
    this.wantResume = resume;
    ws.addEventListener('open', () => log(`[gateway] đã mở kết nối (${resume ? 'resume' : 'mới'})`));
    ws.addEventListener('message', (ev) => {
      let payload;
      try { payload = JSON.parse(typeof ev.data === 'string' ? ev.data : String(ev.data)); } catch {
        warn('[gateway] payload không phải JSON, bỏ qua');
        return;
      }
      this.handle(payload).catch((e) => warn('[gateway] lỗi khi xử lý:', e?.message || e));
    });
    ws.addEventListener('error', () => warn('[gateway] lỗi socket'));
    ws.addEventListener('close', (ev) => this.onClose(ev.code, ev.reason));
  }

  send(payload) {
    if (this.ws && this.ws.readyState === 1) this.ws.send(JSON.stringify(payload));
  }

  clearTimers() {
    if (this.heartbeatTimer) clearInterval(this.heartbeatTimer);
    if (this.heartbeatJitter) clearTimeout(this.heartbeatJitter);
    this.heartbeatTimer = null;
    this.heartbeatJitter = null;
  }

  beat() {
    // Chưa nhận đủ ACK cho 2 nhịp trước ⇒ đường truyền đã chết dù socket còn "mở".
    // Phải tự đóng bằng mã KHÁC 1000 (1000 = tạm biệt hẳn, mất session, không resume được).
    if (this.missedAcks >= 2) {
      warn('[gateway] thiếu 2 ACK liên tiếp → tự đóng để kết nối lại');
      this.clearTimers();
      try { this.ws?.close(4000, 'heartbeat ack timeout'); } catch { /* socket đã chết */ }
      return;
    }
    this.missedAcks++;
    this.send({ op: 1, d: this.seq });
  }

  startHeartbeat(intervalMs) {
    this.clearTimers();
    this.missedAcks = 0;
    // Nhịp đầu phải lệch ngẫu nhiên (jitter) để cả đàn bot không đập cùng một mili-giây.
    this.heartbeatJitter = setTimeout(() => {
      this.beat();
      this.heartbeatTimer = setInterval(() => this.beat(), intervalMs);
    }, Math.floor(intervalMs * Math.random()));
  }

  identify() {
    this.send({
      op: 2,
      d: {
        token: this.token,
        intents: INTENTS,
        properties: { os: process.platform, browser: '8sync-discord-ops', device: '8sync-discord-ops' },
        presence: { status: 'online', afk: false, activities: [] },
      },
    });
  }

  resume() {
    this.send({ op: 6, d: { token: this.token, session_id: this.sessionId, seq: this.seq } });
  }

  async handle(p) {
    if (typeof p.s === 'number') this.seq = p.s;
    switch (p.op) {
      case 10: // HELLO
        this.startHeartbeat(p.d.heartbeat_interval);
        if (this.wantResume && this.sessionId) this.resume(); else this.identify();
        break;
      case 11: // HEARTBEAT ACK
        this.missedAcks = 0;
        break;
      case 1: // Gateway xin một nhịp ngay
        this.send({ op: 1, d: this.seq });
        break;
      case 7: // RECONNECT
        log('[gateway] server yêu cầu reconnect');
        this.clearTimers();
        try { this.ws?.close(4000, 'server asked reconnect'); } catch { /* đã đóng */ }
        break;
      case 9: // INVALID_SESSION — d=true nghĩa là còn resume được
        log(`[gateway] session không hợp lệ (resumable=${!!p.d})`);
        if (!p.d) this.sessionId = null;
        this.clearTimers();
        await sleep(1000 + Math.floor(Math.random() * 4000));
        try { this.ws?.close(4000, 'invalid session'); } catch { /* đã đóng */ }
        break;
      case 0: // DISPATCH
        if (p.t === 'READY') {
          this.attempt = 0;
          this.sessionId = p.d.session_id;
          this.resumeUrl = p.d.resume_gateway_url;
          log(`[READY] bot ${p.d.user?.username} · ${p.d.guilds?.length ?? 0} server`);
        } else if (p.t === 'RESUMED') {
          this.attempt = 0;
          log('[gateway] resume thành công');
        }
        await this.onDispatch(p.t, p.d, this);
        break;
      default:
        break;
    }
  }

  onClose(code, reason) {
    this.clearTimers();
    if (this.stopped) return;
    // 4004 token sai · 4013/4014 intent sai hoặc chưa bật — thử lại vô ích, dừng hẳn.
    const fatal = {
      4004: 'token sai (Discord từ chối xác thực)',
      4013: 'intent không hợp lệ',
      4014: 'intent bị chặn — vào Developer Portal bật MESSAGE CONTENT INTENT',
    };
    if (fatal[code]) {
      warn(`[gateway] đóng ${code}: ${fatal[code]} → dừng.`);
      this.stopped = true;
      process.exitCode = 3;
      return;
    }
    const resumable = code !== 1000 && code !== 1001 && !!this.sessionId;
    const wait = Math.min(30_000, 1000 * 2 ** this.attempt++) + Math.floor(Math.random() * 500);
    warn(`[gateway] đóng ${code} ${redact(reason || '')} → kết nối lại sau ${wait}ms (${resumable ? 'resume' : 'mới'})`);
    setTimeout(() => this.connect(resumable), wait);
  }

  stop() {
    this.stopped = true;
    this.clearTimers();
    try { this.ws?.close(1000, 'bye'); } catch { /* đã đóng */ }
  }
}

// ── Chế độ chạy bot ───────────────────────────────────────────────────────────
async function runBot(opts) {
  const token = requireToken();
  const entries = loadAnswers(opts.answers);
  log(`[kho] ${entries.length} mục câu trả lời từ ${opts.answers}`);
  if (opts.dryRun) log('[dry-run] chỉ in câu định trả lời ra stdout, KHÔNG gửi lên Discord');
  if (opts.channel) log(`[giới hạn] chỉ nghe kênh ${opts.channel}`);

  let selfId = null;
  const lastReply = new Map(); // userId → thời điểm bot trả lời người đó lần cuối
  let emptyContent = 0;
  let warnedIntent = false;

  const client = new GatewayClient({
    token,
    onDispatch: async (type, data, cli) => {
      if (type === 'READY') {
        selfId = data.user?.id;
        if (opts.once) {
          log(`[--once] kết nối OK, ${data.guilds?.length ?? 0} server. Thoát.`);
          cli.stop();
          setTimeout(() => process.exit(0), 50);
        }
        return;
      }
      if (type !== 'MESSAGE_CREATE') return;

      // Không bao giờ trả lời chính mình, bot khác, hay webhook.
      if (!data || data.author?.bot || data.webhook_id) return;
      if (selfId && data.author?.id === selfId) return;
      if (opts.channel && data.channel_id !== opts.channel) return;

      const content = data.content || '';
      if (!content.trim()) {
        // Dấu hiệu kinh điển của việc quên bật MESSAGE CONTENT INTENT.
        if (++emptyContent >= 5 && !warnedIntent) {
          warnedIntent = true;
          warn('[cảnh báo] 5 message liên tiếp có content rỗng → nhiều khả năng chưa bật '
            + 'MESSAGE CONTENT INTENT trong Developer Portal. Bot sẽ không bao giờ khớp được câu hỏi.');
        }
        return;
      }
      emptyContent = 0;

      const now = Date.now();
      for (const [uid, ts] of lastReply) if (now - ts > FLOOD_WINDOW_MS) lastReply.delete(uid);
      const userId = data.author?.id;
      const prev = lastReply.get(userId);
      if (prev && now - prev < FLOOD_WINDOW_MS) {
        log(`[bỏ qua] ${userId} vừa được trả lời ${Math.round((now - prev) / 1000)}s trước (chống lụt ${FLOOD_WINDOW_MS / 1000}s)`);
        return;
      }

      const hit = matchAnswer(content, entries, { minScore: opts.minScore });
      if (!hit) { log(`[im lặng] không đủ khớp: "${content.slice(0, 80)}"`); return; }

      log(`[khớp] "${content.slice(0, 60)}" → ${hit.topic} (điểm ${hit.score}: ${hit.hits.join(' | ')})`);
      if (opts.dryRun) {
        console.log('---8<--- câu định trả lời ---8<---');
        console.log(hit.body);
        console.log('---8<------------------------8<---');
        lastReply.set(userId, now);
        return;
      }
      try {
        await sendMessage(token, data.channel_id, hit.body);
        lastReply.set(userId, now);
      } catch (e) {
        warn('[gửi hụt]', e?.message || e);
      }
    },
  });

  process.on('SIGINT', () => { log('\n[dừng] SIGINT'); client.stop(); process.exit(0); });
  client.connect(false);
}

async function runPost(opts) {
  const token = requireToken();
  if (!opts.channel) throw new AppError('Lệnh post cần --channel <id>. Bật Developer Mode trong Discord rồi chuột phải kênh → Copy Channel ID.');
  if (!opts.file) throw new AppError('Lệnh post cần --file <đường dẫn tới file text chứa nội dung bài>.');
  let body;
  try { body = fs.readFileSync(opts.file, 'utf8'); } catch {
    throw new AppError(`Không đọc được file bài: ${opts.file}`);
  }
  if (!body.trim()) throw new AppError(`File bài rỗng: ${opts.file}`);
  const parts = chunkMessage(body);
  if (opts.dryRun) {
    log(`[dry-run] sẽ gửi ${parts.length} message vào kênh ${opts.channel}:`);
    parts.forEach((p, i) => {
      console.log(`--- phần ${i + 1}/${parts.length} (${p.length} ký tự) ---`);
      console.log(p);
    });
    return;
  }
  const ids = await sendMessage(token, opts.channel, body);
  log(`[đăng xong] ${ids.length} message vào kênh ${opts.channel}: ${ids.join(', ')}`);
}

// ── CLI ───────────────────────────────────────────────────────────────────────
const USAGE = `discord-bot.mjs — bot trả lời tự động + đăng bài cho server Discord 8 Sync Dev
Node thuần (global WebSocket + fetch), KHÔNG dùng discord.js.

CÁCH DÙNG
  node discord-bot.mjs [tuỳ chọn]                          # chạy bot, nghe và trả lời
  node discord-bot.mjs post --channel <id> --file <path>   # đăng 1 bài từ file text
  node discord-bot.mjs --help

TUỲ CHỌN
  --once               Kết nối, in READY + số server rồi thoát 0 (smoke test token/intent).
  --dry-run            In câu định trả lời (hoặc bài định đăng) ra stdout, KHÔNG gửi Discord.
  --channel <id>       Chỉ nghe đúng 1 kênh; với lệnh post là kênh đích.
  --file <path>        (lệnh post) File text chứa nội dung bài.
  --answers <path>     Kho câu trả lời. Mặc định: references/brand-answers.md cạnh skill này.
  --min-score <n>      Ngưỡng khớp tối thiểu (mặc định ${MIN_SCORE}). Thấp hơn = nói nhiều + sai nhiều.
  --help, -h           In bản này.

BIẾN MÔI TRƯỜNG
  DISCORD_BOT_TOKEN    BẮT BUỘC. Token bot. Chỉ đọc từ env — không hardcode, không ghi ra log
                       (mọi log đi qua bộ che, chỉ hiện 4 ký tự cuối).
  DEBUG_STACK=1        In stack trace khi gặp lỗi ngoài dự tính.

HÀNH VI
  · Chỉ trả lời bằng câu đã duyệt trong kho brand-answers.md. Không đủ khớp thì IM LẶNG.
  · Không bao giờ trả lời chính nó, bot khác, hay webhook.
  · Chống lụt: cùng một user được trả lời tối đa 1 lần / ${FLOOD_WINDOW_MS / 1000}s.
  · Cần bật MESSAGE CONTENT INTENT trong Developer Portal, nếu không content luôn rỗng.

MÃ THOÁT
  0 thành công · 1 lỗi vận hành · 2 thiếu DISCORD_BOT_TOKEN · 3 Gateway từ chối (token/intent)

VÍ DỤ
  DISCORD_BOT_TOKEN=... node discord-bot.mjs --once
  DISCORD_BOT_TOKEN=... node discord-bot.mjs --dry-run --channel 123456789012345678
  DISCORD_BOT_TOKEN=... node discord-bot.mjs post --channel 123456789012345678 \\
      --file briefs/discord-news-2026-08-02.txt
`;

export function parseArgs(argv) {
  const opts = {
    cmd: 'run',
    once: false,
    dryRun: false,
    channel: null,
    file: null,
    answers: DEFAULT_ANSWERS,
    minScore: MIN_SCORE,
    help: false,
  };
  const args = [...argv];
  if (args[0] && !args[0].startsWith('-')) {
    const cmd = args.shift();
    if (cmd !== 'post' && cmd !== 'run') throw new AppError(`Lệnh không hiểu: "${cmd}". Chỉ có "run" (mặc định) và "post". Xem --help.`);
    opts.cmd = cmd;
  }
  const need = (flag, v) => {
    if (v === undefined) throw new AppError(`Thiếu giá trị cho ${flag}. Xem --help.`);
    return v;
  };
  while (args.length) {
    const a = args.shift();
    switch (a) {
      case '--help': case '-h': opts.help = true; break;
      case '--once': opts.once = true; break;
      case '--dry-run': opts.dryRun = true; break;
      case '--channel': opts.channel = need('--channel', args.shift()); break;
      case '--file': opts.file = need('--file', args.shift()); break;
      case '--answers': opts.answers = path.resolve(need('--answers', args.shift())); break;
      case '--min-score': opts.minScore = Number(need('--min-score', args.shift())); break;
      default: throw new AppError(`Tuỳ chọn không hiểu: "${a}". Xem --help.`);
    }
  }
  if (!Number.isFinite(opts.minScore) || opts.minScore < 1) throw new AppError('--min-score phải là số ≥ 1.');
  return opts;
}

async function main(argv) {
  const opts = parseArgs(argv);
  if (opts.help) { console.log(USAGE); return 0; }
  if (opts.cmd === 'post') { await runPost(opts); return 0; }
  await runBot(opts);
  return 0; // bot chạy dài; chỉ về đây khi --once đã thoát sớm
}

const invokedDirectly = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (invokedDirectly) {
  main(process.argv.slice(2)).then(
    (code) => { if (typeof code === 'number' && code !== 0) process.exitCode = code; },
    (err) => {
      // Lỗi đã lường trước → một câu tiếng Việt. Lỗi lạ → vẫn che token rồi mới in.
      if (err instanceof AppError) {
        console.error(`\nLỗi: ${redact(err.message)}\n`);
        process.exit(err.exitCode);
      }
      console.error(`\nLỗi ngoài dự tính: ${redact(err?.message || String(err))}`);
      console.error('Chạy lại với DEBUG_STACK=1 để xem stack trace đầy đủ.');
      if (process.env.DEBUG_STACK) console.error(redact(err?.stack || ''));
      process.exit(1);
    },
  );
}
