#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
$| = 1;

my $version = "1.4"; 

################################################################################
# MultiMon for eNodeB
#
# Adds eNobeB Identifier to Trace & Error messages, allowing to join monitor
# outputs for multiple eNodeB's. Can use viewer's -s to lookup moshell ip
# database file for enbid to ip match in logs. Can also use multiple nodes
# using viewers -m ip1,ip2,ip3 flag.
#
# You can then use lteflowfox.pl to view in realtime:
# tail -f joinedfile.log | lteflowfox.pl -l
#
# Application support, contact:
# Dusan Simic (dusan.simic@ericsson.com)
# Alex Perez (alex.perez@ericsson.com)
#
################################################################################
# Change log:
#
# PA1 (edussim) First version
# PA2 (edussim) Correction on usage
# PA3 (edussim) Last message bug fixed
# PA4 (epaerez) Added functionality to lookup node name via viewer IP source info
#               and Moshell ipdatabase
# 1.1 (epaerez) Added multinode input handling from viewer
# 1.2 (epaerez) Help output expanded
# 1.3 (epaerez) Added option to include .monrc file instead of -c file with option -r
# 1.4 (epaerez) Fixed Dusan's email contact

my ( # GetOptions variables
   $nodeId,
   $lookupIpdatabase,
   $configFile,
   $use_rc_file,
   $debug,
   $help,
   $ver,
);

GetOptions(
   "n|node=s"     =>    \$nodeId,
   "l|lookup"     =>    \$lookupIpdatabase,
   "c|config=s"   =>    \$configFile,
   #"r|rcfile"     =>    \$use_rc_file,
   "d|debug"      =>    \$debug,
   "h|help"       =>    \$help,
   "v|ver"        =>    \$ver,
);

my %ip_to_eNBname = ();
my %name_to_ip = ();
my $enbid = $nodeId if $nodeId;

#exit usage() if $help;
exit pod2usage(-verbose => 2, -exitval => 2) if $help;
exit version() if $ver;
if ($nodeId && $lookupIpdatabase) {
   print "\nToo many options provided.\n";
   exit usage();
} elsif ($nodeId && $configFile) {
   print "\nToo many options provided.\n";
   exit usage();
} elsif ($configFile && $lookupIpdatabase) {
   print "\nToo many options provided.\n";
   exit usage();
}

#Check for .monrc
my $fileSpec = $ENV{"HOME"} . "/.monrc";
if (-e $fileSpec) { 
   $use_rc_file = 1;
   print "DEBUG: .monrc config file found.\n" if $debug;
   #$local_config_file = $fileSpec;
} else {
   print "DEBUG: .monrc config file does not exist.\n" if $debug;
}

#Check that $configFile exists or die
if ($configFile) {
   if (-e $configFile) {
      print "DEBUG: Specified config file $configFile found.\n" if $debug;
   } else {
      die "$configFile does not exist, exiting: $!";
   }
}

if ($nodeId) {
   print "DEBUG: Original multimon called\n" if $debug;
   orig_multimon();
} elsif ($lookupIpdatabase) {
   print "DEBUG: New multimon called\n" if $debug;
   new_multimon();
} elsif ($configFile) {
   print "DEBUG: Config multimon called\n" if $debug;
   config_multimon();
} elsif ($use_rc_file) {
   print "DEBUG: .monrc multimon called\n" if $debug;
   config_multimon();
} else {
   # something went wrong, print usage
   exit pod2usage(-verbose => 2, -exitval => 2);
}

sub orig_multimon { #Legacy
   my $init_lookup = 1;       # Used to only lookup ipdatabase once
   while (my $in = <STDIN>){
      my $line = $in;
      chomp($line);
      next if ($line =~ /^$/);
      next if ($line =~ /^TraceViewer/);
      if ( $init_lookup && ($line =~ /^\[\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\]\s+\[/) ) {
         $init_lookup = 0;
         $enbid = lookup_enbid($line);
         $line .= " (enbid = $enbid)";
         print $line."\n";
         next;
      }
      if ( ($line =~ /^\[/) && ($enbid) ){
         $init_lookup = 0;
         $line .= " (enbid = $enbid)";
      }
      print $line."\n";
      if ($debug) {
         print "DEBUG: Single Node, ";
         print "user_nodeId=$nodeId, enbid=$enbid, \n";
      }
   }
}

sub new_multimon {
   my $line = "";
   lookup_enbid($line);
   while (my $in = <STDIN>){
      $line = $in;
      chomp($line);
      next if ($line =~ /^$/);
      next if ($line =~ /^TraceViewer/);
      die "No source IP found, use 'viewer -s' to tag input.\n" if ($line =~ /^\[\d{4}-\d{2}-\d{2}/);
      if ($line =~ /^\[(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\]\s+\[/) {
         my $ip = $1;
         foreach my $elem (keys %ip_to_eNBname) {
            if ($elem =~ $ip) {
               $line .= " (enbid = ${ip_to_eNBname{$elem}})";
            }
         }
      }
      print $line."\n";
   }
}

sub config_multimon {
   my $local_config_file;
   if ($configFile) {
      $local_config_file = $configFile;
   } elsif ($use_rc_file) {
      $local_config_file = $fileSpec;
   }
   open (INFILE, '<', $local_config_file) || die "$local_config_file file not found: $!";
   while (my $line = <INFILE>) {
      chomp ($line);
      next if ($line =~ /^$/ );
      next if ($line =~ /^\s?#/);   
      if ($line =~ /(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\s+([\w-]+)/) {
         $ip_to_eNBname{$1} = $2; # IP -> eNB Name map from ipdatabase
         $name_to_ip{$2} = $1; # eNB Name -> IP map from ipdatabase
      }
   }
   close (INFILE);
   
   while (my $in = <STDIN>){
      my $line = $in;
      chomp($line);
      next if ($line =~ /^$/);
      next if ($line =~ /^TraceViewer/);
      die "No source IP found, use 'viewer -s' to tag input.\n" if ($line =~ /^\[\d{4}-\d{2}-\d{2}/);
      if ($line =~ /^\[(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\]\s+\[/) {
         my $ip = $1;
         foreach my $elem (keys %ip_to_eNBname) {
            if ($elem =~ $ip) {
               $line .= " (enbid = ${ip_to_eNBname{$elem}})";
            }
         }
      }
      print $line."\n";
   }
}

sub lookup_enbid {
   ######################################
   # Moshell ipdatabase IP to Node name
   ######################################
   # 1. viewer is run with --source/-s
   # 2. Look up Moshell/ipdatabase path
   # 3. Map IP in viewer to eNB name in ipdatabase
   # 4. Set $enbid to this new value (run this sub only once)
   print "DEBUG: eNBId lookup called\n" if $debug;
   my $linein = shift @_; chomp($linein);
   my $enbId;
   my $moshell_ipdatabase;
   my @moshell_command = `moshell -n fake.kget uv`;
   foreach my $elem (@moshell_command) {
      if ($elem =~ /^ip_database\s+=\s+([\w\/]+),?/) {
         $moshell_ipdatabase = $1; chomp($moshell_ipdatabase);
         print "DEBUG: ipdatabase path = $moshell_ipdatabase\n" if $debug;
      }
   }
   open (FH, '<', "$moshell_ipdatabase") || print "No Moshell ipdatabase found.\n";
   #my %ip_to_eNBname;
   #my %name_to_ip;
   while (my $line = <FH>) {
#2000010 10.123.10.17            rbs_2000010
#2000020 10.123.9.241            rbs_2000020
   chomp ($line);
   next if ($line =~ /^$/ );
   next if ($line =~ /^\s?#/);
   if ($line =~ /^\s?(\w+)\s+(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\s+/) {
      $ip_to_eNBname{$2} = $1; # IP -> eNB Name map from ipdatabase
      $name_to_ip{$1} = $2; # eNB Name -> IP map from ipdatabase
      }
   }
   close (FH);
   return if $lookupIpdatabase;

   my $ip_in_viewer_source;
   if ($linein =~ /^\[(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\]/) { #NOTE - simple regex, clean this up
      $ip_in_viewer_source = $1;
      #print "DEBUG - ip_in_viewer_source = $ip_in_viewer_source\n";
   }
   foreach my $elem (keys %ip_to_eNBname) {
              $enbId = $ip_to_eNBname{$elem} if ($ip_in_viewer_source =~ $elem);
   }
   if (!$enbId) { #Check that we have some id, if not, use supplied
              $enbId = $enbid;
              print "[multimon.pl $version - enbid = $enbId]\n";
   } else {
              print "[multimon.pl $version - enbid = $enbId for ${name_to_ip{$enbId}} found in ipdatabase file]\n";
   }
   return $enbId;
}

sub version {
	print "Multimon.pl version $version\n";
}

=pod

=head1 NAME

   multimon.pl - Combine and tag multiple nodes trace and error logs  

=head1 SYNOPSIS

   viewer -m <ip1[,ip2,..]> [-s] | multimon.pl [-n <tag> | -r | -c <config file> | -l]

=head1 OPTIONS

=over 4

=item B<-h | --help>

   Prints full help details for this script. 
   OPTIONAL.

=item B<-v | --version>

   Prints the current tool version.
   OPTIONAL.

=item B<-n | --node> <nodeid>

   Tag (nodeid) trace and error output from viewer.
   OPTIONAL. SINGLE MODE.

=item B<-l | --lookup>

   Flag to use Moshell's ipdatabase to tag trace and error ouput from viewer.
   OPTIONAL. SINGLE MODE.

=item B<-c | --config> <config_file>

   Use a configuration file (config_file) to tag trace and error outupt from viewer.
   Format of config file shown below.
   OPTIONAL. MULTI MODE.

=back

=head1 DESCRIPTION

   The multimon.pl script allows trace and error logs to be tagged with node ids.
   This allows us to combine trace and error output from multiple nodes into one file.
   lteflowfox.pl can then use these tags to identify nodes in a flow. Hence mobility
   for LTE nodes can be collected in one file without additional post processing.
   
   The script runs in one of two "modes":
   SINGLE MODE - Single viewer log that is tagged.
   MULTI MODE - Uses viewers ability to specify multiple nodes in one instance.
   
   A default node tag configuration file, .monrc, can be specified in the users HOME
   directory. The file format is the same as used by the --config option.

=head1 EXAMPLES

=over 2

=item 1. single mode, node tagged by user (-n)

   viewer -m <ip address 1> | multimon.pl -n enb1 >> comb.log &
   viewer -m <ip address 2> | multimon.pl -n enb2 >> comb.log &

=item 2. single mode and source (-s), node tagged by Moshell's ipdatabase (else -n)

   viewer -m <ip address> -s | multimon.pl -n enb1 >> comb.log &

=item 3. multi mode and source (-s), nodes tagged by Moshell ipdatabase (-l)

   viewer -m <ip1,ip2,ip3,etc.> -s | multimon.pl -l > comb.log &

=item 4. multi mode and source (-s), nodes tagged by configuration file

   viewer -m <ip1,ip2,ip3,etc.> -s | multimon.pl -c=config.txt > comb.log &

=item 5. multi mode and source (-s), nodes tagged by .monrc configuration file

   viewer -m <ip1,ip2,ip3,etc.> -s | multimon.pl > comb.log &
   
=back

=head1 EXPECTED OUTPUT 

   viewer -m 10.45.18.10,10.45.18.11 -s | multimon.pl -c config.txt | lteflowfox.pl

   Timestamp     LH     eNBid    UE   eNB   TeNB   MME  racUeRef          Message
   [03:22:51.728]000100 4043/3   |<====|     |      |   1          (RRC)  rrcConnectionReconfiguration trgPhCid:456 BW:(DL-20-MHz) antPortCnt:an1
   [03:22:51.732]000100 4043/3   |     |====>|      |   1          (X2AP) SNStatusTransfer ueX2Id:1 ueX2Id:2 eRabId:5
   [03:22:51.848]000100 4043/3   |     |<====|      |   1          (X2AP) UEContextRelease ueX2Id:1 ueX2Id:2
   [03:22:40.132]000100 4044/    |     |====>|      |              (X2AP) X2SetupResponse plmnId:26280 plmnId:26280 enbId:104044 cellId:1 plmnId:26280
   [03:22:51.700]000100 4044/1   |     |<====|      |   2          (X2AP) HandoverRequest ueX2Id:1 cause:radioNetwork:unspecified plmnId:26280 enbId:104044 cellId:1 plmnId:26280 mmeUeS1Id:19646965 eRabId:5 trAddr:10.62.200.232 gtpTeId:074C29A1 plmnId:26280 enbId:104043 cellId:3
   [03:22:51.700]000100 4044/1   |====>|     |      |   2          (RRC)  RRCHandoverPreparationInformation 

   
=head1 DEPENDENCIES

=head2 Requirements:

   multimon.pl expects to receive piped input from the viewer tool.
   If the -c flags is used then the -s flag in viewer must be specified.
   If -l flag is used then the -s flag in viewer must be specified. Moshell's ipdatabase must also be available for tagging.

=head2 Configuration File Format (-c and in ~/.monrc)

   10.45.18.10 enb1du
   10.45.19.10 enb1bb
   10.45.18.11 enb2du
   10.45.19.11 enb2bb
   10.45.18.12 enb3du
   10.45.19.12 enb3bb

=head1 AUTHORS

   Alex Perez (alex.perez@ericsson.com)
   Dusan Simic (dusan.simic@ericsson.com)

=cut
