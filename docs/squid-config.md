# Squid configuration report (from squid-config.log)

This report lists the **enabled/built** modules and helpers based on the configure log, including auto-detected submodules. Line references are **log line numbers** in `squid-config.log`.

## Build configuration

- Static build, loadable modules disabled (compiled-in features only). (squid-config.log:7)
- Configure options recorded in `SQUID_CONFIGURE_OPTIONS` confirm requested feature set. (squid-config.log:2763)

## Authentication helpers (built vs. not buildable)

- Authentication support enabled. (squid-config.log:7782)

### auth/basic

- **Helpers built**: `DB`, `NCSA`, `POP3`, `RADIUS`, `SMB`, `fake`, `getpwnam`. (squid-config.log:8968)
- **Found but cannot be built**: `LDAP`, `NIS`, `PAM`, `SASL`, `SSPI`. (squid-config.log:7784, 8341, 8544, 8545, 8953)

### auth/digest

- **Helpers built**: `file`. (squid-config.log:8972)
- **Found but cannot be built**: `LDAP`, `eDirectory`. (squid-config.log:8970, 8971)

### auth/negotiate

- **Helpers built**: none (explicitly checked as "no"). (squid-config.log:8974)

### auth/ntlm

- **Helpers built**: none (explicitly checked as "no"). (squid-config.log:8976)

## Other helpers

- **log helpers built**: `DB`, `file`. (squid-config.log:8978)
- **external ACL helpers**: disabled / none built. (squid-config.log:9187, 9188)
- **URL rewriters built**: `LFS`, `fake`. (squid-config.log:9189, 9190)
- **cert validators built**: `fake`. (squid-config.log:9191, 9192)
- **cert generators built**: `file` (ssl_crtd uses this). (squid-config.log:9193, 9194)
- **store ID rewriters built**: `file`. (squid-config.log:9195, 9196)

## Internal (non-helper) features

### Storage and I/O

- Store modules built: `aufs`, `diskd`, `rock`, `ufs`. (squid-config.log:2927)
- Removal policies built: `lru`. (squid-config.log:2928)
- Disk I/O enabled with AIO (`USE_DISKIO`, `HAVE_AIO_H`). (squid-config.log:3030, 3031)

### Core protocols and subsystems

- ICMP enabled. (squid-config.log:2929)
- Delay pools enabled. (squid-config.log:2930)
- Cache digests enabled. (squid-config.log:7162)
- WCCP enabled. (squid-config.log:2931)
- WCCPv2 enabled. (squid-config.log:2932)
- SNMP enabled. (squid-config.log:2933)
- HTCP enabled. (squid-config.log:2935)
- EUI (MAC address) controls disabled. (squid-config.log:2934)
- X-Forwarded-For support disabled. (squid-config.log:7780)
- Poll syscall for net I/O enabled. (squid-config.log:7164)

### Adaptation (ICAP/eCAP)

- ICAP client enabled. (squid-config.log:3044)
- Adaptation enabled. (squid-config.log:3046)
- eCAP disabled. (squid-config.log:3045)

### TLS/SSL

- OpenSSL library support enabled. (squid-config.log:3796)
- OpenSSL API usage enabled (`USE_OPENSSL`). (squid-config.log:3337)
- SSL feature requested via configure options; cert generator helper built (`file`). (squid-config.log:7, 9193)

## Requested but not explicitly confirmed in the log

The configure options include `--enable-carp`, but there is no later explicit confirmation line showing CARP enabled. (squid-config.log:7)
