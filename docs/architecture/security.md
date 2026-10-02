# Security Architecture

## 1. Trust boundaries

| Boundary | Threat | Control |
| --- | --- | --- |
| Internet → gateway | Eavesdropping, abuse | TLS (Caddy), rate limits, body size limits |
| Client → API | Impersonation, privilege escalation | EdDSA JWT, per-action policy (ADR-0009), non-disclosing `404` |
| API → database | Cross-tenant leakage through application bugs | RLS with fail-closed tenant context, least-privilege runtime role (ADR-0002) |
| Device → MQTT | Injected or spoofed readings | Per-device credentials, topic ACLs, payload validation |
| Service → service | Forged events | Private network; only core produces `shipment.events`; hash chain makes tampering detectable |
| Platform → IPFS | Document disclosure | Envelope encryption before upload (ADR-0013) |
| Platform → chain | Key theft, nonce races | Relayer-only key custody, role-restricted contract, nonce lock (ADR-0015) |
| Public portal | Label cloning, scraping | Signed serials, scan analytics, rate limits (ADR-0016) |

## 2. Cryptography inventory

| Purpose | Algorithm | Key and secret source |
| --- | --- | --- |
| Password storage | Argon2id (m=19 MiB, t=2, p=1, 16-byte salt) | — |
| Access tokens | EdDSA (Ed25519) JWT, 15 min | `JWT_SIGNING_KEYS` (core only) |
| Refresh tokens | 256-bit random, stored as SHA-256; valid 7 days (`REFRESH_TOKEN_TTL`), rotated on every use | — |
| Pickup codes | 6-digit CSPRNG code, stored as HMAC-SHA256 | `PICKUP_CODE_PEPPER` |
| Event integrity | SHA-256 over RFC 8785 canonical JSON, hash-chained | — |
| Document encryption (M2) | AES-256-GCM, `VTENC1` chunked format; data keys wrapped with AES-256-GCM | `MASTER_KEYS` |
| Label signatures (M2) | HMAC-SHA256 truncated to 128 bits | Per-tenant keys wrapped with `MASTER_KEYS` |
| Merkle anchoring (M2) | keccak256 (OpenZeppelin standard tree) | — |
| Chain transactions (M2) | secp256k1 ECDSA | `RELAYER_PRIVATE_KEY` |
| Scan client fingerprint (M2) | Salted SHA-256 | `SCAN_FINGERPRINT_SALT` |

Every random value comes from `crypto/rand`. Secret comparisons use constant-time functions.

Access tokens carry the claims of ADR-0007. Their `jti` is the refresh session that issued them, so a password
change can revoke every other session of the user and keep the caller's own. A refresh token that is presented
again after its rotation revokes its whole family, and the reuse is logged as a warning.

Passwords have 12 to 128 characters (OWASP ASVS 2.1.1 and 2.1.2). Any characters are allowed and nothing is
trimmed. A hash made with older Argon2id parameters is replaced at the next successful login. The service
runs at most four hashes at a time, because each one holds 19 MiB.

## 3. Secrets handling

- Secrets are read only from the environment, or from files referenced by it in deployment. They are
  never read from source, migrations, images, or logs.
- `.env` files are git-ignored. Each repository commits a `.env.example` with placeholder values and
  generation hints.
- Versioned keys (`kid` for JWT, `master_key_id`, label `key_version`) allow rotation without downtime.
- `PICKUP_CODE_PEPPER` is base64 of at least 32 random bytes. Changing it voids every active pickup code.
- `JWT_SIGNING_KEYS` lists `<kid>:<base64 of 32 random bytes>` entries separated by commas. The first key signs,
  and the JWKS publishes all of them. To rotate, put a new key first; once the old key has signed nothing for
  15 minutes (the access token lifetime), remove it.

## 4. Logging rules

Never log:

- passwords, tokens, pickup codes, or keys;
- document contents;
- full request bodies of authentication endpoints;
- raw consumer IP addresses (M2).

Log instead `trace_id`, `tenant_id`, `user_id`, and identifiers (SSCC, GLN) where they are useful.

## 5. Dependency and supply chain

- Dependabot is enabled for Go modules, GitHub Actions, and Docker base images.
- CI runs `govulncheck`.
- Runtime images are distroless and non-root, with a read-only root filesystem where the service allows it.
