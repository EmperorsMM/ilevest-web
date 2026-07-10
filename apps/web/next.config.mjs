/** @type {import('next').NextConfig} */

// Security headers (hardening item 2.3). Applied to every route.
//
// The Content-Security-Policy is scoped to what the app actually needs:
//   - Supabase: API + Auth (https), realtime (wss), and storage for signed-URL
//     evidence viewing.
//   - Paystack: the inline payment popup (script + frame + api).
//   - Fonts + styles are self-hosted, so 'self' covers them; 'unsafe-inline' is
//     permitted for styles because the app uses inline style attributes.
// If a new third party is added, its origin must be added here or it will be
// blocked — that is the point of a CSP.

const SUPABASE = "https://*.supabase.co";
const SUPABASE_WSS = "wss://*.supabase.co";
const PAYSTACK = "https://*.paystack.co https://*.paystack.com";

const csp = [
  `default-src 'self'`,
  `script-src 'self' 'unsafe-inline' ${PAYSTACK}`,
  `style-src 'self' 'unsafe-inline'`,
  `img-src 'self' data: blob: ${SUPABASE} ${PAYSTACK}`,
  `font-src 'self' data:`,
  `connect-src 'self' ${SUPABASE} ${SUPABASE_WSS} ${PAYSTACK}`,
  `frame-src 'self' ${PAYSTACK}`,
  `object-src 'none'`,
  `base-uri 'self'`,
  `form-action 'self'`,
  `frame-ancestors 'self'`,
  `upgrade-insecure-requests`,
].join("; ");

const securityHeaders = [
  { key: "Content-Security-Policy", value: csp },
  { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains; preload" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "X-Frame-Options", value: "SAMEORIGIN" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
];

const nextConfig = {
  reactStrictMode: true,
  async headers() {
    return [{ source: "/:path*", headers: securityHeaders }];
  },
};

export default nextConfig;
