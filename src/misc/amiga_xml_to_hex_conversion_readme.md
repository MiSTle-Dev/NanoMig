After changes in the configuration file for the onscreen menu,
the **xml** file needs to be converted to **hex** format, so
it can be used to build a core.
This can be done in **Linux** or **WSL** (Windows Subsystem for Linux),
with the following simple steps:

1.) gzip -n amiga.xml  
2.) xxd -c1 -p amiga.xml.gz > amiga_xml.hex
