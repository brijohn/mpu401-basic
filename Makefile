
KICKASS?=/usr/local/bin/kickass

BUILD_DIR?=build


all: $(BUILD_DIR)/mpu401.prg

$(BUILD_DIR)/mpu401.prg: src/mpu401.asm
	$(KICKASS) $< -o $@ -odir ${CURDIR}/$(BUILD_DIR) -bytedump -showmem

clean:
	@rm -rf $(BUILD_DIR)
