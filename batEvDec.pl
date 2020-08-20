#!/usr/bin/perl
use warnings;
use strict;
use Getopt::Long;
use Pod::Usage;
use Cwd;
use FindBin;                     # where was script installed?
use lib "$FindBin::Bin/perllib";     # use that dir for libs, too
use Parallel::ForkManager;

######################
# Batch LTE Cell and UE Trace decode
# Author: EPAEREZ
my $version = "2.0";
######################
# Updates:
#			2.0		Add		  Support for Flowfox (ver 3) - check time stamps on X2 messages
#        1.2      Add        -n flag to ltng when using translation files
#        1.1      Add        Zip of decoded output files supported (-z)
#        1.02     Add        Support for trace files collected directly from eNB (thanks Zlatko Filipovic)
#
#        1.01     Fix        Help printout amended for script name (thanks Tony Stanley)
#                 Mod        $max_processes changed from 5 to 1 (thanks Tony Stanley)
#                 Mod        Default output directory based on Event file name
#                 Add        Flag to specify user output directory (-o)
#                 Add        No flow or No html options (-nf and -nh respectively)
#

my ($help,$ver,$debug,$translation,$ctr_path,$ltng_stack,$output_dir_user,$noflow,$nohtml,$zip_files);
my $max_processes = 1; #default
GetOptions(
	"h|help"               => \$help,
	"d|debug"              => \$debug,
	"v|version"            => \$ver,
	"z|zip"                => \$zip_files,
	"t|translation=s"	     => \$translation,
	"p|ctr_path=s"		     => \$ctr_path,
	"n|numproc=i"          => \$max_processes,
	"s|stack=s"            => \$ltng_stack,
	"o|outdir=s"           => \$output_dir_user,
	"nf|noflow"            => \$noflow,
	"nh|nohtml"            => \$nohtml,
) or die("Invalid Options: use -h for help");

my @ctr_files = ();
my $output_dir = "";
my $ltng_tool;

# MAIN
check_inputs();
check_environment();
load_ctr();
decode_ctr();
final_message();

# SUBS
sub check_inputs {
   if ($debug) {
      print "DEBUG: Options:\n";
      print "\tHelp: $help\n" if $help;
      print "\tVersion: $ver\n" if $ver;
      print "\tDebug: $debug\n" if $debug;
      print "\tTrans: $translation\n" if $translation;
      print "\tCTR_Path: $ctr_path\n" if $ctr_path;
      print "\tProcesses: $max_processes\n" if $max_processes;
      print "\tltng_stack: $ltng_stack\n" if $ltng_stack;
      print "\tzip files: $zip_files\n" if $zip_files;
      print "\tuser_out: $output_dir_user\n" if $output_dir_user;
      print "\tnf: $noflow\n" if $noflow;
      print "\tnh: $nohtml\n" if $nohtml;
   }
	exit pod2usage(-verbose => 2, -exitval => 2) if $help;
	exit version() if $ver;
	exit pod2usage(-verbose => 1) if (!$ctr_path);
	exit pod2usage(-verbose => 1) if ($max_processes && (($max_processes < 1) || ($max_processes > 10)) );
	if ($ltng_stack) {
	   if ( $ltng_stack =~ /^L[0-9]{2}[a-z]\+?$/i ) {
	      $ltng_stack = "-p $ltng_stack";
	   } else {
	      $ltng_stack = "";
	      print "Protocol stack format is wrong, ignoring.\n";
	   }
	   print "DEBUG: stack is: $ltng_stack\n" if $debug;
	} else {
	   $ltng_stack = "";
	}
}

sub check_environment {
	# ltng path check
	$ltng_tool = `which ltng`; chomp($ltng_tool);
	print "DEBUG: ltng at: $ltng_tool\n" if $debug;
	die "Cannot find path to ltng. Aborting here: $!" if !$ltng_tool;
	
	# translation file path check
	if ($translation) {
	   if ( $translation !~ m:(.*)\/$: ) { # check for trailing forward slash presence
	   	$translation = $translation . "/";
	   }
	   print "DEBUG: Translation path input: $translation\n" if $debug;
	   opendir (TEMP, $translation) || die "Could not open translation file path. Aborting here: $!";
	   my @files = grep(/\.xml/, readdir TEMP);
	   print "@files \n" if $debug;
	   my $trans_count = 0;
	   foreach my $file (@files) {
	   	if ( $file =~ /ifModelLm|RbsEhbEventLm|RbsPmEventLm|lteRbsBbMtdInfoDul3|RbsExceptionEventLm/ ) {
	   		++$trans_count;
	   	}
	   }
	   die "The five expected translation files not found, please fetch from RBS or Translation server\n" if ( $trans_count != 5 );
	   closedir (TEMP);
	} elsif (!$translation) {
	   print "Translation path not provided, will attempt decoding with ltng-decoder - ensure you are on the ECN!\n";
	   $ltng_tool = `which ltng-decoder`; chomp($ltng_tool);
	   print "ltng-decoder at: $ltng_tool\n" if $debug;
	   die "Cannot find path to ltng-decoder. Aborting here: $!" if !$ltng_tool;
	}
	
	# ctr path check
	if ( $ctr_path !~ m:^(.*)\/$: ) { # check for trailing forward slash presence
		$ctr_path = $ctr_path . "/";
	}
	print "DEBUG: CTR path input: $ctr_path\n" if $debug;
	opendir (TEMP2, $ctr_path) || die "CTR file path provided not found. Aborting here: $!";
	closedir (TEMP2);
}

sub load_ctr {
	opendir (TEMP, $ctr_path) || die "Could not open input Event path: $!";
	@ctr_files = grep(/A2.*\.bin\.gz/, readdir TEMP);
	print "DEBUG: @ctr_files \n" if $debug;
	die "No files found to process in $ctr_path. Aborting here.\n" if (!@ctr_files);
	if ( $ctr_files[0] =~ /^A2.*_(CellTrace_DUL\d+_\d+|uetrace)_\d+\.bin\.gz$/ ) { #eNB format from /c/pm_data/
	   $output_dir = "$1_";
	} elsif ( $ctr_files[0] =~ /A2\d+.*MeContext=(\w+)(_celltracefile|_(\w+)_(\d+)_uetracefile).*\.bin\.gz/ ) { #OSS-RC format
	   $output_dir = "$1_";
	} else { #if file format not as expected, but .bin.gz dir, then just use dec_ as output folder name
	   $output_dir = "dec_";
	}
	
	#check for existing output dir if specified
	my $out_dir_exists = 0;
	if ( -e $output_dir_user) {
	   print "Output directory already exists, will re-use for processing.\n";
	   $out_dir_exists = 1;
	}
	
   #create output dir
   if ($output_dir_user) {
      if ($output_dir_user =~ /^(\/?(\w+\/?)+\w+)\/?$/) {
         $output_dir = $1;
      }
      if (!$out_dir_exists) {
         mkdir ("$output_dir") || die "Could not create user specified output directory $output_dir: $!";
      }
   } else {
	   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);
	   ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	   my $log_dir = sprintf("%04d%02d%02d_%02d%02d", ($year+1900,$mon+1,$mday,$hour,$min));
	   $output_dir .= "$log_dir";
	   mkdir ("$output_dir") || die "Could not create output directory $output_dir: $!";
	}
}

sub decode_ctr {
	my $loop_count = 0; # 0 - final_count
	my $final_count = @ctr_files; #to process last files
	my $batch_count = 0;
	my (@ltng_array, @ltng_zip_array, @flow_array, @flow_html);
	my $pm = new Parallel::ForkManager($max_processes);
   
	print "##########################################\n";
	print "#\n";
	print "# Batch Cell/UE Trace decoding ($version)\n";
	print "#\n";
	print "##########################################\n";
	print "# $final_count files in decoding path: $ctr_path\n";
	print "# Output directory $output_dir created.\n";
	print "# $max_processes parallel processes specified.\n" if ($max_processes != 1);
	print "# No text flow selected.\n" if $noflow;
	print "# No html flow selected.\n" if $nohtml;
	print "\n";
	
	#decode each file using ltng
	foreach my $file (@ctr_files) {
	   ++$batch_count;
	   ++$loop_count;
	   print "DEBUG: LOOP $loop_count\n" if $debug;
	   my ($dec_file_tmp, $flow_file_tmp);
		if ( $file =~ /(A.*).bin.gz/ ) {
			$dec_file_tmp = $1 . ".dec";
			$flow_file_tmp = $1 . ".flow";
		}
		my $file_path = $ctr_path . $file;
		my $dec_file = $output_dir . "/" . $dec_file_tmp;
		my $flow_file = $output_dir . "/" . $flow_file_tmp;
		print "$dec_file and $flow_file from $file_path\n" if $debug;
		
		if ($translation) {
		   my $dec_args = "$ltng_tool -f $file_path $ltng_stack -t $translation -n > $dec_file";
		   my $dec_zip = "gzip $dec_file" if $zip_files;
		   my $flow_args = "cat $dec_file | lteflowfox.pl -w > $flow_file";
		   my $flow_html = "lteflowfox.pl -f $dec_file -o $flow_file.html";
		   push @ltng_array, ($dec_args);
		   push @ltng_zip_array, ($dec_zip) if ($zip_files);
		   push @flow_array, ($flow_args) if (!$noflow);
		   push @flow_html, ($flow_html) if (!$nohtml);
		   print "Processing $file_path\n";
		} else {
		   my $dec_args = "$ltng_tool -f $file_path $ltng_stack > $dec_file";
		   my $dec_zip = "gzip $dec_file" if $zip_files;
		   my $flow_args = "cat $dec_file | lteflowfox.pl -w > $flow_file";
		   my $flow_html = "lteflowfox.pl -f $dec_file -o $flow_file.html";
		   push @ltng_array, ($dec_args);
		   push @ltng_zip_array, ($dec_zip) if ($zip_files);
		   push @flow_array, ($flow_args) if (!$noflow);
		   push @flow_html, ($flow_html) if (!$nohtml);
		   print "Processing $file_path\n";
		}
		
		#Decode after $max_processes teed up
		if ( ($batch_count == $max_processes) || ($loop_count == $final_count) ) {
		   print "DEBUG: ltng ARRAY:\n@ltng_array \n\n" if $debug;
		   print "DEBUG: flow ARRAY:\n@flow_array \n\n" if $debug;
		   print "DEBUG: html ARRAY:\n@flow_array \n\n" if $debug;
		   local (*OUT, *ERR);
		   open OUT, ">&STDOUT";
		   open ERR, ">&STDERR";
		   close STDOUT;
		   close STDERR;
		   foreach my $child (@ltng_array) {
		      print "DEBUG: ltng forks here\n";
		      $pm->start and next;
		      system($child);
		      $pm->finish;
		   }
		   $pm->wait_all_children;
		   
		   if (!$noflow) {
		      foreach my $child (@flow_array) {
		         print "DEBUG: flow forks here\n";
		         $pm->start and next;
		         system($child);
		         $pm->finish;
		      }
		   }
		   
		   if (!$nohtml) {
		      foreach my $child (@flow_html) {
		         print "DEBUG: html forks here\n";
		         $pm->start and next;
		         system($child);
		         $pm->finish;
		      }
		   }
		   
		   if ($zip_files) {
		      foreach my $child (@ltng_zip_array) {
		         print "DEBUG: zip forks here\n";
		         $pm->start and next;
		         system($child);
		         $pm->finish;
		      }
		   }
		   
		   open STDOUT, ">&OUT";
		   open STDERR, ">&ERR";
		   
		   print "DEBUG: Waiting for child processes to finish here...\n" if $debug;
		   #$pm->wait_all_children;
		   $batch_count = 0;
		   (@ltng_array, @flow_array, @flow_html) = ();
		}
	}
	print "Waiting for forked children to finish...";
	$pm->wait_all_children;
}

sub final_message {
	my $count = @ctr_files;
	print "\n\n##########################################\n";
	print "# Processing completed\n";
	print "##########################################\n";
	my $cwd = getcwd;
	print "# Output files stored in ${cwd}/${output_dir}\n\n";
}

sub version {
	print "Batch event decode version $version\n";
}

=pod

=head1 NAME

   batEvDec.pl - Batch decodes and flows UE and Cell Trace files

=head1 SYNOPSIS

   batEvDec.pl -p <path to UE or Cell Trace files> [-t <path to translation files>] [-n 7] [-s L11B] [-o out] [-nf] [-nh]

=head1 OPTIONS

=over 4

=item B<-h | --help>

   Prints full help details for this script. 
   OPTIONAL.

=item B<-v | --version>

   Prints the current tool version.
   OPTIONAL.

=item B<-p | --ctr_path>

   Path to UE or Cell Trace files to batch decode.
   MANDATORY.

=item B<-t | --translation>

   Path to translation files on server.
   OPTIONAL. Uses translation server in Sweden via ECN otherwise.

=item B<-n | --numproc>

   Number of concurrent processes to decode/flow on system (default 1, max 10).
   OPTIONAL. RANGE 1-10.

=item B<-s | --stack>

   Set the ltng decoder stack for ASN (i.e. L11B, L12A+,).
   OPTIONAL. See 'ltng -l' for details.

=item B<-o | --outdir>

   Specify the output directory for decoded files.
   OPTIONAL. Default output dir based on input file names.

=item B<-nf | --noflow>

   Do not produce flowed text files.
   OPTIONAL. Creates .flow text flow files by default.

=item B<-nh | --nohtml>

   Do not produce flowed html files.
   OPTIONAL. Creates .html flow files by default.
   
=item B<-z | --zip>

   Zip the decoded event files.
   OPTIONAL.

=back

=head1 DESCRIPTION

   The Batch LTE UE and Cell Trace decoding and flowing script
   is intended to help when processing a large number of captured
   event files (say from an OSS-RC server). This script allows
   decoding and flowing to be done outside of the customer env.
   
   The script will produce (by default):
      Decoded Cell or UE Trace files with a .dec suffix
      Flowed files (white, ASN, non customer) ending in .flow suffix
      HTML flowed files (non customer) ending in .html suffix

=head1 EXAMPLES

=over 2

=item 1. Batch decode and flow using downloaded translation files

   ./batEvDec.pl -p input_events/ -t /home/epaerez/support_xml/R23AU/

=item 2. Batch decode and flow using ECN server translation files

   ./batEvDec.pl -p input_events/

=item 3. Batch decode and flow specifing number of processes and protocol stack

   ./batEvDec.pl -p input_events/ -n 10 -s L11B

=item 4. Batch decode with no flow or html and output directory Cell_Trace_Output

   ./batEvDec.pl -p input_events/ -nf -nh -o Cell_Trace_Output

=back

=head1 DEPENDENCIES

=head2 Requirements:

   LteFlowFox tools in the path (i.e. lteflowfox.pl, ltng and ltng-decoder)
   Capable of writing in the current working directory (output directory)
   All translation files from the eNB are expected in the -t path specified  

=head2 Raw Cell Trace and UE Trace files

   The script expects to find a directory containing files with A*.bin.gz

=head1 AUTHORS and CONTRIBUTORS

   Alex Perez (EPAEREZ)
   Tony Stanley (ETONSTA)

=cut
