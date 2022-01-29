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
    print "\nUsage: avaya_summary_skill_parse.pl filename\n";
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
  $query = $dbh->prepare("INSERT INTO avaya_skill_summary (switch_name, report_timestamp, skill, skill_name, acpt_service_level, call_date, time_range, call_hour, acd_calls, avg_speed_answered, abdn_calls, avg_abdn_time,  avg_talk_time, total_after_call, flow_in, flow_out, total_aux_other, avg_staff, pct_in_svc_level, skill_description) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");

  $query->execute($hash{'switch_name'},$hash{'report_timestamp'}, $hash{'skill'},  $hash{'skill_name'}, $hash{'acpt_service_level'}, $hash{'call_date'}, $hash{'time_range'}, $hash{'call_hour'},  $hash{'acd_calls'}, $hash{'avg_speed_answered'}, $hash{'abdn_calls'}, $hash{'avg_abdn_time'},
  $hash{'avg_talk_time'}, $hash{'total_after_call'}, $hash{'flow_in'}, $hash{'flow_out'}, $hash{'total_aux_other'}, $hash{'avg_staff'}, $hash{'pct_in_svc_level'}, $hash{'skill_description'},) or die $DBI::errstr;
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

    my @filePath = split /\//, $filename;
    my @skill = split / /, $filePath[-1];
    #print "Department: $department[0]";

    # ignore the  commentary lines...if not a value in second element, pass
    if ($parsed[1] and $parsed[9] ne "SUMMARY" and $parsed[9] ne "-----------") {
      # add hash values for db call
      $avaya{'switch_name'} = $parsed[1];
      $avaya{'report_timestamp'} = $parsed[2];
      $avaya{'skill'} = $parsed[4];
      $avaya{'skill_name'} = $parsed[6];
      $avaya{'acpt_service_level'} = $parsed[7];
      $avaya{'time_range'} = $parsed[9];
      $avaya{'acd_calls'} = $parsed[10];
      $avaya{'avg_speed_answered'} = $parsed[11];
      $avaya{'abdn_calls'} = $parsed[12];
      $avaya{'avg_abdn_time'} = $parsed[13];
      $avaya{'avg_talk_time'} = $parsed[14];
      $avaya{'total_after_call'} = $parsed[15];
      $avaya{'flow_in'} = $parsed[16];
      $avaya{'flow_out'} = $parsed[17];
      $avaya{'total_aux_other'} =  $parsed[18];
      $avaya{'avg_staff'} =  $parsed[19];
      $avaya{'pct_in_svc_level'} =  $parsed[20] ? $parsed[20] : 0;;
      $avaya{'call_date'} = $call_date;
      my @time_range = split(/:/,$avaya{'time_range'});
      $avaya{'call_hour'} = $time_range[0];
      $avaya{'skill_description'} = $skill[0];
      process_rec(%avaya);
    }
}

close (FILE);
$dbh->disconnect;

exit 0;
