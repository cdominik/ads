# Makefile for 'ads'.  This file only cuts the embedded POD
# documentation from `ads' and copies it into the README.pod file, for
# github to find and format.

README.pod: ads
	perl -ne 'print if /^=pod/../^=cut/' ads > README.pod
