# Squid Container image

This repository builds a minimal Squid proxy container image, compiled from source as a **static build**.

The final container image is built `FROM scratch` and intentionally contains only what is required to run Squid (the Squid executable plus a tiny init wrapper and required runtime assets like CA certificates). From an ITSEC and vulnerability-management perspective, this design aims to reduce risk by minimizing the attack surface:

- Fewer packages means fewer CVEs: typical distro-based images carry a large set of OS packages (shells, coreutils, package managers, interpreters, libraries). Each additional component can introduce vulnerabilities and increases patch/upgrade workload. A `scratch` image eliminates almost all OS-level dependencies, so vulnerability scanners generally have far less “ambient” software to flag.
- Reduced post-exploitation tooling: if a process is compromised, an environment without a shell, package manager, and common utilities makes many common attacker workflows (dropping tools, running scripts, fetching and executing binaries via built-in utilities) harder. This is not a substitute for fixing the underlying vulnerability, but it can meaningfully limit what an attacker can do in practice.
- Clearer ownership of fixes: with a minimal runtime, most meaningful security exposure is in the application itself (Squid) and whatever code is statically linked into it. That makes vulnerability triage more actionable: track Squid and linked-library advisories, then rebuild and redeploy the image.

Important caveats for realistic risk management:

- “Static” does not mean “invulnerable”: if Squid or any statically linked dependency (e.g., TLS/crypto code) has a vulnerability, you still must rebuild to pick up the fix. Static linking changes *how* you patch, not *whether* you patch.
- Container hardening is only one layer: host kernel exposure, network configuration, and Squid configuration (ACLs, authentication, TLS settings) often dominate real-world risk. In particular, an “allow all clients” Squid config is effectively an open proxy and should be treated as high-risk outside of controlled environments.

## Repository layout

- `Dockerfile` — multi-stage build:
  - Builds Squid from source on Alpine with static linking enabled.
  - Produces a tiny `scratch` final image containing the Squid binary, a small init wrapper, a musl loader, and CA certificates.
- `docker-compose.yml` — example runtime config:
  - Runs the image as `squid:dev` with `network_mode: host`.
  - Persists `/var/cache/squid` in a named volume and mounts `./squid.conf` to `/etc/squid/squid.conf`.
- `squid-init.c` — small entrypoint wrapper compiled into the image as `/usr/sbin/squid-init`:
  - Ensures the cache directory exists.
  - Runs `squid -z` to initialize cache directories.
  - Starts Squid in the foreground (`-N`).
  - Supports overrides via flags and environment variables (`SQUID_BIN`, `SQUID_CONF`, `SQUID_CACHE_DIR`, `SQUID_PIDFILE`).
- `squid.conf` — example Squid configuration:
  - Listens on port `3128`.
  - Allows all clients (open proxy) and enables basic caching/logging settings.
  - Disables file rotation and logs to stderr.
- `docs/` — build/config evidence and notes:
  - `docs/squid-config.md` — summarized “what was enabled/built” report derived from the log.
  - `docs/squid-config-analysis.md` — repeatable analysis notes and evidence map for the report.

## Build and run

Build the image:

```bash
docker build -t squid:dev .
```

Run with Docker Compose:

```bash
docker compose up -d
```

## Notes / caveats

- `squid.conf` is intentionally permissive (it allows all clients). Tighten ACLs before using this outside local/testing environments.
- The included Compose file uses `network_mode: host`; adjust to a bridged network + published ports if you prefer container networking.
