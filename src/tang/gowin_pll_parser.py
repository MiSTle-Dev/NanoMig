#!/usr/bin/env python3

import sys

params = { }
with open(sys.argv[1]) as f:
    for line in f:
        parts = line.strip().rstrip(";").split()
        if len(parts) == 4 and parts[0].lower() == "defparam" and parts[2] == "=":
            name = parts[1].split(".")[-1].lower()
            value = parts[3].strip("\"")

            if value.lower() == "false": value = False 
            elif value.lower() == "true": value = True
            elif value.isdigit(): value = int(value)
            else: value = None

            if value != None:
                params[name] = value

if not "fclkin" in params:
    print("No input clock found!")
    sys.exit(-1)

fclkin = params["fclkin"]
    
if "fbdiv_sel" in params:  fbdiv = params["fbdiv_sel"]
else:                      fbdiv = 1

if "idiv_sel" in params:   idiv = params["idiv_sel"]
else:                      idiv = 1

if "mdiv_sel" in params:   mdiv = params["mdiv_sel"]
else:                      mdiv = 1

if "mdiv_frac_sel" in params: mdiv = mdiv + params["mdiv_frac_sel"]/8

print("Input clock:", fclkin, "Mhz")
pf = fclkin*fbdiv/idiv*mdiv
print("pf:", pf, "Mhz")

for i in range(8):
    if "clkout"+str(i)+"_en" in params and params["clkout"+str(i)+"_en"]:
        odiv = params["odiv"+str(i)+"_sel"]
        if "odiv"+str(i)+"_frac_sel" in params:
            odiv = odiv + params["odiv"+str(i)+"_frac_sel"]/8
        
        print("Output"+str(i)+":")
        print("  Freq:", pf/odiv, "Mhz")

        phase = params["clkout"+str(i)+"_pe_coarse"]
        phase = phase + params["clkout"+str(i)+"_pe_fine"]/8;
        phase = 360 * phase / odiv
        print("  Phase:", str(phase) + "°")

