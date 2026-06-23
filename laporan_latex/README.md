# BAB 4 LaTeX

File utama:

```text
Laporan_BAB4.tex
```

Render dengan Times New Roman asli:

```powershell
cd laporan_latex
xelatex -interaction=nonstopmode Laporan_BAB4.tex
xelatex -interaction=nonstopmode Laporan_BAB4.tex
```

PDF hasil render:

```text
laporan_latex/Laporan_BAB4.pdf
```

Cuplikan kode di dokumen memakai `\lstinputlisting` dan mengambil langsung dari file source
project. Karena itu, render harus dilakukan dari folder `laporan_latex` di dalam project ini.
