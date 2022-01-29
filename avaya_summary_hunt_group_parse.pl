#!/usr/bin/perl -w
use strict;
use warnings;
use DBI;
use Time::Local;
use DateTime;

$SIG{__DIE__}=\&handleDeath;

my %config = do 'avaya_config.pl';

my $num_args = $#ARGV + 1;
if ($num_args != 1) {
    print "\nUsage: avaya_summary_hunt_group_parse.pl filename\n";
    exit;
}

my $filename=$ARGV[0];
my $dbh;
my @parsed;
my %avaya;
my $call_date;

$dbh=DBI->connect("dbi:Pg:dbname=$config{DBName};host=$config{DBHost}",$config{DBUser},$config{DBPass}) or die "Error: Unable to connect to database";
# Set autocommit off - transactions.
$dbh->{AutoCommit} = 0;
my $query;

sub handleDeath {
  my $error=1;
  print "Error:  Fatal error occured in $0\n\n";
	if (defined($dbh))
	{
    $dbh->rollback;
    $dbh->disconnect;
  }
  #exit 1;
}

sub parse_csv {
  my $text = shift; ## record containing comma-separated values
  my @new = ();
  push(@new, $+) while $text =~ m{
    ## the first part groups the phrase inside the quotes
    "([^\"\\]*(?:\\.[^\"\\]*)*)",?
      | ([^,]+),?
      | ,
    }gx;
  push(@new, undef) if substr($text, -1,1) eq ',';
  return @new; ## list of values that were comma-spearated
}

sub process_rec {
  my %hash = @_;
  $query = $dbh->prepare("INSERT INTO avaya_hunt_group_summary (switch_name, report_timestamp, group_num, group_name, group_size, measure_hour, total_usage, calls_answered, queue, calls_queue, queue_overflow,  time_avail, speed_answer, group_type, calls_abandon) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");

  $query->execute($hash{'switch_name'},$hash{'report_timestamp'}, $hash{'group_num'},  $hash{'group_name'}, $hash{'group_size'}, $hash{'measure_hour'}, $hash{'total_usage'},  $hash{'calls_ans'}, $hash{'queue'}, $hash{'calls_queue'}, $hash{'queue_overflow'},
  $hash{'time_avail'}, $hash{'speed_answer'}, $hash{'group_type'},  $hash{'calls_abdn'}) or die $DBI::errstr;
  $query->finish();
  $dbh->commit or die $DBI::errstr;
}

sub get_call_date {
  my $report_date = shift;
  #print "Report Date: $report_date";
  #exit 0;
  my ($month, $day, $year) = split(/-/,$report_date);
  #print "get_call_date: $month-$day-$year\n";
  #exit 0;
  my $dt_orig = DateTime->new( year => $year,
                          month      => $month,
                          day        => $day,
                          hour       => 0,
                          minute     => 0,
                          second     => 0,
                           );
  my $offset_date = substr($dt_orig->clone->subtract( days => 1),0,10);
  ($year, $month, $day) = split(/-/,$offset_date);
  my $date_yyyymmdd = $year . $month . $day;
  return $date_yyyymmdd ;
}

# line with Data Export contains the date the report was run
my $date_indicator_1 = " Data Export";
my $date_indicator_2 = " Report for Voice System ";
my $mmddyyyy = "";

open (FILE, $filename);
while (<FILE>) {
    # chomp;
	  s/\s+$//;
    #@record = split('",', $_);
    # get report date
    @parsed = parse_csv($_);
    if ($parsed[0]) {
      if($mmddyyyy eq "" && $parsed[0] =~ m/$date_indicator_1$/ || $parsed[0] =~  m/^.*$date_indicator_2.*$/) {
        $mmddyyyy = substr($parsed[0],0,10);
        # trim extra whitespace
        $mmddyyyy =~ s/^\s+//;
        $mmddyyyy =~ s/\s+$//;
        # offset date since report timestamp is one day before
        $call_date = get_call_date($mmddyyyy);
      }
    }

    # ignore the  commentary lines...if not a value in second element, pass
    if ($parsed[1] and $parsed[5] ne "SUMMARY" and $parsed[5] ne "-----------") {
      # add hash values for db call
      $avaya{'switch_name'} = $parsed[0];
      $avaya{'report_timestamp'} = $parsed[1];
      $avaya{'group_num'} = $parsed[2];
      $avaya{'group_name'} = $parsed[3];
      $avaya{'group_size'} = $parsed[4];
      $avaya{'measure_hour'} = $parsed[5];
      $avaya{'total_usage'} = $parsed[6];
      $avaya{'calls_ans'} = $parsed[7];
      $avaya{'queue'} = $parsed[8];
      $avaya{'calls_queue'} = $parsed[9];
      $avaya{'queue_overflow'} = $parsed[10];
      $avaya{'time_avail'} = $parsed[11];
      $avaya{'speed_answer'} = $parsed[12];
      $avaya{'group_type'} = $parsed[13];
      $avaya{'calls_abdn'} =  $parsed[14];
      $avaya{'call_date'} = $call_date;
      #my @time_range = split(/:/,$avaya{'time_range'});
      #$avaya{'call_hour'} = $time_range[0];
      process_rec(%avaya);
    }
}

close (FILE);
$dbh->disconnect;

exit 0;
