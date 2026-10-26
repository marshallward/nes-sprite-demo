AS = ca65
LD = ld65

BUILD = build
SRC = src
INC = inc
CFG = cfg

CONFIG = $(CFG)/nrom128.cfg
PRG = $(BUILD)/prg.bin
CHR = $(BUILD)/chr.bin
NES = $(BUILD)/jump.nes

# TODO: Automate?
OBJECTS = $(BUILD)/main.o $(BUILD)/pad.o $(BUILD)/bg.o $(BUILD)/move.o \
	$(BUILD)/platform.o $(BUILD)/hazard.o $(BUILD)/game.o $(BUILD)/dash.o $(BUILD)/header.o


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

# Preserve the original six tiles, append diagonal ramp tiles, then zero-pad.
$(CHR): assets/ball.bin tools/gen_chr.py | $(BUILD)
	python3 tools/gen_chr.py assets/ball.bin $@

# Compile the main program
$(BUILD)/main.o: $(INC)/ppu.inc $(INC)/apu.inc $(INC)/boot.inc
$(BUILD)/bg.o: $(INC)/ppu.inc
$(BUILD)/platform.o $(BUILD)/hazard.o: $(INC)/body.inc
$(BUILD)/bg.o $(BUILD)/hazard.o: $(INC)/spikes.inc
$(BUILD)/game.o $(BUILD)/dash.o: $(INC)/dash.inc

$(BUILD)/%.o: $(SRC)/%.s | $(BUILD)
	$(AS) -g -t none -I inc -o $@ $<

$(BUILD):
	mkdir -p $(BUILD)

# Submake force rule
FORCE:

# Wipe the build
clean:
	rm -rf $(BUILD)
