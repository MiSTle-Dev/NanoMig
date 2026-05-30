#pragma once

#include <string>

// Define a structure to hold vAmigaTS configuration settings
struct vAmigaTSConfig {
  std::string config_file_name = "";
  std::string rom_path = "kick13.rom";
  int screenshot_wait_time_seconds = 0;
  int screenshot_wait_time_seconds_offset = 0;
  std::string screenshot_name = "";
  std::string screenshot_dir = ".";  // Default to current directory
  std::string adf_path = "df0.adf";
  std::string config_string = "";
  std::string chipset = "OCS"; // use OCS as default
  std::string cpu_revision = "68000"; // default CPU revision
};

// External variables to hold configuration data
extern int g_vAmigaTS_screenshot_wait_time_seconds;
extern int g_vAmigaTS_screenshot_wait_time_seconds_offset;
extern std::string g_vAmigaTS_screenshot_name;
extern std::string g_vAmigaTS_screenshot_dir;

// Function to normalize vAmigaTS chipset-specific ADF names to the copied ADF path
void normalize_vamigats_adf_path(vAmigaTSConfig &config);

// Function to parse vAmigaTS loader command-line arguments
vAmigaTSConfig parse_vamigats_command_line_args(int argc, char **argv);

// Function to parse a vAmigaTS config script
void parse_vamigats_config_file(const std::string &file_path, vAmigaTSConfig &config);
