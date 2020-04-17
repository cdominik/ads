#!/usr/bin/perl
$version = 2.5;

# Usage information with:   ads -h
# Full manpage with:        perldoc ads

use List::Util qw[min max];

if (not @ARGV or $ARGV[0] =~ /^--?h(elp)?$/) { &usage(); exit(0); }

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

# Process command line options. We do it by hand, to allow
# an arbitraty mix between switches and other args
while ($arg = shift @ARGV) {
  print "Processing argment $arg\n" if $opt_d;
  if ($arg =~ /^-([rd])(.*)/) {
    # a switch without argument
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
    elsif ($1 eq "o") {push @object,  &fix_spaces($value); print "OBJECT:   $object[0]\n" if $opt_d}
    elsif ($1 eq "i") {push @orcid,   &fix_orcid($value);  print "ORCID:    $orcid[0]\n"  if $opt_d}
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

# Send the URL to the browser
print "Calling URL: $url\n" if $opt_d;
if    ($^O =~ /darwin/i) { exec "open '$url'";         }
elsif ($^O =~ /linux/i)  { exec "xdg-open '$url'";     }
elsif ($^O =~ /mswin/i)  { exec "cmd /c start '$url'"; }
elsif ($^O =~ /cygwin/i) { exec "cygstart '$url'";     }
else                     { exec "open '$url'";         } # Fallback option

# And .... we are done

# ==========================================================================
# ==========================================================================

# Subroutines

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
  # Interpret a year specification
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
  # Interpret shortened year specifications
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

sub fix_orcid {
  # Add leading zeros to an incomplete ORCID
  my $o = shift @_;
  my $template = "0000-0000-0000-0000";
  my $lo = length($o);
  my $lt = length($template);
  $o = substr($template,0,-$lo) . $o if $lo < $lt;
  die "Invalid ORCID $o\n" unless $o =~ /^\d{4}-\d{4}-\d{4}-\d{4}$/;
  return $o;
}

sub fix_spaces {
  # Replace underscore with space
  my $s = shift @_;
  $s =~ s/_/ /g;
  return $s;
}

sub get_sorting {
  # Repeatedly apply the sorting hash until we get to the full name.
  # This has to do with the way the sorting hash %shash points from
  # each abbreviation to the canonical abbreviation, and then from the
  # canonical abbreviation to the full sorting keyword.
  my $s = shift @_;
  my $s1;
  $s1 = $s;
  $s = $shash{$s} while length($s) < 4;
  print "Sorting option '$s1' translated to '$s'\n" if $opt_d and $s1 ne $s;
  return $s;
}

sub encode_string {
  # Encode special characters and collapse multiple spaces
  my $s = shift @_;
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
  # Print usage information
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
* Switch and argument clustering:  ads -roVega -sc
* Full manpage with:               perldoc ads
END
}

=pod

=head1 NAME

B<ads> - commandline access to ADS (Astrophysical Data System)

=head1 SYNOPSIS

Make the F<ads> file executable and put in on your execution path.
Then use the command like this:

ads [options] [author]... [year] [endyear]

=head1 DESCRIPTION

B<ads> is a commandline tool to pass a query to the website of the
Astrophysical Data System (ADS). The tool constructs a query and
sends it to the default web browser. B<ads> takes author names and
publishing years from the command line with as little fuss as
possible. Additional search fields can be specified using command line
switches, still a lot faster than the web form.

Alphabetic arguments are parsed as author names. Quotes are only
necessary to protect whitespace inside a name. Alternatively, replace
spaces with underscore C<_> characters. A first name can be added like
C<first.last> (separated by dot) or C<last,first> (separated by
comma). Only the initial letter of the first name is significant, so
C<last,f> and C<last,first> are equivalent.

Arguments that are numbers are interpreted as publishing years. Single
or two-digit years are moved into the 20th and 21st century under the
assumption that the specified year is intended to be at most 1 year
into the future. A second year-like argument or something like
'2012-2014' specifies a range. A year ending with `-` means starting
from that year.

=head1 OPTIONS

=over 5

=item B<-t> STRING

String to matched in the TITLE field, as a phrase.  Repeat the switch
for multiple strings to be matched.

=item B<-a> STRING

Like B<-t>, but match in the ABSTRACT.

=item B<-f> STRING

Like B<-t>, but match in the FULL TEXT.

=item B<-o> OBJECT

An astronomical object to search for. Use multiple B<-o> switches for
multiple objects.  Use C<_> instead of space characters.

=item B<-i> ORCID

Search for an author by ORCID identifier. Several B<-i> switches can
be given, and leading zeros in an ORCID can be left out.

=item B<-s> SORTING

Sorting mode for matched entries. The DEFAULT is 'date', to sort by
date.  Values can be given in full, or be abbreviated. The allowed
values and abbreviations are:

  d                  => date                # This is the default
  a  fa              => first_author
  c  cc              => citation_count
  n  cn ccn nc ncc   => citation_count_norm
  s                  => score

=item B<-r>

Only list refereed sources. Default is to list also unrefereed
sources.

=item B<-d>

Print debugging information. Make this the first command line
argument in order to be useful.

=back

=head1 EXAMPLES

Get papers by Dullemond and Dominik written in 2004.

    ads Dullemond Dominik,C 2004

Same authors, but only the papers where Dullemond is first author, and
in the range from 2000 to 2004.

    ads -r ^Dullemond Dominik 2000 2004
    ads -r ^Dullemond Dominik 2000-2004
    ads -r ^Dullemond Dominik 0-4

Get papers of Ed van den Heuvel. This example shows that spaces in
name field can be replaced by the underscore character, if you don't
want to quote the name.

    ads "van den heuvel,E"
    ads van_den_heuvel,E

Papers by Antonella Natta, sorted by normalized citations.

    ads -sn a.natta

Unlike most unix commands, this command also allows to give the switch
arguments after or mixed with the author and year arguments, because
additional constraints sometimes present themselves while constructing
the query.

    ads natta,a -t protostar 1990 -sn 2000

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

