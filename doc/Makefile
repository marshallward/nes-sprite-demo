# Documentation
.PHONY: doc
all: platforms.pdf asymptote

# This works for .asy but there could be others
.PHONY: asymptote
asymptote:
	make -C asy/

%.pdf: %.txt
	pandoc -f rst -t pdf -o $@ $<
