#!/usr/local/bin/perl

use strict;
use warnings;
sub trim($);
my $start_run = time();

my $dir = 'DATA';
my $date = ();
my %IMEI= ();
my $enodeb = -1;
my $tac=-1;
my %SECTOR_CAP = ();
my %H = ();
my @Header = ();
#open(DATA, "< INPUT_CTUM.OSC") or die "Couldn't open file file.txt, $!";
open OUT,'> ENODEB_CAP.txt' or die $!;
printf OUT "CTUM,enodeb,imei\n";

foreach my $fp (glob("$dir/*.txt")) {
	printf "%s\n", $fp;	
	my $file = substr($fp,length($dir)+1,length($fp)-length($dir)-5);
	open DATA, $fp or die $!;

	while(<DATA>){
	   chomp;
	   my @temps = split ' ', $_;
	   if(index($temps[0],"hour")>-1){
		$temps[1] =~ s/\W//g;		
		#printf OUT $temps[1];
	   }
	   if (index($temps[0],"minute")>-1 or index($temps[0],"second")>-1){
		   if(index($temps[0],"millisecond")>-1){
			   $temps[1] =~ s/\W//g;		
			   #printf OUT ".".$temps[1].",";
		   }
		   else{
			$temps[1] =~ s/\W//g;
			#printf OUT ":".$temps[1];
		   }
	   }
	   if(index($temps[0],"macroEnbIdOption")>-1){
	      next;
	   } 
	   if(index($temps[0],"macroEnbId")>-1){
		$temps[1] =~ s/\W//g;		
		#printf OUT $temps[1].",";
		$enodeb = $temps[1];
	   }
	   if(index($temps[0],"tac")>-1){
		$temps[1] =~ s/\W//g;		
		#printf OUT $temps[1];
		$tac=$temps[1];
	   }
	   if(index($temps[0],"snr")>-1){
		$temps[1] =~ s/\W//g;		
		#printf OUT $temps[1]."\n";
		if(exists $IMEI{$enodeb}{$tac.$temps[1]}){
			next;
		}
		else{
			$IMEI{$enodeb}{$tac.$temps[1]}=$tac.$temps[1];
		}
		$enodeb=-1;$tac=-1;
	   }
	}
	close DATA or die $!;
}


my $d;my $n;
foreach $d (keys %IMEI){
	foreach $n (keys %{$IMEI{$d}}){
         	print OUT "CTUM,".$d.",".$IMEI{$d}{$n}."\n";
        }
}

#calculate time process
my $end_run = time();
my $run_time = $end_run - $start_run;
print "time process $run_time s\n"
	