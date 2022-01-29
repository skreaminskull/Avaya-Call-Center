#!/usr/bin/perl -w
use strict;
use warnings;
use DBI;
use Time::Local;
use JSON::XS qw(encode_json decode_json);
use File::Slurp qw(read_file write_file);

$SIG{__DIE__}=\&handleDeath;

my $num_args = $#ARGV + 1;
if ($num_args != 1) {
    print "\nUsage: eIVR_parse.pl filename\n";
    exit;
}

my $filename=$ARGV[0];
my %eIVR_HoH;
my $pos;
my $pos_end;
my $end;
my $locAction;
my $locID;
my $locHashID;
my $callID;
my $location;
my $client;
my $did;
my $pid;
my $dob;
my @record;
my @time;
my $time;
my $date;
my $age;
my $sequence;
my $jsonDump = '/var/opt/DI/dl-dataroot/projects/DI_CallCenter/data/eIVR_Dump.json';

my %config = do 'eivr_config.pl';
my $dbh=DBI->connect("dbi:Pg:dbname=$config{DBName};host=$config{DBHost}",$config{DBUser},$config{DBPass}) or die "Error: Unable to connect to database";
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

sub hashDump {
    {
        my $json = encode_json \%eIVR_HoH;
        write_file($jsonDump, { binmode => ':raw' }, $json);
    }
}

sub hashRetrieve {
    {
        my $json = read_file($jsonDump, { binmode => ':raw' });
        %eIVR_HoH = %{ decode_json $json };
    }
}

sub process_rec {
    my $channel = shift;
    my %hash = @_;
    my $key;
    my $who;

    #print "Channel: $channel\n";
    #print "-------------------------\n";

    #for $key ( sort keys %{ $hash{$channel} } )
    #{
    #    print "$key=$hash{$channel}{$key} \n";
    #}

    $query = $dbh->prepare("INSERT INTO eivr_call_log (callid,calldatestart,calltimestart,calltimeend,channel,client,patientnumber,patientdob,patientage,paymentsystem,calldateend) VALUES (?,?,?,?,?,?,?,?,?,?,?)");
    $query->execute($hash{$channel}{'CallID'},$hash{$channel}{'CallDateStart'}, $hash{$channel}{'CallTimeStart'}, $hash{$channel}{'CallTimeEnd'}, $channel, $hash{$channel}{'Client'},$hash{$channel}{'PatientNumber'},$hash{$channel}{'DOB'},$hash{$channel}{'Age'},$hash{$channel}{'PaymentSystem'},$hash{$channel}{'CallDateEnd'}) or die $DBI::errstr;
    $query->finish();
    $dbh->commit or die $DBI::errstr;

    my @matching_keys = grep m/^LOC/so => keys %{$hash{$channel}};

    if (@matching_keys)
    {
        # sort by values
        #my @sorted_locs =  sort
        #{
            #substr($hash{$channel}{$a}->{'LocatorTime'},0,2) . substr($hash{$channel}{$a}->{'LocatorTime'},3,2) . substr($hash{$channel}{$a}->{'LocatorTime'},6,2)
            # <=>
            #substr($hash{$channel}{$b}->{'LocatorTime'},0,2) . substr($hash{$channel}{$b}->{'LocatorTime'},3,2) . substr($hash{$channel}{$b}->{'LocatorTime'},6,2)
        #} @matching_keys;
        # sort by array
        my @sorted_locs = sort @matching_keys;
        # matching values are in @{$hash{$key1}}{@matching_keys}
        for my $i (@sorted_locs)
        {
            #print "--------------------------\n";
            #print "$i\n";
            #for $who ( sort keys %{ $hash{$channel}{$i} } )
            #{
                #print "$who=$hash{$channel}{$i}{$who}\n";
            #}
            #$location = substr($i,4);
            $query = $dbh->prepare("INSERT INTO eivr_call_details (callid,locatorid,locatoraction,locatortime,locatordate) VALUES(?,?,?,?,?)");
            $query->execute($hash{$channel}{'CallID'}, $hash{$channel}{$i}{'LocatorID'}, $hash{$channel}{$i}{'LocatorAction'},$hash{$channel}{$i}{'LocatorTime'},$hash{$channel}{$i}{'LocatorDate'});
            $query->finish();
            $dbh->commit or die $DBI::errstr;
        }
    }
    #print "\n";
    @matching_keys = keys %{$hash{$channel}};
    for my $i (@matching_keys)
    {
        delete $hash{$channel}{$i};
    }
    delete $hash{$channel};
}

sub update_trigger {
  $query = $dbh->prepare("UPDATE vdn_fix_trigger SET eivr = true where id = 1");
  $query->execute();
  $query->finish();
  $dbh->commit or die $DBI::errstr;
}

sub get_age {
    # calculate age
    my $dob = shift;
    my $calldate = shift;
    my $age;

    my ($day, $month, $year) = (localtime)[3..5];
    $year += 1900;
    my ($call_day, $call_month, $call_year);
    $call_year = substr($calldate,0,4);
    $call_month = substr($calldate,4,2);
    $call_day = substr($calldate,6,2);

    my ($birth_day, $birth_month, $birth_year);

    $birth_year = substr($dob,0,4);
    $birth_month = substr($dob,4,2);
    $birth_day = substr($dob,6,2);


    if (int($birth_year) >= 1890 && int($birth_year) <= int($year))
    {
        $age = $call_year - $birth_year;
        $age-- unless sprintf("%02d%02d", $call_month, $call_day)
            >= sprintf("%02d%02d", $birth_month, $birth_day);
    } else {
        $age = '999';
    }

    return $age;
}

sub get_ts_date {
    my $timeStamp = shift;
    my @splitStamp = split / / , $timeStamp;
    my @date = split /\// , $splitStamp[0];
    my $yyyymmdd = $date[2] . sprintf("%02d", $date[0]) . sprintf("%02d", $date[1]);
    return $yyyymmdd;
}

sub get_ts_time {
    my $timeStamp = shift;
    my @splitStamp = split / / , $timeStamp;
    # convert to military PM to + 12

    @time = split /:/ , $splitStamp[1];
    if ($splitStamp[2] eq "PM" and $time[0] ne "12" )
    {
        $time[0] = int($time[0]) + 12;
    }
    elsif ($splitStamp[2] eq "AM" and $time[0] eq "12")
    {
        $time[0] = "00";
    }

    $splitStamp[1] = sprintf("%02d", $time[0]) . ':' . sprintf("%02d", $time[1]) . ":". sprintf("%02d", $time[2]);

    return $splitStamp[1];
}

# check to see if there are unprocesssed records from the prior log file
hashRetrieve();

open (FILE, $filename);
while (<FILE>) {
    #chomp;
	s/\s+$//;
    #($time_stamp, $service, $channel, $channel_seq, $description) = split /\|/;
    @record = split / \| / , $_;
    #print "Time Stamp: $time_stamp\n";
    #print "Description: $description\n";
    if ($record[1] && $record[1] =~ m/Voice Service/)
    {
        if ($record[4] =~ m/Processing Call:/)
        {
            # Code to get Call ID
            #$callID = substr($record[4],17);
            $eIVR_HoH{$record[2]}{'CallID'} = substr($record[4],17);
        }
        elsif ($record[4] =~ m/^Next Action:/)
        {
            # Code to get Next Action and Next Parameter
            $pos = index($record[4], ':');
            $pos_end = rindex($record[4], ':');
            $end = $pos_end - $pos - 15;
            $locAction = substr($record[4],$pos + 1, $end);
            $locID = substr($record[4],$pos_end + 1);
            $locAction =~ s/^\s+|\s+$|\)//g ;
            $locID =~ s/^\s+|\s+$|\)//g ;
            $sequence = $record[3];
            $locHashID = "LOC-" . $sequence . "-" . $locID ;

            # locator info
            $eIVR_HoH{$record[2]}{$locHashID}{'LocatorID'} = $locID;
            $eIVR_HoH{$record[2]}{$locHashID}{'LocatorAction'} = $locAction;
			$date = get_ts_date($record[0]);
            $time = get_ts_time($record[0]);
			$eIVR_HoH{$record[2]}{$locHashID}{'LocatorDate'} = $date;
            $eIVR_HoH{$record[2]}{$locHashID}{'LocatorTime'} = $time;

            if ($locID eq "1000" && $locAction eq "CollectAndStore")
            {
				$eIVR_HoH{$record[2]}{'CallDateStart'} = $date;
                $eIVR_HoH{$record[2]}{'CallTimeStart'} = $time;

            }

            if ($locID eq "4037" && $locAction eq "Data Locator")
            {
                $eIVR_HoH{$record[2]}{'PaymentSystem'} = "Instamed";
            }

            if ($locID eq "7039" && $locAction eq "Data Locator")
            {
                $eIVR_HoH{$record[2]}{'PaymentSystem'} = "EPX";
            }

        }
        elsif ($record[4] =~ m/CallInfo Object Has Been Destroyed/)
        {
            # Call ended - time to write out to db
			$date = get_ts_date($record[0]);
            $time = get_ts_time($record[0]);
			$eIVR_HoH{$record[2]}{'CallDateEnd'} = $date;
            $eIVR_HoH{$record[2]}{'CallTimeEnd'} = $time;
            process_rec($record[2], %eIVR_HoH);
        }

    }
    elsif ($record[1] && $record[1] =~ m/User Defined/)
    {
        if ($record[4] =~ m/Using internal variable \(UserVariable1 /)
        {
            # Get DID
            $pos = rindex($record[4], '=');
            $did = substr($record[4], $pos + 1);
            $did =~ s/^\s+|\s+$|\)//g ;
            $eIVR_HoH{$record[2]}{'DID'} = $did;
        }
        elsif ($record[4] =~ m/Using internal variable \(UserVariable2 /)
        {
            # Get Client
            $pos = rindex($record[4], '=');
            $client = substr($record[4], $pos + 1);
            $client =~ s/^\s+|\s+$|\)//g ;
            $eIVR_HoH{$record[2]}{'Client'} = $client;
        }
        elsif($record[4] =~ m/Working Field:ClientName Value:/)
        {
            $pos = rindex($record[4], ':');
            $client = substr($record[4], $pos + 1);
            $client =~ s/^\s+|\s+$|\)//g ;
            $eIVR_HoH{$record[2]}{'Client'} = $client;
        }
        elsif ($record[4] =~ m/Using internal variable \(UserVariable3 /)
        {
            # Get PID & DOB
            $pos = index($record[4], '=');
            $pos_end = rindex($record[4], '=');
            $end = $pos_end - $pos - 11;
            $pid = substr($record[4], $pos + 1, $end);
            $dob = substr($record[4],$pos_end + 1);
            $pid =~ s/^\s+|\s+$|\)//g ;
            $dob =~ s/^\s+|\s+$|\)//g ;
            $dob = substr($dob,6) . substr($dob,0,2) . substr($dob,3,2);
            $age = get_age($dob, $eIVR_HoH{$record[2]}{'CallDateStart'});

            $eIVR_HoH{$record[2]}{'PatientNumber'} = $pid;
            $eIVR_HoH{$record[2]}{'DOB'} =  $dob;
            $eIVR_HoH{$record[2]}{'Age'} =  $age;
        }
    }
}

close (FILE);
update_trigger();
$dbh->disconnect;
# write out a hash dump for any records that did not process
hashDump();
exit 0;
