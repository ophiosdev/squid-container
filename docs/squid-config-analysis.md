# Squid config log analysis notes (process + evidence map)

This file captures **how the analysis was performed** and the **evidence map** used to determine enabled features and helpers from `squid-config.log`. It is designed so the work can be repeated without starting from scratch.

## 1) Data source and scope

- Input file: `squid-config.log`
- Goal: enumerate **eventually enabled/built** features and **built helper submodules** (not just configure flags).
- Principle: prefer **configure summary lines** (e.g., “helpers to be built”, “enabled: yes”) over configure command flags.
- Line numbers in all findings are **log line numbers** (1-based, as reported by Aleph).

## 2) Method (repeatable)

1. Load the log into Aleph:
   - Context id used: `squidcfg`
2. Identify **definitive summary lines**:
   - Patterns like:
     - `helpers to be built:`
     - `enabled:`
     - `support enabled:`
     - `Store modules built:`
     - `Removal policies to build:`
3. Cross-check against **"found but cannot be built"** lines to explain missing helpers.
4. For internal features, prefer **explicit “enabled: yes/no”** lines or **preprocessor defines** (`#define USE_*`, etc.).
5. Flag items that were only **requested** via configure options but had **no explicit confirmation**.

## 3) Evidence map: helpers and submodules

### Authentication support

- Authentication support enabled: `configure:40368` (line 7782)

#### auth/basic

- Helpers built: `DB NCSA POP3 RADIUS SMB fake getpwnam` (line 8968)
- Found but cannot be built:
  - LDAP (line 7784)
  - NIS (line 8341)
  - PAM (line 8544)
  - SASL (line 8545)
  - SSPI (line 8953)

#### auth/digest

- Helpers built: `file` (line 8972)
- Found but cannot be built:
  - LDAP (line 8970)
  - eDirectory (line 8971)

#### auth/negotiate

- Helpers built: none (line 8974)

#### auth/ntlm

- Helpers built: none (line 8976)

### Other helpers

- log helpers built: `DB file` (line 8978)
- external ACL helpers: none (checked `no` line 9187; built list empty line 9188)
- URL rewriters built: `LFS fake` (line 9190; checked line 9189)
- cert validators built: `fake` (line 9192; checked line 9191)
- cert generators built: `file` (line 9194; checked line 9193)
- store ID rewriters built: `file` (line 9196; checked line 9195)

## 4) Evidence map: internal (non-helper) features

### Storage / I/O

- Store modules built: `aufs diskd rock ufs` (line 2927)
- Removal policies: `lru` (line 2928)
- Disk I/O with AIO enabled:
  - `#define USE_DISKIO 1` (line 3030)
  - `#define HAVE_AIO_H 1` (line 3031)

### Core protocols and subsystems

- ICMP enabled (line 2929)
- Delay pools enabled (line 2930)
- Cache digests enabled (line 7162)
- WCCP enabled (line 2931)
- WCCPv2 enabled (line 2932)
- SNMP enabled (line 2933)
- HTCP enabled (line 2935)
- EUI controls disabled (line 2934)
- X-Forwarded-For support disabled (line 7780)
- Poll syscall for net I/O enabled (line 7164)

### Adaptation (ICAP/eCAP)

- ICAP client enabled: `#define ICAP_CLIENT 1` (line 3044)
- Adaptation enabled: `#define USE_ADAPTATION 1` (line 3046)
- eCAP disabled: `#define USE_ECAP 0` (line 3045)

### TLS/SSL

- OpenSSL library support enabled: `OpenSSL library support: yes` (line 3796)
- OpenSSL API usage enabled: `#define USE_OPENSSL 1` (line 3337)
- Cert generator helper built: `file` (line 9194)

## 5) Configure options vs. confirmed status

- Configure options include `--enable-carp`, but **no explicit confirmation** exists later in the log.
  - Only appears in configure invocation / options (line 7 and `SQUID_CONFIGURE_OPTIONS` blocks).
  - Treated as “requested but not confirmed.”

## 6) Verification scan (what was checked)

The following patterns were verified by direct match against the log:

- Helper build lists (`helpers to be built:`) for auth/basic, auth/digest, auth/negotiate, auth/ntlm, log helpers.
- “found but cannot be built” lines for auth/basic and auth/digest helpers.
- External ACL helpers disabled (`checking acl/external helpers: no`) and empty build list.
- URL rewriters, cert validators, cert generators, store ID rewriters.
- Store modules built, removal policies, ICMP, delay pools, WCCP/WCCPv2, SNMP, HTCP, EUI, XFF, poll.
- AIO/disk I/O defines.
- ICAP/adaptation/eCAP defines.
- OpenSSL support line and `USE_OPENSSL` define.

## 7) Re-run guidance

If this analysis needs to be repeated:

1. Load `squid-config.log` in Aleph and search for `helpers to be built:` and `enabled:` lines.
2. Confirm helper failures using `found but cannot be built` lines.
3. Use `Store modules built`, `Removal policies to build`, and `USE_*` defines for internal features.
4. Treat configure options alone as **requests** unless confirmed later in the log.

## 8) Python/exec_python snippets used

### A) Summary-line verification (helpers + internal features)

```python
import re
lines = ctx.splitlines()
phrases = {
    'auth_basic_built': r"auth/basic helpers to be built:\\s+DB NCSA POP3 RADIUS SMB fake getpwnam",
    'auth_digest_built': r"auth/digest helpers to be built:\\s+file",
    'auth_negotiate_built': r"auth/negotiate helpers to be built:\\s*$",
    'auth_ntlm_built': r"auth/ntlm helpers to be built:\\s*$",
    'log_helpers_built': r"log helpers to be built:\\s+DB file",
    'external_acl_built': r"acl/external helpers to be built:\\s*$",
    'url_rewriters_built': r"http/url_rewriters helpers to be built:\\s+LFS fake",
    'cert_validators_built': r"security/cert_validators helpers to be built:\\s+fake",
    'cert_generators_built': r"security/cert_generators helpers to be built:\\s+file",
    'storeid_rewriters_built': r"store/id_rewriters helpers to be built:\\s+file",
    'store_modules_built': r"Store modules built:\\s+aufs diskd rock ufs",
    'removal_policies': r"Removal policies to build:\\s+lru",
    'icmp_enabled': r"ICMP enabled",
    'delay_pools_enabled': r"Delay pools enabled",
    'wccp_enabled': r"Web Cache Coordination Protocol enabled:\\s+yes",
    'wccpv2_enabled': r"Web Cache Coordination V2 Protocol enabled:\\s+yes",
    'snmp_enabled': r"SNMP support enabled:\\s+yes",
    'htcp_enabled': r"HTCP support enabled:\\s+yes",
    'eui_disabled': r"EUI \\(MAC address\\) controls enabled:\\s+no",
    'xff_disabled': r"Support for X-Forwarded-For enabled:\\s+no",
    'poll_enabled': r"enabling poll syscall for net I/O:\\s+yes",
    'cache_digests_enabled': r"Cache Digests enabled:\\s+yes",
    'diskio_aio': r"#define USE_DISKIO 1.*",
    'aio_h': r"#define HAVE_AIO_H 1",
    'icap_client': r"#define ICAP_CLIENT 1",
    'adaptation': r"#define USE_ADAPTATION 1",
    'ecap_disabled': r"#define USE_ECAP 0",
    'openssl_support': r"OpenSSL library support:\\s+yes",
    'use_openssl': r"#define USE_OPENSSL 1",
}

matches = {k: [] for k in phrases}
for i,l in enumerate(lines, start=1):
    for k,pat in phrases.items():
        if re.search(pat, l):
            matches[k].append((i,l))

# print first match for each key
out = []
for k,v in matches.items():
    if v:
        i,l = v[0]
        out.append(f"{k}: {i}: {l}")
    else:
        out.append(f"{k}: NOT FOUND")
print('\\n'.join(out))
```

### B) "Found but cannot be built" verification (auth helpers)

```python
import re
lines = ctx.splitlines()
phrases = {
    'auth_basic_ldap_not_buildable': r"helper auth/basic/LDAP .* found but cannot be built",
    'auth_basic_nis_not_buildable': r"helper auth/basic/NIS .* found but cannot be built",
    'auth_basic_pam_not_buildable': r"helper auth/basic/PAM .* found but cannot be built",
    'auth_basic_sasl_not_buildable': r"helper auth/basic/SASL .* found but cannot be built",
    'auth_basic_sspi_not_buildable': r"helper auth/basic/SSPI .* found but cannot be built",
    'auth_digest_ldap_not_buildable': r"helper auth/digest/LDAP .* found but cannot be built",
    'auth_digest_edir_not_buildable': r"helper auth/digest/eDirectory .* found but cannot be built",
    'auth_support_enabled': r"Authentication support enabled: yes",
    'external_acl_checked_no': r"checking acl/external helpers: no",
    'url_rewriters_checked': r"checking http/url_rewriters helpers: LFS fake",
    'cert_validators_checked': r"checking security/cert_validators helpers: fake",
    'cert_generators_checked': r"checking security/cert_generators helpers: file",
    'storeid_checked': r"checking store/id_rewriters helpers: file",
}

matches = {k: [] for k in phrases}
for i,l in enumerate(lines, start=1):
    for k,pat in phrases.items():
        if re.search(pat, l):
            matches[k].append((i,l))

out = []
for k,v in matches.items():
    if v:
        i,l = v[0]
        out.append(f"{k}: {i}: {l}")
    else:
        out.append(f"{k}: NOT FOUND")
print('\\n'.join(out))
```

### C) CARP confirmation check

```python
import re
lines = ctx.splitlines()
pat = re.compile(r'(?i)carp')
res = []
for i,l in enumerate(lines, start=1):
    if pat.search(l):
        res.append((i,l))
# show matches excluding configure options lines
filtered = [(i,l) for i,l in res if 'SQUID_CONFIGURE_OPTIONS' not in l and './configure' not in l]
print('total_matches:', len(res))
print('filtered_matches:', len(filtered))
print('\\n'.join([f"{i}: {l}" for i,l in filtered[:10]]))
```

## 9) Interpretation rules and pitfalls (important)

- **Configure options vs. final status**: `--enable-*` flags only show *requests*. Treat as confirmed **only** if later lines say “enabled: yes”, “helpers to be built”, or `#define USE_* 1`.
- **"configure:" line numbers are *not* log line numbers**: In `squid-config.log`, the embedded `configure:NNNN` values are internal script offsets. Use Aleph’s 1-based log line numbers for references.
- **Repeated `SQUID_CONFIGURE_OPTIONS` blocks**: These appear multiple times; they repeat the same flags and should not be mistaken for multiple confirmations.
- **"config.status: creating ..." is not a build result**: Makefile creation lines list possible subdirectories, not what actually built. Use “helpers to be built” lines to decide.
- **Static build with `--disable-loadable-modules`**: Anything enabled is compiled into the binary, not dynamically loaded. Confirmed in configure invocation (line 7).
- **Platform-specific helpers**: Several helpers are skipped because of missing headers/libs; these show as “found but cannot be built”. Treat those as explicitly **not built** even if helpers are listed as available in the source tree.
- **Empty build lists**: Lines like `auth/negotiate helpers to be built:` with nothing after the colon mean **none built** (not a parsing error).

## 10) Quick validation checklist

- Confirm one authoritative line per feature group (helpers, protocols, storage, SSL).
- Cross-check helper failures with “found but cannot be built”.
- Flag any feature that appears only in configure options as **requested but not confirmed**.
- Prefer summary lines (enabled/build lists) over raw `#define` where both exist.

## 11) Autoconf context

- `squid-config.log` is an **Autoconf `configure` transcript** (generated by GNU Autoconf from `configure.ac`/`configure.am`).
- This means most authoritative outcomes are reported via **summary lines** and **"result:"** lines emitted by Autoconf macros.

## 12) Additional targeted searches (Autoconf-style)

Use these regex patterns to discover other feature summaries not yet enumerated:

- `^configure:.*enabled:`
- `^configure:.*support enabled:`
- `^configure:.*support requested:`
- `^configure:.*helpers to be built:`
- `^configure:.*modules built:`
- `^configure:.*policies to build:`
- `^configure:.*checking .* helpers:`
- `^configure:.*result: (yes|no)$`
- `^configure:.*result: .*` (general result lines)
- `^\| #define USE_[A-Z0-9_]+ 1` (final preprocessor defines for enabled features)
- `^\| #define HAVE_[A-Z0-9_]+ 1` (capability detection)

Tip: prioritize matches that **summarize a decision** (“enabled”, “to be built”, “result: yes/no”) over raw `checking` lines.
