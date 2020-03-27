PROJECTS = K:\jff\AmigaHD\PROJETS
TARGET_DIR = $(PROJECTS)\CD32GAMES\CDTEST

WHDLOADER = $(TARGET_DIR)/$(PROGNAME).cdslave
SOURCE = $(PROGNAME)CDS.s
WHDBASE = $(PROJECTS)\WHDLoad
all :  $(WHDLOADER)

$(WHDLOADER) : $(SOURCE)
	wdate.py> datetime
	vasmm68k_mot -DDATETIME -IK:/jff/AmigaHD/amiga39_JFF_OS/include -I$(WHDBASE)\Include -I$(WHDBASE)\Src\sources\whdload -phxass -nosym -Fhunkexe -o $(WHDLOADER) $(SOURCE)
