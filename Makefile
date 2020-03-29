

README.pod: ads
	perl -ne 'print if /^=pod/../^=cut/' ads>README.pod
