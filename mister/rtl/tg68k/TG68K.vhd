------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- This is the TOP-Level for TG68K.C to generate 68K Bus signals            --
--                                                                          --
-- Copyright (c) 2021 Tobias Gubener <tobiflex@opencores.org>               -- 
--                                                                          --
-- This source file is free software: you can redistribute it and/or modify --
-- it under the terms of the GNU Lesser General Public License as published --
-- by the Free Software Foundation, either version 3 of the License, or     --
-- (at your option) any later version.                                      --
--                                                                          --
-- This source file is distributed in the hope that it will be useful,      --
-- but WITHOUT ANY WARRANTY; without even the implied warranty of           --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            --
-- GNU General Public License for more details.                             --
--                                                                          --
-- You should have received a copy of the GNU General Public License        --
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.    --
--                                                                          --
------------------------------------------------------------------------------
------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity TG68K is
   generic(
      CPU           : std_logic_vector(1 downto 0):="01"  -- 00->68000  01->68010  11->68020
   );
   port(        
      CLK           : in std_logic;
      RESET         : inout std_logic;
      HALT          : inout std_logic;
      BERR          : in std_logic;     -- only 68000 Stackpointer dummy for Atari ST core
      IPL           : in std_logic_vector(2 downto 0):="111";
      ADDR          : out std_logic_vector(31 downto 0);
      FC            : out std_logic_vector(2 downto 0);
      DATA          : inout std_logic_vector(15 downto 0);
---- bus controll      
--      BG            : out std_logic;
--      BR         	  : in std_logic:='1';
--      BGACK         : in std_logic:='1';
-- async interface      
      AS            : out std_logic;
      UDS           : out std_logic;
      LDS           : out std_logic;
      RW            : out std_logic;
      DTACK         : in std_logic;
-- sync interface      
      E             : out std_logic;
      VPA           : in std_logic;
      VMA           : out std_logic
   );
end TG68K;

ARCHITECTURE logic OF TG68K IS


COMPONENT TG68KdotC_Kernel 
   generic(
      SR_Read : integer:= 2;           --0=>user,     1=>privileged,    2=>switchable with CPU(0)
      VBR_Stackframe : integer:= 2;    --0=>no,       1=>yes/extended,  2=>switchable with CPU(0)
      extAddr_Mode : integer:= 2;      --0=>no,       1=>yes,           2=>switchable with CPU(1)
      MUL_Mode : integer := 2;         --0=>16Bit,    1=>32Bit,         2=>switchable with CPU(1),  3=>no MUL,  
      DIV_Mode : integer := 2;         --0=>16Bit,    1=>32Bit,         2=>switchable with CPU(1),  3=>no DIV,  
      BitField : integer := 2;         --0=>no,       1=>yes,           2=>switchable with CPU(1) 
      
      BarrelShifter : integer := 2;    --0=>no,       1=>yes,           2=>switchable with CPU(1)  
      MUL_Hardware : integer := 1      --0=>no,       1=>yes,  
   );
   port(
      CPU            : in std_logic_vector(1 downto 0):="01";  -- 00->68000  01->68010  11->68020
      clk            : in std_logic;
      nReset         : in std_logic:='1';    --low active
      clkena_in      : in std_logic:='1';
      data_in        : in std_logic_vector(15 downto 0);
      IPL            : in std_logic_vector(2 downto 0):="111";
      IPL_autovector : in std_logic:='0';
      addr_out       : out std_logic_vector(31 downto 0);
      berr           : in std_logic:='0';     -- only 68000 Stackpointer dummy for Atari ST core
      FC             : out std_logic_vector(2 downto 0);
      data_write     : out std_logic_vector(15 downto 0);
      busstate       : out std_logic_vector(1 downto 0);	
      nWr            : out std_logic;
      nUDS, nLDS     : out std_logic;
      nResetOut      : out std_logic;
      skipFetch      : out std_logic
--      longword       : out std_logic;
--      clr_berr       : out std_logic;
   );
   END COMPONENT;



   SIGNAL data_write  : std_logic_vector(15 downto 0);
   SIGNAL r_data      : std_logic_vector(15 downto 0);
   SIGNAL cpuIPL      : std_logic_vector(2 downto 0);
   SIGNAL data_akt_s  : std_logic;
   SIGNAL data_akt_e  : std_logic;
   SIGNAL as_s        : std_logic;
   SIGNAL as_e        : std_logic;
   SIGNAL uds_s       : std_logic;
   SIGNAL uds_e       : std_logic;
   SIGNAL lds_s       : std_logic;
   SIGNAL lds_e       : std_logic;
   SIGNAL rw_s        : std_logic;
   SIGNAL rw_e        : std_logic;
   SIGNAL vpad        : std_logic;
   SIGNAL waitm       : std_logic;
   SIGNAL clkena_e    : std_logic;
   SIGNAL S_state     : std_logic_vector(1 downto 0);
   SIGNAL decode      : std_logic;
   SIGNAL wr          : std_logic;
   SIGNAL uds_in      : std_logic;
   SIGNAL lds_in      : std_logic;
   SIGNAL state       : std_logic_vector(1 downto 0);
   SIGNAL clkena      : std_logic;
   SIGNAL skipFetch   : std_logic;
   SIGNAL nResetOut   : std_logic;
   SIGNAL autovector  : std_logic;
   SIGNAL cpu1reset   : std_logic;


   type sync_state_t is (sync0, sync1, sync2, sync3, sync4, sync5, sync6, sync7, sync8, sync9);
   signal sync_state : sync_state_t;

BEGIN  
   DATA <= data_write WHEN data_akt_e='1' OR data_akt_s='1' ELSE "ZZZZZZZZZZZZZZZZ";
   AS <= as_s AND as_e;
   RW <= rw_s AND rw_e;
   UDS <= uds_s AND uds_e;
   LDS <= lds_s AND lds_e;
   
   RESET <= '0' WHEN nResetOut='0' ELSE 'Z';
   HALT <=  '0' WHEN nResetOut='0' ELSE 'Z';
   cpu1reset <= RESET OR HALT;

cpu1: TG68KdotC_Kernel 
   generic map(
      SR_Read => 2,              --0=>user,     1=>privileged,    2=>switchable with CPU(0)
      VBR_Stackframe => 2,       --0=>no,       1=>yes/extended,  2=>switchable with CPU(0)
      extAddr_Mode => 2,         --0=>no,       1=>yes,           2=>switchable with CPU(1)
      MUL_Mode => 2,             --0=>16Bit,    1=>32Bit,         2=>switchable with CPU(1),  3=>no MUL,  
      DIV_Mode => 2,             --0=>16Bit,    1=>32Bit,         2=>switchable with CPU(1),  3=>no DIV,  
      BitField => 2,             --0=>no,       1=>yes,           2=>switchable with CPU(1) 

      BarrelShifter => 0,        --0=>no,       1=>yes,           2=>switchable with CPU(1)  
      MUL_Hardware => 1          --0=>no,       1=>yes,  
   )
   PORT MAP(
      CPU => CPU,                -- : in std_logic_vector(1 downto 0):="01";  -- 00->68000  01->68010  11->68020
      clk => CLK,                -- : in std_logic;
      nReset => cpu1reset,       -- : in std_logic:='1';       --low active
      clkena_in => clkena,       -- : in std_logic:='1';
      data_in => r_data,         -- : in std_logic_vector(15 downto 0);
      IPL => cpuIPL,             -- : in std_logic_vector(2 downto 0):="111";
      IPL_autovector => autovector, -- : in std_logic:='0';
      addr_out => ADDR,          -- : buffer std_logic_vector(31 downto 0);
      berr => BERR,              -- : in std_logic:='0';     -- only 68000 Stackpointer dummy for Atari ST core
      FC => FC,                  -- : out std_logic_vector(2 downto 0);
      data_write => data_write,  -- : out std_logic_vector(15 downto 0);
      busstate => state,         -- : buffer std_logic_vector(1 downto 0);	
      nWr => wr,                 -- : out std_logic;
      nUDS => uds_in,            -- : out std_logic;
      nLDS => lds_in,            -- : out std_logic;
      nResetOut => nResetOut,    -- : out std_logic;
      skipFetch => skipFetch     -- : out std_logic
   );
 
   PROCESS (CLK)
   BEGIN
      IF falling_edge(CLK) THEN
         IF sync_state=sync5 THEN
            E <= '1';
         END IF;
         IF sync_state=sync9 THEN
            E <= '0';
         END IF;
      END IF;
      
      IF rising_edge(CLK) THEN
         CASE sync_state IS
            WHEN sync0  => sync_state <= sync1;
            WHEN sync1  => sync_state <= sync2;
            WHEN sync2  => sync_state <= sync3;
            WHEN sync3  => sync_state <= sync4;
                        VMA <= VPA;
                        vpad <= VPA;
                        autovector <= NOT VPA;
            WHEN sync4  => sync_state <= sync5;
            WHEN sync5  => sync_state <= sync6;
            WHEN sync6  => sync_state <= sync7;
            WHEN sync7  => sync_state <= sync8;
            WHEN sync8  => sync_state <= sync9;
            WHEN OTHERS => sync_state <= sync0;
                        VMA <= '1';
         END CASE;
      END IF;
   END PROCESS;


   PROCESS (state, clkena_e, skipFetch)
   BEGIN
      IF state="01" OR clkena_e='1' OR skipFetch='1' THEN
         clkena <= '1';
      ELSE 
         clkena <= '0';
      END IF;
   END PROCESS;

PROCESS (CLK, RESET, state, as_s, as_e, rw_s, rw_e, uds_s, uds_e, lds_s, lds_e)
   BEGIN
      IF RESET='0' THEN
         S_state <= "11";
         as_s <= '1';
         rw_s <= '1';
         uds_s <= '1';
         lds_s <= '1';
         data_akt_s <= '0';
      ELSIF rising_edge(CLK) THEN
         as_s <= '1';
         rw_s <= '1';
         uds_s <= '1';
         lds_s <= '1';
         data_akt_s <= '0';
         CASE S_state IS
            WHEN "00" =>
                      IF state/="01" AND skipFetch='0' THEN
                         IF wr='1' THEN
                            uds_s <= uds_in;
                            lds_s <= lds_in;
                         END IF;
                         as_s <= '0';
                         rw_s <= wr;
                         S_state <= "01";
                      END IF;
            WHEN "01" => 
                      as_s <= '0';
                      rw_s <= wr;
                      uds_s <= uds_in;
                      lds_s <= lds_in;
                      S_state <= "10";
            WHEN "10" =>
                      data_akt_s <= NOT wr;
                      r_data <= DATA;
                      IF waitm='0' OR (vpad='0' AND sync_state=sync9) THEN
                         S_state <= "11";
                      ELSE	
                         as_s <= '0';
                         rw_s <= wr;
                         uds_s <= uds_in;
                         lds_s <= lds_in;
                      END IF;
            WHEN "11" =>
                      S_state <= "00";
            WHEN OTHERS => null;
         END CASE;
      END IF;
      
      IF RESET='0' THEN
         as_e <= '1';
         rw_e <= '1';
         uds_e <= '1';
         lds_e <= '1';
         clkena_e <= '0';
         data_akt_e <= '0';
      ELSIF falling_edge(CLK) THEN
         as_e <= '1';
         rw_e <= '1';
         uds_e <= '1';
         lds_e <= '1';
         clkena_e <= '0';
         data_akt_e <= '0';
         CASE S_state IS
            WHEN "00" =>
                      cpuIPL <= IPL;      --for HALT command
            WHEN "01" =>
                      data_akt_e <= NOT wr;
                      as_e <= '0';
                      rw_e <= wr;
                      uds_e <= uds_in;
                      lds_e <= lds_in;
            WHEN "10" =>
                      rw_e <= wr;
                      data_akt_e <= NOT wr;
                      cpuIPL <= IPL;
                      waitm <= DTACK;
            WHEN OTHERS =>
                      clkena_e <= '1';
         END CASE;
      END IF;
   END PROCESS;
END;