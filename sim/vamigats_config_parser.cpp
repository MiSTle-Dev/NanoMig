#include "vamigats_config_parser.h"
#include <iostream>
#include <fstream>
#include <sstream>
#include <algorithm> // Include for std::string::replace

int g_vAmigaTS_screenshot_wait_time_seconds = 0;
int g_vAmigaTS_screenshot_wait_time_seconds_offset = 0;
std::string g_vAmigaTS_screenshot_name = "";
std::string g_vAmigaTS_screenshot_dir = ".";

// Function to normalize vAmigaTS chipset-specific ADF names to the copied ADF path
void normalize_vamigats_adf_path(vAmigaTSConfig &config) {
    size_t ocs_pos = config.adf_path.find("_ocs.adf");
    if (ocs_pos != std::string::npos) {
        config.adf_path.replace(ocs_pos, 8, ".adf");
    }

    size_t ecs_pos = config.adf_path.find("_ecs.adf");
    if (ecs_pos != std::string::npos) {
        config.adf_path.replace(ecs_pos, 8, ".adf");
    }
}
// Function to parse vAmigaTS loader command-line arguments
vAmigaTSConfig parse_vamigats_command_line_args(int argc, char **argv) {
    vAmigaTSConfig config; // Create a local instance of vAmigaTSConfig

    for (int arg_pos = 1; arg_pos < argc; arg_pos++) {
        std::string arg = argv[arg_pos];

        // Check for the vAmigaTS config-file argument
        if (arg.rfind("vamigats_config=", 0) == 0) {
            std::string config_file = arg.substr(16);
            std::cout << "Config file detected: " << config_file << std::endl;
            parse_vamigats_config_file(config_file, config); // Pass the config object
        } 
        // Check if the argument starts with "screenshot_dir="
        else if (arg.rfind("screenshot_dir=", 0) == 0) {
            config.screenshot_dir = arg.substr(15);
            std::cout << "Screenshot directory detected: " << config.screenshot_dir << std::endl;
        }
    }

    return config; // Return the populated config object
}

// Function to parse a vAmigaTS config script
void parse_vamigats_config_file(const std::string &file_path, vAmigaTSConfig &config) {
    std::ifstream file(file_path);
    if (!file.is_open()) {
        std::cerr << "Failed to open vAmigaTS config file: " << file_path << std::endl;
        return;
    }
	config.config_file_name = file_path;

    std::string line;
    while (std::getline(file, line)) {
        std::istringstream iss(line);
        std::string command;
        iss >> command;

        if (command == "regression") {
            std::string subcommand;
            iss >> subcommand;

            if (subcommand == "setup") {
                iss >> config.config_string >> config.rom_path;
                // Determine the chipset based on the configuration
                if (config.config_string.find("OCS") != std::string::npos) {
                    config.chipset = "OCS";
                } else if (config.config_string.find("ECS") != std::string::npos) {
                    config.chipset = "ECS";
                } else if (config.config_string.find("PLUS") != std::string::npos) {
                    config.chipset = "PLUS";
                }
            } else if (subcommand == "run") {
                iss >> config.adf_path;
                normalize_vamigats_adf_path(config); // Call the function after setting adf_path
            }
        } else if (command == "cpu") {
            std::string subcommand;
            iss >> subcommand;
            
            if (subcommand == "set") {
                std::string revision;
                iss >> revision >> config.cpu_revision;
            }
        } else if (command == "wait") {
            int time;
            std::string unit;
            if (iss >> time >> unit) {
                config.screenshot_wait_time_seconds = time;
            } else {
                std::cerr << "Error: Invalid format in wait command.\n";
            }
        } else if (command == "screenshot") {
            std::string subcommand;
            iss >> subcommand;

            if (subcommand == "save") {
                iss >> config.screenshot_name;
            }
        }
    }
    file.close();

    // Print the loaded values
    std::cout << "Loaded values from " << file_path << ":\n";
    std::cout << "Configuration: " << config.config_string << "\n";
    std::cout << "Chipset: " << config.chipset << "\n"; // Print the chipset value
    std::cout << "CPU Revision: " << config.cpu_revision << "\n"; // Print the CPU revision value
    std::cout << "ROM Path: " << config.rom_path << "\n";
    std::cout << "ADF Path: " << config.adf_path << "\n";
    std::cout << "Wait Time: " << config.screenshot_wait_time_seconds << " seconds\n";
    std::cout << "Screenshot Name: " << config.screenshot_name << "\n";
}

