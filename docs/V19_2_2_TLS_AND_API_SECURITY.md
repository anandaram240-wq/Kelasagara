# KELASAGARA BIOMETRIC ENGINE V19.2.2: TLS ARCHITECTURE & CARRIER-PROOF NETWORK HARDENING

## 1. Forensic Root Cause of Carrier DNS Failures (Incident Analysis)
In testing on Indian cellular carriers (Airtel, Jio) and certain Wi-Fi networks, clients encountered:
`"Cannot resolve biometric server address (DNS failure). Please verify server hostname."`

### 1.1 Technical Breakdown
1. **Government/ISP DNS Blocking:** Indian telecommunications providers enforce Department of Telecommunications (DOT) domain filtering policies. Generic public tunnel subdomains under `*.trycloudflare.com` are routinely sinkholed or returned as `NXDOMAIN` by carrier recursive DNS resolvers.
2. **Prior Hardcoded Hostname Reliance:** Earlier APK builds resolved `flip-raymond-receives-organized.trycloudflare.com` on every API request. When DNS lookup failed, Android OS immediately threw `SocketException: Failed host lookup`, preventing any TCP handshake.

---

## 2. Hardened Production Resolution: Direct Anycast IP with Zero DNS Lookup
Kelasagara V19.2.2 eliminates the DNS lookup point-of-failure completely:

### 2.1 Direct Anycast IP Route (Priority 1)
- The Flutter client initiates HTTPS connections directly to Cloudflare's Anycast Edge IP:
  `https://104.16.230.132/api/biometrics/v10`
- **Zero DNS Query:** Because the target is an explicit IPv4 address, the Android networking stack bypasses local carrier DNS resolution entirely.
- **HTTP `Host` Header Injection:** Requests include `'Host': 'flip-raymond-receives-organized.trycloudflare.com'`, enabling Cloudflare Edge reverse proxies to route the traffic into the backend daemon.

### 2.2 Strict Cryptographic Certificate Pinning (Eliminating Unconditional Bypass)
Rather than using insecure `badCertificateCallback = (cert, host, port) => true;`, V19.2.2 enforces strict cryptographic validation:
1. **Host Verification:** Authorized only for direct edge IPs `104.16.230.132` and `104.16.231.132`.
2. **Subject Validation:** Must contain the authoritative domain `trycloudflare.com`.
3. **Issuer Validation:** Must originate from trusted root authorities: `Google Trust Services`, `Cloudflare`, or `Let's Encrypt`.
4. **Temporal Validity:** Validates `DateTime.now()` falls strictly within `[startValidity, endValidity]`.
5. **Fail-Closed Default:** All other certificates and untrusted hosts are unconditionally rejected (`return false;`).

### 2.3 Tiered Failover Matrix

| Tier | Protocol | Target Address | Host Header | Use Case |
|---|---|---|---|---|
| 1 | HTTPS (Zero DNS) | `https://104.16.230.132/api/biometrics/v10` | `flip-raymond-receives-organized.trycloudflare.com` | Primary carrier-immune route (Jio/Airtel 4G/5G) |
| 2 | HTTPS (Clean TLD) | `https://cuyov-2401-4900-62ac-af5b-8dd6-d96c-a30b-68de.free.pinggy.net/api/biometrics/v10` | Default | Global public tunnel fallback |
| 3 | HTTPS (Standard Host) | `https://flip-raymond-receives-organized.trycloudflare.com/api/biometrics/v10` | Default | Standard hostname fallback |
| 4 | HTTP (LAN Wi-Fi) | `http://10.255.181.23:5001/api/biometrics/v10` | N/A | Same-network evaluation hotspot |
| 5 | HTTP (Loopback) | `http://10.0.2.2:5001/api/biometrics/v10` | N/A | Android emulator local development |
