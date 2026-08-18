#!/bin/sh
#
# Build cups154-<version>.pkg from a staged install tree.  Run this ON A SCO
# BOX -- pkgmk, pkgproto and pkgtrans are part of the OpenServer base system.
#
# Usage:  sh make-pkg.sh <staged-tree> [output.pkg]
#
# where <staged-tree> is the directory produced by
#     gmake BUILDROOT=/tmp/stage install
# in the CUPS source tree, i.e. it contains ./usr/local/cups154/...
#
# The prototype is generated rather than checked in: the tree is ~1100 files
# and hand-maintaining that list would rot immediately.

set -e

STAGE=$1
OUT=$2
HERE=`pwd`

if [ -z "$STAGE" ] || [ ! -d "$STAGE/usr/local/cups154" ]; then
	echo "usage: sh make-pkg.sh <staged-tree> [output.pkg]" >&2
	echo "  <staged-tree> must contain usr/local/cups154" >&2
	exit 1
fi

VERSION=`grep '^VERSION=' "$HERE/pkginfo" | sed 's/^VERSION=//'`
[ -z "$OUT" ] && OUT=/tmp/cups154-$VERSION.pkg

echo "Staging tree : $STAGE"
echo "Output       : $OUT"

# pkgmk wants the control files alongside the payload root.
cp "$HERE/pkginfo" "$HERE/postinstall" "$HERE/preremove" "$STAGE/"
chmod +x "$STAGE/postinstall" "$STAGE/preremove"

cd "$STAGE"

# The three control files are 'i' (information) entries; everything else is
# generated.  pkgproto reads a find(1) listing on stdin.
{
	echo "i pkginfo"
	echo "i postinstall"
	echo "i preremove"
	find usr -print | pkgproto
} > prototype

# pkgproto records whatever owner the staged files happen to have.  Normalise
# to root/sys so the package installs identically regardless of who built it.
sed -e 's/ [a-zA-Z0-9_][a-zA-Z0-9_]* [a-zA-Z0-9_][a-zA-Z0-9_]*$/ root sys/' \
	prototype > prototype.new && mv prototype.new prototype

echo "Prototype    : `wc -l < prototype` entries"

rm -rf /tmp/cups154-spool
mkdir -p /tmp/cups154-spool

pkgmk -o -r "$STAGE" -f prototype -d /tmp/cups154-spool
pkgtrans -s /tmp/cups154-spool "$OUT" cups154

# Tidy the control files back out of the staged tree.
rm -f "$STAGE/pkginfo" "$STAGE/postinstall" "$STAGE/preremove" "$STAGE/prototype"
rm -rf /tmp/cups154-spool

echo ""
echo "Built $OUT"
ls -l "$OUT"
echo ""
echo "Verify with:  pkginfo -d $OUT"
echo "Install with: pkgadd -d $OUT cups154"
