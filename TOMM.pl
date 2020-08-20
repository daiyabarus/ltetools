#!bin/perl

use strict;
use warnings;
sub trim($);
my $start_run = time();

my $dir = 'LOG';
open OUT,'>LTE Sector TA Histogram.csv' or die $!;
my %HoH= ();
my %H = (
"16" => 0,
"32" => 0,
"48" => 0,
"64" => 0,
"80" => 0,
"96" => 0,
"112" => 0,
"128" => 0,
"144" => 0,
"160" => 0,
"176" => 0,
"192" => 0,
"208" => 0,
"224" => 0,
"240" => 0,
"256" => 0,
"272" => 0,
"288" => 0,
"304" => 0,
"320" => 0,
"336" => 0,
"352" => 0,
"368" => 0,
"384" => 0,
"400" => 0,
"416" => 0,
"432" => 0,
"448" => 0,
"464" => 0,
"480" => 0,
"496" => 0,
"512" => 0,
"528" => 0,
"544" => 0,
"560" => 0,
"576" => 0,
"592" => 0,
"608" => 0,
"624" => 0,
"640" => 0,
"656" => 0,
"672" => 0,
"688" => 0,
"704" => 0,
"720" => 0,
"736" => 0,
"752" => 0,
"768" => 0,
"784" => 0,
"800" => 0,
"816" => 0,
"832" => 0,
"848" => 0,
"864" => 0,
"880" => 0,
"896" => 0,
"912" => 0,
"928" => 0,
"944" => 0,
"960" => 0,
"976" => 0,
"992" => 0,
"1008" => 0,
"1024" => 0,
"1040" => 0,
"1056" => 0,
"1072" => 0,
"1088" => 0,
"1104" => 0,
"1120" => 0,
"1136" => 0,
"1152" => 0,
"1168" => 0,
"1184" => 0,
"1200" => 0,
"1216" => 0,
"1232" => 0,
"1248" => 0,
"1264" => 0,
"1280" => 0,
"1296" => 0,
"1312" => 0,
"1328" => 0,
"1344" => 0,
"1360" => 0,
"1376" => 0,
"1392" => 0,
"1408" => 0,
"1424" => 0,
"1440" => 0,
"1456" => 0,
"1472" => 0,
"1488" => 0,
"1504" => 0,
"1520" => 0,
"1536" => 0,
"1552" => 0,
"1568" => 0,
"1584" => 0,
"1600" => 0,
"1616" => 0,
"1632" => 0,
"1648" => 0,
"1664" => 0,
"1680" => 0,
"1696" => 0,
"1712" => 0,
"1728" => 0,
"1744" => 0,
"1760" => 0,
"1776" => 0,
"1792" => 0,
"1808" => 0,
"1824" => 0,
"1840" => 0,
"1856" => 0,
"1872" => 0,
"1888" => 0,
"1904" => 0,
"1920" => 0,
"1936" => 0,
"1968" => 0,
"1984" => 0,
"2000" => 0,
"2016" => 0,
"2032" => 0,
"2048" => 0,
"2112" => 0,
"2176" => 0,
"2192" => 0,
"2208" => 0,
"2224" => 0,
"2240" => 0,
"2352" => 0,
"2544" => 0,
"2928" => 0,
"3152" => 0
);

my @Header = ();
my $TA= 0;
my $CI=0;
my $GCID = ();

#foreach my $fp (glob("$dir/*.osc")) {
my $num_args = $#ARGV + 1;
if ($num_args != 1) {
    print "\nInput file not found\n";
    exit;
}
my $fp=$ARGV[0];

	#printf "%s\n", $fp;	
	printf "Reading file ".$fp."\n";
	#my $file = substr($fp,4,length($fp)-length($dir)-5);
	
	open FILE, $fp or die $!;
	while(<FILE>)
	{
		chomp;
		
		if(index($_,"INTERNAL_PER_RADIO_UE_MEASUREMENT_TA")>-1 && index($_,"[info]")<0)
		{
			$TA = 1;
			next;
		}
		
		my @temp = ();
		my @temp2= ();
		if(index($_,"EVENT_PARAM_GLOBAL_CELL_ID")>-1 && $TA == 1)
		{
			@temp = split ' ', $_;
			@temp2 = split ',', $temp[1];
			$GCID = $temp2[0];
			#print $GCID."\n";
			if(not exists $HoH{$GCID}{16}){
				%{$HoH{$GCID}} = %H;
			}
			$CI=1;
			next;
		}
		if(index($_,"EVENT_ARRAY_TA unavailable")>-1 && $CI==1)
		{
			$TA=0;$CI=0;next;
		}	
		if(index($_,"EVENT_ARRAY_TA")>-1 && $CI==1)
		{
			@temp = split ' ', $_;
			@temp2 = split ',', $temp[1];
			#printf $GCID." ".$temp2[0]."\n";
			$HoH{$GCID}{$temp2[0]}++; 		
			next;
		}

		next;
		
	}
	printf "Processing...\n";
	close FILE or die $!;
#}

sub bin2dec {
    return unpack("N", pack("B32", substr("0" x 32 . shift, -32)));
}

print OUT "EnodeBID-SectorID|Event Parameter value|Occurance (#)|Distance(m)|Cumulative Occurance (#)| %Cumulative Occurance(%)\n";
printf "Generating output....\n";
foreach my $itemKey ( keys %HoH ) {
	my $CO=0;
	my $SUM=0;
	foreach my $d (keys $HoH{$itemKey}){
		$SUM+=$HoH{$itemKey}{$d};}
	foreach my $d (sort {$a <=> $b} keys $HoH{$itemKey}){
		my $dis = $d * 4.88; 
		$CO += $HoH{$itemKey}{$d};
		#printf $CO."\n";
		my $bin = sprintf ("%b",$itemKey);
		my $enodeBID=bin2dec(substr($bin,0,length($bin)-8));
		my $sectorID=bin2dec(substr($bin,20,8));
		print OUT $enodeBID."-".$sectorID."|".$d."|".$HoH{$itemKey}{$d}."|".$dis."|".$CO."|".($CO/$SUM*100)."\n";
	}
	#print OUT "\n";
}
print "The output store in \"LTE Sector TA Histogram.csv\"\n";
#calculate time process
my $end_run = time();
my $run_time = $end_run - $start_run;
print "time process $run_time s\n"
	