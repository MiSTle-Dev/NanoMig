always @* case(opc_l[2:0])
	3'd0: misc_e = 20'h801FE;
	3'd1: misc_e = 20'h80004;
	3'd2: misc_e = 20'h80010;
	3'd3: misc_e = 20'h80224;
	3'd4: misc_e = 20'h80414;
	3'd5: misc_e = 20'h80212;
	3'd6: misc_e = 20'h80808;
	3'd7: misc_e = 20'h80218;
endcase
