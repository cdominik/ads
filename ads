#!/usr/bin/perl
$version = 3.0;

# Usage information with:   ads -h
# Full manpage with:        perldoc ads

use List::Util qw[min max];

if (not @ARGV or $ARGV[0] =~ /^--?h(elp)?$/) { &usage(); exit(0); }

# Some defaults and option hashes

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
  &dbg("Processing argment $arg\n");
  if ($arg =~ /^-([dDrcAPG])(.*)/) {
    # a switch without argument
    if ($1 eq "r")    { $opt_r = 1;  &dbg("REFEREED only\n")      }
    elsif ($1 eq "c") { $opt_s = $1; &dbg("Interpreted as -sc\n") }
    elsif ($1 eq "A" or $1 eq "P" or $1 eq "G") {
      $database = $1;
      &dbg("Selecting $dhash{$1} database\n");
    } else {
      $opt_d = 1; &dbg("Debugging on\n");
      $noexecute = 1 if $1 eq "D";
    }
    # Put clustered arguments rest back onto ARGV
    unshift @ARGV,"-".$2 if $2;
  } elsif ($arg =~ /^-([tafso])(.*)/) {
    # A switch with a value
    $value = length($2)>0 ? $2 : shift @ARGV;
    if ($1 eq "s")    {$opt_s = $value;       &dbg("SORTING:  $value\n")}
    elsif ($1 eq "t") {push @title,   $value; &dbg("TITLE:    $value\n")}
    elsif ($1 eq "a") {push @abstract,$value; &dbg("ABSTRACT: $value\n")}
    elsif ($1 eq "f") {push @fulltext,$value; &dbg("FULLTEXT: $value\n")}
    elsif ($1 eq "o") {push @object,  &fix_spaces($value);
                       &dbg("OBJECT:   $object[0]\n")}
  } elsif ($arg =~ /^(\d+|-\d+|\d+-|\d+-\d+)$/) {
    # This is a year specification: 2000 or -2000 or 2000- or 2000-2005
    &handle_year($arg);
  } elsif ($arg =~ /^\d{1,4}(-\d{4}){2,3}$/) {
    # This looks like an ORCID without a -i switch.
    push @orcid,&fix_orcid($arg);   &dbg("ORCID:    $orcid[0]\n");
  } elsif ($arg =~ /\w/ and $arg =~ /\d/) {
    # This looks like an object name
    push @object,&fix_spaces($arg); &dbg("OBJECT:   $object[0]\n");
  } elsif ($arg =~ /^-/) {
    die "Unknown command line switch `$arg'.\nRun `ads' for usage info, `perldoc ads' for full manpage.\n";
  } else {
    # Everything else is an author name
    &handle_author($arg);
  }
}

# Build the different pecesof the query

if (@years) {
  $y1 = min @years;
  $y2 = max @years;
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
&dbg("Calling URL: $url\n");
unless ($noexecute) {
  if    ($^O =~ /darwin/i) { exec "open '$url'";         }
  elsif ($^O =~ /linux/i)  { exec "xdg-open '$url'";     }
  elsif ($^O =~ /mswin/i)  { exec "cmd /c start '$url'"; }
  elsif ($^O =~ /cygwin/i) { exec "cygstart '$url'";     }
  else                     { exec "open '$url'";         } # Fallback option
}
# And .... we are done

# ==========================================================================
# ==========================================================================

# Subroutines

sub dbg {
  # Print a line if debugging is on
  print shift if $opt_d;
}

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
    &dbg("AUTHOR:   \"$a\"\n");
  } else {
    &dbg("AUTHOR:   \"$a1\" as \"$a\"\n");
  }
  push @authors,$a;
}

sub handle_year {
  # Interpret a year specification
  my $ys = shift;
  my $y1,$y2;
  my $force;
  die "Bad year argument $ys\n" unless $ys =~ /^(-)?(\d+)(-(\d+)?)?/;
  if ($ys =~ /^(\d+)$/) {
    # Single year
    $y2 = $1;
  } elsif ($ys =~ /^-(\d+)$/) {
    # UNTIL range
    $force = "until";
    $y2 = $1;
  } elsif ($ys =~ /^(\d+)-$/) {
    # SINCE range
    print "here\n";
    $force = "since";
    $y1 = $1;
  } elsif ($ys =~ /^(\d+)-(\d+)$/) {
    # full range
    ($y1,$y2) = ($1,$2);
  } else { die "Something went wrong with year processing of $ys\n" }
  $y1 = &normalize_year($y1);
  $y2 = &normalize_year($y2);
  if ($y1) {push @years,$y1; &dbg("YEAR: $force $y1\n")}
  if ($y2) {push @years,$y2; &dbg("YEAR: $force $y2\n")}
  $force_yr_range = $force unless $force_yr_range;
}

sub normalize_year {
  # Interpret shortened year specifications
  my $y = shift @_;
  return "" if $y =~ /^ *$/;    # year was empty
  if ($y < 100) {
    # two digit year - check of 19.. or 20.. is meant
    my $cy = &current_year();
    my $two_d_year = substr $cy,2;
    my $century = 100 * substr( $cy,0,2);
    my $yn = $y + $century - ($y <= $two_d_year+1 ? 0 : 100);
    &dbg("Year $y interpreted as $yn\n");
    $y = $yn;
  }
  return $y;
}

sub current_year {
  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
  return $year+1900;
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
  &dbg("Sorting option '$s1' translated to '$s'\n") if $s1 ne $s;
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
   -t -a -f STRING  Title/Abstract/Fulltext phrase
   -o OBJECT        Object name
   -c               Sort by citation count instead of date (short for -sc)
   -r               Refereed only
   -A -P -G         Narrow to astronomy, physics or general database
   -s a|c|n|s       Sorting: author cite normcite score (default:date)
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
sends it to the default web browser. B<ads> takes author names,
publishing years, and astronomical object identifiers from the command
line with as little fuss as possible. Additional search fields and
options can be specified using command line switches.

=head1 ARGUMENTS and OPTIONS

=over 5

=item AUTHOR NAMES

I<Alphabetic> arguments are parsed as author last names. A first name
initial can be added like 'f.last' (separated by dot) or 'last,f'
(separated by comma). Use underscores as in 'van_den_Heuvel' or quote
'"van den Heuvel"' if the name contains spaces.  If an argument looks
like (the significant tail of) an ORCID, find articles claimed by that
ORCID.

=item PUBLISHING YEARS

I<Numerical> arguments are interpreted as publishing years. Single or
two-digit years are moved into the current or previous century. Two
numerical arguments or an argument like '2012-2014' specify a
range. '2004-' means since 2004, '-2004' means until 2004.

=item B<-o> OBJECT

Read the next argument as the name or identifier of an astronomical
object. Underscore may be used instead of space to eliminate the need
for quotes.  If the name contains both letters and digits, recognition
as an object identifier will be automatic and the B<-o> may be left
out. But it is needed for more classical names that have no digits
like `B<-o> Aldebaran' or 'B<-o> CS_Cha'.

=item B<-t> STRING, B<-a> STRING, B<-f> STRING

String phrase to be matched in the I<title>, I<abstract>, or
I<fulltext>, respectively, of a bibliographic source.  Multiple
B<-t>/B<-a>/B<-f> switches with strings can be given to retrieve only
sources that match all requested strings.

=item B<-c>

Sort the output by citation count.  The default is to sort by
date. B<-c> is a shorthand for B<-sc>.

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
author, and in the range from 1999 to 2004.

    ads -r ^Dullemond Dominik 1999 2004
    ads -r ^Dullemond Dominik 1999-2004
    ads -r ^Dullemond Dominik 99-4

Get papers of Ed van den Heuvel.

    ads "van den heuvel,E"
    ads van_den_heuvel,E

Papers by Antonella Natta, sorted by normalized citations.

    ads -sn a.natta

B<ads> allows to freely mix switch arguments with author and year
arguments.

    ads natta,a -sn 1990 2000 -t protostar

Papers by Muro-Arena, Ginski, and Benisty on the object SR 21.

    ads ginski muro-arena benisty sr_21

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

