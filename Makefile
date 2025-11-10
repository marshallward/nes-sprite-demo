AS=ca65
LD=ld65

BUILD=build
SRC=src
INC=inc
GENHEADER=tools/genheader.sh

CONFIG=$(SRC)/nrom128.cfg
MAIN=$(BUILD)/main.bin
NES=$(BUILD)/main.nes

all: $(NES)

# Prepend the iNES header
$(NES): $(MAIN)
	$(GENHEADER) -o $@ -i $^

# Build the ROM chip data
$(MAIN): $(BUILD)/main.o $(CONFIG) | $(BUILD)
	$(LD) -C $(CONFIG) -o $@ $<

# Compile the asm
$(BUILD)/main.o: $(SRC)/main.s $(INC)/ppu.inc $(INC)/apu.inc $(INC)/boot.inc | $(BUILD)
	$(AS) -t none -I inc -o $@ $<

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)
