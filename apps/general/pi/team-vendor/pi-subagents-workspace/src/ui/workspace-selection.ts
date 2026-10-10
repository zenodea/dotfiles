import type { Component } from "@earendil-works/pi-tui";

const VIEWPORT_TUI = Symbol.for("@earendil-works/pi-tui/viewport");
const installed = new WeakSet<object>();
type RuntimeObject = Record<PropertyKey, unknown>;
type RuntimeMethod = (this: RuntimeObject, ...args: unknown[]) => unknown;
type Scope = { root: Component; document: Component };
type Dispatch = { x: number; y: number; type: string; hit: boolean };
type Rect = { x: number; y: number; width: number; height: number };

function object(value: unknown): value is RuntimeObject {
  return value !== null && typeof value === "object";
}

function finite(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function fullscreen(owner: RuntimeObject): boolean {
  return owner.mode === "fullscreen" && owner[VIEWPORT_TUI] === true;
}

function rawRenderer(tui: RuntimeObject): RuntimeObject | undefined {
  const key = Symbol("workspace-selection-owner");
  let owner: RuntimeObject | undefined;
  try {
    if (!Reflect.set(tui, key, function (this: RuntimeObject) {
      owner = this;
      return this;
    })) return undefined;
    const probe = tui[key];
    if (typeof probe !== "function") return undefined;
    Reflect.apply(probe, tui, []);
    return object(owner) ? owner : undefined;
  } finally {
    Reflect.deleteProperty(owner ?? tui, key);
  }
}

function contains(value: unknown, x: number, y: number): boolean {
  if (!object(value)) return false;
  const rect = value as Partial<Rect>;
  return finite(rect.x) && finite(rect.y) && finite(rect.width) && finite(rect.height)
    && rect.width > 0 && rect.height > 0
    && x >= rect.x && x < rect.x + rect.width && y >= rect.y && y < rect.y + rect.height;
}

function documentScrollView(root: RuntimeObject, document: Component, x: number, y: number): RuntimeObject | undefined {
  const pending = [{ box: root, depth: 0, inDocument: false }];
  const seen = new Set<object>();
  let match: { scrollView: RuntimeObject; depth: number } | undefined;
  while (pending.length > 0) {
    const { box, depth, inDocument } = pending.pop()!;
    if (seen.has(box)) return undefined;
    seen.add(box);
    if (!contains(box.clip, x, y)) continue;
    if (!Array.isArray(box.children)) return undefined;
    const selected = box.component === document;
    if (selected && !contains(box.rect, x, y)) continue;
    const inside = inDocument || selected;
    if (inside && box.scrollView !== undefined && contains(box.rect, x, y)) {
      const scrollView = box.scrollView;
      if (!object(scrollView) || !finite(scrollView.scrollTop)
        || typeof scrollView.scrollBy !== "function" || !Array.isArray(box.scrollContentLines)) return undefined;
      if (!match || depth > match.depth) match = { scrollView, depth };
    }
    for (let index = box.children.length - 1; index >= 0; index--) {
      const child: unknown = box.children[index];
      if (!object(child)) return undefined;
      pending.push({ box: child, depth: depth + 1, inDocument: inside });
    }
  }
  return match?.scrollView;
}

function point(value: unknown): value is RuntimeObject & { row: number; col: number } {
  return object(value) && finite(value.row) && finite(value.col) && value.row >= 0 && value.col >= 0;
}

export function installWorkspaceSelectionScope(
  tui: unknown,
  scope: () => Scope | undefined,
): (() => void) | undefined {
  let owner: RuntimeObject;
  let originalPoint: RuntimeMethod;
  let originalDispatch: RuntimeMethod;
  let originalScrollPoint: RuntimeMethod;
  let pointDescriptor: PropertyDescriptor | undefined;
  let dispatchDescriptor: PropertyDescriptor | undefined;
  try {
    if (!object(tui) || !fullscreen(tui) || typeof scope !== "function"
      || typeof tui.getSelectionPoint !== "function" || typeof tui.getScrollSelectionPoint !== "function"
      || typeof tui.dispatchMouseToOverlay !== "function" || !("currentLayout" in tui)) return undefined;
    const raw = rawRenderer(tui);
    if (!raw || !fullscreen(raw) || installed.has(raw)
      || typeof raw.getSelectionPoint !== "function" || typeof raw.getScrollSelectionPoint !== "function"
      || typeof raw.dispatchMouseToOverlay !== "function" || !("currentLayout" in raw)) return undefined;
    if (raw.currentLayout !== undefined && (!object(raw.currentLayout) || !object(raw.currentLayout.root))) return undefined;
    owner = raw;
    originalPoint = raw.getSelectionPoint as RuntimeMethod;
    originalDispatch = raw.dispatchMouseToOverlay as RuntimeMethod;
    originalScrollPoint = raw.getScrollSelectionPoint as RuntimeMethod;
    pointDescriptor = Object.getOwnPropertyDescriptor(raw, "getSelectionPoint");
    dispatchDescriptor = Object.getOwnPropertyDescriptor(raw, "dispatchMouseToOverlay");
  } catch {
    return undefined;
  }

  let active = true;
  let recent: Dispatch | undefined;
  function dispatch(this: RuntimeObject, ...args: unknown[]): unknown {
    recent = undefined;
    const result = Reflect.apply(originalDispatch, this, args);
    try {
      const event = args[0];
      if (active && this === owner && object(event) && object(result)
        && finite(event.screenX) && finite(event.screenY)
        && typeof event.type === "string" && typeof result.hit === "boolean") {
        const recorded = { x: event.screenX, y: event.screenY, type: event.type, hit: result.hit };
        recent = recorded;
        queueMicrotask(() => { if (recent === recorded) recent = undefined; });
      }
    } catch {
      recent = undefined;
    }
    return result;
  }

  function selectionPoint(this: RuntimeObject, ...args: unknown[]): unknown {
    const original = Reflect.apply(originalPoint, this, args);
    try {
      const event = args[0];
      if (!active || this !== owner || args[1] !== undefined || !point(original) || original.scrollView !== undefined
        || !object(event) || !finite(event.x) || !finite(event.y) || !Number.isInteger(event.button)
        || event.release !== false || ((event.button as number) & 3) !== 0 || ((event.button as number) & 96) !== 0
        || !recent || recent.hit || recent.type !== "press" || recent.x !== event.x || recent.y !== event.y
        || !fullscreen(owner)) return original;
      const current = scope();
      const frame = owner.currentLayout;
      if (!current || !object(frame) || !object(frame.root) || owner.layoutRoot !== current.root
        || frame.root.component !== current.root) return original;
      const scrollView = documentScrollView(frame.root, current.document, event.x, event.y);
      if (!scrollView) return original;
      const bounded = Reflect.apply(originalScrollPoint, owner, [scrollView, event.x, event.y]);
      return point(bounded) && bounded.scrollView === scrollView ? bounded : original;
    } catch {
      return original;
    }
  }

  function restore(name: string, wrapper: RuntimeMethod, descriptor: PropertyDescriptor | undefined): void {
    try {
      if (Object.getOwnPropertyDescriptor(owner, name)?.value !== wrapper) return;
      if (descriptor) Object.defineProperty(owner, name, descriptor);
      else Reflect.deleteProperty(owner, name);
    } catch {}
  }

  const cleanup = (): void => {
    if (!active) return;
    active = false;
    recent = undefined;
    restore("getSelectionPoint", selectionPoint, pointDescriptor);
    restore("dispatchMouseToOverlay", dispatch, dispatchDescriptor);
    installed.delete(owner);
  };
  const patch = (name: string, wrapper: RuntimeMethod, descriptor: PropertyDescriptor | undefined): void => {
    Object.defineProperty(owner, name, {
      configurable: descriptor?.configurable ?? true,
      enumerable: descriptor?.enumerable ?? false,
      writable: descriptor && "value" in descriptor ? descriptor.writable : true,
      value: wrapper,
    });
  };
  try {
    patch("getSelectionPoint", selectionPoint, pointDescriptor);
    patch("dispatchMouseToOverlay", dispatch, dispatchDescriptor);
    installed.add(owner);
    return cleanup;
  } catch {
    cleanup();
    return undefined;
  }
}
