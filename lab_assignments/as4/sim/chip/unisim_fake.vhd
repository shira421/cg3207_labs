-- Simulation-only stand-ins for the Xilinx primitives TOP uses, so GHDL can convert TOP to Verilog.
-- MMCME2_BASE: CLKOUT0 = CLKIN1 / (CLKOUT0_DIVIDE_F / CLKFBOUT_MULT_F), CLKOUT1 = CLKIN1 / (CLKOUT1_DIVIDE / CLKFBOUT_MULT_F)
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
package VComponents is
  component MMCME2_BASE is
    generic (BANDWIDTH : string := "OPTIMIZED"; CLKIN1_PERIOD : real := 0.0; CLKFBOUT_MULT_F : real := 5.0;
             DIVCLK_DIVIDE : integer := 1; CLKOUT0_DIVIDE_F : real := 1.0; CLKOUT1_DIVIDE : integer := 1;
             STARTUP_WAIT : boolean := false);
    port (CLKIN1, CLKFBIN, PWRDWN, RST : in std_logic; CLKFBOUT, CLKOUT0, CLKOUT1, LOCKED : out std_logic);
  end component;
  component BUFG is port (I : in std_logic; O : out std_logic); end component;
  component BUFGCE is port (I, CE : in std_logic; O : out std_logic); end component;
end package;

library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity MMCME2_BASE is
  generic (BANDWIDTH : string := "OPTIMIZED"; CLKIN1_PERIOD : real := 0.0; CLKFBOUT_MULT_F : real := 5.0;
           DIVCLK_DIVIDE : integer := 1; CLKOUT0_DIVIDE_F : real := 1.0; CLKOUT1_DIVIDE : integer := 1;
           STARTUP_WAIT : boolean := false);
  port (CLKIN1, CLKFBIN, PWRDWN, RST : in std_logic; CLKFBOUT, CLKOUT0, CLKOUT1, LOCKED : out std_logic);
end entity;
architecture sim of MMCME2_BASE is
  constant D0 : integer := integer(CLKOUT0_DIVIDE_F / CLKFBOUT_MULT_F);
  signal c0 : unsigned(7 downto 0) := (others => '0');
  signal o0 : std_logic := '0';
  signal lk : unsigned(4 downto 0) := (others => '0');
begin
  process(CLKIN1) begin
    if rising_edge(CLKIN1) then
      if c0 = to_unsigned(D0/2 - 1, 8) then c0 <= (others => '0'); o0 <= not o0; else c0 <= c0 + 1; end if;
      if lk /= 31 then lk <= lk + 1; end if;
    end if;
  end process;
  CLKOUT0 <= o0 when D0 > 1 else CLKIN1;
  CLKOUT1 <= CLKIN1;
  CLKFBOUT <= CLKIN1;
  LOCKED <= '1' when lk = 31 else '0';
end architecture;

library ieee; use ieee.std_logic_1164.all;
entity BUFG is port (I : in std_logic; O : out std_logic); end entity;
architecture sim of BUFG is begin O <= I; end architecture;

library ieee; use ieee.std_logic_1164.all;
entity BUFGCE is port (I, CE : in std_logic; O : out std_logic); end entity;
architecture sim of BUFGCE is begin O <= I and CE; end architecture;
