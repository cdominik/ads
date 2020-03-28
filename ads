#!/usr/bin/perl
# Version 2.0

# Usage information with:   perldoc ads

# Defaults for stuff that can be set with options

use List::Util qw[min max];

$sort       = "date";
$sort_dir   = "desc";

%shash =  ( "c"   => "citation_count",      "cc"  => "citation_count",
            "cn"  => "citation_count_norm", "ccn" => "citation_count_norm",
            "nc"  => "citation_count_norm", "ncc" => "citation_count_norm",
            "ac"  => "author_count",        "na"  => "author_count",
            "cf"  => "classic_factor",
            "a"   => "first_author",        "fa"  => "first_author", #      make ascending the default
            "d"   => "date",
            "ed"  => "entry_date",
            "r"   => "read_count",          "rc"  => "read_count",
            "s"   => "score" );
%srevhash = reverse %shash;

# Process command line options
use Getopt::Std;
getopts('rds:t:a:f:');

if ($opt_r) { $refereed = 1 }

# Process the arguments 
while ($arg = shift @ARGV) {
  print "Processing argment $arg\n" if $opt_d;
  if ($arg =~ /^-([tafs])(.*)/) {
    # This is a delayed switch argument, lets process it.
    $value = length($2)>0 ? $2 : shift @ARGV;
    if ($1 eq "s") {
      # replace when sorting
      $cmd = sprintf("\$opt_%s = \"%s\";",$1,$value);
    } else {
      # append when part of a text field search
      $cmd = sprintf("\$opt_%s .= \" %s\";",$1,$value);
    }
    print "delayed arg: $cmd\n" if $opt_d;
    eval $cmd;

  } elsif ($arg =~ /^[0-9][-0-9]*$/) {
    # This is a year specification
    &handle_year($arg);
  } else {
    # Everything else is an author name
    $arg=~s/_/ /g;
    push @authors,$arg;
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

if ($opt_t) { $title = ' title:"' . $opt_t . '"'; }
if ($opt_a) { $abstract = ' abs:"' . $opt_a . '"'; }
if ($opt_f) { $fulltext = ' full:"' . $opt_f . '"'; }

if ($opt_s) {
  if ($shash{$opt_s}) {
    $sort = $shash{$opt_s};
  } elsif ($srevhash{$opt_s}) {
    $sort = $opt_s;
  }
}

if ($sort eq "first_author") {$sort_dir = "asc";} # change sort direction
$sorting  = "&sort=$sort $sort_dir, bibcode desc";

$refstring =  "filter_property_fq_property=AND&filter_property_fq_property=property%3A%22refereed%22&fq=%7B!type=aqp%20v%3D%24fq_property%7D&fq_property=(property%3A%22refereed%22)&";

$url = "q=" . " $authors$years" . $title . $abstract . $fulltext . "$sorting" . "&p_=0";
# Encode special characters
$url =~ s/"/%22/g;
$url =~ s/ +/%20/g;
$url =~ s/,/%2C/g;
$url =~ s/\$/%24/g;
$url =~ s/\^/%5E/g;
$url =~ s/:/%3A/g;
$url =~ s/{/%7B/g;
$url =~ s/}/%7D/g;

$url = "https://ui.adsabs.harvard.edu/search/" . ($opt_r ? $refstring : "") . $url;

print "Calling URL: $url\n" if $opt_d;
exec "open '$url'";

sub handle_year {
  my $ys = shift;
  die "Bad year argument $ys\n" unless $ys =~ /^([0-9]+)(-([0-9]+)?)?/;
  ($y1,$y2) = ($1,$3);
  $force_yr_range = 1 if $ys =~ /-$/;  # Dash at end, force range to today
  $y1 = &normalize_year($y1);
  $y2 = &normalize_year($y2);
  push @years,$y1 if $y1;
  push @years,$y2 if $y2;
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
  

=pod

=head1 NAME

B<ads> - commandline access to ADS (Astrophysical data system)

=head1 SYNOPSIS

ads [options] author [author2]... [startyear] [endyear]

=head1 DESCRIPTION

B<ads> is a commandline tool to pass a query to the website of the
Astrophysical data system (ADS). The tool will construct a query and
send it to the default web browser.  B<ads> takes author names and
publishing years from the command line with as little fuss as
possible. Some search parameters can be changed with command line
switches.

The main reason for writing this tool is that the author intensely
dislikes filling web forms on a regular basis.

Arguments containing letters are parsed as author names. Spaces in
author names can be given as underscores `_`, or you can put the
name in quotes.

Number arguments are parsed as publishing year. Single or two-digit
years are interpeted as 19.. or 20.. in a way that makes sense.
A second year-like argument or something like '2012-2014' specifies
a range. A year ending with `-` means starting from that year.

=head1 OPTIONS

=over 5

=item B<-t> STRING

A string to put into the title search field.

=item B<-a> STRING

A string to put into the abstract search field.

=item B<-f> STRING

A string to put into the fulltext search field.

=item B<-s> SORTING

Sorting mode for matched entries.  DEFAULT is 'date', to sort by date.
Values can be given in full, or be abbreviated.  The allowed values
and abbreviations are:
 
   d              => date                       This is the default
   a  fa          => first_author
   c  cc          => citation_count
   cn ccn nc ncc  => citation_count_norm
   s              => score

=item B<-r>

Only list refereed sources.  Default is to list also unrefereed.

=item B<-d>

Print debugging information

=back

=head1 EXAMPLES

Get papers by Dullemond and Dominik written in 2004.

    ads Dullemond Dominik,C 2004

Same authors, but only the papers where Dullemond is first author, and
in the range from 2000 to 2004.

    ads -r ^Dullemond Dominik 2000 2004

Get papers of Ed van den Heuvel.  This example shows that spaces in
name field can be replaced by the underscore character, if you don't
want to quote the name.

    ads "van den heuvel,E"
    ads van_den_heuvel,E

Same, sorted by normalized citations.

    ads -scn van_den_heuvel,E

For fun, and because I often think of additional constraints only after
I have typed the names, this command also allows to give the switch
arguments after or mixed with the author and year arguments.

    ads tielens,a -t interstellar 1979 -scc 1980

=head1 AUTHOR

Carsten Dominik    <dominik@uva.nl>

This program is free software.  It it released under the rules like
Perl itself, so wither the GNU General Public License, or the Artistic
License.

=cut

