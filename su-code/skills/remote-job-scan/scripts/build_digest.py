#!/usr/bin/env python3
"""build_digest.py — merge board data -> filter (no-gamble/no-crypto, EN+CJK) -> categorize -> PDF.

Run: uv run --with weasyprint --with pypdf python build_digest.py \
       [--dir /tmp/jobscan] [--out ~/Downloads/RemoteJobs_Digest_<date>.pdf] [--candidate "..."]

Inputs in --dir: linkedin.json (from linkedin-scrape.snippet.js), remoteok.json,
remotive_*.json, wwr_*.rss, eleduck*.json (from fetch_boards.sh).
Validated 2026-07-17: 277 jobs, 13 pages, 0 exclusion leftovers.
"""
import argparse
import datetime
import html as H
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

BAD = re.compile(
    r'casino|gambl|igaming|i-gaming|betting|\bbet\b|poker|slot machine|sportsbook|'
    r'crypto|blockchain|web3|\bnft\b|defi|\btoken\b|binance|tether|kraken|coinbase|'
    r'okx|bybit|bitcoin|ethereum|exchange platform|evolution (gaming|singapore)', re.I)
BAD_CJK = re.compile(
    r'博彩|菠菜|棋牌|赌|区块链|链上|加密货币|虚拟货币|合约交易|交易所|挖矿|币圈|数字货币|发币|'
    r'solana|\bamm\b|\bdex\b|\bcex\b|usdt|\bswap\b|链游', re.I)
ROLE = re.compile(
    r'developer|engineer|program(mer|ming)|full[- ]?stack|front[- ]?end|back[- ]?end|software|'
    r'\bweb\b|mobile|\bios\b|android|flutter|react|node|python|typescript|\bai\b|\bml\b|'
    r'machine learning|llm|data scien|game|unity|unreal|gameplay|'
    r'design(er)?|artist|illustrat|\bux\b|\bui\b|art director|motion|graphic|creative|animat|3d|2d|'
    r'开发|工程师|前端|后端|全栈|程序|设计|美术|插画|游戏|算法|架构', re.I)
NOISE = re.compile(
    r'sales|account (manager|executive)|recruit|talent acquisition|\bhr\b|payroll|bookkeep|'
    r'finance|financeiro|admin(istrativ|istrator)?\b|caretaker|sourcing|customer (support|service)|'
    r'virtual assistant|copywrit|content writer|seo |social media|crediti|get paid|record your daily', re.I)
CN_CO = re.compile(
    r'bytedance|tiktok|tencent|alibaba|shopee|netease|mihoyo|hoyoverse|huawei|baidu|xiaomi|'
    r'\bsea\b|lazada|didi|ant group|pdd|temu|alipay|garena', re.I)

CATS = ['AI / ML', 'Web', 'Mobile / App', 'Game', 'Design / Art']
LI_CAT = {'ai': 'AI / ML', 'ml': 'AI / ML', 'fullstack': 'Web', 'web': 'Web',
          'mobile': 'Mobile / App', 'game': 'Game', 'gameart': 'Game',
          'design': 'Design / Art', 'art': 'Design / Art', 'cn': 'Web', 'cndev': 'Web'}
REM_CAT = {'ai': 'AI / ML', 'machine-learning': 'AI / ML', 'typescript': 'Web',
           'design': 'Design / Art', 'mobile': 'Mobile / App', 'game': 'Game',
           'react-native': 'Mobile / App', 'flutter': 'Mobile / App'}
WWR_CAT = {'wwr_prog': 'Web', 'wwr_fullstack': 'Web', 'wwr_design': 'Design / Art'}


def bad(*parts):
    s = ' '.join(p or '' for p in parts)
    return bool(BAD.search(s) or BAD_CJK.search(s))


def collect(base: Path):
    jobs = []
    f = base / 'linkedin.json'
    if f.exists():
        for k, arr in json.loads(f.read_text()).items():
            for j in arr:
                if bad(j.get('title'), j.get('company')):
                    continue
                jobs.append(dict(src='LinkedIn', title=j['title'], company=j.get('company', ''),
                                 loc=j.get('loc', ''), url=j['href'], salary='',
                                 cat=LI_CAT.get(k, 'Web'), cn=k in ('cn', 'cndev')))
    for f in base.glob('remotive_*.json'):
        q = f.stem.replace('remotive_', '')
        try:
            d = json.loads(f.read_text())
        except Exception:
            continue
        for j in d.get('jobs', []):
            if bad(j.get('title'), j.get('company_name'), ' '.join(j.get('tags', []))):
                continue
            jobs.append(dict(src='Remotive', title=j['title'], company=j.get('company_name', ''),
                             loc=j.get('candidate_required_location', ''), url=j['url'].split('?')[0],
                             salary=j.get('salary', '') or '', cat=REM_CAT.get(q, 'Web'), cn=False))
    f = base / 'remoteok.json'
    if f.exists():
        try:
            rok = json.loads(f.read_text())
        except Exception:
            rok = []
        for j in rok:
            if not isinstance(j, dict) or not j.get('position'):
                continue
            tags = ' '.join(j.get('tags', []))
            if bad(j.get('position'), j.get('company'), tags, j.get('description', '')[:300]):
                continue
            t = tags.lower()
            tp = t + ' ' + j['position'].lower()
            if re.search(r'\bai\b|machine learning|\bml\b|llm', tp):
                cat = 'AI / ML'
            elif re.search(r'mobile|ios|android|flutter|react native', t):
                cat = 'Mobile / App'
            elif re.search(r'game', tp):
                cat = 'Game'
            elif re.search(r'design|art|ux|ui|illustr', tp):
                cat = 'Design / Art'
            elif re.search(r'dev|engineer|front|back|full', tp):
                cat = 'Web'
            else:
                continue
            sal = f"${j['salary_min'] // 1000}k-${j.get('salary_max', 0) // 1000}k" if j.get('salary_min') else ''
            jobs.append(dict(src='RemoteOK', title=j['position'], company=j.get('company', ''),
                             loc=j.get('location', '') or 'Worldwide', url=j.get('url', '').split('?')[0],
                             salary=sal, cat=cat, cn=False))
    for f in base.glob('wwr_*.rss'):
        try:
            root = ET.fromstring(f.read_text())
        except Exception:
            continue
        for item in root.iter('item'):
            title = (item.findtext('title') or '').strip()
            link = (item.findtext('link') or '').strip()
            region = (item.findtext('region') or 'Anywhere').strip() if item.find('region') is not None else 'Anywhere'
            if not title or not link:
                continue
            m = re.match(r'(.+?):\s*(.+)', title)
            company, jt = (m.group(1), m.group(2)) if m else ('', title)
            if bad(jt, company):
                continue
            c = WWR_CAT.get(f.stem, 'Web')
            tl = jt.lower()
            if re.search(r'\bai\b|machine learning|llm|\bml\b', tl):
                c = 'AI / ML'
            elif re.search(r'mobile|ios|android|flutter|react native', tl):
                c = 'Mobile / App'
            elif re.search(r'game', tl):
                c = 'Game'
            jobs.append(dict(src='WeWorkRemotely', title=jt, company=company, loc=region,
                             url=link.split('?')[0], salary='', cat=c, cn=False))
    for f in sorted(base.glob('eleduck*.json')):
        try:
            d = json.loads(f.read_text())
        except Exception:
            continue
        for p in d.get('posts', []):
            title = p.get('title', '').strip()
            if not title or bad(title):
                continue
            tl = title.lower()
            if re.search(r'ai|大模型|llm|算法', tl):
                cat = 'AI / ML'
            elif re.search(r'ios|android|flutter|安卓|移动|app', tl):
                cat = 'Mobile / App'
            elif re.search(r'游戏|unity|unreal', tl):
                cat = 'Game'
            elif re.search(r'设计|ui|ux|美术|插画', tl):
                cat = 'Design / Art'
            else:
                cat = 'Web'
            jobs.append(dict(src='电鸭社区 (eleduck)', title=title,
                             company=p.get('user', {}).get('nickname', ''), loc='远程 (Remote, CN)',
                             url=f"https://eleduck.com/posts/{p['id']}", salary='', cat=cat, cn=True))
    seen, uniq = set(), []
    for j in jobs:
        if j['url'] in seen:
            continue
        seen.add(j['url'])
        uniq.append(j)
    jobs = [j for j in uniq if ROLE.search(j['title']) and not NOISE.search(j['title'])]
    for j in jobs:
        j['title'] = H.unescape(j['title'])
        j['company'] = H.unescape(j.get('company') or '')
        if CN_CO.search(j['company']):
            j['cn'] = True
    return jobs


def esc(s):
    return H.escape(s or '')


def rows(arr):
    return '\n'.join(
        f'<tr><td class="t"><a href="{esc(j["url"])}">{esc(j["title"])}</a>'
        f'<div class="u">{esc(j["url"])}</div></td><td>{esc(j["company"])}</td>'
        f'<td>{esc(j["loc"])}{(" · " + esc(j["salary"])) if j["salary"] else ""}</td>'
        f'<td class="s">{esc(j["src"])}</td></tr>' for j in arr)


def section(title, arr, color):
    parts = [f'<h1 style="color:{color}">{title} <span class="cnt">({len(arr)} jobs)</span></h1>']
    for c in CATS:
        sub = [j for j in arr if j['cat'] == c]
        if not sub:
            continue
        parts.append(f'<h2>{c} — {len(sub)}</h2><table><thead><tr><th>Vị trí / Link</th>'
                     f'<th>Công ty</th><th>Khu vực · Lương</th><th>Nguồn</th></tr></thead>'
                     f'<tbody>{rows(sub)}</tbody></table>')
    return '\n'.join(parts)


CSS = '''
@page { size: A4; margin: 14mm 12mm 16mm 12mm;
  @bottom-left { content: "Remote Jobs Digest · no-gambling / no-crypto verified"; font-size: 7.5pt; color:#888; font-family: "Noto Sans CJK HK", sans-serif; }
  @bottom-right { content: "Trang " counter(page) "/" counter(pages); font-size: 7.5pt; color:#888; font-family: "Noto Sans CJK HK", sans-serif; } }
body { font-family: "Noto Sans CJK HK", "DejaVu Sans", sans-serif; font-size: 8.5pt; color:#16181d; margin:0; }
.cover h1 { font-size: 20pt; margin: 2mm 0 1mm 0; }
.meta { color:#444; margin-bottom: 4mm; } .meta b { color:#111; }
h1 { font-size: 14pt; border-bottom: 1.5pt solid currentColor; padding-bottom: 1mm; margin: 6mm 0 2mm 0; page-break-after: avoid; }
h2 { font-size: 10.5pt; color:#0f4c81; margin: 3.5mm 0 1mm 0; page-break-after: avoid; }
.cnt { font-size: 9pt; color:#777; font-weight: normal; }
table { width:100%; border-collapse: collapse; table-layout: fixed; }
th { background:#eef2f8; color:#0f4c81; text-align:left; font-size:8pt; padding:1mm 1.5mm; border:0.5pt solid #bbb; }
td { border:0.5pt solid #ccc; padding:1mm 1.5mm; vertical-align:top; overflow-wrap:break-word; }
tr { page-break-inside: avoid; } thead { display: table-header-group; }
td.t a { color:#0b57d0; text-decoration:none; font-weight:600; }
.u { font-size:6.6pt; color:#777; font-family:"DejaVu Sans Mono", monospace; }
td.s { font-size:7.5pt; color:#555; }
th:nth-child(1) { width:46%; } th:nth-child(2) { width:20%; } th:nth-child(3) { width:22%; } th:nth-child(4) { width:12%; }
.note { background:#f4f7fc; border:0.8pt solid #0f4c81; padding:2mm 3mm; margin:2mm 0 3mm 0; }
'''


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dir', default='/tmp/jobscan')
    ap.add_argument('--out', default='')
    ap.add_argument('--candidate',
                    default='Nguyễn Phương Anh Tú — AI Engineer · LLM/RAG · Full-stack TypeScript/Python · art/design')
    a = ap.parse_args()
    base = Path(a.dir)
    today = datetime.date.today().strftime('%d/%m/%Y')
    out = a.out or str(Path.home() / 'Downloads' / f"RemoteJobs_Digest_{datetime.date.today().isoformat()}.pdf")
    jobs = collect(base)
    cn = [j for j in jobs if j['cn']]
    en = [j for j in jobs if not j['cn']]
    body = f'''<div class="cover"><h1>Remote Jobs Digest — {today}</h1>
<div class="meta">Ứng viên: <b>{esc(a.candidate)}</b><br>
Phạm vi: <b>mobile · web · app · AI · game · design/digital art</b> — 100% remote · Ưu tiên: <b>Trung Quốc &gt; Anh/quốc tế</b><br>
Ràng buộc: <b>KHÔNG gambling/casino/betting — KHÔNG crypto/web3/NFT</b> (lọc 2 lớp EN + 中文)<br>
Nguồn: LinkedIn (authed browser) · 电鸭社区 eleduck.com · WeWorkRemotely RSS · Remotive API · RemoteOK API.</div>
<div class="note">Tổng <b>{len(jobs)}</b> job sau lọc — <b>{len(cn)}</b> ưu tiên Trung + <b>{len(en)}</b> quốc tế.</div></div>
{section('PHẦN A — 中国 · Ưu tiên Trung Quốc', cn, '#b3261e')}
{section('PHẦN B — Quốc tế (Anh ngữ)', en, '#0f4c81')}'''
    doc = ('<!DOCTYPE html><html lang="vi"><head><meta charset="utf-8">'
           f'<style>{CSS}</style></head><body>{body}</body></html>')
    (base / 'digest.html').write_text(doc)
    from weasyprint import HTML
    HTML(string=doc, base_url=str(base)).write_pdf(out)
    txt = subprocess.run(['pdftotext', out, '-'], capture_output=True, text=True).stdout
    leftovers = [l for l in txt.splitlines()
                 if (BAD.search(l) or BAD_CJK.search(l)) and 'Digest' not in l and 'KHÔNG' not in l]
    print(f'OK {out} — {len(jobs)} jobs ({len(cn)} CN / {len(en)} EN); leftover-hits={len(leftovers)}')
    if leftovers:
        print('\n'.join(leftovers[:5]))
        sys.exit(1)


if __name__ == '__main__':
    main()
