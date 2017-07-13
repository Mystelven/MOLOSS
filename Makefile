OCB = ocamlbuild -classic-display \
			-use-menhir \
			-libs unix \
			-package msat \
			-package minisat 

TARGET = native

PDFLTX = pdflatex -synctex=1 -interaction=nonstopmode

all:  main

tst:
	$(OCB) source/test.$(TARGET) 

main:
	$(OCB) source/main.$(TARGET) 
	mv main.native moloss

rapport: 
	cd report; dot -Tpdf dep.dot -o dep.pdf
	cd report; $(PDFLTX) report.tex; bibtex report.aux; $(PDFLTX) report.tex
	mv report/report.pdf ./

doc:
	$(OCB) -I _build/ source/solve.docdir/dep.dot
	$(OCB) -I _build/ source/solve.docdir/index.html
	ln -f -s solve.docdir/index.html 

graph:
	dot -Tpdf solve.docdir/dep.dot -o dep.pdf


clean:
	rm -rf _build/
	rm -f *.pdf
	rm -f moloss direct
	rm -f *.native
	rm -f *.html
	rm -f *.sh
	rm -rf solve.docdir
	cd report; rm -rf *.aux *.log *.out *.toc *.pdf *.bbl *.blg *.gz
	rm -rf *~

realclear:
	rm -f *~
