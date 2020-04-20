#!/usr/bin/perl
$version = 2.6;

# Usage information with:   ads -h
# Full manpage with:        perldoc ads

use List::Util qw[min max];

if (not @ARGV or $ARGV[0] =~ /^--?h(elp)?$/) { &usage(); exit(0); }

# Some Defaults and option hashes

# Collections to be searched.  This can be P for "physics", A for "astronomy",
# or G for general.  Leave empty to search all by default.
$database = "";
%dhash = ( A => "astronomy", P => "physics", G => "general" );

# Sorting mode and direction
$sort     = "date";  $sort_dir = "desc";
%shash = ( c => "citation_count",      cc  => "c",
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
  if ($arg =~ /^-([rdcAPG])(.*)/) {
    # a switch without argument
    if ($1 eq "r")    { $opt_r = 1;  print "REFEREED only\n"      if $opt_d }
    elsif ($1 eq "c") { $opt_s = $1; print "Interpreted as -sc\n" if $opt_d }
    elsif ($1 eq "A" or $1 eq "P" or $1 eq "G") {
      $database = $1;
      print "Selecting $dhash{$1} database\n" if $opt_d;
    }
    else              { $opt_d = 1;  print "Debugging on\n" }
    # Put the rest back onto ARGV
    unshift @ARGV,"-".$2 if $2;
  } elsif ($arg =~ /^-([tafsoi])(.*)/) {
    # A switch with a value
    $value = length($2)>0 ? $2 : shift @ARGV;
    if ($1 eq "s")    {$opt_s = $value;       print "SORTING:  $value\n" if $opt_d}
    elsif ($1 eq "t") {push @title,   $value; print "TITLE:    $value\n" if $opt_d}
    elsif ($1 eq "a") {push @abstract,$value; print "ABSTRACT: $value\n" if $opt_d}
    elsif ($1 eq "f") {push @fulltext,$value; print "FULLTEXT: $value\n" if $opt_d}
    elsif ($1 eq "o") {push @object,  &fix_spaces($value); print "OBJECT:   $object[0]\n" if $opt_d}
    elsif ($1 eq "i") {push @orcid,   &fix_orcid($value);  print "ORCID:    $orcid[0]\n"  if $opt_d}
  } elsif ($arg =~ /^-?[0-9][-0-9]*$/) {
    # This is a year specification
    &handle_year($arg);
  } elsif ($arg =~ /^-/) {
    die "Unknown command line switch `$arg'.\nRun `ads' for usage info, `perldoc ads' for full manpage.\n";
  } else {
    # Everything else is an author name
    &handle_author($arg);
  }
}

if (@years) {
  $y1 = min @years;
  $y2 = max @years;
  print "tears $y1 $y2>>$force_yr_range<<\n";
  $years = " year:";
  if    ($y2 > $y1)                  {$years .= "$y1-$y2"}
  elsif ($force_yr_range eq "since") {$years .= "$y1-"}
  elsif ($force_yr_range eq "until") {$years .= "-$y2"}
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

$database = "&fq=database:$dhash{$database}" if $database;

if ($sort eq "first_author") {$sort_dir = "asc";} # change sort direction
$sorting  = "&sort=$sort $sort_dir, bibcode desc";

$refstring =  "filter_property_fq_property=AND&filter_property_fq_property=property%3A%22refereed%22&fq=%7B!type=aqp%20v%3D%24fq_property%7D&fq_property=(property%3A%22refereed%22)&";

$url = "q=" . " $authors$years"
  . $title . $abstract . $fulltext . $object . $orcid . $database
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
  my $y1,$y2;
  die "Bad year argument $ys\n" unless $ys =~ /^(-)?(\d+)(-(\d+)?)?/;
  if ($ys =~ /^(\d+)$/) {
    # Single year
    $y2 = $1;
  } elsif ($ys =~ /^-(\d+)$/) {
    # UNTIL range
    $force_yr_range = "until";
    $y2 = $1;
  } elsif ($ys =~ /^(\d+)-$/) {
    # SINCE range
    print "here\n";
    $force_yr_range = "since";
    $y1 = $1;
  } elsif ($ys =~ /^(\d+)-(\d+)$/) {
    # full range
    ($y1,$y2) = ($1,$2);
  } else { die "Something went wrong with year processing of $ys\n" }
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
    my $two_d_year = substr &current_year()+1900,2;
    my $yn = $y + ($y <= $two_d_year+1 ? 2000 : 1900);
    print "Year $y interpreted as $yn\n" if $opt_d;
    $y = $yn;
  }
  return $y;
}

sub current_year {
  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
  return $year;
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
   -t STRING   Title phrase
   -a STRING   Abstract phrase
   -f STRING   Fulltext phrase
   -o OBJECT   Object name
   -i ORCID    ORCID search
   -c          Sort by citation count instead of date (same as -sc)
   -r          Refereed only
   -A -P -G    Narrow to astronomy, physics or general database
   -s a|c|n|s  Sorting: author cite normcite score (default:date)
EXAMPLE: ads dominik,c -t rolling -sn -r 1995-2014
* Options and arguments can be arbitrarily mixed, see EXAMPLE.
* Switch repetition:               ads -t galaxy -t evolution
* Switch and argument clustering:  ads -roVega -sn
* Full manpage with:               perldoc ads
END
}

=pod

=head1 NAME

B<ads> - commandline access to ADS (Astrophysical Data System)

=head1 SYNOPSIS

Make the F<ads> file executable and put it on your execution path.

  ads [options] [author]... [year] [endyear]

=head1 DESCRIPTION

B<ads> is a commandline tool to pass a query to the website of the
Astrophysical Data System (ADS). The tool constructs a query URL and
sends it to the default web browser. B<ads> takes author names and
publishing years from the command line with as little fuss as
possible. Additional search fields and options can be specified using
command line switches.

=head1 ARGUMENTS and OPTIONS

=over 5

=item AUTHOR NAMES

I<Alphabetic> arguments are parsed as author names. To protect
whitespace in names, use quotes or replace space characters by
underscore C<_> characters. A first name initial can be added like
C<f.last> (separated by dot) or C<last,f> (separated by comma).  If
necessary, an exact author match can be done using B<-i> ORCID.

=item PUBLISHING YEARS

I<Numerical> arguments are interpreted as publishing years. Single or
two-digit years are moved into the 20th/21st century, such that the
year is the current year (+1) or earlier. Two numerical arguments or
an argument like '2012-2014' specify a range. '2004-' means since
2004, '-2004' means until 2004.

=item B<-t> STRING, B<-a> STRING, B<-f> STRING

String phrase to be matched in the I<title>, I<abstract>, or
I<fulltext>, respectively, of a bibliographic source.  Multiple
B<-t>/B<-a>/B<-f> switches with strings can be given to retrieve only
sources that match all requested strings.

=item B<-o> OBJECT

An astronomical object to search for. Quote OBJECT to protect
whitespace, or replace spaces with underscore characters.

=item B<-i> ORCID

Search for an author by ORCID identifier. Leading zeros in the ORCID
can be left out.

=item B<-c>

Sort matched bibliographic sources by citation count.  The default is
to sort by date. B<-c> is a shorthand for B<-sc>, see below.

=item B<-r>

List only refereed sources.

=item B<-A>, B<-P>, B<-G>

Narrow to I<astronomy>, I<physics>, or I<general> database,
respectively.

=item B<-s> SORTING

Sorting mode for matched entries. The mode can be given as a single
letter, in full, or abbreviated.

  d  => date                  # This is the default
  a  => first_author          # abbreviations: fa
  c  => citation_count        # abbreviations: cc
  n  => citation_count_norm   # abbreviations: cn ccn nc ncc
  s  => score

=item B<-d>

Print debugging information. This needs to be the first command line
argument to be effective.

=back

=head1 EXAMPLES

Get papers by Dullemond and Dominik written in 2004.

    ads Dullemond Dominik,C 2004

Same authors, but only refereed papers where Dullemond is first
author, and in the range from 2000 to 2004.

    ads -r ^Dullemond Dominik 2000 2004
    ads -r ^Dullemond Dominik 2000-2004
    ads -r ^Dullemond Dominik 0-4

Get papers of Ed van den Heuvel, a name with spaces that need to be
protected.

    ads "van den heuvel,E"
    ads van_den_heuvel,E

Papers by Antonella Natta, sorted by normalized citations.

    ads -sn a.natta

B<ads> allows to freely mix switch arguments with author and year
arguments.

    ads natta,a -sn 1990 2000 -t protostar

Find articles with the phrase "planet formation" in the abstract.

    ads -a "planet formation"

Find articles with both "planet" and "system" anywhere in the
abstract.

    ads -aplanet -a system

=head1 AUTHOR

Carsten Dominik    <dominik.dominik@gmail.com>

This program is free software. It it released under the same rules as
Perl itself, see https://dev.perl.org/licenses/.

=cut

