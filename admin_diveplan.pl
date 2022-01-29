#!/usr/bin/perl

my $model_root = $ARGV[0] || die $!;
my $projDir = '/projects/DI_CallCenter';
my $head_file = qq{$projDir/data/admin_generic.dvp.head};
my $tail_file = qq{$projDir/data/admin_generic.dvp.tail};
my $model_alias;
my $model_name;
my $year;

my @models = <$projDir/models/$model_root>;
#print @models;

# The output buffer
my $out = ();

# Read in the header file and append it to the output
open(IN,$head_file) || die $!;
$out .= join('',<IN>);

foreach my $model (sort @models) {
	$model_name = $model;
	$model_name =~ s!^.*/!!g;
    $model_alias = $model_name;
    $model_alias =~ s/\.mdl$//;
    #print $model;
    ($year) = ($model_alias =~ m!(\d{4})\d{2}$!);
    next if ($year < 2011);

    if ($local eq "local")
    {
        $out .= "\t{\n\t\tdbname=\"$model_alias\"},\n";
    } else
    {
        $out .= "\t{\n\t  dbname=\"/Models/$client/$model_name\",\n";
        $out .= "\t  aliases={\"$model_alias\",\"model=\"}\n\t},\n";
    }
}

# if trans, then add monthrev_aronly
if (index($model_root, 'trans_2') != -1 || index($model_root, 'trans_container_2') != -1)  {
    $out .= "\t{\n\t  dbname=\"/Models/$client/monthrev_aronly.mdl\",\n";
    $out .= "\t  aliases={\"monthrev_aronly\",\"model=\"}\n\t},\n";
    # print "$model_root contains trans\n";
}

# Read in the footer file and append it to the output
open(IN,$tail_file) || die $!;
$out .= join('',<IN>);

# Dump Buffer
print $out;
