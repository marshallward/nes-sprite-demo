AS=ca65
LD=ld65

BUILD=build
SRC=src
INC=inc
GENHEADER=tools/genheader.sh

CONFIG=$(SRC)/nrom128.cfg
BOOT=$(BUILD)/boot.bin
NES=$(BUILD)/boot.nes

all: $(NES)

# Prepend the iNES header
$(NES): $(BOOT)
	$(GENHEADER) -o $@ -i $^

# Build the ROM chip data
$(BOOT): $(BUILD)/boot.o $(CONFIG) | $(BUILD)
	$(LD) -C $(CONFIG) -o $@ $<

# Compile the asm
$(BUILD)/boot.o: $(SRC)/boot.s $(INC)/ppu.inc $(INC)/apu.inc | $(BUILD)
	$(AS) -t none -I inc -o $@ $<

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)
