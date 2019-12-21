LINK = phxlnk 
ASM = phxass


OBJDIR = /obj
EXEDIR = /bin


OBJS = $(OBJDIR)/main.o $(OBJDIR)/reloc.o $(OBJDIR)/rnloader.o

all : $(EXEDIR)/cd32load


clean:
	delete $(EXEDIR)/#? $(OBJDIR)/#?.o FORCE QUIET

$(EXEDIR)/cd32load	: $(OBJS) $(MAKEFILE)
	$(LINK) FROM $(OBJS) $(LINKOPTS) TO $(EXEDIR)/cd32load

	
$(OBJDIR)/main.o: util.asm main.asm macros.i struct.i
	$(ASM) main.asm TO $(OBJDIR)/main.o
	
# no optimize options for RN loader since it's direct IRA disassemble
$(OBJDIR)/rnloader.o: rnloader.asm
	$(ASM) OPT 0 rnloader.asm TO $(OBJDIR)/rnloader.o

$(OBJDIR)/pgloader.o: pgloader.asm
	$(ASM) OPT 0 pgloader.asm TO $(OBJDIR)/pgloader.o

$(OBJDIR)/reloc.o: whd.asm cdio.asm util.asm reloc.asm loaders.asm cd32loader.asm send_key_event.asm hunk.asm ReadJoyPad.s copymem.asm custom.asm \
    DebugScreen.s virtual_keyboard.asm virtual_mouse.asm macros.i struct.i RNC12Decrunch.asm TPWMDecrunch.asm ATNDecrunch.asm
	$(ASM) reloc.asm TO $(OBJDIR)/reloc.o
