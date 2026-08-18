#!/bin/sh
#
# Build CUPS 1.5.4 for SCO OpenServer 5.
#
#   sh build.sh /path/to/cups-source-tree
#
# Requires, on the SCO box:
#   * gcc 3.4.6 as /usr/local/bin/gcc-3.4.6   (the C compiler)
#   * g++ 2.95.3 as /usr/gnu/bin/g++          (C++: ppdc and cups-driverd only)
#   * GNU make as /usr/gnu/bin/gmake
#   * the gwxlibs component (libjpeg/libpng/libtiff/libslp)
#
# The two compilers really are different versions.  /usr/local/bin/gcc-3.4.6
# was built without cc1plus so it cannot compile C++, and the gcc on the
# default PATH is Skunkware 2.95.3 which is too old for the C.  Mixing is safe
# here: CUPS's C++ uses no STL, templates or namespaces, and no C++ objects
# cross the compiler boundary.
#
# The source tree must already have the patches from patches/ applied and a
# generated ./configure -- see README.md, "Building from source".

set -e

SRC=$1
PREFIX=${PREFIX:-/usr/local/cups154}
GS=${GS:-/usr/local/bin/gs}

if [ -z "$SRC" ] || [ ! -f "$SRC/config-scripts/cups-common.m4" ]; then
	echo "usage: sh build.sh /path/to/cups-source-tree" >&2
	exit 1
fi

cd "$SRC"

if [ ! -f ./configure ]; then
	cat >&2 <<'NOCONF'
ERROR: ./configure is missing.

The GitHub archive for release-1.5.4 ships only configure.in, and OpenServer's
autoconf is 2.54 -- far too old to regenerate it.  Generate it on a modern
machine (autoconf 2.71 works) and copy it across:

    autoconf && scp configure sco-box:/path/to/tree/

NOCONF
	exit 1
fi

PATH=/usr/local/bin:/bin:/usr/bin:/etc:/sbin:/usr/gnu/bin:/usr/ccs/bin
export PATH

echo "Configuring (prefix $PREFIX, ghostscript $GS) ..."

# --- why each of these is here -----------------------------------------------
# ac_cv_search_getaddrinfo/getnameinfo=no
#     A box with a maintenance pack has MP5's rs507d.tcp211 TCP stack, which
#     provides these; a base 5.0.7 install does NOT.  Building with them makes
#     binaries that die at run time on stock boxes with "symbol not found:
#     getnameinfo" -- and because OpenServer binds lazily, it surfaces late and
#     at random.  Forcing CUPS's gethostbyname fallback makes one build work
#     everywhere.  OpenServer has no IPv6, so nothing is lost.
#     NOTE: these are AC_SEARCH_LIBS, so the cache names are ac_cv_search_*,
#     NOT the ac_cv_func_* you would expect.
# --disable-threads   no pthreads on OpenServer 5.
# --disable-ssl       the only OpenSSL here is 0.9.7i (2005).  Means no ipps://.
# --disable-ldap      the build box may have OpenLDAP; target boxes do not.
# --disable-dnssd     no Bonjour/Avahi.
# --disable-libusb    no libusb, and the usb backend is dropped anyway.
# --with-pdftops      wires in Ghostscript 9.06 -- this is what gives 1.5.4
#                     modern PDF printing, which CUPS 1.1.23 cannot do at all.
CC=gcc-3.4.6 CXX=g++ \
ac_cv_search_getaddrinfo=no ac_cv_search_getnameinfo=no \
/bin/sh ./configure \
	--prefix="$PREFIX" \
	--disable-threads --disable-ssl --disable-gssapi --disable-dbus \
	--disable-dnssd --disable-libusb --disable-pam --disable-ldap \
	--disable-libpaper --disable-acl --disable-launchd \
	--with-pdftops="$GS"

echo "Building ..."
/usr/gnu/bin/gmake

cat <<DONE

Built.  To stage an install tree for packaging:

    /usr/gnu/bin/gmake BUILDROOT=/tmp/stage install

then see packaging/pkgsrc/make-pkg.sh.

To install straight onto this machine instead:

    /usr/gnu/bin/gmake install

DONE
