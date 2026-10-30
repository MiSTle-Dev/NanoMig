library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity TG68K_MMU030 is
	port(
		clk        : in  std_logic;
		reset      : in  std_logic;
		k_ena      : in  std_logic;
		cfg_wr     : in  std_logic;

		tc         : in  std_logic_vector(31 downto 0);
		crp        : in  std_logic_vector(63 downto 0);
		srp        : in  std_logic_vector(63 downto 0);
		tt0        : in  std_logic_vector(31 downto 0);
		tt1        : in  std_logic_vector(31 downto 0);

		l_addr     : in  std_logic_vector(31 downto 0);
		l_state    : in  std_logic_vector(1 downto 0);
		l_fc       : in  std_logic_vector(2 downto 0);
		l_rmw      : in  std_logic;
		l_uds      : in  std_logic;
		l_lds      : in  std_logic;
		l_wr       : in  std_logic_vector(15 downto 0);
		l_long     : in  std_logic;

		p_addr     : out std_logic_vector(31 downto 0);
		p_state    : out std_logic_vector(1 downto 0);
		p_uds      : out std_logic;
		p_lds      : out std_logic;
		p_wr       : out std_logic_vector(15 downto 0);
		p_long     : out std_logic;
		p_ci       : out std_logic;
		p_ack      : in  std_logic;
		p_rd       : in  std_logic_vector(15 downto 0);
		stall      : out std_logic;

		cmd_go     : in  std_logic;
		cmd_op     : in  std_logic_vector(2 downto 0);
		cmd_ea     : in  std_logic_vector(31 downto 0);
		cmd_fc     : in  std_logic_vector(2 downto 0);
		cmd_mask   : in  std_logic_vector(2 downto 0);
		cmd_rd     : in  std_logic;
		cmd_level  : in  std_logic_vector(2 downto 0);
		mmusr      : out std_logic_vector(15 downto 0);
		mmusr_we   : out std_logic;
		desc_addr  : out std_logic_vector(31 downto 0);

		fault      : out std_logic;
		f_ack      : in  std_logic
	);
end TG68K_MMU030;

architecture rtl of TG68K_MMU030 is

	constant N : integer := 22;

	type v24_t is array(0 to N-1) of std_logic_vector(23 downto 0);
	type v3_t  is array(0 to N-1) of std_logic_vector(2 downto 0);
	type ti_t  is array(0 to 3) of std_logic_vector(3 downto 0);

	signal a_log, a_phy : v24_t;
	signal a_fc         : v3_t;
	signal a_v          : std_logic_vector(N-1 downto 0) := (others => '0');
	signal a_h, a_b, a_ci, a_wp, a_m : std_logic_vector(N-1 downto 0) := (others => '0');

	type st_t is (S_IDLE, S_CMD, S_WSH, S_WROOT, S_WLEVEL, S_WIDX, S_WADDR, S_WFETCH, S_WEVAL,
	              S_WIND, S_WPAGE, S_WLIM, S_WWB, S_WDONE);
	signal st, w_ret : st_t;

	signal ti        : ti_t;
	signal last_t    : integer range 0 to 3;
	signal pm        : std_logic_vector(23 downto 0);
	signal lowm      : std_logic_vector(31 downto 0);

	signal need      : std_logic;
	signal xv        : std_logic;
	signal phys      : std_logic_vector(31 downto 0);
	signal ci_r      : std_logic;
	signal is_wr     : std_logic;
	signal f_hold    : std_logic;

	signal lk_addr   : std_logic_vector(31 downto 0);
	signal lk_fc     : std_logic_vector(2 downto 0);
	signal hit_v     : std_logic_vector(N-1 downto 0);
	signal hit       : std_logic;
	signal hit_i     : integer range 0 to N-1;
	signal rep_i     : integer range 0 to N-1;
	signal tt_hit    : std_logic;
	signal tt_ci     : std_logic;

	signal c_op      : std_logic_vector(2 downto 0);
	signal c_ea      : std_logic_vector(31 downto 0);
	signal c_fc      : std_logic_vector(2 downto 0);
	signal c_mask    : std_logic_vector(2 downto 0);
	signal c_rd      : std_logic;
	signal c_level   : std_logic_vector(2 downto 0);
	signal c_act     : std_logic;

	signal w_addr    : std_logic_vector(31 downto 0);
	signal w_fc      : std_logic_vector(2 downto 0);
	signal w_wr      : std_logic;
	signal w_test    : std_logic;
	signal w_sh      : std_logic_vector(31 downto 0);
	signal w_rem     : std_logic_vector(31 downto 0);
	signal w_cnt     : std_logic_vector(3 downto 0);
	signal w_idx     : std_logic_vector(14 downto 0);
	signal w_t       : integer range 0 to 4;
	signal w_num     : std_logic_vector(2 downto 0);
	signal w_tbl     : std_logic_vector(31 downto 0);
	signal w_da      : std_logic_vector(31 downto 0);
	signal w_wc      : std_logic_vector(1 downto 0);
	signal w_big     : std_logic;
	signal d_hi      : std_logic_vector(31 downto 0);
	signal d_lo      : std_logic_vector(31 downto 0);
	signal d_long    : std_logic;
	signal w_et      : std_logic;
	signal w_ind     : std_logic;
	signal w_pg      : std_logic_vector(31 downto 0);
	signal w_off     : std_logic_vector(31 downto 0);
	signal f_wp, f_sv, f_inv, f_lim, f_m, f_ci : std_logic;
	signal wb_data   : std_logic_vector(15 downto 0);

	signal b_addr    : std_logic_vector(31 downto 0);
	signal b_state   : std_logic_vector(1 downto 0);

	type u24_t is array(0 to 2) of std_logic_vector(23 downto 0);
	type u3_t  is array(0 to 2) of std_logic_vector(2 downto 0);
	signal u_log, u_phy : u24_t;
	signal u_fc         : u3_t;
	signal u_v, u_rok, u_wok, u_ci : std_logic_vector(2 downto 0) := (others => '0');
	signal u_s          : integer range 0 to 2;
	signal u_hit        : std_logic;
	signal tt_rhit      : std_logic;
	signal tt_whit      : std_logic;

	function tt_match(tt : std_logic_vector(31 downto 0); a : std_logic_vector(31 downto 0);
	                  fc : std_logic_vector(2 downto 0); rd : std_logic; rmw : std_logic) return std_logic is
	begin
		if tt(15) = '1'
		   and ((a(31 downto 24) xor tt(31 downto 24)) and not tt(23 downto 16)) = x"00"
		   and ((fc xor tt(6 downto 4)) and not tt(2 downto 0)) = "000"
		   and (tt(8) = '1' or (rmw = '0' and tt(9) = rd)) then
			return '1';
		end if;
		return '0';
	end function;

begin

	ti(0) <= tc(15 downto 12);
	ti(1) <= tc(11 downto 8);
	ti(2) <= tc(7 downto 4);
	ti(3) <= tc(3 downto 0);

	last_t <= 0 when tc(11 downto 8) = "0000" else
	          1 when tc(7 downto 4) = "0000" else
	          2 when tc(3 downto 0) = "0000" else 3;

	process (tc)
	begin
		pm <= (others => '1');
		lowm <= x"000000FF";
		for k in 0 to 6 loop
			if tc(23) = '1' and k < conv_integer(tc(22 downto 20)) then
				pm(k) <= '0';
				lowm(k + 8) <= '1';
			end if;
		end loop;
	end process;

	need  <= '1' when tc(31) = '1' and l_state /= "01" and l_fc /= "111" else '0';
	is_wr <= '1' when l_state = "11" or l_rmw = '1' else '0';

	lk_addr <= c_ea when c_act = '1' else l_addr;
	lk_fc   <= c_fc when c_act = '1' else l_fc;

	process (a_v, a_fc, a_log, lk_addr, lk_fc, pm)
	begin
		for i in 0 to N-1 loop
			if a_v(i) = '1' and a_fc(i) = lk_fc and ((a_log(i) xor lk_addr(31 downto 8)) and pm) = x"000000" then
				hit_v(i) <= '1';
			else
				hit_v(i) <= '0';
			end if;
		end loop;
	end process;

	process (hit_v)
	begin
		hit <= '0';
		hit_i <= 0;
		for i in N-1 downto 0 loop
			if hit_v(i) = '1' then
				hit <= '1';
				hit_i <= i;
			end if;
		end loop;
	end process;

	process (a_v, a_h)
		variable f : boolean;
	begin
		rep_i <= 0;
		f := false;
		for i in 0 to N-1 loop
			if not f and a_v(i) = '0' then
				rep_i <= i;
				f := true;
			end if;
		end loop;
		for i in 0 to N-1 loop
			if not f and a_h(i) = '0' then
				rep_i <= i;
				f := true;
			end if;
		end loop;
	end process;

	tt_hit <= tt_match(tt0, lk_addr, lk_fc, not is_wr, l_rmw) or tt_match(tt1, lk_addr, lk_fc, not is_wr, l_rmw)
	          when c_act = '0' else
	          tt_match(tt0, lk_addr, lk_fc, c_rd, '0') or tt_match(tt1, lk_addr, lk_fc, c_rd, '0');
	tt_ci  <= (tt_match(tt0, l_addr, l_fc, not is_wr, l_rmw) and tt0(10)) or
	          (tt_match(tt1, l_addr, l_fc, not is_wr, l_rmw) and tt1(10));
	tt_rhit <= tt_match(tt0, l_addr, l_fc, '1', l_rmw) or tt_match(tt1, l_addr, l_fc, '1', l_rmw);
	tt_whit <= tt_match(tt0, l_addr, l_fc, '0', l_rmw) or tt_match(tt1, l_addr, l_fc, '0', l_rmw);

	u_s   <= 0 when l_state(1) = '0' else 1 when l_state(0) = '0' else 2;
	u_hit <= '1' when st = S_IDLE and f_hold = '0' and u_v(u_s) = '1' and u_fc(u_s) = l_fc and
	                  ((u_log(u_s) xor l_addr(31 downto 8)) and pm) = x"000000" and
	                  ((is_wr = '1' and u_wok(u_s) = '1') or (is_wr = '0' and u_rok(u_s) = '1')) else '0';

	stall <= '1' when st /= S_IDLE or (need = '1' and xv = '0' and u_hit = '0') else '0';
	fault <= f_hold;

	process (st, need, xv, u_hit, u_s, u_phy, u_ci, pm, l_addr, l_state, phys, b_addr, b_state, l_uds, l_lds, l_wr, l_long, wb_data, ci_r)
	begin
		if st = S_IDLE then
			if need = '1' then
				if xv = '1' then
					p_addr <= phys;
				else
					p_addr <= (u_phy(u_s) or (l_addr(31 downto 8) and not pm)) & l_addr(7 downto 0);
				end if;
				if xv = '1' or u_hit = '1' then
					p_state <= l_state;
				else
					p_state <= "01";
				end if;
			else
				p_addr <= l_addr;
				p_state <= l_state;
			end if;
			p_uds  <= l_uds;
			p_lds  <= l_lds;
			p_wr   <= l_wr;
			p_long <= l_long;
			if xv = '1' then
				p_ci <= ci_r and need;
			else
				p_ci <= u_ci(u_s) and need;
			end if;
		else
			p_addr  <= b_addr;
			p_state <= b_state;
			p_uds   <= '0';
			p_lds   <= '0';
			p_wr    <= wb_data;
			p_long  <= '0';
			p_ci    <= '1';
		end if;
	end process;

	process (clk)
		variable dt   : std_logic_vector(1 downto 0);
		variable sv   : std_logic;
		variable wp   : std_logic;
		variable nd   : std_logic_vector(15 downto 0);
		variable hn   : std_logic_vector(N-1 downto 0);
		variable lv   : std_logic_vector(14 downto 0);
		variable viol : std_logic;
	begin
		if rising_edge(clk) then
			mmusr_we <= '0';
			if reset = '1' or f_ack = '1' then
				f_hold <= '0';
			end if;
			if reset = '1' then
				st <= S_IDLE;
				xv <= '0';
				c_act <= '0';
				b_state <= "01";
				u_v <= "000";
			else
				case st is

				when S_IDLE =>
					b_state <= "01";
					if need = '0' or (xv = '1' and p_ack = '1') then
						xv <= '0';
					end if;
					if need = '1' and xv = '0' and u_hit = '0' and f_hold = '0' then
						if tt_hit = '1' then
							phys <= l_addr;
							ci_r <= tt_ci;
							xv <= '1';
							u_v(u_s) <= '1';
							u_fc(u_s) <= l_fc;
							u_log(u_s) <= l_addr(31 downto 8) and pm;
							u_phy(u_s) <= l_addr(31 downto 8) and pm;
							u_rok(u_s) <= tt_rhit;
							u_wok(u_s) <= tt_whit;
							u_ci(u_s) <= tt_ci;
						elsif hit = '1' and (a_b(hit_i) = '1' or (is_wr = '1' and a_wp(hit_i) = '1')) then
							f_hold <= '1';
						elsif hit = '1' and (is_wr = '0' or a_m(hit_i) = '1') then
							phys <= ((a_phy(hit_i) and pm) or (l_addr(31 downto 8) and not pm)) & l_addr(7 downto 0);
							ci_r <= a_ci(hit_i);
							xv <= '1';
							u_v(u_s) <= '1';
							u_fc(u_s) <= l_fc;
							u_log(u_s) <= l_addr(31 downto 8) and pm;
							u_phy(u_s) <= a_phy(hit_i) and pm;
							u_rok(u_s) <= not tt_rhit;
							u_wok(u_s) <= not tt_whit and a_m(hit_i) and not a_wp(hit_i);
							u_ci(u_s) <= a_ci(hit_i);
							hn := a_h;
							hn(hit_i) := '1';
							if hn = (hn'range => '1') then
								hn := (others => '0');
								hn(hit_i) := '1';
							end if;
							a_h <= hn;
						else
							if hit = '1' then
								a_v(hit_i) <= '0';
							end if;
							w_addr <= l_addr;
							w_fc <= l_fc;
							w_wr <= is_wr;
							w_test <= '0';
							st <= S_WSH;
						end if;
					end if;
					if (cmd_go = '1' or cfg_wr = '1') and k_ena = '1' then
						u_v <= "000";
					end if;
					if cmd_go = '1' and k_ena = '1' then
						c_op <= cmd_op;
						c_ea <= cmd_ea;
						c_fc <= cmd_fc;
						c_mask <= cmd_mask;
						c_rd <= cmd_rd;
						c_level <= cmd_level;
						c_act <= '1';
						xv <= '0';
						st <= S_CMD;
					end if;
					w_sh <= l_addr;
					w_rem <= (others => '1');
					w_cnt <= tc(19 downto 16);
					w_num <= "000";
					w_t <= 0;
					w_et <= '0';
					w_ind <= '0';
					f_wp <= '0'; f_sv <= '0'; f_inv <= '0'; f_lim <= '0'; f_m <= '0'; f_ci <= '0';
					if tc(25) = '1' and l_fc(2) = '1' then
						d_hi <= srp(63 downto 32);
						d_lo <= srp(31 downto 0);
					else
						d_hi <= crp(63 downto 32);
						d_lo <= crp(31 downto 0);
					end if;
					d_long <= '1';

				when S_CMD =>
					w_sh <= c_ea;
					w_rem <= (others => '1');
					w_cnt <= tc(19 downto 16);
					w_num <= "000";
					w_t <= 0;
					w_et <= '0';
					w_ind <= '0';
					f_wp <= '0'; f_sv <= '0'; f_inv <= '0'; f_lim <= '0'; f_m <= '0'; f_ci <= '0';
					if tc(25) = '1' and c_fc(2) = '1' then
						d_hi <= srp(63 downto 32);
						d_lo <= srp(31 downto 0);
					else
						d_hi <= crp(63 downto 32);
						d_lo <= crp(31 downto 0);
					end if;
					d_long <= '1';
					w_addr <= c_ea;
					w_fc <= c_fc;
					w_wr <= not c_rd;
					st <= S_IDLE;
					c_act <= '0';
					case c_op is
						when "001" =>
							a_v <= (others => '0');
						when "100" =>
							for i in 0 to N-1 loop
								if ((a_fc(i) xor c_fc) and c_mask) = "000" then
									a_v(i) <= '0';
								end if;
							end loop;
						when "110" =>
							for i in 0 to N-1 loop
								if ((a_fc(i) xor c_fc) and c_mask) = "000" and ((a_log(i) xor c_ea(31 downto 8)) and pm) = x"000000" then
									a_v(i) <= '0';
								end if;
							end loop;
						when "010" =>
							if hit = '1' then
								a_v(hit_i) <= '0';
							end if;
							w_test <= '0';
							c_act <= '1';
							st <= S_WSH;
						when "011" =>
							if c_level = "000" then
								desc_addr <= (others => '0');
								mmusr_we <= '1';
								if tt_hit = '1' then
									mmusr <= x"0040";
								elsif hit = '0' then
									mmusr <= x"0400";
								else
									mmusr <= a_b(hit_i) & "000" & a_wp(hit_i) & a_b(hit_i) & a_m(hit_i) & "000000000";
								end if;
							else
								w_test <= '1';
								c_act <= '1';
								st <= S_WSH;
							end if;
						when others => null;
					end case;

				when S_WSH =>
					if w_cnt /= "0000" then
						w_sh <= w_sh(30 downto 0) & '0';
						w_rem <= '0' & w_rem(31 downto 1);
						w_cnt <= w_cnt - 1;
					else
						st <= S_WROOT;
					end if;

				when S_WROOT =>
					dt := d_hi(1 downto 0);
					w_big <= dt(0);
					if dt = "00" then
						f_inv <= '1';
						st <= S_WDONE;
					elsif dt = "01" then
						w_et <= '1';
						st <= S_WPAGE;
					elsif tc(24) = '1' then
						w_tbl <= d_lo(31 downto 4) & "0000";
						w_idx <= "000000000000" & w_fc;
						st <= S_WADDR;
					else
						st <= S_WLEVEL;
					end if;

				when S_WLEVEL =>
					w_cnt <= ti(w_t);
					w_idx <= (others => '0');
					st <= S_WIDX;

				when S_WIDX =>
					if w_cnt /= "0000" then
						w_idx <= w_idx(13 downto 0) & w_sh(31);
						w_sh <= w_sh(30 downto 0) & '0';
						w_rem <= '0' & w_rem(31 downto 1);
						w_cnt <= w_cnt - 1;
					else
						viol := '0';
						if d_long = '1' then
							if d_hi(31) = '1' then
								if w_idx < d_hi(30 downto 16) then viol := '1'; end if;
							else
								if w_idx > d_hi(30 downto 16) then viol := '1'; end if;
							end if;
						end if;
						if viol = '1' then
							f_lim <= '1';
							f_inv <= '1';
							st <= S_WDONE;
						else
							if d_long = '1' then
								w_tbl <= d_lo(31 downto 4) & "0000";
							else
								w_tbl <= d_hi(31 downto 4) & "0000";
							end if;
							w_t <= w_t + 1;
							st <= S_WADDR;
						end if;
					end if;

				when S_WADDR =>
					if w_big = '1' then
						w_da <= w_tbl + ("00000000000000" & w_idx & "000");
					else
						w_da <= w_tbl + ("000000000000000" & w_idx & "00");
					end if;
					w_num <= w_num + 1;
					w_wc <= "00";
					st <= S_WFETCH;

				when S_WFETCH =>
					b_addr <= w_da + ("00000000000000000000000000000" & w_wc & '0');
					b_state <= "10";
					if b_state = "10" and p_ack = '1' then
						b_state <= "01";
						case w_wc is
							when "00" => d_hi(31 downto 16) <= p_rd;
							when "01" => d_hi(15 downto 0) <= p_rd;
							when "10" => d_lo(31 downto 16) <= p_rd;
							when others => d_lo(15 downto 0) <= p_rd;
						end case;
						if w_wc = (w_big & '1') then
							d_long <= w_big;
							st <= S_WEVAL;
						else
							w_wc <= w_wc + 1;
						end if;
					end if;

				when S_WEVAL =>
					dt := d_hi(1 downto 0);
					if w_ind = '1' then
						if dt = "01" then
							st <= S_WPAGE;
						else
							f_inv <= '1';
							st <= S_WDONE;
						end if;
					elsif dt = "00" then
						f_inv <= '1';
						st <= S_WDONE;
					elsif dt = "01" then
						if w_t <= last_t then
							w_et <= '1';
						end if;
						st <= S_WPAGE;
					else
						w_big <= dt(0);
						sv := f_sv;
						if w_t <= last_t and d_long = '1' and d_hi(8) = '1' and w_fc(2) = '0' then
							sv := '1';
						end if;
						f_sv <= sv;
						if w_t <= last_t and d_hi(2) = '1' then
							f_wp <= '1';
						end if;
						if w_test = '1' and w_num = c_level then
							w_ret <= S_WDONE;
						elsif w_t <= last_t then
							w_ret <= S_WLEVEL;
						else
							w_ret <= S_WIND;
						end if;
						if w_t <= last_t and w_test = '0' and d_hi(3) = '0' and sv = '0' then
							wb_data <= d_hi(15 downto 4) & '1' & d_hi(2 downto 0);
							st <= S_WWB;
						elsif w_test = '1' and w_num = c_level then
							st <= S_WDONE;
						elsif w_t <= last_t then
							st <= S_WLEVEL;
						else
							st <= S_WIND;
						end if;
					end if;

				when S_WIND =>
					if d_long = '1' then
						w_da <= d_lo(31 downto 2) & "00";
					else
						w_da <= d_hi(31 downto 2) & "00";
					end if;
					w_num <= w_num + 1;
					w_wc <= "00";
					w_ind <= '1';
					st <= S_WFETCH;

				when S_WPAGE =>
					sv := f_sv;
					wp := f_wp;
					nd := d_hi(15 downto 0);
					if w_num /= "000" then
						if d_long = '1' and d_hi(8) = '1' and w_fc(2) = '0' then
							sv := '1';
						end if;
						if d_hi(2) = '1' then
							wp := '1';
						end if;
						if w_test = '0' and sv = '0' then
							if w_wr = '1' and wp = '0' then
								nd(4) := '1';
							end if;
							nd(3) := '1';
						end if;
						f_ci <= d_hi(6);
						f_m <= nd(4);
					else
						f_m <= w_wr and not w_test;
					end if;
					f_sv <= sv;
					f_wp <= wp;
					if d_long = '1' then
						w_pg <= d_lo(31 downto 8) & x"00";
					else
						w_pg <= d_hi(31 downto 8) & x"00";
					end if;
					w_off <= w_addr and w_rem and not lowm;
					if w_et = '1' and d_long = '1' then
						w_ret <= S_WLIM;
						w_cnt <= ti(w_t);
						w_idx <= (others => '0');
					else
						w_ret <= S_WDONE;
					end if;
					if nd /= d_hi(15 downto 0) then
						wb_data <= nd;
						d_hi(15 downto 0) <= nd;
						st <= S_WWB;
					elsif w_et = '1' and d_long = '1' then
						w_cnt <= ti(w_t);
						w_idx <= (others => '0');
						st <= S_WLIM;
					else
						st <= S_WDONE;
					end if;

				when S_WLIM =>
					if w_cnt /= "0000" then
						w_idx <= w_idx(13 downto 0) & w_sh(31);
						w_sh <= w_sh(30 downto 0) & '0';
						w_cnt <= w_cnt - 1;
					else
						viol := '0';
						if d_hi(31) = '1' then
							if w_idx < d_hi(30 downto 16) then viol := '1'; end if;
						else
							if w_idx > d_hi(30 downto 16) then viol := '1'; end if;
						end if;
						if viol = '1' then
							f_lim <= '1';
							f_inv <= '1';
						end if;
						st <= S_WDONE;
					end if;

				when S_WWB =>
					b_addr <= w_da(31 downto 2) & "10";
					b_state <= "11";
					if b_state = "11" and p_ack = '1' then
						b_state <= "01";
						st <= w_ret;
					end if;

				when S_WDONE =>
					st <= S_IDLE;
					c_act <= '0';
					if w_test = '1' then
						mmusr <= (f_inv and '0') & f_lim & f_sv & '0' & f_wp & f_inv & f_m & "000000" & w_num;
						if w_num = "000" then
							desc_addr <= (others => '0');
						else
							desc_addr <= w_da;
						end if;
						mmusr_we <= '1';
					else
						a_log(rep_i) <= w_addr(31 downto 8) and pm;
						a_fc(rep_i)  <= w_fc;
						a_phy(rep_i) <= (w_pg(31 downto 8) + w_off(31 downto 8)) and pm;
						a_v(rep_i)   <= '1';
						a_b(rep_i)   <= f_inv or f_sv;
						a_ci(rep_i)  <= f_ci;
						a_wp(rep_i)  <= f_wp;
						a_m(rep_i)   <= f_m;
						hn := a_h;
						hn(rep_i) := '1';
						if hn = (hn'range => '1') then
							hn := (others => '0');
							hn(rep_i) := '1';
						end if;
						a_h <= hn;
					end if;

				end case;
			end if;
		end if;
	end process;

end rtl;
