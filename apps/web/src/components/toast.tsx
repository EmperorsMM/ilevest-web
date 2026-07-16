"use client";

// Post-action feedback the operator was missing: a small toast that confirms
// an action landed (or explains why it didn't). Success auto-dismisses; errors
// stay until dismissed, since a refusal is worth reading. The database's own
// words are shown verbatim — they are written for humans.
import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from "react";

type Toast = { id: number; kind: "ok" | "err"; text: string };
type Ctx = { show: (kind: "ok" | "err", text: string) => void };

const ToastCtx = createContext<Ctx | null>(null);

export function useToast(): Ctx {
  const c = useContext(ToastCtx);
  if (!c) return { show: () => {} };
  return c;
}

export function ToastHost({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<Toast[]>([]);
  const show = useCallback((kind: "ok" | "err", text: string) => {
    const id = Date.now() + Math.random();
    setItems((x) => [...x, { id, kind, text }]);
    if (kind === "ok") setTimeout(() => setItems((x) => x.filter((t) => t.id !== id)), 3200);
  }, []);
  const dismiss = (id: number) => setItems((x) => x.filter((t) => t.id !== id));

  return (
    <ToastCtx.Provider value={{ show }}>
      {children}
      <div style={{ position: "fixed", left: 0, right: 0, bottom: 20, display: "flex",
                    flexDirection: "column", alignItems: "center", gap: 8, zIndex: 1000, pointerEvents: "none" }}>
        {items.map((t) => (
          <div key={t.id} onClick={() => dismiss(t.id)}
               style={{ pointerEvents: "auto", cursor: "pointer", maxWidth: 520, margin: "0 16px",
                        padding: "12px 16px", borderRadius: 10, fontSize: 14, lineHeight: 1.4,
                        color: "#fff", background: t.kind === "ok" ? "var(--cleared)" : "var(--red)",
                        boxShadow: "0 6px 24px rgba(0,0,0,0.18)" }}>
            {t.text}
          </div>
        ))}
      </div>
    </ToastCtx.Provider>
  );
}
