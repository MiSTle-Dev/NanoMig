# Run NanoMig Simulation with test from vAmiga Test Suite

The tests from the [vAmiga Test Suite](https://github.com/dirkwhoffmann/vAmigaTS) can be used to validate the accuracy of the NanoMig Verilator simulation. 

For this purpose the parameters from the vAmiga Test Suite config scripts are used to configure the NanoMig Verilator simulation. Screenshots of the NanoMig Verilator simulation are taken for comparison against the reference images provided by the vAmiga Test Suite.

## Benefit

The vAmiga Test Suite has been validated against real Amiga hardware, providing a benchmark for simulation accuracy.
These tests can help further improve the precision of the NanoMig simulation.

## Usage

### Running the Simulation with the Makefile

This project uses a `Makefile` to automate the process of collecting tests and running the simulations.

#### Key Variables in the Makefile

- **`SRC_DIR`:** The directory where the vAmiga Test Suite files are located. `SRC_DIR` is passed to the Makefile as a parameter.
- **`FALLBACK_DIR`:** The default directory where the vAmiga Test Suite files are located. If `SRC_DIR` is not specified, this path is used.
- **`SIM_COMMAND`:** The command used to run the simulation. It defaults to `make run` in the parent directory.
- **`KICK_PATH`:** The path to the `kick13.rom` file, which is necessary for the simulation.

#### How to Use

1. **Prepare the Environment:**
   - Ensure that the vAmiga Test Suite files are located in the directory specified by `SRC_DIR` or the `FALLBACK_DIR` in the Makefile. For example under `~/vAmigaTS/`
   - Make sure that the `kick13.rom` file is available in the path specified by `KICK_PATH`.

2. **Run the Simulation with vAmiga Test Suite Tests:**

   - To use the vAmigaTS tests from the `FALLBACK_DIR`, execute the following command in your terminal:
     ```bash
     make
     ```

   - To use the vAmigaTS tests from a specific directory, such as `~/vAmigaTS/Agnus/Blitter/bbusy`, execute the following command in your terminal:
     ```bash
      make SRC_DIR=~/vAmigaTS/Agnus/Blitter/bbusy
     ```
	 

   - A single test can be executed using the same approach:
     ```bash
      make SRC_DIR=~/vAmigaTS/Agnus/Blitter/bltint/bltint1
     ```
	 

## Todo
- Take into account CPU revision mentioned in vAmigaTS config scripts
- Take into account the amount of RAM mentioned in vAmigaTS config scripts
- Test handling of directories with multiple config scripts
