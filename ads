#!/usr/bin/perl
$version = 2.4;

# Usage information with:   ads -h
# Full manpage with:        perldoc ads

use List::Util qw[min max];

if (not @ARGV or $ARGV[0] =~ /^--?h(elp)?$/) { &usage(); exit(0) }

# Defaults for stuff that can be set with options
$sort       = "date";
$sort_dir   = "desc";

%shash =  ( c => "citation_count",      cc  => "c",
            n => "citation_count_norm", cn  => "n", nc  => "n",
                                        ccn => "n", ncc => "n",
            f => "classic_factor",      cf  => "f",
            a => "first_author",        fa  => "a",
            d => "date",
            e => "entry_date",          ed  => "e",
            r => "read_count",          rc  => "r",
            s => "score",
            ac=> "author_count",        na  => "ac"
  );

# Process command line options. We do it by hand, to allow,
# an arbitraty mix between switches and other args
while ($arg = shift @ARGV) {
  print "Processing argment $arg\n" if $opt_d;
  if ($arg =~ /^-([rd])(.*)/) {
    # a switch without arguments
    if ($1 eq "r") {
      $opt_r = 1; print "REFEREED only\n" if $opt_d;
    } else {$opt_d=1}
    # Put the rest back onto ARGV
    unshift @ARGV,"-".$2 if $2;
  } elsif ($arg =~ /^-([tafsoi])(.*)/) {
    # A switch with a value
    $value = length($2)>0 ? $2 : shift @ARGV;
    if ($1 eq "s") {$opt_s = $value;          print "SORTING:  $value\n" if $opt_d}
    elsif ($1 eq "t") {push @title,   $value; print "TITLE:    $value\n" if $opt_d}
    elsif ($1 eq "a") {push @abstract,$value; print "ABSTRACT: $value\n" if $opt_d}
    elsif ($1 eq "f") {push @fulltext,$value; print "FULLTEXT: $value\n" if $opt_d}
    elsif ($1 eq "o") {push @object,  $value; print "OBJECT:   $value\n" if $opt_d}
    elsif ($1 eq "i") {push @orcid,   $value; print "ORCID:    $value\n" if $opt_d}
  } elsif ($arg =~ /^-/) {
    die "Unknown command line switch `$arg'.\nRun `ads' for usage info, `perldoc ads' for full manpage.\n"      
  } elsif ($arg =~ /^[0-9][-0-9]*$/) {
    # This is a year specification
    &handle_year($arg);
  } else {
    # Everything else is an author name
    &handle_author($arg);
  }
}

if (@years) {
  $y1 = min @years;
  $y2 = max @years;
  $years = " year:";
  if ($force_yr_range) {$years .= "$y1-"}
  elsif ($y2 > $y1) {$years .= "$y1-$y2"}
  else {$years .= $y1}
}

while ($a=shift(@authors)) { $authors .= " author:\"$a\""; }
$authors =~ s/ //;

$title    .= sprintf(' title:"%s"'  ,shift(@title))    while @title;
$abstract .= sprintf(' abs:"%s"'    ,shift(@abstract)) while @abstract;
$fulltext .= sprintf(' full:"%s"'   ,shift(@fulltext)) while @fulltext;
$object   .= sprintf(' object:"%s"' ,shift(@object))   while @object;
$orcid    .= sprintf(' orcid:"%s"'  ,shift(@orcid))    while @orcid;

if ($opt_s) {
  unless ($shash{$opt_s}) {    
    print STDERR "Invalid sorting option '$opt_s', falling back to date sorting\n";
    $opt_s = "date";
  }
  # get the official sorting key out of the hash, if necessary by a chain
  $sort = &get_sorting($opt_s);
}

if ($sort eq "first_author") {$sort_dir = "asc";} # change sort direction
$sorting  = "&sort=$sort $sort_dir, bibcode desc";

$refstring =  "filter_property_fq_property=AND&filter_property_fq_property=property%3A%22refereed%22&fq=%7B!type=aqp%20v%3D%24fq_property%7D&fq_property=(property%3A%22refereed%22)&";

$url = "q=" . " $authors$years"
  . $title . $abstract . $fulltext . $object . $orcid
  . "$sorting" . "&p_=0";

# Encode special characters
$url = &encode_string($url);

# Put everything together
$url = "https://ui.adsabs.harvard.edu/search/"
  . ($opt_r ? $refstring : "") . $url;

print "Calling URL: $url\n" if $opt_d;

if    ($^O =~ /darwin/i)  {  exec "open '$url'";         }
elsif ($^O =~ /linux/i)   {  exec "xdg-open '$url'";     }
elsif ($^O =~ /mswin/i)   {  exec "cmd /c start '$url'"; }
elsif ($^O =~ /cygwin/i)  {  exec "cygstart '$url'";     }
else                      {  exec "open '$url'";         } # Fallback option

sub handle_author {
  # Put initials in the back, and convert underscore to space
  my $a = shift;
  my $a1 = $a;
  $a = "$3,$1" if $a =~ /((\w+\.)+)(.+)/;
  $a =~ s/_/ /g;
  $a =~ s/^\s+//;
  $a =~ s/\s+$//;
  $a =~ s/\.$//;
  if ($a eq $a1) {
    printf "Adding author \"$a\"\n" if $opt_d;
  } else {
    printf "Adding author \"$a1\" as \"$a\"\n" if $opt_d;
  }
  push @authors,$a;
}

sub handle_year {
  my $ys = shift;
  die "Bad year argument $ys\n" unless $ys =~ /^([0-9]+)(-([0-9]+)?)?/;
  ($y1,$y2) = ($1,$3);
  $force_yr_range = 1 if $ys =~ /-$/;  # Dash at end, force range to today
  $y1 = &normalize_year($y1);
  $y2 = &normalize_year($y2);
  if ($y1) {push @years,$y1; print "YEAR: $y1\n" if $opt_d;}
  if ($y2) {push @years,$y2; print "YEAR: $y2\n" if $opt_d;}
}

sub normalize_year {
  my $y = shift @_;
  return "" if $y =~ /^ *$/;    # year was empty
  if ($y < 100) {
    # two digit year - check of 19.. or 20.. is meant
    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
    $two_d_year = substr $year,1;
    $yn = $y + ($y <= $two_d_year+1 ? 2000 : 1900);
    print "Year $y interpreted as $yn\n" if $opt_d;
    $y = $yn;
  }
  return $y;
}

sub get_sorting {
  my $s = shift @_;
  $s1 = $s;
  $s = $shash{$s} while length($s) < 4;
  print "Sorting option '$s1' translated to '$s'\n" if $opt_d and $s1 ne $s;
  return $s;
}

sub encode_string {
  my $s = shift @_;
  # Encode special characters and collapse multiple spaces
  $s =~ s/"/%22/g;
  $s =~ s/ +/%20/g;
  $s =~ s/,/%2C/g;
  $s =~ s/\$/%24/g;
  $s =~ s/\^/%5E/g;
  $s =~ s/:/%3A/g;
  $s =~ s/{/%7B/g;
  $s =~ s/}/%7D/g;
  return $s;
}

sub usage {
  # print usage information
  print <<'END';
USAGE:    ads [options] [author]... [year[-endyear]] [options]
OPTIONS:
   -s a|c|n|s  Sorting: author cite normcite score (default:date)
   -t STRING   Title phrase
   -a STRING   Abstract phrase
   -f STRING   Fulltext phrase
   -o OBJECT   Object name
   -i ORCID    ORCID search
   -r          refereed only
EXAMPLE: ads dominik,c -t rolling -s n -r 1995-2014
* Options and arguments can be arbitrarily mixed, see EXAMPLE.
* Switch repetition:               ads -t galaxy -t evolution
* Switch and argument clusting:    ads -roVega -sc
* Full manpage with:               perldoc ads
END
}

=pod

=head1 NAME

B<ads> - commandline access to ADS (Astrophysical data system)

=head1 SYNOPSIS

ads [options] [author]... [year] [endyear]

=head1 DESCRIPTION

B<ads> is a commandline tool to pass a query to the website of the
Astrophysical data system (ADS). The tool will construct a query and
send it to the default web browser. B<ads> takes author names and
publishing years from the command line with as little fuss as
possible. Some search parameters can be changed with command line
switches.

The main reason for writing this tool is that the author intensely
dislikes filling web forms on a regular basis.

Most arguments are parsed as author names. Necessary spaces in author
names can be given as underscores `_`, or be presented in quotes. To
be more specific than just a last name, a first name or initial can be
given like first.last (separated by dot) or last,first (separated by
comma). Only the initial letter of the first name is significant, so
last,f and last,first are equivalent.

Arguments that are numbers are interpreted as publishing year. Single
or two-digit years are moved into the 20th and 21st century under the
assumption that years are at most 1 year into the future. A second
year-like argument or something like '2012-2014' specifies a range. A
year ending with `-` means starting from that year.

=head1 OPTIONS

=over 5

=item B<-t> STRING

A string to put into the title search field. If there are several
words in a single B<-t> argument, the title will be searched for the
phrase. Use several B<-t> arguments to require the different words
anywhere in the title.

=item B<-a> STRING

A string to put into the abstract search field. See also B<-t> for
information about the effect of several B<-a> switches.

=item B<-f> STRING

A string to put into the fulltext search field. See also B<-t> for
information about the effect of several B<-f> switches.

=item B<-o> OBJECT

An object to search for. Use multiple B<-o>
switches for multiple objects.

=item B<-i> ORCID

Search for an author by ORCID identifier. Several B<-i> switches can
be given.

=item B<-s> SORTING

Sorting mode for matched entries. DEFAULT is 'date', to sort by date.
Values can be given in full, or be abbreviated. The allowed values and
abbreviations are:

   d                  => date                    # This is the default
   a  fa              => first_author
   c  cc              => citation_count
   n  cn ccn nc ncc   => citation_count_norm
   s                  => score

=item B<-r>

Only list refereed sources. Default is to list also unrefereed.

=item B<-d>

Print debugging information. Make this the first command line
argument in order to be most useful.

=back

=head1 EXAMPLES

Get papers by Dullemond and Dominik written in 2004.

    ads Dullemond Dominik,C 2004

Same authors, but only the papers where Dullemond is first author, and
in the range from 2000 to 2004.

    ads -r ^Dullemond Dominik 2000 2004
    ads -r ^Dullemond Dominik 2000-2004
    ads -r ^Dullemond Dominik 0-4

Get papers of Ewine van Dishoeck. This example shows that spaces in
name field can be replaced by the underscore character, if you don't
want to quote the name.

    ads "van dishoeck,E"
    ads van_dishoeck,E

Papers by Alexander Tielens, sorted by normalized citations.

    ads -sn a.tielens

Unlike most unix commands, this command also allows to give the switch
arguments after or mixed with the author and year arguments, because
additional constraints sometimes present themselves while constructing
the query.

    ads tielens,a -t interstellar 1979 -sn 1980

Find articles with the phrase "planet formation" in the abstract.

    ads -a "planet formation"

Find articles with both "planet" and "system" anywhere in the
abstract.

    ads -aplanet -a system

=head1 AUTHOR

Carsten Dominik    <dominik.dominik@gmail.com>

This program is free software. It it released under the rules like
Perl itself, so wither the GNU General Public License, or the Artistic
License.

=cut

