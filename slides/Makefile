CHAPTERS = chapter01 chapter02 chapter03 chapter04 chapter05 chapter06 chapter07 \
           chapter08 chapter09 chapter10 chapter11 chapter12 chapter13 chapter14 \
           chapter15 chapter16 chapter17 chapter18 chapter19 chapter20 chapter21 \
           chapter22 chapter23 chapter24 chapter25 chapter26 chapter27

PANDOC   = pandoc
FLAGS    = -t revealjs -s --slide-level=2 \
           -V theme=white \
           -V revealjs-url=../reveal.js \
           --mathjax

.PHONY: all clean apresentacao $(CHAPTERS)

all: apresentacao $(CHAPTERS)

apresentacao:
	$(PANDOC) $(FLAGS) apresentacao/apresentacao.md -o apresentacao/apresentacao.html

$(CHAPTERS):
	$(PANDOC) $(FLAGS) $@/slides.md -o $@/slides.html

clean:
	rm -f apresentacao/apresentacao.html
	rm -f $(CHAPTERS:%=%/slides.html)
