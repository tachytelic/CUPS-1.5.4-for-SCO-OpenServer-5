# CUPS 1.5.4 for SCO OpenServer 5

A working build of [CUPS](https://www.cups.org/) **1.5.4** (July 2012) for
**SCO OpenServer 5.0.7** — replacing the 1.1.23 that SCO shipped in
Maintenance Pack 4, which dates from **January 2005**.

```
$ lpstat -r
scheduler is running

$ lpadmin -p hp477 -v ipp://192.0.2.50/ipp/print \
          -m drv:///sample.drv/generic.ppd -E

$ lp -d hp477 invoice.pdf          # a modern PDF, on a 2005 operating system
request id is hp477-1 (1 file(s))
```

Verified end to end on OpenServer 5.0.7: queue creation, printing a PDF to an
HP PageWide Pro 477dw over IPP, and the web interface.

## Why 1.5.4?

Because it is the **last release before CUPS 1.6 gutted it** for this use case.
Measured from the actual source trees:

| | 1.1.23 (SCO's) | **1.5.4** | 1.6+ |
|---|---|---|---|
| `parallel`, `serial` backends | yes | **yes** | **removed** |
| `imagetops`, `imagetoraster`, `texttops`, `pstops` | yes | **yes** | **removed** |
| `pdftops` | **no** | **yes** | removed |
| `scsi` backend, `hpgltops` | yes | no | no |

CUPS 1.6 moved almost every filter out to *cups-filters*, a separate project
that depends on Poppler — modern C++, which gcc 3.4.6 will not build. A 1.6+
build on OpenServer could not print a text file, an image or a PDF.

1.5.4 keeps everything 1.1.23 had except the SCSI backend and HP-GL/2, and
**adds `pdftops`** — which is the whole point.

## The headline: modern PDF printing

CUPS 1.1.23 has no PDF filter at all. 1.5.4's `configure` takes
`--with-pdftops=/path/to/gs`, so this build wires in
[Ghostscript 9.06 for OpenServer](https://github.com/tachytelic/Ghostscript-9.06-for-SCO-OpenServer-5),
giving the filter chain

    PDF -> pdftops -> gs 9.06 -> pstops -> backend

SCO's stock path rasterises through **ESP Ghostscript 7.07** (2003), which
chokes on anything modern.

## Install

```sh
curl -LO https://github.com/tachytelic/CUPS-1.5.4-for-SCO-OpenServer-5/releases/download/v1.0.0/cups154-1.5.4.pkg.gz
gunzip cups154-1.5.4.pkg.gz
pkgadd -d cups154-1.5.4.pkg cups154
/usr/local/cups154/sbin/cupsd
```

`pkgadd` needs the package uncompressed, hence the `gunzip` step.

It installs entirely under `/usr/local/cups154` and does **not** touch SCO's
own `cups` component, so it can sit alongside a stock install. The postinstall
handles the OpenServer-specific setup — see below for what and why.

Remove with `pkgrm cups154`.

### Prerequisites

- The **gwxlibs** component (libjpeg/libpng/libtiff/libslp), which
  `libcupsimage` needs. SCO's own cups component depends on it too.
- **Ghostscript 9.06** at `/usr/local/bin/gs` if you want to print PDFs.
  Without it everything else still works.

## Important: `lp` still means the SVR4 spooler

Installing this package does **not** change what `lp` does. Plain `lp`
resolves to `/usr/bin/lp` — SCO's SVR4 spooler — and OpenServer keeps
`lpsched` running independently. To make `lp`, `lpstat` and `lpr` mean CUPS:

```sh
PATH=/usr/local/cups154/bin:/usr/local/cups154/sbin:$PATH; export PATH
```

That is enough for anything that resolves `lp` through `PATH`, which includes
most applications that shell out to print. **Anything calling `/usr/bin/lp` by
absolute path is unaffected** — a lot of SVR4-era business software does, so
check before assuming a PATH change is sufficient.

## What the postinstall does, and why

Each of these is a real trap found the hard way. All are idempotent.

1. **`chmod 755 /usr/local/bin`** — it ships `drwx------` on some installs, so
   the unprivileged `lp` user cannot execute anything in it. Symptom: `Unable
   to execute gs program: Permission denied` and a zero-byte print job.

2. **Wraps `gs`** so it finds `libXt`/`libX11` in `/usr/X11R6/lib`, which is
   not on the default runtime library search path. Skipped if gs already runs.

3. **Removes the `Listen .../cups.sock` line from `cupsd.conf`.** This is the
   important one. On OpenServer, CUPS does not treat a UNIX-domain-socket peer
   as local, so `Allow localhost` never matches *and* local certificate
   authentication fails — admin operations return `Forbidden` or
   `Unauthorized`. Over TCP loopback everything works. Reproduced on two
   independent boxes, one with no resolver configured at all, so it is not a
   DNS artefact.

4. **Adds `ServerAlias localhost` and `ServerName <host>`.** CUPS 1.5 validates
   the `Host:` header strictly (DNS-rebinding protection); without the alias
   every request is `Bad Request`. Without `ServerName`, generated URLs read
   `UNKNOWN:631`.

5. **Adds `Allow all` to the `<Location>` blocks.** Safe *only* because
   `Listen` is loopback-only. **Revisit this before exposing cupsd on a real
   interface.**

The original config is kept as `cupsd.conf.pre-cups154`.

## Choosing a protocol

For a network printer, prefer **IPP** (`ipp://ADDR/ipp/print`) over JetDirect
(`socket://ADDR:9100`) unless you have a reason not to. JetDirect is a raw byte
pipe with no status channel — CUPS gets printer state over SNMP instead, so if
the printer has SNMP disabled you get no feedback at all: no job state, no
supply levels, no out-of-paper. IPP carries that itself.

This build has no TLS (`--disable-ssl`), so `ipps://` will not work. Plain IPP
is fine on most printers — check `uri-security-supported` includes `none`.

## Building from source

```sh
# On a modern machine: fetch, patch, and generate configure.
curl -LO https://github.com/apple/cups/archive/refs/tags/release-1.5.4.tar.gz
tar xzf release-1.5.4.tar.gz && cd cups-release-1.5.4
for p in ../patches/*.patch; do git apply "$p" || patch -p1 < "$p"; done
autoconf                       # OpenServer's autoconf 2.54 is too old

# Copy the tree to the SCO box, then:
sh build.sh /usr/local/src/cups-release-1.5.4
```

`build.sh` documents every configure flag and why it is there. The
non-obvious ones:

- **`ac_cv_search_getaddrinfo=no ac_cv_search_getnameinfo=no`** — a box with a
  maintenance pack has MP5's `rs507d.tcp211` TCP stack, which provides these
  calls; a **base 5.0.7 install does not**. Building with them yields binaries
  that die at run time on stock boxes with `symbol not found: getnameinfo`,
  and because OpenServer binds lazily it surfaces late and unpredictably.
  Forcing CUPS's `gethostbyname` fallback makes one build work everywhere, and
  OpenServer has no IPv6 so nothing is lost. (These are `AC_SEARCH_LIBS`, so
  the cache variables are `ac_cv_search_*`, **not** `ac_cv_func_*`.)
- **Two different compilers.** C is gcc 3.4.6; C++ (`ppdc`, `cups-driverd`) is
  g++ 2.95.3, because the 3.4.6 install has no `cc1plus`. Safe here — CUPS's
  C++ uses no STL, templates or namespaces, and no C++ objects cross the
  boundary.

A useful trick when checking portability: `LD_BIND_NOW=1 <binary>` on a stock
target forces full symbol resolution at startup and surfaces every missing
symbol at once, instead of one build cycle at a time.

## The patches

| | |
|---|---|
| `0001` | SCO OpenServer backend support, forward-ported from SCO's own 1.1.23 source drop (`_SCO_DS` device enumeration for parallel and serial) |
| `0002` | drop the `usb` backend from the build — it is the only part wanting SCO HDK headers |
| `0003` | don't assume `getaddrinfo` implies `AF_INET6`. CUPS guards every `AF_INET6` reference except the two in the `HAVE_GETADDRINFO` path; OpenServer has getaddrinfo but no IPv6 |
| `0004` | fall back to `int` when `socklen_t` is missing — CUPS uses it unconditionally and never checks; OpenServer predates POSIX 2001 |
| `0005` | use the SVR4 shared-library flags on SCO — `SCO_SV` fell through to `-Wl,-soname -shared`, which SCO's `i386ld` rejects |
| `0006` | embed an SVR4 runpath. Without it, `/usr/lib/libcups.so.2` (a symlink to SCO's stock 1.1.23) silently wins at run time |

0003 and 0004 are genuine upstream portability bugs, not SCO quirks.

## Documentation

- [docs/INSTALL.md](docs/INSTALL.md) — install prerequisites and every
  required config change, in full
- [docs/cupsd.conf.example](docs/cupsd.conf.example) — a known-good config

## Licence

GPLv2 / LGPLv2, same as CUPS itself. See [LICENSE](LICENSE).

## See also

- [Ghostscript 9.06 for SCO](https://github.com/tachytelic/Ghostscript-9.06-for-SCO-OpenServer-5)
  — install this first if you want to print PDFs; it is what `pdftops` calls.
- [a2ps 4.14 for SCO](https://github.com/tachytelic/a2ps-4.14-for-SCO-OpenServer-5)
  — text/source → PostScript, the natural way to feed a queue from a script.
- [curl 7.88.1 for SCO](https://github.com/tachytelic/curl-7.88.1-for-SCO-OpenServer-5)
  — the first install on a fresh SCO box.
- [VirtIO drivers for SCO on Proxmox/QEMU](https://github.com/tachytelic/sco-openserver-proxmox)
  — if you are running OpenServer as a VM.
- [More SCO OpenServer 5 binaries](https://tachytelic.net/2017/07/sco-openserver-5-binaries/)
  — the hub.
