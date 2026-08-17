.PHONY: default pdf clean

default: pdf

pdf:
	pdflatex --shell-escape main.tex
	pdflatex --shell-escape main.tex

clean:
	rm -f main.pdf main.aux main.log main.toc main.out \
	      main.lof main.lot main.idx main.ilg main.ind \
	      _minted-main
	rm -rf _minted-main
