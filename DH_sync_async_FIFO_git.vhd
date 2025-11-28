
----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 03/11/2024 11:14:51 PM
-- Design Name: 
-- Module Name: DH_sync_async_FIFO - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
library UNISIM;
use UNISIM.VComponents.all;
Library xpm;
use xpm.vcomponents.all;
Library UNIMACRO;
use UNIMACRO.vcomponents.all;
use work.fifo_pkg.all;


entity DH_sync_async_FIFO is
     GENERIC (DWIDTH_EXP     : integer;
              metadata_width : integer;
              DEPTH_EXP      : integer;
              CDC            : BOOLEAN;
              PIPELINE_EN    : BOOLEAN;
              PIPELINE_STAGES: NATURAL;
              AF_OFFSET      : bit_vector;
              AE_OFFSET      : bit_vector);
     PORT (CLK_a           : in std_logic;
           RST             : in std_logic;

           CLK_b           : in std_logic;

           s_axis_stream   : in AXIS_8_t;
           s_axis_tready   : out std_logic;

           m_axis_stream   : out AXIS_8_t;
           m_axis_tready   : in std_logic);    
end DH_sync_async_FIFO;

architecture Behavioral of DH_sync_async_FIFO is

signal m_almost_empty, s_almost_full, m_axis_fifo_empty, s_axis_fifo_full, 
       s_axis_wr_error, m_axis_rd_error, m_axis_tready_int, m_axis_fifo_valid : std_logic := '0';
       
signal s_wr_cnt, m_rd_cnt : std_logic_vector (DEPTH_EXP downto 0) := (others => '0');

signal s_axis_dbus, m_axis_dbus : std_logic_vector(2**DWIDTH_EXP + metadata_width - 1 downto 0) := (others => '0');

type m_stream_pipeline_buffer_t is array(0 to PIPELINE_STAGES - 1) of AXIS_8_t;
signal m_stream_pipeline_buffer : m_stream_pipeline_buffer_t;

signal RSTb : STD_LOGIC;

--------------------------------------------------------------
attribute keep : string;
--------------------------------------------------------------------------------------------------------------------
attribute keep of m_axis_dbus: signal is "true"; 
attribute keep of m_axis_fifo_empty: signal is "true"; 

begin

    -- DWIDTH must be in supported range
    ASSERT_DWIDTH_RANGE : assert (2**DWIDTH_EXP >= 1 and 2**DWIDTH_EXP <= 72)
      report "DH_sync_async_FIFO: DWIDTH=" & integer'image(DWIDTH_EXP) &
             " is out of supported range [1..72] for FIFO_SIZE=""36Kb""."
      severity failure;

    -- For each DWIDTH band, enforce minimum DEPTH_EXP for RDCOUNT/WRCOUNT bits
    ASSERT_DEPTH_37_72 : assert not (2**DWIDTH_EXP >= 37 and 2**DWIDTH_EXP <= 72) or (DEPTH_EXP >= 9)
      report "DH_sync_async_FIFO: DEPTH_EXP=" & integer'image(DEPTH_EXP) &
             " too small for DWIDTH=" & integer'image(2**DWIDTH) &
             " (requires at least 9-bit RD/WR count)."
      severity failure;

    ASSERT_DEPTH_19_36 : assert not (2**DWIDTH_EXP >= 19 and 2**DWIDTH_EXP <= 36) or (DEPTH_EXP >= 10)
      report "DH_sync_async_FIFO: DEPTH_EXP=" & integer'image(DEPTH_EXP) &
             " too small for DWIDTH=" & integer'image(2**DWIDTH_EXP) &
             " (requires at least 10-bit RD/WR count)."
      severity failure;

    ASSERT_DEPTH_10_18 : assert not (2**DWIDTH_EXP >= 10 and 2**DWIDTH_EXP <= 18) or (DEPTH_EXP >= 11)
      report "DH_sync_async_FIFO: DEPTH_EXP=" & integer'image(DEPTH_EXP) &
             " too small for DWIDTH=" & integer'image(2**DWIDTH_EXP) &
             " (requires at least 11-bit RD/WR count)."
      severity failure;

    ASSERT_DEPTH_5_9 : assert not (2**DWIDTH_EXP >= 5 and 2**DWIDTH_EXP <= 9) or (DEPTH_EXP >= 12)
      report "DH_sync_async_FIFO: DEPTH_EXP=" & integer'image(DEPTH_EXP) &
             " too small for DWIDTH=" & integer'image(2**DWIDTH_EXP) &
             " (requires at least 12-bit RD/WR count)."
      severity failure;

    ASSERT_DEPTH_1_4 : assert not (2**DWIDTH_EXP >= 1 and 2**DWIDTH_EXP <= 4) or (DEPTH_EXP >= 13)
      report "DH_sync_async_FIFO: DEPTH_EXP=" & integer'image(DEPTH_EXP) &
             " too small for DWIDTH=" & integer'image(2**DWIDTH_EXP) &
             " (requires at least 13-bit RD/WR count)."
      severity failure;

   MASTER_RESET_SYNCH : xpm_cdc_async_rst
   generic map (
      DEST_SYNC_FF => 2,    -- DECIMAL; range: 2-10
      INIT_SYNC_FF => 1,    -- DECIMAL; 0=disable simulation init values, 1=enable simulation init values
      RST_ACTIVE_HIGH => 1  -- DECIMAL; 0=active low reset, 1=active high reset
   )
   port map (
      dest_arst => RSTb, -- 1-bit output: src_arst asynchronous reset signal synchronized to destination
                              -- clock domain. This output is registered. NOTE: Signal asserts asynchronously
                              -- but deasserts synchronously to dest_clk. Width of the reset signal is at least
                              -- (DEST_SYNC_FF*dest_clk) period.

      dest_clk => CLK_b,   -- 1-bit input: Destination clock.
      src_arst => RST    -- 1-bit input: Source asynchronous reset signal.
   );

    s_axis_tready <= not s_axis_fifo_full;
    s_axis_dbus   <= s_axis_stream.data(2**DWIDTH_EXP - 1 downto 0) & s_axis_stream.tlast;
    -----------------------------------------------------------------
    -- DATA_WIDTH | FIFO_SIZE | FIFO Depth | RDCOUNT/WRCOUNT Width --
    -- ===========|===========|============|=======================--
    --   37-72    |  "36Kb"   |     512    |         9-bit         --
    --   19-36    |  "36Kb"   |    1024    |        10-bit         --
    --   19-36    |  "18Kb"   |     512    |         9-bit         --
    --   10-18    |  "36Kb"   |    2048    |        11-bit         --
    --   10-18    |  "18Kb"   |    1024    |        10-bit         --
    --    5-9     |  "36Kb"   |    4096    |        12-bit         --
    --    5-9     |  "18Kb"   |    2048    |        11-bit         --
    --    1-4     |  "36Kb"   |    8192    |        13-bit         --
    --    1-4     |  "18Kb"   |    4096    |        12-bit         --
    -----------------------------------------------------------------
    GEN_nCDC : if CDC = FALSE GENERATE
    
        sync_FIFO_inst : FIFO_SYNC_MACRO
        generic map (
           DEVICE              => "7SERIES",            -- Target Device: "VIRTEX5, "VIRTEX6", "7SERIES" 
           ALMOST_FULL_OFFSET  => AF_OFFSET,  -- Sets almost full threshold
           ALMOST_EMPTY_OFFSET => AE_OFFSET, -- Sets the almost empty threshold
           DATA_WIDTH          => (2**DWIDTH_EXP + metadata_width),   -- Valid values are 1-72 (37-72 only valid when FIFO_SIZE="36Kb")
           FIFO_SIZE           => "36Kb")            -- Target BRAM, "18Kb" or "36Kb" 
        port map (
           ALMOSTEMPTY => m_almost_empty,                   -- 1-bit output almost empty
           ALMOSTFULL  => s_almost_full,                    -- 1-bit output almost full
           DO          => m_axis_dbus,                      -- Output data, width defined by DATA_WIDTH parameter
           EMPTY       => m_axis_fifo_empty   ,             -- 1-bit output empty
           FULL        => s_axis_fifo_full   ,              -- 1-bit output full
           RDCOUNT     => m_rd_cnt(DEPTH_EXP - 1 downto 0), -- Output read count, width determined by FIFO depth
           RDERR       => m_axis_rd_error,                  -- 1-bit output read error
           WRCOUNT     => s_wr_cnt(DEPTH_EXP - 1 downto 0), -- Output write count, width determined by FIFO depth
           WRERR       => s_axis_wr_error,                  -- 1-bit output write error
           CLK         => CLK_b,                            -- 1-bit input clock
           DI          => s_axis_dbus,                      -- Input data, width defined by DATA_WIDTH parameter
           RDEN        => m_axis_tready_int,                    -- 1-bit input read enable
           RST         => RST,                              -- 1-bit input reset
           WREN        => s_axis_stream.valid               -- 1-bit input write enable
        );
    END GENERATE GEN_nCDC;

    GEN_CDC : if CDC = TRUE GENERATE 
    
        FIFO_MACRO_inst0 : FIFO_DUALCLOCK_MACRO
        generic map (
           DEVICE => "7SERIES",            -- Target Device: "VIRTEX5", "VIRTEX6", "7SERIES" 
           ALMOST_FULL_OFFSET => AF_OFFSET,  -- Sets almost full threshold
           ALMOST_EMPTY_OFFSET => AE_OFFSET, -- Sets the almost empty threshold
           DATA_WIDTH => (2**DWIDTH_EXP + metadata_width),   -- Valid values are 1-72 (37-72 only valid when FIFO_SIZE="36Kb")
           FIFO_SIZE => "36Kb",            -- Target BRAM, "18Kb" or "36Kb" 
           FIRST_WORD_FALL_THROUGH => TRUE) -- Sets the FIFO FWFT to TRUE or FALSE
        port map (
           ALMOSTEMPTY => m_almost_empty  ,           -- 1-bit output almost empty
           ALMOSTFULL  => s_almost_full  ,           -- 1-bit output almost full
           DO          => m_axis_dbus,                    -- Output data, width defined by DATA_WIDTH parameter
           EMPTY       => m_axis_fifo_empty,           -- 1-bit output empty
           FULL        => s_axis_fifo_full,            -- 1-bit output full
           RDCOUNT     => m_rd_cnt(DEPTH_EXP - 1 downto 0), -- Output read count, width determined by FIFO depth
           RDERR       => m_axis_rd_error,                  -- 1-bit output read error
           WRCOUNT     => s_wr_cnt(DEPTH_EXP - 1 downto 0), -- Output write count, width determined by FIFO depth
           WRERR       => s_axis_wr_error,                  -- 1-bit output write error
           DI          => s_axis_dbus,         -- Input data, width defined by DATA_WIDTH parameter
           RDCLK       => CLK_b,         -- 1-bit input read clock
           RDEN        => m_axis_tready_int,         -- 1-bit input read enable
           RST         => RST,         -- 1-bit input reset
           WRCLK       => CLK_a,         -- 1-bit input write clock
           WREN        => s_axis_stream.valid           -- 1-bit input write enable
        );
    END GENERATE GEN_CDC;
    
    GEN_PIPELINE_EN : if PIPELINE_EN = TRUE GENERATE
        PIPELINE_PROC : process (CLK_b) 
        begin
            if rising_edge(CLK_b) then
                if RSTb = '1' then 
                    m_stream_pipeline_buffer(0).data  <= (others => '0');
                    m_stream_pipeline_buffer(0).valid <= '0';
                    m_stream_pipeline_buffer(0).tlast <= '0';
                else
                
                    m_stream_pipeline_buffer(0).data(2**DWIDTH_EXP - 1 downto 0) <= m_axis_dbus(2**DWIDTH_EXP + metadata_width - 1 downto 1);
                    m_stream_pipeline_buffer(0).valid                            <= not m_axis_fifo_empty;
                    m_stream_pipeline_buffer(0).tlast                            <= m_axis_dbus(m_axis_dbus'low); 
                    
                    for i in 1 to PIPELINE_STAGES - 1 loop
                        m_stream_pipeline_buffer(i) <= m_stream_pipeline_buffer(i - 1);
                    end loop;
                    
                end if;
            end if; 
        end process PIPELINE_PROC;

        m_axis_stream.data  <= m_stream_pipeline_buffer(PIPELINE_STAGES - 1).data(2**DWIDTH_EXP - 1 downto 0);
        m_axis_stream.valid <= m_stream_pipeline_buffer(PIPELINE_STAGES - 1).valid;
        m_axis_stream.tlast <= m_stream_pipeline_buffer(PIPELINE_STAGES - 1).tlast;        
        
    END GENERATE GEN_PIPELINE_EN;
    
    nGEN_PIPELINE_EN : if PIPELINE_EN = FALSE GENERATE
         m_axis_stream.data  <= m_axis_dbus(2**DWIDTH_EXP + metadata_width - 1 downto metadata_width);
         m_axis_stream.valid <= not m_axis_fifo_empty;
         m_axis_stream.tlast <= m_axis_dbus(m_axis_dbus'low); 
    END GENERATE nGEN_PIPELINE_EN;
    
    m_axis_tready_int <= m_axis_tready;


end Behavioral;  

