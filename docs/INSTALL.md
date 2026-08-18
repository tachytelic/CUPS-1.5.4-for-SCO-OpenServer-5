# Installing CUPS 1.5.4 on SCO OpenServer 5

Package: `dist/cups154-osr5.tar.gz` — self-contained under `/usr/local/cups154`,
nothing outside the prefix. Extract at `/`:

    cd / && gunzip -c cups154-osr5.tar.gz | tar xf -

## Prerequisites on the target

- **gwxlibs** — supplies libjpeg/libpng/libtiff/libslp, which libcupsimage needs.
- **Ghostscript 9.06** at `/usr/local/bin/gs` for the PDF path. The prebuilt
  binary needs `libXt`/`libX11` from `/usr/X11R6/lib`, which is NOT in the
  default runtime search path, so wrap it:

      mv /usr/local/bin/gs /usr/local/bin/gs.real
      cat > /usr/local/bin/gs <<'W'
      #!/bin/sh
      LD_LIBRARY_PATH=/usr/X11R6/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
      export LD_LIBRARY_PATH
      exec /usr/local/bin/gs.real "$@"
      W
      chmod 755 /usr/local/bin/gs

- **`chmod 755 /usr/local/bin`** — it ships `drwx------` on some installs, which
  stops the unprivileged `lp` user executing anything in it, including gs.

## cupsd.conf changes required

1. `ServerAlias localhost` — CUPS 1.5 validates the `Host:` header strictly
   (DNS-rebinding protection). Without this every request is "Bad Request",
   because reverse lookup of the client fails and it is logged as "UNKNOWN".
2. `ServerName <hostname>` — otherwise generated URLs say `UNKNOWN:631`.
3. **Delete the `Listen /usr/local/cups154/var/run/cups/cups.sock` line.** On
   OpenServer, CUPS does not treat a UNIX-domain-socket peer as local, so both
   `Allow localhost`/`Allow 127.0.0.1` matching AND local certificate
   authentication fail — admin operations return "Forbidden" or "Unauthorized".
   Over TCP loopback everything works. This is the single most important item.
4. `Allow all` inside the `<Location>` blocks. Safe only because `Listen` is
   `localhost:631`, so nothing off-box can reach it. Revisit before exposing
   cupsd on a real interface.
5. `FileDevice Yes` only if you want `file:` device URIs (test/debug).

## Verified on

- **VM 101 `scoscsi`** (192.168.250.248, prox2) — OSR 5.0.7 + MP (rs507d,
  40 entries), virtio-scsi, no CUPS component. Full pass.
- **sco-vmware `scosysv`** (10.1.1.13, ESXi) — MP5, stock CUPS 1.1.23 present;
  ran in parallel on port 6310 without disturbing it.

## Build note

Built with `ac_cv_search_getaddrinfo=no ac_cv_search_getnameinfo=no` on purpose.
The build box has MP5's `rs507d.tcp211.1.0a` TCP stack, which provides those two
calls; a base 5.0.7 install does NOT, and the binaries died at run time with
`symbol not found: getnameinfo` (lazy binding, so it surfaced late). Forcing the
`gethostbyname` fallback makes one package work on both. OSR5 has no IPv6, so
nothing is lost.
