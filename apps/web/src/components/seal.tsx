// The Ilevest seal — the signature mark. A finely-drawn, static registry seal:
// concentric rings, a notched official rim, and a verification tick at the
// centre. It ties the abstract promise ("a sealed, tamper-evident record") to a
// concrete institutional symbol a buyer already trusts — a notary/registry
// stamp. Static and restrained by design (ratified): institutional, not
// gimmicky. One component, so the hero and the /verify certificate carry the
// identical mark.
//
// `tone`:
//   "brand"    — ink ring + green tick (marketing surfaces: hero)
//   "official" — monochrome ink, sober (trust surface: the certificate)

export default function Seal({
  size = 96,
  tone = "brand",
  label,
}: {
  size?: number;
  tone?: "brand" | "official";
  label?: string;
}) {
  const ring = tone === "official" ? "var(--ink)" : "var(--ink)";
  const tick = tone === "official" ? "var(--ink)" : "var(--green)";
  const faint = "var(--muted)";
  const notches = 48;

  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 100 100"
      role="img"
      aria-label={label ?? "Ilevest verification seal"}
      style={{ display: "block" }}
    >
      {/* notched official rim */}
      <g stroke={ring} strokeWidth="0.6" opacity={0.55}>
        {Array.from({ length: notches }).map((_, i) => {
          const a = (i / notches) * Math.PI * 2;
          const r1 = 47, r2 = 49.4;
          return (
            <line
              key={i}
              x1={50 + r1 * Math.cos(a)}
              y1={50 + r1 * Math.sin(a)}
              x2={50 + r2 * Math.cos(a)}
              y2={50 + r2 * Math.sin(a)}
            />
          );
        })}
      </g>

      {/* concentric rings */}
      <circle cx="50" cy="50" r="45.5" fill="none" stroke={ring} strokeWidth="1.4" />
      <circle cx="50" cy="50" r="38" fill="none" stroke={ring} strokeWidth="0.7" opacity={0.7} />

      {/* circular legend text on the top arc; plain lettering, not crypto-styled */}
      <defs>
        <path id="sealArcTop" d="M 50 50 m -32 0 a 32 32 0 1 1 64 0" />
        <path id="sealArcBottom" d="M 50 50 m 32 0 a 32 32 0 1 1 -64 0" />
      </defs>
      <text fill={faint} style={{ fontFamily: "var(--sans)", fontSize: 5.4, letterSpacing: 1.6, fontWeight: 700 }}>
        <textPath href="#sealArcTop" startOffset="50%" textAnchor="middle">
          ILEVEST · VERIFIED
        </textPath>
      </text>
      <text fill={faint} style={{ fontFamily: "var(--sans)", fontSize: 5.4, letterSpacing: 2.2, fontWeight: 700 }}>
        <textPath href="#sealArcBottom" startOffset="50%" textAnchor="middle">
          EVIDENCE · SEALED
        </textPath>
      </text>

      {/* the verification tick — the heart of the mark */}
      <circle cx="50" cy="50" r="20" fill="none" stroke={tick} strokeWidth="1.2" opacity={0.9} />
      <path
        d="M 41 50.5 L 47.5 57 L 60 43"
        fill="none"
        stroke={tick}
        strokeWidth="3"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
