#!/usr/bin/env bash
# Generate a random Crockford Base32 string of a given length.
#
# Crockford Base32 (https://www.crockford.com/base32.html) uses the 32
# symbols 0-9 A-Z minus I, L, O and U -- chosen to avoid visual ambiguity
# (I/L vs 1, O vs 0) and accidental obscenity (U). Each output character
# encodes 5 bits.
#
# Randomness comes from /dev/urandom, one byte per output character. 256 is
# an exact multiple of 32, so `byte % 32` is uniform -- no modulo bias.
#
# Usage:  secrets/gen-crockford-base32.sh <length>
# e.g.    secrets/gen-crockford-base32.sh 26
set -euo pipefail

alphabet='0123456789ABCDEFGHJKMNPQRSTVWXYZ'

length=${1:-}
if ! [[ $length =~ ^[1-9][0-9]*$ ]]; then
  echo "usage: $0 <length>   (length: positive integer)" >&2
  exit 1
fi

out=''
for byte in $(head -c "$length" /dev/urandom | od -An -tu1); do
  out+=${alphabet:byte % 32:1}
done
printf '%s\n' "$out"
