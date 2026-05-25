import geometry;

// Sans serif
texpreamble("\usepackage{sfmath}");
texpreamble("\renewcommand{\familydefault}{\sfdefault}");

//// Needs the XeTeX family of tools
//// But this is not yet working.
//settings.tex = "xelatex";
//texpreamble("\usepackage{fontspec}");
//texpreamble("\setmainfont{DejaVu Sans}");
//texpreamble("\usepackage{unicode-math}");
//texpreamble("\setmathfont{DejaVu Math TeX Gyre}");

settings.outformat="svg";

picture pic1;
picture pic2;

pair A = (0,0);
pair B = (3,1);
pair P = (1,2);
pair Q = (2.5,-0.5);

void platform(picture pic=currentpicture) {
    size(pic, 200);
    draw(pic, A--B, linewidth(2));
    draw(pic, P--Q, linewidth(1.25), Arrow(6));

    label(pic, "A", A, W);
    label(pic, "B", B, E);
    label(pic, "P", P, N);
    label(pic, "Q", Q, S);
}

platform(pic1);
platform(pic2);

// Across-platform test

draw(pic1, A--P, Arrow(6));
draw(pic1, A--Q, Arrow(6));

markangle(pic1, "$\phi_P$", radius=15, B, A, P);
markangle(pic1, "$\phi_Q$", radius=-15, B, A, Q);

// Along-platform test

draw(pic2, P--A, Arrow(6));
draw(pic2, P--B, Arrow(6));

markangle(pic2, "$\phi_A$", radius=-15, Q, P, A);
markangle(pic2, "$\phi_B$", radius=15, Q, P, B);

shipout("cross_platform", pic1);
shipout("along_platform", pic2);
