/**
 * Browser - the agent drives a Chromium of its own.
 *
 * /browser turns it on and off (remembered in <agent dir>/browser.json). While
 * it is on, the status line says "browser" and the agent has the browser_*
 * tools; while the browser is open, colours run through the word's letters.
 *
 * Fresh: it opens on the first tool call with a new, empty profile
 * (<agent dir>/browser-profiles/<pi's pid>) that is deleted when the session
 * ends. The agent never sees my everyday browser, is logged in nowhere and
 * leaves no cookies behind; each pi session has its own. Downloads go to
 * <agent dir>/browser-downloads.
 *
 * Watched: there is no window. The page is drawn in a terminal pane beside pi
 * (kitty graphics), anew whenever it changes, and I can use it there: click,
 * type, scroll, alt+arrows for back and forward, F5. What I select with the
 * mouse is copied to my clipboard. Closing the pane (ctrl+c) closes the browser.
 * None of what I do there is recorded or shown to the model, so that is where
 * I log in or answer an "are you human" check. The agent's pointer, an arrow
 * in pi's colour, floats on every page and glides to what it clicks or types
 * into. /browser watch switches between the pane and a real window.
 *
 * Quick: a model turn takes seconds and the browser milliseconds, so
 * browser_act runs several steps in one call, answers with only the lines of
 * the page that changed, and waits exactly as long as the page is busy.
 *
 * Seen: each browser_* call in the transcript says what the browser did since
 * the last one (pages, requests, where data was sent, popups, downloads;
 * ctrl+o lists it), and <agent dir>/browser.log keeps every request and all
 * the agent's JavaScript for a week. Password fields are not recorded.
 *
 * Fenced: it cannot reach this machine, my home network or Tailscale (its one
 * road out is a proxy in this file; /browser allow host:port lets one address
 * through for the session). On Linux it runs in a bubblewrap box with none of
 * my files or environment. Nothing shaped like a key is typed, opened or run.
 * guard.ts sends its JavaScript, the first visit to a site and long typed
 * text to the permission judge, yolo or not.
 *
 * Talks the Chrome DevTools Protocol over a pipe only this process holds: no
 * port, no Playwright, no packages. BROWSER_BIN names another Chromium. To
 * sites it gives the name it would have with a window, not "headless": the
 * ones that turn robots away would otherwise turn away a browser I sit at.
 * Not yet: iframes, file uploads, drag and drop.
 */

import { type ChildProcess, spawn } from "node:child_process";
import { lookup } from "node:dns/promises";
import { createWriteStream, existsSync, mkdirSync, readdirSync, readFileSync, readlinkSync, rmSync, type WriteStream, writeFileSync } from "node:fs";
import { rm } from "node:fs/promises";
import { type AddressInfo, BlockList, createServer, isIP, type Server, type Socket, connect as tcp } from "node:net";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import type { Readable, Writable } from "node:stream";
import { pathToFileURL } from "node:url";
import { StringEnum } from "@earendil-works/pi-ai";
import { type ExtensionAPI, type ExtensionContext, getAgentDir, type Theme } from "@earendil-works/pi-coding-agent";
import { hyperlink, Text } from "@earendil-works/pi-tui";
import { type Static, type TSchema, Type } from "typebox";

const STATE_FILE = join(getAgentDir(), "browser.json");
// Each pi has its browser's profile in here, under its own process id, and beside it the socket of its
// pane. Both exist only while that browser runs; what a pi that died left behind goes at the next start.
const PROFILES = join(getAgentDir(), "browser-profiles");
const PROFILE = join(PROFILES, String(process.pid));
const WATCH_SOCKET = join(PROFILES, `${process.pid}.sock`);
// Chromium itself: BROWSER_BIN, or the first of the usual places that has one.
const BROWSER_BIN =
	process.env.BROWSER_BIN ??
	["/usr/lib/chromium/chromium", "/usr/bin/chromium", "/usr/bin/chromium-browser", "/usr/bin/google-chrome-stable", "/Applications/Chromium.app/Contents/MacOS/Chromium", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"].find((path) => existsSync(path)) ??
	"chromium";
const DOWNLOADS = join(getAgentDir(), "browser-downloads");
const LOG_FILE = join(getAgentDir(), "browser.log");
// When the log is opened, entries older than LOG_KEEP_DAYS go, and past LOG_MAX_BYTES its older half goes too.
const LOG_KEEP_DAYS = 7;
const LOG_MAX_BYTES = 2_000_000;
// Addresses that are mine and not the web's: this machine, home networks, link-local (where cloud machines
// keep their keys), Tailscale (100.64/10), and their IPv6 kin. The browser does not connect to these.
const LOCAL = new BlockList();
for (const [net, bits] of [["0.0.0.0", 8], ["10.0.0.0", 8], ["100.64.0.0", 10], ["127.0.0.0", 8], ["169.254.0.0", 16], ["172.16.0.0", 12], ["192.168.0.0", 16], ["224.0.0.0", 3]] as const) {
	LOCAL.addSubnet(net, bits, "ipv4");
}
for (const [net, bits] of [["::", 127], ["fc00::", 7], ["fe80::", 10], ["ff00::", 8]] as const) LOCAL.addSubnet(net, bits, "ipv6");
// What a key or token looks like, and the secrets my own environment holds. Nothing containing one is typed, opened or run.
const KEY_SHAPES =
	/sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[0-9A-Z]{16}|xox[abprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{35}|-----BEGIN [A-Z ]*PRIVATE KEY-----|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\./;
const ENV_SECRETS = Object.entries(process.env).flatMap(([name, value]) => (/KEY|TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL/i.test(name) && value && value.length >= 12 ? [{ name, value }] : []));
// Inside the box, Chromium's home folder: empty, and gone with the box.
const BOX_HOME = "/home/agent";
// What every tab is asked to report: its pages loading, its errors, its requests.
const DOMAINS = ["Page", "Runtime", "Network", "Log"];
const COMMAND_MS = 30_000;
// After an action: the page counts as settled once nothing has moved for QUIET_MS.
// A page load gets LOAD_MS to produce its DOM, requests the page then makes get FETCH_MS.
const QUIET_MS = 120;
const FETCH_MS = 2500;
const LOAD_MS = 10_000;
// Requests whose answer can change what the page says. Images, styles and fonts are not waited for.
const CONTENT = new Set(["Document", "Script", "XHR", "Fetch"]);
const MAX_CHARS = 20_000;
// pi's colour in the browser: the pointer.
const DOT_COLOR = "#ff8a3d";
// The status line's word while the browser is open: the colour wheel turns once per turnMs, each letter
// `spread` degrees behind the one before it, redrawn every stepMs.
const WAVE = { turnMs: 3000, spread: 28, stepMs: 150 };
// The page's pointer: how long a move takes (a short hop, the longest trip, and what each pixel
// in between adds), and how long typing into one field may take to look typed, not pasted.
// Every step waits for its move, so these are also what the visuals cost.
const GLIDE = { min: 130, max: 340, perPixel: 0.22 };
const TYPING_MS = 150;
// The pointer: its width on the page, and where its tip waits before the agent's first move.
const POINTER_PX = 32;
// Its float: three waves each for sideways, up-and-down and tilt, as [length in ms, size in px or degrees, shift].
// The lengths share no rhythm, so the path does not come round again the way a looped animation's does.
const DRIFT = {
	x: [[700, 1.4, 0], [1130, 1.0, 2], [1870, 0.7, 4]],
	y: [[820, 2.4, 1], [1310, 1.6, 3], [2130, 1.0, 5]],
	turn: [[930, 2.2, 0.5], [1490, 1.4, 2.5], [2410, 0.8, 4.5]],
};
// The browser is handed the float a stretch at a time, as points `step` ms apart; a float that starts swells from nothing over `swell` ms.
const FLOAT = { span: 12_000, step: 120, swell: 1500 };
const REST: [number, number] = [30, 30];
// The pane runs WATCH_VIEWER, which only passes bytes between its terminal and WATCH_SOCKET: what it
// shows and what I do in it are both handled here.
const WATCH_VIEWER = join(getAgentDir(), "browser-watch.mjs");
// Chromium sends a picture of the page whenever the page changes. FRAME_MS is the least time between two that
// are passed on to the pane; once neither the agent nor I have touched the browser for IDLE_AFTER_MS it is
// IDLE_FRAME_MS, so a page that never stops moving by itself does not keep the machine busy for nobody.
const FRAME_MS = 33;
const IDLE_FRAME_MS = 200;
const IDLE_AFTER_MS = 10_000;
// The page is laid out at least this wide, so a narrow pane still gets a site's desktop version.
const PAGE_MIN_WIDTH = 1000;
// One notch of the wheel in the pane, in page pixels.
const WHEEL_PX = 100;
// Clicking a pane to put the keyboard in it also clicks what is under the mouse: a click this soon after is not passed on.
const FOCUS_CLICK_MS = 150;
// In the pane, the pointer comes to rest after this long with nothing to do, so that a page at rest is a picture that stays the same.
const DOZE_MS = 6000;
// The scripts below run in their own JavaScript world: they share the page's DOM but not its globals.
const SANDBOX = "pi";

// How Chromium is started. Its profile is new, so nothing of a first run is to show. It is spoken to over a
// pipe, not a port. And everything goes out through the proxy in this file, names unresolved, this machine's
// own addresses included.
const flags = (proxyPort: number, headless: boolean) => [
	"--remote-debugging-pipe",
	`--user-data-dir=${PROFILE}`,
	// A real window: on a Wayland desktop Chromium has to be told so, since the box holds none of the hints it would go by.
	...(headless ? ["--headless=new"] : process.env.WAYLAND_DISPLAY ? ["--ozone-platform=wayland"] : []),
	"--no-first-run",
	"--no-default-browser-check",
	"--disable-breakpad",
	"--disable-sync",
	"--disable-component-update",
	"--disable-background-networking",
	"--password-store=basic",
	"--disable-features=Translate,MediaRouter",
	// Without this every page is told "a program drives this browser", and many then refuse it even with me at the pane.
	"--disable-blink-features=AutomationControlled",
	`--proxy-server=socks5://127.0.0.1:${proxyPort}`,
	"--proxy-bypass-list=<-loopback>",
	"--host-resolver-rules=MAP * ~NOTFOUND , EXCLUDE 127.0.0.1",
	// The roads that would go around a proxy: QUIC, and calls between browsers.
	"--disable-quic",
	"--webrtc-ip-handling-policy=disable_non_proxied_udp",
	"--force-webrtc-ip-handling-policy=disable_non_proxied_udp",
	"about:blank",
];

// pointerAt(x, y): pi's pointer on this page, made with its tip at (x, y) if the page has none yet.
// It lives in a shadow tree of its own, where the page's style sheets do not reach: a page that
// resizes every svg or animates every div would otherwise bend it. Nested boxes, each moved by one
// thing: sideways travel, downwards travel, the float, the press of a click. Built with DOM calls
// and the CSSOM only, which a strict CSP allows. Returns its handle: at (where the tip is), the
// boxes, float() and still(ms).
const POINTER = `const pointerAt = (x, y) => {
		if (!document.getElementById("pi-browser-pointer") && document.documentElement && window.top === window) {
			const make = (tag, attrs, css) => {
				const node = document.createElementNS("http://www.w3.org/2000/svg", tag);
				for (const name in attrs) node.setAttribute(name, attrs[name]);
				if (css) node.style.cssText = css;
				return node;
			};
			const box = (css) => {
				const node = document.createElement("div");
				node.style.cssText = "width:0;height:0;" + css;
				return node;
			};
			const host = document.createElement("pi-pointer");
			host.id = "pi-browser-pointer";
			host.style.cssText = "all:initial;position:fixed;top:0;left:0;width:0;height:0;z-index:2147483647;pointer-events:none";
			const across = box("transform:translateX(" + x + "px)");
			const down = box("transform:translateY(" + y + "px)");
			const float = box("");
			const press = box("transform-origin:0 0");
			// An arrow, drawn 64 by 72 with its tip at (8, 3); the margins put that tip on the point.
			const art = make("svg", { viewBox: "0 0 64 72" }, "display:block;width:${POINTER_PX}px;height:${(POINTER_PX * 72) / 64}px;margin:${(-3 * POINTER_PX) / 64}px 0 0 ${(-8 * POINTER_PX) / 64}px;overflow:visible;filter:drop-shadow(0 2px 3px #0007)");
			art.append(make("path", { d: "M8 6 L8 54 Q8 59 12 55.5 L22 46.5 L30.5 64 Q32 67.5 35.5 66 L41 63.5 Q44.5 62 43 58.5 L34.5 41.5 L48.5 41.5 Q53 41.5 49.5 38 L12.5 4 Q8 0.5 8 6 Z", fill: "${DOT_COLOR}", stroke: "white", "stroke-width": 3.5, "stroke-linejoin": "round" }));
			press.append(art);
			float.append(press);
			down.append(float);
			across.append(down);
			host.attachShadow({ mode: "closed" }).append(across);
			document.documentElement.append(host);
			const me = (globalThis.piPointer = { at: [x, y], across, down, press });

			// Where the float has it at clock time t, at a strength from 0 to 1. It is worked out from the
			// clock, not played from a recording, so it carries on unbroken on the next page.
			const DRIFT = ${JSON.stringify(DRIFT)};
			const wave = (t, parts) => parts.reduce((sum, [length, size, shift]) => sum + Math.sin(t / length + shift) * size, 0);
			const drift = (t, strength) => "translate(" + (wave(t, DRIFT.x) * strength).toFixed(2) + "px," + (wave(t, DRIFT.y) * strength).toFixed(2) + "px) rotate(" + (wave(t, DRIFT.turn) * strength).toFixed(2) + "deg)";
			// The next stretch of it, handed to the browser as points to pass through, so it stays smooth while a page is busy.
			let began = 0;
			const stretch = () => {
				const from = Date.now();
				const points = [];
				for (let at = 0; at <= ${FLOAT.span}; at += ${FLOAT.step}) {
					const swell = Math.min(1, (from + at - began) / ${FLOAT.swell});
					points.push({ transform: drift(from + at, swell * swell * (3 - 2 * swell)) });
				}
				me.drift = float.animate(points, { duration: ${FLOAT.span} });
				me.drift.onfinish = stretch;
			};
			// float(): afloat, and (where piDoze says so) at rest again after that long with nothing to do.
			me.float = () => {
				clearTimeout(me.doze);
				if (!me.drift) {
					began = Date.now();
					stretch();
				}
				if (globalThis.piDoze) me.doze = setTimeout(() => me.still(900), globalThis.piDoze);
			};
			// still(ms): eases back onto its tip from wherever the float had it, and stays there.
			me.still = (ms) => {
				clearTimeout(me.doze);
				if (!me.drift) return;
				const now = getComputedStyle(float).transform;
				me.drift.onfinish = null;
				me.drift.cancel();
				me.drift = undefined;
				float.animate({ transform: [now, "none"] }, { duration: ms, easing: "ease-out" });
			};
			me.float();
		}
		return globalThis.piPointer;
	};`;

// What every page gets before its own scripts run: the pointer, where it was on the page before.
// doze: in the pane, how long the pointer floats with nothing to do before it rests; 0 in a window, where it never rests.
const markers = (x: number, y: number, doze: number) => `() => {
	${POINTER}
	const add = () => {
		if (window.top !== window || !document.documentElement) return;
		globalThis.piDoze = ${doze};
		pointerAt(${x}, ${y});
	};
	add();
	document.addEventListener("DOMContentLoaded", add);
}`;

// The mouse cursor a page asks for at (x, y), by its CSS name. "auto" is the page leaving it to the
// browser: a bar where text is typed, an arrow elsewhere.
const CURSOR = `(x, y) => {
	const el = document.elementFromPoint(x, y);
	const asked = el ? getComputedStyle(el).cursor.split(",").pop().trim() : "default";
	if (asked !== "auto") return /^[a-z-]+$/.test(asked) ? asked : "default";
	return el.isContentEditable || (el.matches("input,textarea") && typeof el.selectionStart === "number") ? "text" : "default";
}`;

// What is selected on the page, as text: in a field, the selected part of what it holds. Never out of a password field.
const SELECTED = `() => {
	const el = document.activeElement;
	if (el?.type === "password") return "";
	const held = el && typeof el.selectionStart === "number" ? el.value.slice(el.selectionStart, el.selectionEnd) : "";
	return (held || String(getSelection())).slice(0, 100000);
}`;

// The pane's program, given the socket to join. It puts its terminal back the way it was when the browser, or I, end it.
const VIEWER = `import { connect } from "node:net";
const pipe = connect(process.argv[2]);
const bye = (why) => {
	process.stdout.write("\\x1b]22;\\x07\\x1b[?1003l\\x1b[?1004l\\x1b[?1006l\\x1b[?2048l\\x1b[?25h\\x1b[?1049l" + why);
	process.exit(0);
};
pipe.on("error", () => bye("The agent's browser is not open: it opens on the agent's first browser_ call.\\n"));
pipe.on("close", () => bye(""));
process.stdin.setRawMode(true);
process.stdin.pipe(pipe).pipe(process.stdout);
`;

// The page as text, in document order. Everything that can be clicked or typed
// into gets a number, and the elements are kept in piRefs for the next call.
// An element keeps its number for as long as its page lives, so two snapshots
// of one page can be compared line by line.
const SNAPSHOT = String.raw`(px, py) => {
	${POINTER}
	pointerAt(px, py);
	const INTERACTIVE = "a[href],button,input:not([type=hidden]),select,textarea,summary,[contenteditable=''],[contenteditable=true],[role=button],[role=link],[role=checkbox],[role=radio],[role=tab],[role=menuitem],[role=option],[role=switch],[role=combobox],[role=textbox],[role=searchbox]";
	const BLOCK = /^(P|DIV|LI|TR|H[1-6]|SECTION|ARTICLE|HEADER|FOOTER|MAIN|NAV|ASIDE|UL|OL|TABLE|FORM|BLOCKQUOTE|PRE|DT|DD|FIGCAPTION|BR|HR|DETAILS|FIELDSET|LABEL)$/;
	const ids = (globalThis.piIds ||= new WeakMap());
	const refs = (globalThis.piRefs = new Map());
	const out = [];
	let line = "";
	const squash = (text) => (text || "").replace(/\s+/g, " ").trim();
	const flush = () => {
		const text = squash(line);
		if (text) out.push(text);
		line = "";
	};
	const walk = (node) => {
		if (node.nodeType === 3) line += node.nodeValue;
		if (node.nodeType !== 1) return;
		const el = node;
		const tag = el.tagName.toUpperCase();
		if (/^(SCRIPT|STYLE|NOSCRIPT|TEMPLATE|SVG|HEAD)$/.test(tag) || el.id.startsWith?.("pi-browser-") || el.getAttribute("aria-hidden") === "true") return;
		// display:contents has no box of its own, so checkVisibility calls it hidden.
		if (!el.checkVisibility({ visibilityProperty: true }) && getComputedStyle(el).display !== "contents") return;
		if (tag === "IMG") {
			if (el.alt) line += " [image: " + el.alt + "] ";
			return;
		}
		if (tag === "IFRAME") {
			flush();
			out.push("(iframe, not read: " + el.src + ")");
			return;
		}
		if (el.matches(INTERACTIVE) && !el.disabled) {
			flush();
			let id = ids.get(el);
			if (!id) ids.set(el, (id = globalThis.piNext = (globalThis.piNext || 0) + 1));
			refs.set(id, el);
			const role = el.getAttribute("role") || { A: "link", BUTTON: "button", SUMMARY: "button", SELECT: "select" }[tag] || (/^(checkbox|radio|submit|button|reset|file|range)$/.test(el.type) ? el.type : "textbox");
			const pressable = /^(button|submit|reset)$/.test(role);
			const ticked = /^(checkbox|radio|switch)$/.test(role);
			const name = squash(el.getAttribute("aria-label") || (tag === "SELECT" ? "" : el.innerText) || (pressable && el.value) || el.labels?.[0]?.innerText || el.placeholder || el.title || el.name || el.querySelector("img[alt]")?.alt).slice(0, 100);
			let entry = "[" + id + "] " + role + ' "' + name + '"';
			if (tag === "SELECT") entry += " = " + squash(el.selectedOptions[0]?.text) + " (options: " + [...el.options].slice(0, 12).map((o) => squash(o.text)).join(" | ") + ")";
			else if (ticked) entry += el.checked || el.getAttribute("aria-checked") === "true" ? " (checked)" : "";
			else if (!pressable && typeof el.value === "string" && el.value) entry += el.type === "password" ? " (filled)" : " = " + el.value.slice(0, 80);
			out.push(entry);
			return;
		}
		// A label's text is already the name of its field; saying it twice costs tokens.
		if (tag === "LABEL" && el.control?.checkVisibility()) {
			flush();
			for (const field of el.querySelectorAll(INTERACTIVE)) walk(field);
			return;
		}
		const block = BLOCK.test(tag);
		if (block) flush();
		if (/^H[1-6]$/.test(tag)) line = "#".repeat(Number(tag[1])) + " ";
		if (tag === "LI") line = "- ";
		const slotted = tag === "SLOT" ? el.assignedNodes() : [];
		for (const child of slotted.length ? slotted : (el.shadowRoot || el).childNodes) walk(child);
		if (block) flush();
	};
	if (document.body) walk(document.body);
	flush();
	return "# " + document.title + "\n" + location.href + "\n\n" + out.join("\n");
}`;

// Shared start of the two scripts that act on a numbered element.
const REF = `const el = globalThis.piRefs?.get(n);
	if (!el?.isConnected) throw new Error("No element " + n + " on this page: take a new browser_snapshot");`;

// Brings the element into view and moves pi's pointer onto it, before anything is done to it.
// (fromX, fromY): where to draw the pointer if this page somehow has none. Leaves x, y: where it is now, and me: its handle.
const POINT = `${POINTER}
	let box = el.getBoundingClientRect();
	const out = () => box.top + box.height / 2 < 40 || box.top + box.height / 2 > innerHeight - 40 || box.left + box.width / 2 < 0 || box.left + box.width / 2 > innerWidth;
	// A target already in view stays where it is: a page that recentres on every step is hard to watch.
	if (out()) {
		const seen = document.visibilityState === "visible";
		el.scrollIntoView({ block: "center", inline: "nearest", behavior: seen ? "smooth" : "instant" });
		// Wait for the scroll to end; it may also never start, when the page is already as far as it goes.
		if (seen) await new Promise((done) => {
			let moving = false;
			addEventListener("scroll", () => (moving = true), { once: true, capture: true });
			addEventListener("scrollend", done, { once: true, capture: true });
			setTimeout(() => moving || done(), 120);
			setTimeout(done, 900);
		});
		box = el.getBoundingClientRect();
	}
	const x = Math.round(Math.min(Math.max(box.left + box.width / 2, 0), innerWidth - 1));
	const y = Math.round(Math.min(Math.max(box.top + box.height / 2, 0), innerHeight - 1));
	const me = pointerAt(fromX, fromY);
	const [wasX, wasY] = me.at;
	const far = Math.hypot(x - wasX, y - wasY);
	// It stops floating, so its tip lands exactly on the point.
	clearTimeout(me.resume);
	me.still(160);
	if (far > 1) {
		// Sideways and downwards run on different curves, which bends the path the way a hand's does.
		const duration = Math.round(Math.min(Math.max(${GLIDE.min} + far * ${GLIDE.perPixel}, ${GLIDE.min}), ${GLIDE.max}));
		const glide = me.across.animate({ transform: ["translateX(" + wasX + "px)", "translateX(" + x + "px)"] }, { duration, easing: "cubic-bezier(.25,.1,.25,1)" });
		me.down.animate({ transform: ["translateY(" + wasY + "px)", "translateY(" + y + "px)"] }, { duration, easing: "cubic-bezier(.5,0,.3,1)" });
		me.across.style.transform = "translateX(" + x + "px)";
		me.down.style.transform = "translateY(" + y + "px)";
		me.at = [x, y];
		// The timeout is for a tab in the background, where animations stand still.
		await Promise.race([glide.finished, new Promise((done) => setTimeout(done, duration + 80))]);
	}
	me.resume = setTimeout(me.float, 700);`;

// The pointer squashes as it presses, and a soft disc spreads from its tip.
const PRESS = `me.press.animate({ transform: ["scale(1)", "scale(0.78,0.86)", "scale(1.07,1.03)", "scale(1)"] }, { duration: 300, easing: "ease-out" });
	const ring = document.createElement("div");
	ring.id = "pi-browser-ripple";
	ring.style.cssText = "position:fixed;left:" + (x - 16) + "px;top:" + (y - 16) + "px;width:32px;height:32px;border-radius:50%;background:${DOT_COLOR}66;z-index:2147483646;pointer-events:none";
	document.documentElement.append(ring);
	ring.animate({ transform: ["scale(0.2)", "scale(1.5)"], opacity: [0.8, 0] }, { duration: 420, easing: "ease-out" }).finished.then(() => ring.remove(), () => ring.remove());
	setTimeout(() => ring.remove(), 1500);`;

const TARGET = `async (n, fromX, fromY) => {
	${REF}
	${POINT}
	${PRESS}
	return [x, y];
}`;

// Gets a field ready to be typed over. A <select> can't be typed into, so its option is picked here instead.
const FOCUS = `async (n, text, fromX, fromY) => {
	${REF}
	${POINT}
	// The field it is about to fill glows for a moment.
	el.animate({ boxShadow: ["0 0 0 3px ${DOT_COLOR}99", "0 0 0 3px ${DOT_COLOR}00"] }, { duration: 900, easing: "ease-out" });
	if (el.tagName === "SELECT") {
		const option = [...el.options].find((o) => o.text.trim() === text || o.value === text);
		if (!option) throw new Error("No such option. Choices: " + [...el.options].map((o) => o.text.trim()).join(" | "));
		el.value = option.value;
		el.dispatchEvent(new Event("input", { bubbles: true }));
		el.dispatchEvent(new Event("change", { bubbles: true }));
		return ["picked", x, y, false];
	}
	el.focus();
	if (el.select) el.select();
	else getSelection().selectAllChildren(el);
	return ["focused", x, y, el.type === "password"];
}`;

// The keys that are not characters, by the name the DOM gives them, with the number pages still read from keyCode.
const KEY_CODES: Record<string, number> = { Enter: 13, Tab: 9, Backspace: 8, Escape: 27, Delete: 46, ArrowLeft: 37, ArrowUp: 38, ArrowRight: 39, ArrowDown: 40, Home: 36, End: 35, PageUp: 33, PageDown: 34 };
// The same keys as a terminal sends them from the pane, and as typed text spells Enter and Tab.
const PANE_KEYS: Record<string, string> = {
	"\r": "Enter",
	"\n": "Enter",
	"\t": "Tab",
	"\x7f": "Backspace",
	"\b": "Backspace",
	"\x1b": "Escape",
	"\x1b[A": "ArrowUp",
	"\x1b[B": "ArrowDown",
	"\x1b[C": "ArrowRight",
	"\x1b[D": "ArrowLeft",
	"\x1b[H": "Home",
	"\x1b[F": "End",
	"\x1b[5~": "PageUp",
	"\x1b[6~": "PageDown",
	"\x1b[3~": "Delete",
};
const MODIFIER = { alt: 1, control: 2, shift: 8 };

// One key going down and coming up, as Chromium wants it told. A character brings itself along as text,
// unless ctrl or alt make it a command; a named key and a letter bring the code pages look for.
function keystroke(key: string, modifiers = 0): object[] {
	const named = KEY_CODES[key];
	const text = named ? (key === "Enter" ? "\r" : undefined) : modifiers & (MODIFIER.control | MODIFIER.alt) ? undefined : key;
	const code = named ? { code: key, windowsVirtualKeyCode: named } : /^[a-z]$/i.test(key) ? { code: `Key${key.toUpperCase()}`, windowsVirtualKeyCode: key.toUpperCase().charCodeAt(0) } : {};
	return [
		{ type: text ? "keyDown" : "rawKeyDown", key, text, modifiers, ...code },
		{ type: "keyUp", key, modifiers, ...code },
	];
}

// What went wrong in a page, in one line.
const problem = (details: any) => String(details.exception?.description ?? details.text).replace(/^Error: /, "").split("\n")[0] ?? "";

// session: which tab a command is for; none for the browser as a whole.
type Link = { send: (method: string, params?: object, session?: string, signal?: AbortSignal) => Promise<any>; close: () => void; alive: () => boolean };
// A tab: Chromium's own id for it, the script that draws the pointer on its pages, and the moment it is ready to be driven.
type Tab = { target: string; preload?: string; ready?: Promise<void> };
// One thing the window did. "request" carries what is needed to group it; the rest are just text.
type Seen = { kind: "opened" | "request" | "failed" | "error" | "popup" | "download"; text: string; host?: string; sends?: boolean };
// What happened between two browser_* calls, already counted and trimmed for the transcript.
type Activity = { opened?: string; requests: number; sites: [string, number][]; sent: string[]; failed: string[]; errors: string[]; popups: string[]; downloads: string[] };
type Result = { content: ({ type: "text"; text: string } | { type: "image"; data: string; mimeType: string })[]; details: { chars?: number; activity?: Activity } };

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

function clip(text: string): string {
	return text.length <= MAX_CHARS ? text : `${text.slice(0, MAX_CHARS)}\n\n[… cut at ${MAX_CHARS} of ${text.length} characters]`;
}

// "shop.example.com/cart": a URL without its scheme or query, short enough for one line.
function brief(url: string): string {
	try {
		const { host, pathname } = new URL(url);
		const short = host + (pathname === "/" ? "" : pathname);
		return short.length > 70 ? `${short.slice(0, 69)}…` : short;
	} catch {
		return url.slice(0, 70);
	}
}

const tilde = (path: string) => path.replace(homedir(), "~");

// What is new in a page since it was last read: the new lines, each run led by the
// unchanged line above it, then the lines that went away. undefined when so much
// changed that the whole page reads better.
function changes(before: string[], after: string[]): string | undefined {
	const left = new Map<string, number>();
	for (const line of before) left.set(line, (left.get(line) ?? 0) + 1);
	const fresh = after.map((line) => {
		const had = left.get(line) ?? 0;
		if (had) left.set(line, had - 1);
		return !had;
	});
	// A numbered element whose line changed shows up as new; its old line would only say it twice.
	const renewed = new Set(after.filter((_line, i) => fresh[i]).map((line) => /^\[\d+\]/.exec(line)?.[0]));
	const gone = [...left].flatMap(([line, times]) => Array<string>(times).fill(line)).filter((line) => !renewed.has(/^\[\d+\]/.exec(line)?.[0] ?? line));
	const added = fresh.filter(Boolean).length;
	if (!added && !gone.length) return "Nothing on the page changed.";
	if (added > after.length / 2) return undefined;
	const out = ["Changed since you last read this page (the rest is as it was):"];
	after.forEach((line, i) => {
		if (!fresh[i]) return;
		if (i && !fresh[i - 1]) out.push(`  ${after[i - 1]}`);
		out.push(`+ ${line}`);
	});
	for (const line of gone.slice(0, 40)) out.push(`- ${line}`);
	return out.join("\n");
}

const size = (bytes: number) => (bytes < 1000 ? `${bytes} B` : `${(bytes / 1000).toFixed(1)} kB`);

function summarize(seen: Seen[]): Activity | undefined {
	if (!seen.length) return undefined;
	const sites = new Map<string, number>();
	for (const item of seen) if (item.host) sites.set(item.host, (sites.get(item.host) ?? 0) + 1);
	// Enough to read, not enough to bloat the session file; browser.log has the rest.
	const texts = (kind: Seen["kind"], only?: (item: Seen) => boolean) => seen.filter((item) => item.kind === kind && (!only || only(item))).map((item) => item.text).slice(0, 20);
	return {
		opened: texts("opened").at(-1),
		requests: seen.filter((item) => item.kind === "request").length,
		sites: [...sites].sort((a, b) => b[1] - a[1]).slice(0, 20),
		sent: texts("request", (item) => item.sends === true),
		failed: texts("failed"),
		errors: texts("error"),
		popups: texts("popup"),
		downloads: texts("download"),
	};
}

const textResult = (text: string): Result => ({ content: [{ type: "text", text: clip(text) }], details: { chars: text.length } });

// Where a name leads, and whether any of that is LOCAL.
async function whereIs(host: string): Promise<{ name: string; addresses: string[]; local: boolean }> {
	const name = host.replace(/^\[|\]$/g, "").toLowerCase();
	const found = isIP(name) ? [{ address: name, family: isIP(name) }] : await lookup(name, { all: true });
	return { name, addresses: found.map(({ address }) => address), local: found.some(({ address, family }) => LOCAL.check(address, family === 6 ? "ipv6" : "ipv4")) };
}

// The browser's one road out: a SOCKS5 proxy in this process. It looks every name up itself and connects to
// the address it checked, so a page cannot show one address to the check and use another for the connection.
// `allowed`: the host:port pairs I let through although they are local. `refused`: told about each one that is not.
function openProxy(allowed: Set<string>, refused: (where: string) => void): Promise<Server> {
	const server = createServer((client) => {
		client.on("error", () => {});
		// First a greeting (answered: no password needed), then the one request: 5, 1 for "connect", 0, the kind of address, the address, the port.
		client.once("data", (hello) => {
			if (hello[0] !== 5) return client.destroy();
			client.write(Buffer.from([5, 0]));
			client.once("data", async (ask) => {
				const answer = (code: number) => client.write(Buffer.from([5, code, 0, 1, 0, 0, 0, 0, 0, 0]));
				try {
					const kind = ask[3];
					const end = kind === 3 ? 5 + (ask[4] ?? 0) : kind === 4 ? 20 : 8;
					const host = kind === 3 ? ask.toString("latin1", 5, end) : kind === 4 ? (ask.toString("hex", 4, 20).match(/.{4}/g) ?? []).join(":") : ask.subarray(4, 8).join(".");
					const port = ask.readUInt16BE(end);
					if (ask[1] !== 1) throw new Error("only connections are carried");
					const { name, addresses, local } = await whereIs(host);
					if (local && !allowed.has(`${name}:${port}`)) {
						refused(`${name}:${port}`);
						answer(2);
						return client.end();
					}
					// A name can have several addresses, and the first need not answer.
					const out = await new Promise<Socket>((resolve, reject) => {
						const next = (at: number) => {
							const socket = tcp(port, addresses[at] ?? "");
							socket.once("error", (error) => (at + 1 < addresses.length ? next(at + 1) : reject(error)));
							socket.once("connect", () => {
								socket.removeAllListeners("error");
								resolve(socket);
							});
						};
						next(0);
					});
					out.on("error", () => client.destroy());
					out.on("close", () => client.destroy());
					client.on("close", () => out.destroy());
					answer(0);
					client.pipe(out).pipe(client);
				} catch {
					answer(4);
					client.end();
				}
			});
		});
	});
	return new Promise((resolve, reject) => server.once("error", reject).listen(0, "127.0.0.1", () => resolve(server)));
}

// How Chromium is run. On Linux, inside a bubblewrap box: its own process list, none of my environment (so
// none of my keys), and a file system that holds the system's programs, its profile and its downloads, and
// nothing else of mine. A page that breaks out of the browser finds no home folder there. The network is
// shared, because the proxy is on it. macOS has nothing as simple: there Chromium runs as me.
// window: it is to show a real window, which needs the desktop's socket.
function boxed(args: string[], window: boolean): { command: string; args: string[]; env: NodeJS.ProcessEnv } {
	if (process.platform !== "linux") return { command: BROWSER_BIN, args, env: process.env };
	const box = ["--unshare-all", "--share-net", "--die-with-parent", "--new-session", "--clearenv", "--proc", "/proc", "--dev", "/dev", "--tmpfs", "/tmp", "--dir", BOX_HOME, "--ro-bind", "/usr", "/usr"];
	// /bin, /lib and their kin are links into /usr on most systems; where they are folders, they come along as they are.
	for (const name of ["bin", "sbin", "lib", "lib32", "lib64"]) {
		try {
			box.push("--symlink", readlinkSync(`/${name}`), `/${name}`);
		} catch {
			box.push("--ro-bind-try", `/${name}`, `/${name}`);
		}
	}
	for (const path of ["/etc/fonts", "/etc/ssl", "/etc/ca-certificates", "/etc/localtime"]) box.push("--ro-bind-try", path, path);
	// A Chromium that is not one of the system's programs comes along with its folder.
	if (!BROWSER_BIN.startsWith("/usr/")) box.push("--ro-bind-try", dirname(BROWSER_BIN), dirname(BROWSER_BIN));
	box.push("--bind", PROFILE, PROFILE, "--bind", DOWNLOADS, DOWNLOADS);
	const env: Record<string, string> = { HOME: BOX_HOME, PATH: "/usr/bin:/bin", LANG: process.env.LANG ?? "C.UTF-8" };
	// A real window needs the desktop's socket, and nothing else of the desktop.
	const { XDG_RUNTIME_DIR, WAYLAND_DISPLAY } = process.env;
	if (window && XDG_RUNTIME_DIR && WAYLAND_DISPLAY) {
		box.push("--ro-bind", join(XDG_RUNTIME_DIR, WAYLAND_DISPLAY), join(XDG_RUNTIME_DIR, WAYLAND_DISPLAY));
		Object.assign(env, { XDG_RUNTIME_DIR, WAYLAND_DISPLAY });
	}
	for (const [name, value] of Object.entries(env)) box.push("--setenv", name, value);
	return { command: "bwrap", args: [...box, BROWSER_BIN, ...args], env: process.env };
}

// Stops anything that carries a secret before it reaches the browser. A tripwire for the obvious case, not a filter: a key cut in two passes.
function noSecret(text: string) {
	let plain = text;
	try {
		plain = decodeURIComponent(text);
	} catch {
		// Not an encoded address: checked as it is.
	}
	const held = ENV_SECRETS.find(({ value }) => text.includes(value) || plain.includes(value));
	const what = held ? `the value of $${held.name}` : KEY_SHAPES.test(text) || KEY_SHAPES.test(plain) ? "something shaped like a key or token" : undefined;
	if (what) throw new Error(`Not sent: this contains ${what}. Secrets do not go into the browser.`);
}

// Chromium's own pipe, on the child's 4th and 5th file handle: one JSON message after another, each
// ended by a zero byte. Commands go out with an id and their replies come back under it; events have none.
function attach(child: ChildProcess, onEvent: (method: string, params: any, session?: string) => void): Link {
	const [out, back] = [child.stdio[3] as Writable | undefined, child.stdio[4] as Readable | undefined];
	const pending = new Map<number, { resolve: (value: any) => void; reject: (error: Error) => void }>();
	let lastId = 0;
	let open = true;
	let rest = "";
	const end = () => {
		open = false;
		for (const waiter of pending.values()) waiter.reject(new Error("the browser closed"));
		pending.clear();
	};
	back?.setEncoding("utf8");
	back?.on("data", (chunk: string) => {
		rest += chunk;
		if (!chunk.includes("\0")) return;
		const whole = rest.split("\0");
		rest = whole.pop() ?? "";
		for (const text of whole) {
			const message = JSON.parse(text);
			if (!message.id) {
				onEvent(message.method, message.params, message.sessionId);
				continue;
			}
			const waiter = pending.get(message.id);
			pending.delete(message.id);
			if (message.error) waiter?.reject(new Error(message.error.message));
			else waiter?.resolve(message.result);
		}
	});
	for (const end$ of [back, out]) end$?.on("error", end).on("close", end);
	child.once("error", end).once("exit", end);
	return {
		alive: () => open,
		close: end,
		send: (method, params = {}, session, signal) =>
			new Promise((resolveReply, rejectReply) => {
				if (!open || !out) return rejectReply(new Error("the browser closed"));
				const id = ++lastId;
				pending.set(id, { resolve: resolveReply, reject: rejectReply });
				// Esc (the turn's signal) or COMMAND_MS, whichever comes first.
				const timeout = AbortSignal.timeout(COMMAND_MS);
				const stop = signal ? AbortSignal.any([signal, timeout]) : timeout;
				stop.addEventListener("abort", () => {
					if (pending.delete(id)) rejectReply(new Error(`${method} ${signal?.aborted ? "was cancelled" : "timed out"}`));
				});
				out.write(`${JSON.stringify({ id, method, params, sessionId: session })}\0`);
			}),
	};
}

// A word with each letter in its colour of the moment. The colours are soft ones (HSL at 75% saturation,
// 68% lightness), so they read on a dark and on a light status line.
function wave(word: string): string {
	const turn = (Date.now() / WAVE.turnMs) * 360;
	const letters = [...word].map((letter, at) => {
		const hue = (((turn - at * WAVE.spread) % 360) + 360) % 360;
		const [r, g, b] = [0, 8, 4].map((n) => Math.round(255 * (0.68 - 0.24 * Math.max(-1, Math.min(((n + hue / 30) % 12) - 3, 9 - ((n + hue / 30) % 12), 1)))));
		return `\x1b[38;2;${r};${g};${b}m${letter}`;
	});
	return `${letters.join("")}\x1b[39m`;
}

function loadState(): { enabled: boolean; watch: boolean } {
	try {
		const saved = JSON.parse(readFileSync(STATE_FILE, "utf8"));
		return { enabled: saved.enabled === true, watch: saved.watch !== false };
	} catch {
		return { enabled: false, watch: true };
	}
}

const count = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`;

// One line: where it went, how much traffic, then the things worth a look. Expanded: the lists behind those numbers.
// loud: the call ran the agent's own JavaScript, so data leaving the page is shown as a warning.
function renderResult(result: { content: { type: string; text?: string }[]; details?: unknown }, expanded: boolean, loud: boolean, theme: Theme) {
	const details = result.details as Result["details"] | undefined;
	if (!details) return new Text(theme.fg("error", result.content.map((c) => c.text ?? "").join("\n")), 0, 0);
	const did = details.activity;
	const dim = (text: string) => theme.fg("dim", text);
	const flag = (text: string) => theme.fg("warning", text);
	const read = details.chars ? dim(`${details.chars.toLocaleString()} characters`) : "";

	if (!expanded || !did) {
		const sentTo = [...new Set((did?.sent ?? []).map((line) => line.split(" ")[1]?.split("/")[0]))];
		const parts = did
			? [
					did.opened ? dim(`→ ${brief(did.opened)}`) : "",
					did.requests ? dim(`${count(did.requests, "request")} to ${count(did.sites.length, "site")}`) : "",
					sentTo.length ? (loud ? flag : dim)(`sent data to ${sentTo.slice(0, 3).join(", ")}${sentTo.length > 3 ? ` +${sentTo.length - 3}` : ""}`) : "",
					did.downloads.length ? flag(count(did.downloads.length, "download")) : "",
					did.popups.length ? flag(count(did.popups.length, "popup")) : "",
					did.failed.length ? dim(`${did.failed.length} failed`) : "",
					did.errors.length ? dim(count(did.errors.length, "page error")) : "",
				]
			: [];
		return new Text([...parts, read].filter(Boolean).join(dim(" · ")) || dim("done"), 0, 0);
	}

	const rows: string[] = [];
	const row = (label: string, lines: string[], paint: (text: string) => string = dim) => lines.forEach((line, i) => rows.push(dim((i ? "" : label).padEnd(10)) + paint(line)));
	if (did.opened) row("opened", [did.opened]);
	row("sites", did.sites.map(([host, n]) => `${host} ${n}`));
	row("sent", did.sent, loud ? flag : dim);
	row("download", did.downloads, flag);
	row("popup", did.popups, flag);
	row("failed", did.failed);
	row("error", did.errors);
	if (read) row("read", [read]);
	row("log", [hyperlink(tilde(LOG_FILE), pathToFileURL(LOG_FILE).href)]);
	return new Text(rows.join("\n"), 0, 0);
}

export default function (pi: ExtensionAPI) {
	let { enabled, watch } = loadState();
	let engine: ChildProcess | undefined;
	// The browser's road out, and the local host:port pairs I let it reach this session (/browser allow).
	let proxy: Server | undefined;
	const allowed = new Set<string>();
	// link: the pipe to a browser that is ready. wire: the same pipe from the moment it exists, for what happens while the browser starts.
	let link: Link | undefined;
	let wire: Link | undefined;
	// The name each tab is told to give to sites, where Chromium's own would say "headless".
	let guise: object | undefined;
	let starting: Promise<Link> | undefined;
	// The tab being driven, by the id of the session Chromium speaks to it under; and every open tab, oldest first.
	let tab: string | undefined;
	const tabs = new Map<string, Tab>();
	const tools: string[] = [];
	// What the window did since the last browser_* call reported.
	let seen: Seen[] = [];
	// What settle() watches. loading: the driven tab has left its old page and the new one has no DOM yet.
	// inFlight: requests without an answer yet, with when they left and whether they are CONTENT. lastStir: when any of this last moved.
	let loading = false;
	const inFlight = new Map<string, { url: string; left: number; content: boolean }>();
	let lastStir = 0;
	// Where the pointer's tip is in the window. Each tab has a script that draws it there on every page
	// it opens; it is registered again after each move, one change at a time (`preloads`).
	let pointer: [number, number] = [...REST];
	let preloads: Promise<unknown> = Promise.resolve();

	const mark = (session: string) => {
		preloads = preloads
			.then(async () => {
				const page = tabs.get(session);
				if (!wire || !page) return;
				const old = page.preload;
				const source = `(${markers(...pointer, watch ? DOZE_MS : 0)})()`;
				page.preload = (await wire.send("Page.addScriptToEvaluateOnNewDocument", { source, worldName: SANDBOX, runImmediately: true }, session)).identifier;
				if (old) await wire.send("Page.removeScriptToEvaluateOnNewDocument", { identifier: old }, session);
			})
			.catch(() => {});
		return preloads;
	};
	const movedTo = (x: number, y: number) => {
		pointer = [x, y];
		return tab ? mark(tab) : preloads;
	};
	// /browser watch. viewer: the pane's end of WATCH_SOCKET. pane: its size, in cells and in pixels.
	// view: the tab whose pictures it is getting, and the page size that fits it.
	// posing: the pointer is hidden for the agent's own screenshot.
	let server: Server | undefined;
	let viewer: Socket | undefined;
	let pane: { cols: number; rows: number; width: number; height: number } | undefined;
	let view: { tab: string; width: number; height: number } | undefined;
	let posing = false;
	// The page as the model last read it, to answer the next action with only what changed.
	let lastRead: { tab?: string; url: string; lines: string[] } | undefined;
	let log: WriteStream | undefined;
	let ui: ExtensionContext["ui"] | undefined;
	let animated = false;
	let waving: ReturnType<typeof setInterval> | undefined;

	// "browser" while the tools are on. While the browser is open its letters run through the colours;
	// that only moves in the terminal UI, and stops with the browser.
	const showStatus = () => {
		const open = enabled && link?.alive() === true;
		if (waving && !(open && ui)) {
			clearInterval(waving);
			waving = undefined;
		}
		if (!ui) return;
		if (open && animated && !waving) waving = setInterval(showStatus, WAVE.stepMs);
		ui.setStatus("browser", !enabled ? undefined : open ? wave("browser") : ui.theme.fg("accent", "browser"));
	};

	// One line in browser.log. Opened on first use, private, and started afresh once it is big.
	const write = (line: string) => {
		if (!log) {
			try {
				// Every entry starts with its date, oldest first. Rewritten in place: another pi may be adding to it.
				const cutoff = new Date(Date.now() - LOG_KEEP_DAYS * 86_400_000).toLocaleDateString("sv");
				const old = readFileSync(LOG_FILE, "utf8");
				const lines = old.split("\n");
				const first = lines.findIndex((entry) => /^\d{4}-\d\d-\d\d /.test(entry) && entry.slice(0, 10) >= cutoff);
				let kept = first < 0 ? "" : lines.slice(first).join("\n");
				if (kept.length > LOG_MAX_BYTES) kept = kept.slice(kept.indexOf("\n", kept.length - LOG_MAX_BYTES / 2) + 1);
				if (kept.length !== old.length) writeFileSync(LOG_FILE, kept);
			} catch {
				// No log yet.
			}
			log = createWriteStream(LOG_FILE, { flags: "a", mode: 0o600 });
			log.on("error", () => {});
		}
		const now = new Date();
		const stamp = `${now.toLocaleDateString("sv")} ${now.toLocaleTimeString("sv")}`;
		log.write(`${stamp}  ${line.replaceAll("\n", `\n${" ".repeat(stamp.length + 2)}`)}\n`);
	};

	const note = (item: Seen, full = item.text) => {
		// A page that never stops polling must not grow this without end; the log still gets everything.
		if (seen.length < 5000) seen.push(item);
		write(`${item.kind.padEnd(8)} ${full}`);
	};

	// One picture of the driven tab, sent to the pane as a kitty image laid over the last, which is removed
	// only then: replacing an image in place leaves the pane empty for a moment, and it flashes. Chromium
	// sends its next picture once this one is acknowledged, and that holds it to the pane's pace: the pane
	// must have taken this one in, and acknowledgements go out no closer together than FRAME_MS.
	let image = 1;
	let ackAt = 0;
	// When the agent or I last did something in the browser.
	let touched = 0;
	const onFrame = (session: string, frame: { data: string; sessionId: number }) => {
		const [mine, size] = [viewer, pane];
		const ack = () => void wire?.send("Page.screencastFrameAck", { sessionId: frame.sessionId }, session).catch(() => {});
		if (!mine || !size || session !== view?.tab || posing) return ack();
		const old = image;
		image = 3 - image;
		// 2026: the terminal shows the frame only once all of it has arrived.
		let out = "\x1b[?2026h\x1b[H";
		for (let at = 0; at < frame.data.length; at += 4096) {
			const head = at ? "" : `a=T,f=100,i=${image},p=1,q=2,C=1,c=${size.cols},r=${size.rows},`;
			out += `\x1b_G${head}m=${at + 4096 < frame.data.length ? 1 : 0};${frame.data.slice(at, at + 4096)}\x1b\\`;
		}
		const due = (ackAt = Math.max(Date.now(), ackAt + (Date.now() - touched < IDLE_AFTER_MS ? FRAME_MS : IDLE_FRAME_MS)));
		mine.write(`${out}\x1b_Ga=d,d=I,i=${old},q=2\x1b\\\x1b[?2026l`, () => setTimeout(ack, Math.max(0, due - Date.now())));
	};

	const onEvent = (method: string, params: any, session?: string) => {
		if (method.startsWith("Target.") || method.startsWith("Page.frame") || method.startsWith("Network.")) lastStir = Date.now();
		switch (method) {
			case "Page.screencastFrame":
				return session ? onFrame(session, params) : undefined;
			// A tab, whether I opened it or a click did: it is made ready, and becomes the one driven.
			case "Target.attachedToTarget": {
				if (params.targetInfo.type !== "page") return;
				const mine: string = params.sessionId;
				const page: Tab = { target: params.targetInfo.targetId };
				tabs.set(mine, page);
				tab = mine;
				loading = false;
				// Told to behave as the tab in front: without that, keys reach a page only once it has been clicked.
				const asks = [...DOMAINS.map((domain) => wire?.send(`${domain}.enable`, {}, mine)), wire?.send("Emulation.setFocusEmulationEnabled", { enabled: true }, mine)];
				if (guise) asks.push(wire?.send("Emulation.setUserAgentOverride", guise, mine));
				page.ready = Promise.all(asks)
					.then(() => mark(mine))
					.then(
						() => {},
						() => {},
					);
				return;
			}
			case "Target.detachedFromTarget":
				tabs.delete(params.sessionId);
				if (tab === params.sessionId) tab = undefined;
				return;
			// The tab's own frame (it carries the tab's id) leaves for another page.
			case "Page.frameStartedNavigating":
				if (session !== tab || params.frameId !== tabs.get(session ?? "")?.target || /sameDocument/i.test(params.navigationType)) return;
				loading = true;
				if (/^https?:/.test(params.url)) note({ kind: "opened", text: params.url });
				return;
			case "Page.domContentEventFired":
				if (session === tab) loading = false;
				return;
			case "Network.requestWillBeSent": {
				const { method: verb, url, postData, headers } = params.request;
				if (!/^https?:/.test(url)) return;
				// A page may leave requests unanswered for good; they must not pile up here.
				if (inFlight.size > 5000) inFlight.clear();
				inFlight.set(params.requestId, { url, left: Date.now(), content: CONTENT.has(params.type) });
				const sends = !/^(GET|HEAD|OPTIONS)$/.test(verb);
				const bytes = postData?.length ?? Number(headers?.["Content-Length"] ?? 0);
				const body = sends && bytes ? ` (${size(bytes)})` : "";
				return note({ kind: "request", text: `${verb} ${brief(url)}${body}`, host: new URL(url).host, sends }, `${verb} ${url}${body}`);
			}
			case "Network.responseReceived":
				if (params.response.status >= 400) note({ kind: "failed", text: `${params.response.status} ${brief(params.response.url)}` }, `${params.response.status} ${params.response.url}`);
				return;
			case "Network.loadingFinished":
			case "Network.loadingFailed": {
				const url = inFlight.get(params.requestId)?.url;
				inFlight.delete(params.requestId);
				// A request the page itself gave up on, as when it is left for another, is not a failure.
				if (method.endsWith("Failed") && url && !params.canceled) note({ kind: "failed", text: `${brief(url)}: ${params.errorText}` }, `${url}: ${params.errorText}`);
				return;
			}
			case "Log.entryAdded":
				if (params.entry.level === "error") note({ kind: "error", text: String(params.entry.text).slice(0, 200) });
				return;
			case "Runtime.exceptionThrown":
				return note({ kind: "error", text: problem(params.exceptionDetails).slice(0, 200) });
			// An alert or confirm holds its page up until it is answered: it is dismissed.
			case "Page.javascriptDialogOpening":
				void wire?.send("Page.handleJavaScriptDialog", { accept: false }, session).catch(() => {});
				return note({ kind: "popup", text: `${params.type}: "${String(params.message).slice(0, 200)}" (dismissed)` });
			case "Browser.downloadWillBegin":
				// A download starts out as a page load, but the page never changes.
				loading = false;
				seen = seen.filter((item) => !(item.kind === "opened" && item.text === params.url));
				return note({ kind: "download", text: `${params.suggestedFilename} from ${brief(params.url)}, saved in ${tilde(DOWNLOADS)}` }, `${params.suggestedFilename} from ${params.url}, saved in ${DOWNLOADS}`);
		}
	};

	async function start(): Promise<Link> {
		// What is left of a pi that no longer runs: it died before it could delete its browser's profile.
		mkdirSync(PROFILES, { recursive: true, mode: 0o700 });
		for (const left of readdirSync(PROFILES)) {
			let running = Number.parseInt(left, 10) !== process.pid;
			try {
				process.kill(Number.parseInt(left, 10), 0);
			} catch {
				running = false;
			}
			if (!running) rmSync(join(PROFILES, left), { recursive: true, force: true });
		}
		mkdirSync(PROFILE);
		mkdirSync(DOWNLOADS, { recursive: true });
		const road = await openProxy(allowed, (where) => note({ kind: "failed", text: `refused: ${where} is on this machine or its own network` }));
		proxy = road;

		const run = boxed(flags((road.address() as AddressInfo).port, watch), !watch);
		// detached: its own process group, so a ctrl+c meant for pi never reaches it. The two pipes are Chromium's
		// line to pi, and its lifeline: when pi dies, however suddenly, they close and Chromium quits.
		const child = spawn(run.command, run.args, { detached: true, stdio: ["ignore", "ignore", "ignore", "pipe", "pipe"], env: run.env });
		child.unref();
		engine = child;
		let failed: string | undefined;
		const fix = run.command === "bwrap" ? "It needs bubblewrap (on Linux the browser only runs boxed in) and a Chromium; BROWSER_BIN names one." : "BROWSER_BIN names a Chromium.";
		child.once("error", (error) => (failed = `Cannot run ${run.command} (${error.message}). ${fix}`));
		child.once("exit", () => (failed ??= `Chromium (${BROWSER_BIN}) quit before it was ready. ${fix}`));
		// A browser that ends by itself takes its dot with it.
		child.once("exit", () => setTimeout(showStatus));
		const next = attach(child, onEvent);
		wire = next;
		// Its first answer is the sign that it is up, and says what it calls itself.
		const { userAgent, product } = await next.send("Browser.getVersion").catch((error) => {
			throw new Error(failed ?? `Chromium did not start: ${error.message}`);
		});
		const brands = [
			{ brand: "Chromium", version: /\/(\d+)/.exec(product)?.[1] ?? "" },
			{ brand: "Not?A_Brand", version: "24" },
		];
		const platform = process.platform === "darwin" ? "macOS" : "Linux";
		guise = /Headless/.test(userAgent) ? { userAgent: userAgent.replace("Headless", ""), userAgentMetadata: { brands, platform, platformVersion: "", architecture: "x86", model: "", mobile: false } } : undefined;
		await next.send("Browser.setDownloadBehavior", { behavior: "allow", downloadPath: DOWNLOADS, eventsEnabled: true });
		// From here on every tab reports in as it opens, the one Chromium starts with included: that one is driven first.
		await next.send("Target.setAutoAttach", { autoAttach: true, waitForDebuggerOnStart: false, flatten: true, filter: [{ type: "page" }] });
		for (let tries = 0; !tab && tries < 100; tries++) await sleep(20);
		if (tab) await tabs.get(tab)?.ready;
		else await openTab(next);
		link = next;
		// The browser is still worth having when its pane cannot be opened.
		if (watch) await openWatch().catch((error) => ui?.notify(`Browser watch: no pane (${error instanceof Error ? error.message : error})`, "warning"));
		showStatus();
		return next;
	}

	// Keeps the pane showing the driven tab for as long as `mine` is the viewer. Chromium sends a picture
	// whenever that page changes, and only then; this sees to it that the right tab is the one sending,
	// laid out to the pane's shape, and starts it afresh when either changes, so a page at rest shows at once too.
	async function frames(mine: Socket) {
		let fitted: typeof pane;
		while (viewer === mine && !mine.destroyed) {
			const [open, session, size] = [link, tab, pane];
			if (open?.alive() && session && size && (view?.tab !== session || fitted !== size)) {
				const width = Math.max(size.width, PAGE_MIN_WIDTH);
				const height = Math.round((width * size.height) / size.width);
				try {
					if (view && view.tab !== session) await open.send("Page.stopScreencast", {}, view.tab).catch(() => {});
					await tabs.get(session)?.ready;
					await open.send("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: 1, mobile: false }, session);
					await open.send("Page.stopScreencast", {}, session);
					view = { tab: session, width, height };
					fitted = size;
					await open.send("Page.startScreencast", { format: "png" }, session);
				} catch {
					// A tab that just closed, or a browser on its way out: the next round sees it.
				}
			}
			await sleep(100);
		}
	}

	// What I do in the pane reaches the page as if I sat at the browser: clicks, drags, the wheel, keys.
	// None of it is written down or shown to the model, so a password typed here is seen by the page alone.
	// held: my mouse button is down on the page. focusedAt: when the pane last got the keyboard.
	// pressedAt, clicks: when I last pressed, and how many presses in a row that made. dragged: the mouse moved while held.
	let dragged = false;
	let held = false;
	let focusedAt = 0;
	let pressedAt = 0;
	let clicks = 0;

	// Where my mouse rests on the pane, the page is told, so its menus and highlights react; and the
	// pane's mouse cursor takes the shape the page asks for there: a hand over a link, a bar in a text field.
	// One spot at a time, always the latest: a mouse reports faster than a page answers.
	let spot: [number, number] | undefined;
	let asking = false;
	let shape = "";
	const hoverAt = async (x: number, y: number) => {
		spot = [x, y];
		if (asking) return;
		asking = true;
		try {
			while (spot && link?.alive() && view) {
				const [atX, atY] = spot;
				spot = undefined;
				const session = view.tab;
				await link.send("Input.dispatchMouseEvent", { type: "mouseMoved", x: atX, y: atY }, session);
				const wanted = String(await run(link, session, CURSOR, [atX, atY]));
				// OSC 22: the terminal's own way to be told a cursor shape, by the same names CSS uses.
				if (wanted !== shape) viewer?.write(`\x1b]22;${(shape = wanted)}\x1b\\`);
			}
		} catch {
			// The page went away under the mouse.
		} finally {
			asking = false;
		}
	};

	// What I have just selected on the page with the mouse goes to my clipboard, the way a terminal copies on
	// select. OSC 52 is how a program in a terminal hands text to the clipboard, wherever that terminal is shown.
	const copySelected = async (to: Socket) => {
		if (!link?.alive() || !view) return;
		const text = String((await run(link, view.tab, SELECTED).catch(() => "")) ?? "");
		if (text) to.write(`\x1b]52;c;${Buffer.from(text).toString("base64")}\x07`);
	};

	const onPane = (from: Socket, data: string) => {
		const [open, shown, size] = [link, view, pane];
		touched = Date.now();
		const act = (method: string, params: object) => void open?.send(method, params, shown?.tab).catch(() => {});
		const press = (key: string, modifiers = 0) => {
			for (const event of keystroke(key, modifiers)) act("Input.dispatchKeyEvent", event);
		};
		// A report or key sequence, alt with a key, or one character.
		for (const [token] of data.matchAll(/\x1b\[[<0-9;]*[A-Za-z~]|\x1b[^[\x1b]?|[^\x1b]/gu)) {
			const resized = /^\x1b\[48;(\d+);(\d+);(\d+);(\d+)t$/.exec(token);
			const moused = /^\x1b\[<(\d+);(\d+);(\d+)([Mm])$/.exec(token);
			if (resized) {
				const [rows, cols, height, width] = resized.slice(1).map(Number) as [number, number, number, number];
				if (rows < 2 || !cols) continue;
				// A terminal that will not say its size in pixels: assume its cells are twice as tall as wide.
				pane = { rows, cols, height: height || rows * 16, width: width || cols * 8 };
				from.write("\x1b[2J\x1b_Ga=d,d=A,q=2\x1b\\");
			} else if (moused && shown && size) {
				const [code, col, row] = moused.slice(1, 4).map(Number) as [number, number, number];
				// The middle of the cell, as a point on the page.
				const x = Math.round(((col - 0.5) / size.cols) * shown.width);
				const y = Math.round(((row - 0.5) / size.rows) * shown.height);
				// 64: the wheel. 32: the mouse moved. The low bits: which button, of which only the left one is passed on.
				if (code & 64) act("Input.dispatchMouseEvent", { type: "mouseWheel", x, y, deltaX: 0, deltaY: code & 1 ? WHEEL_PX : -WHEEL_PX });
				else if (code & 32 && !held) void hoverAt(x, y);
				else if (code & 3) continue;
				else if (moused[4] === "m") {
					if (held) {
						act("Input.dispatchMouseEvent", { type: "mouseReleased", x, y, button: "left", clickCount: clicks });
						// A drag or a double click selects; a plain click does not, and would copy whatever was selected before.
						if (dragged || clicks > 1) void copySelected(from);
					}
					held = false;
				} else if (code & 32) {
					dragged = true;
					act("Input.dispatchMouseEvent", { type: "mouseMoved", x, y, button: "left", buttons: 1 });
				}
				else if (Date.now() - focusedAt > FOCUS_CLICK_MS) {
					// A press soon after the last is a double click, which picks a word.
					clicks = Date.now() - pressedAt < 400 ? clicks + 1 : 1;
					pressedAt = Date.now();
					act("Input.dispatchMouseEvent", { type: "mousePressed", x, y, button: "left", clickCount: clicks });
					held = true;
					dragged = false;
				}
			} else if (token === "\x1b[I") focusedAt = Date.now();
			else if (token === "\x03") return void from.end();
			else if (token === "\x1b[1;3D" || token === "\x1b[1;3C") act("Runtime.evaluate", { expression: token.endsWith("D") ? "history.back()" : "history.forward()" });
			else if (token === "\x1b[15~") act("Page.reload", {});
			else if (token === "\x1b[Z") press("Tab", MODIFIER.shift);
			else if (token in PANE_KEYS) press(PANE_KEYS[token] ?? "");
			else if (token.length === 2 && token[0] === "\x1b") press(token[1] ?? "", MODIFIER.alt);
			else if (token.length === 1 && token < " ") press(String.fromCharCode(token.charCodeAt(0) + 96), MODIFIER.control);
			else if (!token.startsWith("\x1b")) press(token);
		}
	};

	// Opens the pane beside pi. In Rex that is a split of pi's own block; anywhere else I start the viewer myself.
	function openPane() {
		const { REX_BLOCK, REX_SESSION } = process.env;
		const byHand = () => ui?.notify(`To watch the agent's browser, run this in a terminal with kitty graphics:  node ${tilde(WATCH_VIEWER)} ${tilde(WATCH_SOCKET)}`, "info");
		if (!REX_BLOCK) return byHand();
		const where = ["-b", REX_BLOCK, ...(REX_SESSION ? ["-s", REX_SESSION] : [])];
		const rex = spawn("rex", ["split", ...where, "--focus=false", "--shell=none", "--label", "browser", "--", process.execPath, WATCH_VIEWER, WATCH_SOCKET], { stdio: "ignore" });
		rex.once("error", byHand);
		rex.once("exit", (code) => code && byHand());
	}

	async function openWatch() {
		rmSync(WATCH_SOCKET, { force: true });
		writeFileSync(WATCH_VIEWER, VIEWER);
		const listening = createServer((socket) => {
			// One pane at a time: a new one takes over.
			viewer?.end();
			viewer = socket;
			pane = view = undefined;
			socket.on("error", () => {});
			// The pane closed, and not because the browser did or another pane took over: a browser I cannot
			// see is not left running.
			socket.on("close", () => {
				if (viewer !== socket) return;
				viewer = undefined;
				ui?.notify("Browser closed with its pane", "info");
				void stop();
			});
			socket.setEncoding("utf8");
			socket.on("data", (data: string) => onPane(socket, data));
			// Its own screen, no cursor; the mouse (1003: every move, click and turn of the wheel) and whether the
			// pane has the keyboard (1004) as input; 2048: say your size now and whenever it changes.
			shape = "";
			socket.write("\x1b[?1049h\x1b[?25l\x1b[?1003h\x1b[?1006h\x1b[?1004h\x1b[?2048h");
			void frames(socket);
		});
		await new Promise<void>((resolve, reject) => listening.once("error", reject).listen(WATCH_SOCKET, resolve));
		server = listening;
		openPane();
	}

	// Ends Chromium and deletes everything it knew. Nothing of it is kept, so there is nothing to shut down gently:
	// it is killed, and its profile goes once it has stopped writing there.
	async function discard(child: ChildProcess | undefined) {
		if (!child) return;
		const gone = child.exitCode === null && child.signalCode === null && new Promise((done) => child.once("exit", done));
		child.kill("SIGKILL");
		if (gone) await Promise.race([gone, sleep(3000)]);
		await rm(PROFILE, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 }).catch(() => {});
	}

	async function stop() {
		await starting?.catch(() => {});
		const [open, child] = [link, engine];
		link = wire = engine = tab = lastRead = undefined;
		tabs.clear();
		pointer = [...REST];
		loading = false;
		inFlight.clear();
		viewer?.end();
		server?.close();
		// Only its own: another pi session may be the one listening there.
		if (server) rmSync(WATCH_SOCKET, { force: true });
		viewer = server = pane = view = undefined;
		open?.close();
		proxy?.close();
		proxy = undefined;
		await discard(child);
		if (open) write("── browser closed, its profile deleted");
		log?.end();
		log = undefined;
		seen = [];
		showStatus();
	}

	function browser(): Promise<Link> {
		if (link?.alive()) return Promise.resolve(link);
		starting ??= start()
			.catch(async (error) => {
				proxy?.close();
				await discard(engine);
				engine = proxy = undefined;
				throw error;
			})
			.finally(() => (starting = undefined));
		return starting;
	}

	// The open tabs, oldest first, with what each is showing.
	async function tabList(open: Link): Promise<{ session: string; target: string; url: string }[]> {
		const { targetInfos } = await open.send("Target.getTargets");
		return [...tabs].flatMap(([session, { target }]) => {
			const info = targetInfos.find((one: { targetId: string }) => one.targetId === target);
			return info ? [{ session, target, url: String(info.url) }] : [];
		});
	}

	// A new tab, which becomes the one driven once it has reported in.
	async function openTab(open: Link, signal?: AbortSignal): Promise<string> {
		const { targetId } = await open.send("Target.createTarget", { url: "about:blank" }, undefined, signal);
		for (let tries = 0; tries < 150; tries++) {
			const found = [...tabs].find(([, page]) => page.target === targetId);
			if (found) {
				await found[1].ready;
				return (tab = found[0]);
			}
			await sleep(20);
		}
		throw new Error("The new tab did not open.");
	}

	// The driven tab; once that has closed, the one opened last; with none left, a new one.
	async function currentTab(open: Link): Promise<string> {
		if (tab && tabs.has(tab)) return tab;
		const left = [...tabs.keys()].at(-1);
		return left ? (tab = left) : openTab(open);
	}

	// Runs one of the scripts above in a tab, in the scripts' own world on its page. That world is asked
	// for by name, which gives the one the pointer already lives in.
	async function run(open: Link, session: string, script: string, args: (string | number)[] = [], signal?: AbortSignal): Promise<any> {
		const { executionContextId } = await open.send("Page.createIsolatedWorld", { frameId: tabs.get(session)?.target, worldName: SANDBOX }, session, signal);
		const reply = await open.send("Runtime.callFunctionOn", { functionDeclaration: script, executionContextId, arguments: args.map((value) => ({ value })), awaitPromise: true, returnByValue: true }, session, signal);
		if (reply.exceptionDetails) throw new Error(problem(reply.exceptionDetails));
		return reply.result.value;
	}

	// The same, in the driven tab.
	async function call(script: string, args: (string | number)[] = [], signal?: AbortSignal): Promise<any> {
		const open = await browser();
		return run(open, await currentTab(open), script, args, signal);
	}

	// Waits until the page has finished reacting to an action that began at `since`: a page it is
	// loading has its DOM, the requests it made since have their answers, and nothing has moved for
	// QUIET_MS. A click that does nothing costs QUIET_MS; a page that never goes quiet costs FETCH_MS.
	// `from`: when to count the patience for requests from, if later than `since`.
	async function settle(since: number, from = since) {
		for (const [id, { left }] of inFlight) if (left < since - 60_000) inFlight.delete(id);
		while (link?.alive()) {
			await sleep(20);
			const now = Date.now();
			if (loading && now - since < LOAD_MS) continue;
			const fetching = [...inFlight.values()].some(({ left, content }) => content && left >= since);
			if ((fetching || now - lastStir < QUIET_MS) && now - from < FETCH_MS) continue;
			if (now - since >= QUIET_MS) return;
		}
	}

	// The driven tab's page as text. After an action (`whole` false) on a page the model has
	// already read, only what changed: the model still has the rest, and rereading it costs a turn's worth of tokens.
	async function read(signal: AbortSignal | undefined, whole: boolean, lead = ""): Promise<Result> {
		const text = (await call(SNAPSHOT, pointer, signal)) as string;
		const [title, url, , ...lines] = text.split("\n");
		const before = lastRead;
		lastRead = { tab, url: url ?? "", lines };
		const same = !whole && before && before.tab === tab && before.url === url ? changes(before.lines, lines) : undefined;
		return textResult(lead + (same ? `${title}\n${url}\n\n${same}` : text));
	}

	async function click(ref: number, signal?: AbortSignal) {
		const [x, y] = await call(TARGET, [ref, ...pointer], signal);
		const open = await browser();
		const session = await currentTab(open);
		// Before the click, so a page the click opens already draws the pointer here.
		await movedTo(x, y);
		for (const type of ["mouseMoved", "mousePressed", "mouseReleased"]) {
			await open.send("Input.dispatchMouseEvent", { type, x, y, button: type === "mouseMoved" ? "none" : "left", clickCount: 1 }, session, signal);
		}
	}

	async function type(ref: number, text: string, submit: boolean | undefined, signal?: AbortSignal) {
		const [how, x, y, hidden] = await call(FOCUS, [ref, text, ...pointer], signal);
		await movedTo(x, y);
		// The call's own line in the log leaves the text out, because only here is it known what kind of field it went into.
		write(`   [${ref}] ${how === "picked" ? `picked "${text}"` : hidden ? `a password field: ${text.length} characters, not recorded` : `typed "${text}"`}`);
		if (how !== "focused") return;
		const open = await browser();
		const session = await currentTab(open);
		const press = (key: string) => Promise.all(keystroke(key).map((event) => open.send("Input.dispatchKeyEvent", event, session, signal)));
		// The field's old content is selected, so typing replaces it; typing nothing deletes it.
		const keys = [...text.replaceAll("\r", "")].map((char) => PANE_KEYS[char] ?? char);
		// A beat between keys so the text is seen arriving, within TYPING_MS for the whole field. Long text goes in at once.
		const beat = Math.min(12, Math.floor(TYPING_MS / Math.max(keys.length, 1)));
		if (!keys.length) await press("Delete");
		else if (beat < 2) await open.send("Input.insertText", { text }, session, signal);
		else {
			for (const key of keys) {
				await press(key);
				await sleep(beat);
			}
		}
		if (submit) await press("Enter");
	}

	// Opens an address in a tab. Chromium answers once the new page is on its way; settle() then waits for
	// its DOM and for what its scripts fetch, not for its images.
	async function go(open: Link, session: string, url: string, signal?: AbortSignal) {
		const since = Date.now();
		loading = true;
		const reply = await open.send("Page.navigate", { url }, session, signal).catch((error) => ({ errorText: String(error.message), loaderId: "none" }));
		// Nothing loads when only the part after the # differs, and a download never becomes a page.
		if (!reply.loaderId || reply.errorText === "net::ERR_ABORTED") loading = false;
		else if (reply.errorText) {
			loading = false;
			throw new Error(`${url} did not open: ${reply.errorText}`);
		}
		await settle(since, Date.now());
	}

	const localRefusal = (where: string) => `${where} is on this machine or its own network, which this browser may not reach. Only the user can let it through, with /browser allow ${where}`;

	// The proxy would refuse the same addresses; asking first gives the model a reason instead of a page that will not load.
	async function webUrl(url: string): Promise<string> {
		// file: and about: pages would let the agent read what guard.ts keeps from it.
		if (!/^https?:\/\//i.test(url)) throw new Error("Only http(s) pages can be opened");
		const { hostname, port, protocol } = new URL(url);
		const { name, local } = await whereIs(hostname);
		const where = `${name}:${port || (protocol === "https:" ? 443 : 80)}`;
		if (local && !allowed.has(where)) throw new Error(localRefusal(where));
		return url;
	}

	function tool<S extends TSchema>(options: {
		name: string;
		description: string;
		parameters: S;
		guidelines?: string[];
		summary: (args: Partial<Static<S>>) => unknown;
		// What the log's line for the call says, when that is not the summary.
		logged?: (params: Static<S>) => unknown;
		run: (params: Static<S>, signal?: AbortSignal) => Promise<Result>;
	}) {
		const name = `browser_${options.name}`;
		tools.push(name);
		pi.registerTool({
			name,
			label: `Browser ${options.name}`,
			description: options.description,
			promptGuidelines: options.guidelines,
			parameters: options.parameters,
			// Off until /browser; one at a time because they all act on the same tab.
			defaultActive: false,
			executionMode: "sequential",
			// Each result carries what the window did since the last one, so nothing falls between two calls.
			async execute(_id: string, params: Static<S>, signal?: AbortSignal) {
				// Before anything is done or written down: no address, text or code that carries a secret.
				try {
					noSecret(JSON.stringify(params));
				} catch (error) {
					write(`── ${name} refused: it carried a secret`);
					throw error;
				}
				write(`── ${name} ${String((options.logged ?? options.summary)(params) ?? "")}`.trimEnd());
				touched = Date.now();
				try {
					const result = await options.run(params, signal);
					touched = Date.now();
					const activity = summarize(seen);
					seen = [];
					return { ...result, details: { ...result.details, activity } };
				} catch (error) {
					write(`   failed: ${error instanceof Error ? error.message : error}`);
					throw error;
				}
			},
			renderCall: (args: Partial<Static<S>>, theme: Theme) => new Text(theme.fg("toolTitle", theme.bold(`${name} `)) + theme.fg("muted", String(options.summary(args ?? {}) ?? "")), 0, 0),
			renderResult: (result: Result, view: { expanded?: boolean }, theme: Theme) => renderResult(result, view?.expanded === true, options.name === "eval", theme),
		} as any);
	}

	tool({
		name: "navigate",
		description: "Open a URL in the browser tab you are driving. Returns the page as text, with a number in [brackets] before everything that can be clicked or typed into.",
		guidelines: [
			"Use browser_navigate and the other browser_ tools only when a page needs a real browser: JavaScript, a login, clicking or filling forms. Search with web_search and read plain pages with web_fetch: they are cheaper, and search engines put a human check in front of this browser.",
			"The browser_ tools drive a browser of your own that the user watches. It starts empty every session: it is logged in nowhere and nothing in it is kept. The user can click and type in it too. If a page needs an account, or asks to prove a human is there, ask the user to do that in the browser themselves, then carry on; do not try to get past such a check yourself. Never ask for a password in the chat: what they type to you is stored and leaves their machine.",
			"Put every step you can already see into one browser_act call: fill all the fields of a form and click its button in one go, not one call per field.",
		],
		parameters: Type.Object({ url: Type.String({ description: "http(s) URL" }) }),
		summary: (args) => args.url,
		async run(params, signal) {
			const url = await webUrl(params.url);
			const open = await browser();
			await go(open, await currentTab(open), url, signal);
			return read(signal, true);
		},
	});

	tool({
		name: "snapshot",
		description: "Read the whole current page as text. An element keeps its number for as long as the page stays open.",
		parameters: Type.Object({}),
		summary: () => "",
		run: (_params, signal) => read(signal, true),
	});

	const describe = (step: { action?: string; ref?: number; text?: string; submit?: boolean }) =>
		`${step.action ?? ""} [${step.ref ?? ""}]${step.action === "type" ? ` "${step.text ?? ""}"${step.submit ? " ⏎" : ""}` : ""}`;

	tool({
		name: "act",
		description:
			"Click and type on numbered elements, several steps in one call. Steps run in order and stop at the first that fails, for example because an earlier step moved to another page. Returns only what changed on the page; browser_snapshot reads all of it again.",
		parameters: Type.Object({
			steps: Type.Array(
				Type.Object({
					action: StringEnum(["click", "type"] as const, { description: "type replaces a text field's content, or picks the option of a select by its label" }),
					ref: Type.Number({ description: "The element's number" }),
					text: Type.Optional(Type.String({ description: "type: the text to enter, or the option to pick" })),
					submit: Type.Optional(Type.Boolean({ description: "type: press Enter afterwards" })),
				}),
				{ minItems: 1, maxItems: 20 },
			),
		}),
		summary: (args) => (Array.isArray(args.steps) ? args.steps.map((step) => describe(step ?? {})).join(" · ") : ""),
		logged: (params) => params.steps.map((step) => `${step.action} [${step.ref}]`).join(" · "),
		async run(params, signal) {
			let stopped = "";
			for (const [done, step] of params.steps.entries()) {
				const since = Date.now();
				try {
					if (step.action === "click") await click(step.ref, signal);
					else await type(step.ref, step.text ?? "", step.submit, signal);
				} catch (error) {
					if (signal?.aborted) throw error;
					const steps = params.steps.length;
					stopped = `Step ${done + 1} of ${steps} (${describe(step)}) failed: ${error instanceof Error ? error.message : error}. ${done ? `The ${done === 1 ? "step" : `${done} steps`} before it ran.` : "Nothing was done."} The page now:\n\n`;
					break;
				}
				await settle(since);
			}
			// After a failure the model needs the numbers that are valid now, so it gets the whole page.
			return read(signal, stopped !== "", stopped);
		},
	});

	tool({
		name: "screenshot",
		description: "Take a picture of what the browser tab shows right now. For layout and looks; browser_snapshot is cheaper for reading.",
		parameters: Type.Object({}),
		summary: () => "",
		async run(_params, signal) {
			const open = await browser();
			// The pointer sits on the last thing clicked, which is often what the picture is for.
			const show = (on: number) => call(`(on) => { const el = document.getElementById("pi-browser-pointer"); if (el) el.style.visibility = on ? "" : "hidden"; }`, [on]).catch(() => {});
			posing = true;
			await show(0);
			const shot = await open
				.send("Page.captureScreenshot", { format: "jpeg", quality: 80 }, await currentTab(open), signal)
				.finally(() => show(1))
				.finally(() => (posing = false));
			return { content: [{ type: "image", data: shot.data, mimeType: "image/jpeg" }], details: { chars: 0 } };
		},
	});

	tool({
		name: "eval",
		description: "Run JavaScript in the page and return the value of its last expression. For what the other browser_ tools can't do: scrolling, going back (history.back()), reading a link's href.",
		parameters: Type.Object({ code: Type.String({ description: "JavaScript; a promise is awaited" }) }),
		// All of it, never a shortened form: this is the one tool whose effect may not show in the window.
		// guard.ts sends the same code to the permission judge before it runs.
		summary: (args) => (args.code?.includes("\n") ? `\n${args.code}` : args.code),
		async run(params, signal) {
			const open = await browser();
			const reply = await open.send("Runtime.evaluate", { expression: params.code, awaitPromise: true, returnByValue: true, userGesture: true }, await currentTab(open), signal);
			if (reply.exceptionDetails) throw new Error(problem(reply.exceptionDetails));
			// What cannot be sent as data (a function, an element) is at least named.
			const value = "value" in reply.result ? reply.result.value : (reply.result.description ?? null);
			return textResult(typeof value === "string" ? value : JSON.stringify(value, null, 1));
		},
	});

	tool({
		name: "tabs",
		description: "List the browser's tabs, open a new one, switch to one or close one. The * marks the tab you are driving.",
		parameters: Type.Object({
			action: StringEnum(["list", "new", "select", "close"] as const),
			index: Type.Optional(Type.Number({ description: "Tab number from the list (select, close)" })),
			url: Type.Optional(Type.String({ description: "http(s) URL to open (new, required)" })),
		}),
		summary: (args) => [args.action, args.index, args.url].filter((part) => part !== undefined).join(" "),
		async run(params, signal) {
			const url = params.action === "new" ? await webUrl(params.url ?? "") : undefined;
			const open = await browser();
			const picked = async () => {
				const found = (await tabList(open))[(params.index ?? 0) - 1];
				if (!found) throw new Error(`No tab ${params.index}: list the tabs first`);
				return found;
			};
			if (params.action === "new") {
				await go(open, await openTab(open, signal), url ?? "", signal);
			} else if (params.action === "select") {
				const found = await picked();
				tab = found.session;
				await open.send("Target.activateTarget", { targetId: found.target }, undefined, signal);
			} else if (params.action === "close") {
				const found = await picked();
				await open.send("Target.closeTarget", { targetId: found.target }, undefined, signal);
				for (let tries = 0; tabs.has(found.session) && tries < 50; tries++) await sleep(10);
			}
			const driven = await currentTab(open);
			return textResult((await tabList(open)).map((page, i) => `${i + 1}${page.session === driven ? " *" : ""} ${page.url}`).join("\n"));
		},
	});

	const apply = (ctx: ExtensionContext) => {
		if (!ctx.hasUI) return;
		const others = pi.getActiveTools().filter((name) => !tools.includes(name));
		pi.setActiveTools(enabled ? [...others, ...tools] : others);
		ui = ctx.ui;
		animated = ctx.mode === "tui";
		showStatus();
	};

	pi.on("session_start", async (_event, ctx) => apply(ctx));
	pi.on("session_shutdown", async () => {
		await stop();
		ui = undefined;
	});

	pi.registerCommand("browser", {
		description: "Toggle the browser tools: the agent drives a fresh browser of its own. /browser watch: pane beside pi or a real window. /browser allow host:port: let it reach a local address this session",
		handler: async (args, ctx) => {
			const save = () => {
				try {
					writeFileSync(STATE_FILE, `${JSON.stringify({ enabled, watch })}\n`);
				} catch {
					// Still applies to this session; it just won't be remembered.
				}
			};
			const [word, what = ""] = String(args ?? "").trim().split(/\s+/);
			if (word === "allow") {
				// Mine to give, and only until the session ends: the agent cannot run commands.
				if (!/^[^\s:/]+:\d+$/.test(what)) return ctx.ui.notify(`/browser allow host:port, for example localhost:5173. Allowed now: ${[...allowed].join(", ") || "nothing local"}`, "info");
				allowed.add(what.toLowerCase());
				return ctx.ui.notify(`The browser may reach ${what.toLowerCase()} until this session ends`, "info");
			}
			if (word === "watch") {
				const wasOpen = link?.alive() === true;
				watch = !watch;
				save();
				// A window cannot lose or gain its screen while it runs, so it starts again in the new way.
				await stop();
				const again = wasOpen ? " (the browser was closed; it reopens on the agent's next browser_ call)" : "";
				ctx.ui.notify((watch ? "Browser watch on: no window, the page shows in a pane beside pi" : "Browser watch off: the agent's browser is a window again") + again, "info");
				return;
			}
			enabled = !enabled;
			save();
			apply(ctx);
			if (!enabled) await stop();
			ctx.ui.notify(enabled ? "Browser on: the agent gets a fresh, empty browser of its own" : "Browser off", "info");
		},
	});
}
