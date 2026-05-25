AS = ca65
LD = ld65

BUILD = build
SRC = src
INC = inc
CFG = cfg
GENHEADER = tools/genheader.sh

CONFIG = $(CFG)/nrom128.cfg
PRG = $(BUILD)/prg.bin
CHR = $(BUILD)/chr.bin
NES = $(BUILD)/jump.nes

# TODO: Automate?
OBJECTS = $(BUILD)/main.o $(BUILD)/pad.o $(BUILD)/bg.o $(BUILD)/jump.o \
	$(BUILD)/header.o


# Build rules

all: $(NES)

doc: FORCE
	make -C doc/

# Append the CHR ROM
$(NES): $(PRG) $(CHR)
	cat $(PRG) > $@
	cat $(CHR) >> $@

# Build the PRG ROM
$(PRG): $(OBJECTS) | $(BUILD) $(CONFIG)
	$(LD) --dbgfile $(BUILD)/jump.dbg -C $(CONFIG) -o $@ $^

# Generate the raw CHR ROM
# - ball.bin is an 96 B file of 6 tiles.  We append the rest with zeros.
# - TODO: Would a nice readable text form be good here?
build/chr.bin:
	cat assets/ball.bin > $@
	dd if=/dev/zero bs=8096 count=1 >> $@ 2> /dev/null

# Compile the main program
$(BUILD)/main.o: $(INC)/ppu.inc $(INC)/apu.inc $(INC)/boot.inc
$(BUILD)/bg.o: $(INC)/ppu.inc

$(BUILD)/%.o: $(SRC)/%.s | $(BUILD)
	$(AS) -g -t none -I inc -o $@ $<

$(BUILD):
	mkdir -p $(BUILD)

# Submake force rule
FORCE:

# Wipe the build
clean:
	rm -rf $(BUILD)
