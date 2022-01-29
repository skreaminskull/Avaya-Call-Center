#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper;

$SIG{__DIE__} = \&handleDeath;

sub handleDeath {
    my $error = 1;
    print "Error:  Fatal error occured in $0\n\n";
}

my $inFile=$ARGV[0];
my $outFile=$inFile . ".tmp";
my @record;
my %ccNums;
my $ccNum = "";
my $last4 = "";

print "\n\neIVR Scrubber\n-----------------------------------------\n";

open (FILE, $inFile) or die $!;
print "Status: building list of CC Numbers\n";
while (<FILE>) {
  s/\s+$//;
  @record = split / \| / , $_;
  if ($record[1] && $record[1] =~ m/User Defined/) {
    # Does line have a CC #? -> Working Field:CCNUM
    if ($record[4] =~ m/LocatorVA->Working Field:CCNUM Value:/) {
      $ccNum = substr($record[4],37);
      my $numDigits = length($ccNum);
      my $asterisks = "*" x ($numDigits - 4);
      $last4 = substr($ccNum,-4);
      $ccNums{$ccNum} = $asterisks . $last4;
    }
  }
}
close (FILE);

open (FILE, $inFile) or die $!;
open (OUT, ">", $outFile) or die $!;

my $scrubbed;
my $line;
print "Status: scrubbing list of CC Numbers\n";
while (<FILE>) {
  s/\s+$//;
  $line = $_;
  ($scrubbed = $line) =~ s/(@{[join "|", keys %ccNums]})/$ccNums{$1}/g;
  print OUT $scrubbed . "\n";
}

# print Dumper(%ccNums);
close (FILE);
close(OUT);

unlink $inFile;
rename $outFile, $inFile;
print "Status: finished processing eIVR file $inFile\n";
exit 0;
