library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package fifo_pkg is
  
  ---------------------------------------------------------------------------
  -- Types
  ---------------------------------------------------------------------------
  constant dwidth : integer := 8;

  type AXIS_8_t is record
    data  : std_logic_vector(dwidth - 1 downto 0);
    valid : std_logic;
    tlast : std_logic;
  end record;


end package;



package body fifo_pkg is


end package body;
