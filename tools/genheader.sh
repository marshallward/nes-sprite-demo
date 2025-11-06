#!/bin/sh

# Example script to prepend an iNES header to a compiled ROM file.
#
# This is not very extensible, because it assumes a single PRG ROM and does not
# specify a CHR ROM.  But I can see it being improved.

usage() {
  cat <<-USAGE
Usage: $0 -o output -i input
    -o output   output NES rom
    -i input    input PRG rom
    -h help     show this help
USAGE
    exit 1
}

outfile=""
infile=""

while getopts "o:i:h" opt; do
    case "$opt" in
        o) outfile=$OPTARG ;;
        i) infile=$OPTARG ;;
        h) usage ;;
        *) usage;;
    esac
done

# Verify that arguments are present
[ -n "$outfile" ] || { echo "missing -o"; usage; }
[ -n "$infile" ] || { echo "missing -i"; usage; }

# Verify that input is readable
if [ ! -r "$infile" ]; then
    echo "input file not found or not readable: $infile" >&2
    exit 2
fi

# Verify output target
: > "$outfile" || { echo "cannot write to $outfile" >&2; exit 3; }


# -- Begin output --

# iNES signature ("NES" + SUB)
printf "\x4e\x45\x53\x1a" > $outfile

# Two 16 kiB PRG ROMs
printf "\x02" >> $outfile

# One 8 kiB CHR ROM
printf "\x01" >> $outfile

# Pad the next 10 (unused) header bytes
printf "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" >> $outfile

# Write the 16 kiB PRG rom twice; second rom $C000-$ffff contains start address.
cat $infile >> $outfile
cat $infile >> $outfile

# Pad the 8 kiB CHR rom (currently unused)
dd if=/dev/zero bs=8192 count=1 >> $outfile 2> /dev/null
