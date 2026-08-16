#!/usr/bin/env python3
"""Template SSE latency timer for a streaming endpoint (review-mr skill).

Adapt BASE / KEY / BOT / path / body to the endpoint under review. Measures one turn.

The copilot lane has no livechat widget, so the only honest way to see what a
CRM operator feels is to speak SSE to it directly and time the frames. What the
operator waits on is the FIRST token; everything after that arrives while they
are already reading, so ttft is reported apart from total.

The `done` frame carries the server's own stage breakdown (usage.timings), so
each row pairs what the client felt with what the server measured.

Usage: copilot_bench.py <label> <userText> [repeat]
Prints a TSV row per run: label ttft total main_ms retr_ms less_ms tool rag chars reply
"""
import json
import sys
import time
import urllib.request

BASE = "https://prod-dev-agentic-cloudgo-v1-kufi.encr.app"
KEY = "ak_live_LUcuvNOF9y-2NGKb2twFbpxxoqwGCjkrAN2Jxg_POuo"
BOT = "01TESTBOT70000000000000000"


def one(text, session):
    body = json.dumps({
        "botId": BOT,
        "sessionId": session,
        "channel": "copilot",
        "userText": text,
        "user_info": {
            "id": "42", "email": "hieu.nv@cloudgo.vn",
            "firstName": "Hiếu", "lastName": "Nguyễn",
            "phoneMobile": "0909123456", "title": "Nhân viên kinh doanh",
            "department": "Sales", "language": "vi",
        },
        "history": [],
    }).encode()
    req = urllib.request.Request(
        BASE + "/copilot/stream", data=body,
        headers={
            "Content-Type": "application/json",
            "x-access-key": KEY,
            # Cloudflare fronts the encr.app host and answers a bare
            # Python-urllib agent with 1010 before the app sees the turn.
            "User-Agent": "curl/8.5.0",
            "Accept": "*/*",
        },
    )
    t0 = time.monotonic()
    ttft = None
    n_tool = n_rag = 0
    out = []
    tm = {}
    with urllib.request.urlopen(req, timeout=240) as r:
        for raw in r:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            try:
                ev = json.loads(line[5:].strip())
            except json.JSONDecodeError:
                continue
            kind = ev.get("type")
            if kind == "token":
                if ttft is None:
                    ttft = time.monotonic() - t0
                out.append(ev.get("token", ""))
            elif kind == "tool":
                n_tool += 1
            elif kind == "rag":
                n_rag += len(ev.get("rag") or [])
            elif kind == "done":
                tm = ((ev.get("result") or {}).get("usage") or {}).get("timings") or {}
            elif kind == "error":
                print("ERROR frame:", ev.get("error"), file=sys.stderr)
    return {
        "ttft": ttft, "total": time.monotonic() - t0,
        "main": tm.get("main_ms", 0), "retr": tm.get("retrieve_ms", 0),
        "less": tm.get("lesson_ms", 0), "tool_ms": tm.get("tool_ms", 0),
        "n_tool": n_tool, "n_rag": n_rag, "reply": "".join(out),
    }


def main():
    label, text = sys.argv[1], sys.argv[2]
    repeat = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    for i in range(repeat):
        m = one(text, "bench-%s-%d-%d" % (label, i, time.time()))
        print("%s\t%s\t%.2f\t%d\t%d\t%d\t%d\t%d\t%d\t%s" % (
            label, ("%.2f" % m["ttft"]) if m["ttft"] else "-", m["total"],
            m["main"], m["retr"], m["less"], m["n_tool"], m["n_rag"],
            len(m["reply"]), m["reply"][:60].replace("\n", " ")))
        sys.stdout.flush()
        if i + 1 < repeat:
            time.sleep(2)


if __name__ == "__main__":
    main()
