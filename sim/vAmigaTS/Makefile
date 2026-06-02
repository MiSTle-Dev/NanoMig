# Makefile

# Default source directory if SRC_DIR is not provided
#FALLBACK_DIR=~/vAmigaTS/Agnus/Blitter/bbusy
#FALLBACK_DIR=~/vAmigaTS/Agnus/Blitter/bltint
# maybe add wait_time_seconds_offset as parameter here?
# bbusy needs 6 seconds, bltint needs 7 seconds
FALLBACK_DIR=~/vAmigaTS/Agnus/Blitter/fill
# this command is run in the parent directory
SIMULATION_CMD=make run
# this directory is located in the parent directory
SCREENSHOT_DIR=$(CURDIR)/screenshots
KICK_PATH=../kick13.rom

# Use SRC_DIR if defined, otherwise fallback to FALLBACK_DIR
SRC_DIR ?= $(FALLBACK_DIR)

TMP_DIR=/tmp
SCRIPT_TMP_DIR=$(TMP_DIR)/nanomig_vamigats_scripts
PARENT_DIR=..

# Run make for each vAmigaTS config script (.ini/.retrosh) in the parent directory
run_all: collect_files
	@mkdir -p $(SCREENSHOT_DIR)  # Ensure the screenshots directory exists
	@echo "Running simulations for each .ini/.retrosh file..."
	@scripts=$$(find $(SCRIPT_TMP_DIR) -maxdepth 1 \( -name "*.ini" -o -name "*.retrosh" \) -print | sort); \
	if [ -z "$$scripts" ]; then \
		echo "No .ini or .retrosh files found in $(SRC_DIR). Refusing to run default config."; \
		exit 1; \
	fi; \
	for script in $$scripts; do \
		echo "Found config script: $$script"; \
		(cd $(PARENT_DIR) && $(SIMULATION_CMD) VAMIGATS_CONFIG=$$script SCREENSHOT_DIR=$(SCREENSHOT_DIR)); \
	done

# Collect all .ini, .retrosh and .adf files from the specified directory
collect_files:
	@echo "Collecting .ini, .retrosh and .adf files from $(SRC_DIR)..."
	@mkdir -p $(TMP_DIR)  # Ensure the temporary directory exists
	@mkdir -p $(SCRIPT_TMP_DIR)  # Ensure the temporary script directory exists
	@rm -f $(SCRIPT_TMP_DIR)/*.ini $(SCRIPT_TMP_DIR)/*.retrosh
	@-find $(SRC_DIR) -name "*.ini" -exec cp {} $(SCRIPT_TMP_DIR) \; || echo "No .ini files found."
	@-find $(SRC_DIR) -name "*.retrosh" -exec cp {} $(SCRIPT_TMP_DIR) \; || echo "No .retrosh files found."
	@-find $(SRC_DIR) -name "*.adf" -exec cp {} $(TMP_DIR) \; || echo "No .adf files found."
	@echo "Scripts collected in $(SCRIPT_TMP_DIR):"
	@ls $(SCRIPT_TMP_DIR)
	@echo "Files collected in $(TMP_DIR):"
	@echo "Copying kick13.rom to $(TMP_DIR)..."
	@cp $(KICK_PATH) $(TMP_DIR) || echo "$(KICK_PATH) not found."
	@ls $(TMP_DIR)

# Clean up the temporary directory
clean:
	@echo "Cleaning up..."
	@rm -rf $(TMP_DIR)
	@make clean

# Default target
all: run_all

# End of Makefile
