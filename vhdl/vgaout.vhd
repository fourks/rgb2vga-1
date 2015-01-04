library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity vgaout is
	generic(
		hor_active_video		: integer := 640;
		hor_front_porch		: integer := 16;
		hor_sync_pulse			: integer := 96;
		hor_back_porch			: integer := 48;

		vert_active_video		: integer := 480;
		vert_front_porch		: integer := 10;
		vert_sync_pulse		: integer := 2;
		vert_back_porch		: integer := 33		
		
	);
	
    port(clock_vga  : in std_logic;
         vga_out	  : out unsigned(9 downto 0); -- r, g, b, hsync, vsync
								
			pixel_in		: in unsigned(7 downto 0);		
			row_number	: buffer unsigned(9 downto 0);
			col_number	: out unsigned(9 downto 0); 
			load_req	: out std_logic := '0';
			load_ack  : in std_logic;

			scanline	: in std_logic;
			deinterlace	: in std_logic;			
			
			clock_dram: std_logic;
			video_active : std_logic
			
         );
end vgaout;

architecture behavioral of vgaout is

signal hcount												: unsigned(13 downto 0);
signal vcount												: unsigned(9 downto 0);
signal videov, videoh, hsync, vsync					: std_logic;
signal animate												: unsigned(9 downto 0);
signal bar_color											: unsigned(2 downto 0);
signal bar_cnt												: integer;
	
	
function f_scanline(adc: unsigned) return unsigned;

function f_scanline(adc: unsigned) return unsigned is
variable VALUE : unsigned (2 downto 0); 
begin
		case adc is
		
			when "000" => VALUE := "000";
			when "001" => VALUE := "000";
			when "010" => VALUE := "001";
			when "011" => VALUE := "001";
			when "100" => VALUE := "011";
			when "101" => VALUE := "011";
			when "110" => VALUE := "100";
			when "111" => VALUE := "100";
		end case;
		return VALUE;
end f_scanline;
	
begin


vcounter: process (clock_vga, hcount, vcount)
begin
	if(rising_edge(clock_vga)) then

		if hcount = (hor_active_video + hor_front_porch + hor_sync_pulse + hor_back_porch - 1) then
			vcount <= vcount + 1;
		end if;
		
      if vcount = (vert_active_video + vert_front_porch + vert_sync_pulse + vert_back_porch - 1) and hcount = (hor_active_video + hor_front_porch + hor_sync_pulse + hor_back_porch - 1) then 
			vcount <= (others => '0');
		end if;
		
	end if;
end process;

v_sync: process(clock_vga, vcount)
begin
	if(rising_edge(clock_vga)) then
		vsync <= '1';
		if (vcount <= (vert_active_video + vert_front_porch + vert_sync_pulse - 1) and vcount >= (vert_active_video + vert_front_porch - 1)) then
			vsync <= '0';
			animate <= animate + 1;
		end if;
	end if;
end process;

hcounter: process (clock_vga, hcount)
begin
	if (rising_edge(clock_vga)) then				
		hcount <= hcount + 1;
		
		bar_cnt <= bar_cnt + 1;
		if (bar_cnt >= 80) then
			bar_color <= bar_color + 1;
			bar_cnt <= 0;
		end if;
		
		
      if hcount = (hor_active_video + hor_front_porch + hor_sync_pulse + hor_back_porch - 1)	then 
        hcount <= (others => '0');
		  bar_cnt <= 0;
		  bar_color <= (others => '0');
		end if;	
		
	end if;
end process;


h_sync: process (clock_vga, hcount)
variable row : integer range 0 to 1024;
begin
	if (rising_edge(clock_vga)) then     
	   hsync <= '1';				
		
		if (deinterlace = '0') then
			row := to_integer(vcount(9 downto 0)) + 1;
		else
			row := to_integer(vcount(9 downto 1)) + 1;		
		end if;		
		
		row_number <= to_unsigned(row, row_number'length);
		
      if (hcount <= (hor_active_video + hor_front_porch + hor_sync_pulse - 1) and hcount >= (hor_active_video + hor_front_porch - 1)) then
        hsync <= '0';
      end if;
	end if;		
end process;

load_row: process(clock_dram, load_ack, hsync)
begin
	if (load_ack = '1') then
		load_req <= '0';
	elsif (rising_edge(clock_dram)) then
		if (hsync = '0') then
			load_req <= '1';
		end if;
	end if;
end process;

pixel_out: process (clock_dram, hcount, vcount)
begin
	if (rising_edge(clock_dram)) then	
		col_number <= hcount(9 downto 0);		
	end if;
end process;

pixel: process(clock_vga, hcount, vcount, videoh, videov, pixel_in, hsync, vsync)
variable blank: std_logic;
variable vga_pixel: unsigned(7 downto 0);
begin
	if (rising_edge(clock_vga)) then

		blank := videoh and videov;		
		
		if (video_active = '0') then
			vga_pixel := pixel_in;
		else
			--vga_pixel := not(vcount(8 downto 1) xor hcount(8 downto 1));
			vga_pixel(7 downto 0) := "00000000";
			
			if (vcount < 120) then
				vga_pixel(7 downto 5) := bar_color;
			elsif (vcount < 240) then
				vga_pixel(4 downto 2) := bar_color;
			elsif (vcount < 360) then
				vga_pixel(1 downto 0) := bar_color(2 downto 1);
			else 
				vga_pixel(7 downto 0) := bar_color & bar_color & bar_color(2 downto 1);
			end if;
			
		end if;

		if (scanline = '0' and vcount(0) = '0') then
			--vga_pixel := '0'&vga_pixel(7 downto 6) & '0'&vga_pixel(4 downto 3) & '0'&vga_pixel(1);
			vga_pixel := f_scanline(vga_pixel(7 downto 5)) & f_scanline(vga_pixel(4 downto 2)) & f_scanline(vga_pixel(1 downto 0)&'0')(2 downto 1);
		end if;		

		vga_out(9 downto 2) <= vga_pixel and blank&blank&blank&blank&blank&blank&blank&blank;
		vga_out(1 downto 0) <= hsync & vsync;		
		
	end if;
end process;

process (clock_vga, vcount)
begin
	if (rising_edge(clock_vga)) then
		videov <= '1'; 
		if vcount > vert_active_video-1 or vcount < 1 then 
			videov <= '0';
		end if;	
   end if;
end process;


process (clock_vga, hcount)
begin
	if (rising_edge(clock_vga)) then
		videoh <= '1';
		if hcount > hor_active_video-1 then
			videoh <= '0';
		end if;
	end if;
end process;

end behavioral;