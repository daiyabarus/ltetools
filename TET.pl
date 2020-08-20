#!/usr/bin/perl

################################################################################
#  Description
#
#  Copyright Ericsson AB
#
#  The copyright to the computer programs herein is the property of
#  Ericsson AB. The programs may be used and/or copied only
#  with the written permission from Ericsson AB or in
#  accordance with the terms conditions stipulated in the agreement/contract
#  under which the programs have been supplied.
#
################################################################################

=head1 NAME

TET - B<T>race and B<E>rror B<T>ranslator


=head1 SYNOPSIS

TET.pl [-options]

Reads log data from stdin and translates all baseband trace data found, while leaving other data.

=head1 OPTIONS

=over 8

=item B<-h>, B<--help>

Displays help text

=item B<-v <lvl>>

Enable verbosity level lvl

=item B<--trace_strings <file>>

File to read trace string definitions from (eg lteRbsBbmContDul2Lm.txt)

=item B<--trace_groups <file>>

File to read trace groups from.

=item B<--trace_obj_list <file>>

File to read trace object names from.

=item B<--signals <file>>

XML file with signal numbers and names, when translating interface traces

=item B<--no-clearcase>

Do not assume we have clearcase access to the vob. This means that if the version of the  string list does not match the version in the the trace header, we fail rather than try to pick the right version from the VOB.

=item B<--force>

Use specified trace_string file even if strid doesn't match (may lead to incorrect translation, do not use this unless you understand why you need it).

=item B<--build_view <view>>

Look for trace string files in <view> instead of in current view. Should not be used together with --trace_groups, --trace_obj_list or --signals.

=item B<--out_file <file>>

use .out-file to generate temporary trace string file.

=item B<--out_file_dir <dir>>

use all .out files in dir to generate temporary string file.

=item B<--use_utc>

use utc traces to set correct timestamps on traces (this is the default behaviour).

=item B<--nouse_utc>

don't use utc traces to set correct timestamps on traces.

=item B<--xml_file>

Use the lteRbsBbTraceTranslation xml file for all tranlation information.


=back


=head1 DESCRIPTION

TET is used to post-process binary DSP trace data in the GCPU log file.
Stringfile contains all the trace strings. These must be stored in
FIXME: what format?

=cut
#$| = 1;


################### MODULES ###################
#use FindBin;                # where was script installed?
#use lib "$FindBin::Bin/perllib";      # use that dir for libs, too
#use lib "/vobs/erbs/ext/tools/flexTools";
#my ($BASE) = rel2abs( $0 ); 
#print "BASE = $BASE\n";
BEGIN {
my ($BASE) = ($0 =~ /\// ? substr($0, 0, rindex($0,"/")) : "."); # magic line so that we can use decoder from anywhere
push(@INC, $BASE);
push(@INC, $BASE."/lib");
push(@INC, $BASE."/ltelib");
push(@INC, $BASE."/perllib");
}
use fap qw/:llog fatalError warning/;
use XML::Parser::Expat;
use XML::Parser;
use XML::Simple;


fap::use Data::Dumper;
fap::use Getopt::Long;
fap::use Pod::Usage;
fap::use "Storable qw /dclone/";

#require ("/vobs/erbs/ext/tools/flexTools/traceLib/rev2verLib.pl");
require ("traceLib/rev2verLib.pl");


################### PRAGMAS ###################
use strict;

################### GLOBAL VARIABLES ###################

### XML tags
my $HASH_GCPUID_TAG = "GCPU_ID";
my $HASH_SEQNO_TAG = "Seqno";
my $HASH_PRODUCER_TAG = "Producer";
my $HASH_HDRVERSION_TAG = "Hdr_Version";
my $HASH_STRVERSION_TAG = "Trace_String_Version";
my $HASH_TRACETYPE_TAG = "Trace_Type";
my $HASH_FRAGTOTAL_TAG = "Frag_Total";
my $HASH_FRAGNO_TAG = "Frag_No";
my $HASH_SIZE_TAG = "CM_buffer_len";
my $HASH_OVERWRITTEN_TAG = "Overwritten";
my $HASH_NID_TAG = "NID";
my $HASH_LEN_TAG = "LDM_buffer_len";
my $HASH_TRGRP_TAG = "Trace_group";
my $HASH_TRID_TAG = "Trace_ID";
my $HASH_TRONAME_TAG = "Trace_object_name";
my $HASH_STRID_TAG = "STRID";
my $HASH_BFNREG_TAG = "BFN";
my $HASH_LENGTH_TAG = "Trace_len";
my $HASH_LPID_TAG = "lPID";
my $HASH_PID_TAG = "PID";
my $HASH_STRING_TAG = "String";
my $HASH_WARNING_TAG = "Warning";

### Hash tags not in XML
my $HASH_TIME_TAG = "Time";

##Strid xml tags
my $TOP_TAG = 'stridTranslator';
my $STRIDLIST_TAG = "stridList";

### Trace types
my $TRACE_TYPE_NORMAL = 1;
my $TRACE_TYPE_BUS = 2;
my $TRACE_TYPE_WH = 3;


### Default places to look for strid file
my @DEFAULT_STRID_FILE_ARR = 
  ("./tracestr.txt",
   "./lteRbsBbmContLm.txt",
   "/vobs/erbs/node/lm/bbmContLmU/build/lteRbsBbmContLm.txt",
   "/vobs/erbs/node/lm/bbmContDul2LmU/build/lteRbsBbmContDul2Lm.txt",
   "/vobs/erbs/node/lm/bbmContDul3LmU/build/lteRbsBbmContDul3Lm.txt",
   "/vobs/erbs/node/lm/upUl1LmU/build/upUl1LmU.txt", 
   "/vobs/erbs/node/lm/upUl1LmU/build/upUl1LmU_DUL2.txt", 
   "/vobs/erbs/node/lm/upUl1LmU/build/upUl1LmU_DUL3.txt", 
   "/vobs/erbs/node/lm/upUl2LmU/build/upUl2LmU.txt", 
   "/vobs/erbs/node/lm/upUl2LmU/build/upUl2LmU_DUL2.txt", 
   "/vobs/erbs/node/lm/upUl2LmU/build/upUl2LmU_DUL3.txt", 
   "/vobs/erbs/node/lm/upDlLmU/build/upDlLmU.txt", 
   "/vobs/erbs/node/lm/upDlLmU/build/upDlLmU_DUL2.txt", 
   "/vobs/erbs/node/lm/upDlLmU/build/upDlLmU_DUL3.txt", 
   "/vobs/erbs/node/lm/upcLmU/build/upcLmU.txt", 
   "/vobs/erbs/node/lm/upcLmU/build/upcLmU_DUL2.txt", 
   "/vobs/erbs/node/lm/upcLmU/build/upcLmU_DUL3.txt" 
  );
my @CC_WHITE_STRING_VERSION_BASE_ARR = 
  ("/vobs/erbs/binaries1/bbmContLm/lteRbsBbmContLm.txt\@\@/CXP9020077_",
   "/vobs/erbs/binaries1/bbmContDul2Lm/lteRbsBbmContDul2Lm.txt\@\@/CXP9020272_",
   "/vobs/erbs/binaries<binDirNum>/bbmContDul3Lm/lteRbsBbmContDul3Lm.txt\@\@/CXP9020294_"
  );

my @CC_WHITE_CONFIG_SPEC_BASE_ARR = 
  ("/vobs/erbs/binaries1/bbmContLm/cs\@\@/CXP9020077_",
   "/vobs/erbs/binaries1/bbmContDul2Lm/cs\@\@/CXP9020272_",
   "/vobs/erbs/binaries<binDirNum>/bbmContDul3Lm/cs\@\@/CXP9020294_"
  );

my @HW_VERSION_NAMES =
  ("DUL 1", "DUL 2", "DUL 3");

### LPP constants
my $MAX_INTERFACE_NAME = 30; #max chars in interface name

### Initial switch values
my $traceStringBib = "";
#  "/vobs/erbs/elib/bbBaseBl/traceStringsLU/inc/bbbase_traceStrings.txt";
my $traceGroupBib =
  "/vobs/erbs/elib/bbBaseBl/traceStringsLU/inc/bbbase_traceGroups.txt";
my $traceObjList =
  "/vobs/erbs/elib/bbBaseBl/traceStringsLU/inc/bbiTrace_objects.h";
#  "/vobs/erbs/elib/bbBaseBl/traceStringsLU/inc/bbbase_traceMacros.h";
my $sigFileBib =
  "/vobs/erbs/elib/bbBaseBl/commonLU/inc/bbiSignals.sig";

my $tokenString = "$HASH_TIME_TAG $HASH_BFNREG_TAG " .
   "$HASH_PRODUCER_TAG $HASH_TRONAME_TAG $HASH_TRGRP_TAG $HASH_STRING_TAG";
#  "$HASH_GCPUID_TAG $HASH_TRONAME_TAG $HASH_TRGRP_TAG $HASH_STRING_TAG";

my $formatString = "%s 0x%08x ULMA%d/%s %s %s\n";
my $lpp_traceObject = "LPP_TRACE_BIN";

my $verTraceStringsFile   = -1;
my $verTraceStringsFileUnknown = 0; # true if we have tried to find version but failed.
my $verTraceStringsHeader = -1;

my $haveReadTraceStrings = 0;
my %traceStrings;

my $noClearCase = 0;

my @verbose;

my $showUTCtraces = 0;

my $useUTCtraces = 1;

my %lastSeq = {};

my $forceTraceStrings = 0; # should tracestring-file be used even if wrong version?

my %traceGroups;
my %signals;
my %traceObjIds;

my $xmlFile;

# globals for handling tracefile generation from .obj
my $outFile;
my $outFileDir;
my $stridGenCommand = "/vobs/erbs/elib/lpp/export/tracestr --info \"TET.pl\" ";
my $tempStridFile = "/tmp/TET_tracestr.txt";
my %lmIds = ("upUl1LmU.out", 1, "upUl2LmU.out", 2, "upDlLmu.out", 3, "upcLmU.out", 4, "upUl1.out", 1, "upUl2.out", 2, "upDl.out", 3, "upc.out", 4);
# global for looking for trace strings in other view
my $buildView;
my $startView = "cleartool startview ";
my $viewPath = "/view/";

#UTC translation globals
my $utcTraceRead = 0;
my $utcBfn = 0;
my $utcMs = 0;
my $utcSec = 0;
my $version = "R1C";
my $cc_version = "D3-EXTTOOLSFLEXTOOLS_LTE_RBS_16.2_KI";

################### MAIN ###################
MAIN: {
    ### Parse arguments
    GetOptions("help"=>sub { pod2usage(-exitstatus => 1, -verbose => 1); },
	       "tokens=s"=>\$tokenString,
	       "format=s"=>\$formatString,
	       "trace_object=s"=>\$lpp_traceObject,
	       "trace_obj_list=s"=>\$traceObjList,
	       "trace_strings=s"=>\$traceStringBib,
	       "trace_groups=s"=>\$traceGroupBib,
	       "signals=s"=>\$sigFileBib,
	       "no-clearcase"=>sub { $noClearCase = 1; },
	       "verb=i"=>sub { verbosityLvl @_[1]; },
	       "utc"=>sub{$showUTCtraces = 1},
	       "force!"=>\$forceTraceStrings,
	       "out_file=s"=>\$outFile,
	       "out_file_dir=s"=>\$outFileDir,
	       "build_view=s"=>\$buildView,
	       "xml_file=s"=>\$xmlFile,
	       "use_utc!"=>\$useUTCtraces,
               "version"=>sub {print"fTET version: $version, based on CC version: $cc_version.\n";exit },
	      )
      or pod2usage(2);
    
    #fatalError("$traceGroupBib doesn't exists") if (!-e $traceGroupBib);

    handleOutFile();
    handleXmlFile();
 
    ### Parse file
    my @binData;
    my $isTracing = 0;
    llog("Parsing input", 1);
    
    my @trArr;
    my %pendingData;

    $SIG{ALRM} = sub { printTraces( \@trArr,1)};#Print out left over if there is no data after one second;

    my $currentLine = <>;
    while ($currentLine){ # 
	#print "New loop: \n";
	#print $1;
	alarm(1);#If there are no data in 1 second, print out the left over.
		
	my $str = $currentLine;
	llog("Line is: $_\n", 4);

	#the regexp matches a timestamp followed by either gcpuNNNN/traceobj or just traceobj followed by -:0, or HICAP
	# apperently we also need /00100/gcpuNNNN
	if ($str =~ /\[([\dx]{4}-[\dx]{1,2}-[\dx]{1,2} [\dx]{1,2}:[\dx]{1,2}:[\dx]{1,2}\.[\dx]{1,3})\] ((([\d]*\/)?(gcpu\d*\/)?([[:alnum:]_-]+)) -:0|HICAP)/) {
	    my $traceTime = $1;
	    my $headerLine = $currentLine;

	    # found a trace chunk, collect the data in the chunk
	    my @U8Arr;
	    $currentLine = <>;
	    while ($currentLine) {
		$_ = $currentLine;
		llog("Sees $_", 4);
		if (/^[\w]*[\da-fA-F]{4} ([A-Fa-f\d\t ]+)/) {
		    push (@U8Arr, split(" ", $1));
		    llog("Found bin ROW $1", 3);
		    $currentLine = <>;
		} else {
		    last;
		}
	    }

	    if (scalar(@U8Arr) == 0) {
		llog("found header with no data, may be a mp/gcpu trace: $headerLine", 1);
		print $headerLine; #tor part of a trace, just print line
		# Must have redo here, since the "Read input" loop above has
		# eaten the first line following the binary blob, which just
		# might be the first line of the next trace buffer. So, we
		# want to check it again.
		#redo OUTER;		# Break this iteration redo OUTER;
	    } else {

		# Translate the data
		@binData = convertToU16(@U8Arr);
		
		translateData(\@binData,
			      \@trArr,
			      \%traceObjIds,
			      \%traceGroups,
			      \%pendingData,
			      $traceTime,
			      #$gcpuId,
			      #$traceObj,
			      #$traceGrp,
			      \%signals);
		
		# Sort descending according to BFN
		@trArr = sort { $a->{$HASH_BFNREG_TAG} <=> $b->{$HASH_BFNREG_TAG} } @trArr;


		### Append time to each trace if not already set.
		map { $_->{$HASH_TIME_TAG} = "[" . $traceTime . "]" if ! defined $_->{$HASH_TIME_TAG}} @trArr;
		
		printTraces(\@trArr,0);
		
		# Must have redo here, since the "Read input" loop above has
		# eaten the first line following the binary blob, which just
		# might be the first line of the next trace buffer. So, we
		# want to check it again.
		#redo OUTER;		# Break this iteration
	    }
	} else { # do not match regexp 
	    
	    if ($str =~ /^\$/) {
		# Last line of log file, empty array of the last traces
		printTraces(\@trArr,1 );
	    }
	    #take care of the signal name for timmig measurment.(this can not be done in the code since it is in the sigDisp.)
	    if($str =~ /^Time measurement for sigNo=(\d+)( .*)/)
	    {
                my $sigName = defined $signals{$1} ? $signals{$1} : "UNKNOWN_SIGNAL";
		print "Time measurement for sigNo=$1 ($sigName) $2\n";
	    }
	    else
	    {
		## If here not a interresting line, just print it
		printTraces(\@trArr,1 );
		print "$str";
	    }
	    
	    $currentLine = <>;
	}
    }

    # Print out any left overs in the array
    if (scalar(@trArr) > 0) {
	printTraces(\@trArr,1 );
    }
}

################################################################################
# Routine translateTraceBus
##
# @brief Translates a "normal" trace bus. Also checks for (undocumented) interface trace, and tries to parse that.
#
# @param[in]     $signals_ref    reference to hash of signal names
# @param[out]    $tracearr_ref   reference to the trace array where the trace data is put 
# @param[in]     $traceTime      bfn-time from data-chunk
# @param[in]     $traceObjIds_p  reference to traceId hash
# @param[in]     $traceGroups_p  reference to tracegroup hash
# @param[in]     $binData_p      reference to the raw data array.
#
# @return        NONE       
#
################################################################################
sub translateTraceBus {
  my $signals_ref = shift;
  my $trace_hash_ref = shift;
  my $tracearr_ref = shift;
  my $traceTime = shift;
  my $traceObjIds_p = shift;
  my $traceGroups_p = shift;
  my $binData_p = shift;
  my @binData = @{$binData_p};
  my $fixHeaderLength = 8;
  
  my $TOT_LENGTH_TAG = "TOT_LENGTH";
  my $READ_DATA_TAG  = "READ_DATA";
  my $RAW_DATA_TAG   = "RAW_DATA";
  my $trObj;
  my $str;
  my %trace_hash =%{$trace_hash_ref};
    llog("Parsing BUS data for traceobj $trObj", 1);

  #read header from start of buffer, offset is modified with the number of items read
  my $offset = 0;
  my ($bufSize, $pid, $trGrp, $traceId, $bfn, $payloadSize) = 
    readBusHeader(\@binData, \$offset, \%trace_hash );
  @binData = splice(@binData, $offset); # remove info read from beginning of buffer

 
  $trace_hash{$HASH_TIME_TAG} = "[" . $traceTime . "]";
  llog("time       = $trace_hash{$HASH_TIME_TAG}", 3);
  
  if (exists($traceGroups_p->{$trGrp})) {
    $trace_hash{$HASH_TRGRP_TAG} = $traceGroups_p->{$trGrp};
  } else {
    $trace_hash{$HASH_TRGRP_TAG} = "TraceGroup: $trGrp";
  }
  llog("traceGrp   = $trace_hash{$HASH_TRGRP_TAG}", 3);
  
  if (exists($traceObjIds_p->{$traceId})) {
    $trace_hash{$HASH_TRONAME_TAG} = $traceObjIds_p->{$traceId};
  } else {
    $trace_hash{$HASH_TRONAME_TAG} = "TraceId: $traceId";
  }
  llog("traceObj   = $trace_hash{$HASH_TRONAME_TAG}", 3);


  my @dataCopy = @binData; # used if parsing fails
  my $parseOk = 1;

  my $dataOffset = shift(@binData);
  llog("dataOffset = $dataOffset", 3);

  my $totLen     = shift(@binData);
  llog("totDataLen = $totLen", 3);

  my $bfn        = shift(@binData)<<16 | shift(@binData);
   llog("bfn        = $bfn", 3);
 
  my $sessionRef = shift(@binData)<<16 | shift(@binData);
  llog("sessionRef = $sessionRef", 3);

  my $sigNo      = shift(@binData);
  llog("sigNo      = $sigNo", 3);

  my $dspNo      = shift(@binData);
  llog("dspNo      = $dspNo", 3);
  
  $trace_hash{$HASH_BFNREG_TAG} = $bfn;
  if ($useUTCtraces && $utcTraceRead) {
    my $utcTime = getUtcTime($trace_hash{$HASH_BFNREG_TAG});
    $trace_hash{$HASH_TIME_TAG} = $utcTime;
    llog("$HASH_TIME_TAG = $trace_hash{$HASH_TIME_TAG}", 3);
    
  }
  $trace_hash{$HASH_NID_TAG} = $dspNo;
  $trace_hash{$TOT_LENGTH_TAG} = $totLen;
  
  $str = "";
  # Now read name of interface
  my $interfaceName = "";
  my $charCount = 0;
  llog("Parsing interface name", 3);
  while ( $charCount <= $MAX_INTERFACE_NAME ) {
    my $currChar = shift @binData;
    llog("currchar: $currChar",4);
    $charCount += 1;
    if ($currChar == 0) {
      # Found a NULL terminated string
      last;
    }

    # End of arr
    if ( $#binData == 0 ) {
      llog("Error in header [not a BB trace?], name is $interfaceName. Array is empty but no null termination found!", 1);
      return 0;
    }
	
	
    # Not a character
    #	return 0 if ($nextChar !~ /[A-Za-z0-9:_ ]/);
    #if ($nextChar !~ /[\w\s:_\-\/]/) {
    if (!($currChar >= 32 && $currChar <= 126)){ 
      $parseOk = 0;
      llog("Unknown next character [$currChar], NOT a valid formatted header. Skipping!", 2);
      last;
    }
	
    $interfaceName = $interfaceName.chr($currChar);
  } 
  
  if ($charCount > $MAX_INTERFACE_NAME) {
    $parseOk = 0;
    llog("interface name is too long, possibly not an interface trace", 2);
    
  }
  llog("Interface name is $interfaceName", 3);
  if ((my $start = $charCount + $fixHeaderLength) != $dataOffset/2) {
    $parseOk = 0;
    llog("Error in interface trace header, data start is $dataOffset but found start is $start!", 2);
  }
  
  if ($parseOk) {
  
    my $sigName = defined $signals_ref->{$sigNo} ? 
      $signals_ref->{$sigNo} : "UNKNOWN_SIGNAL";
    llog("sigName    = $sigName", 3);
    
    $str = sprintf("$str: $sigName ($sigNo) %s", 
		   $trace_hash{$HASH_TRGRP_TAG} eq "bin_send" 
		   ? "=> " 
		   :  $trace_hash{$HASH_TRGRP_TAG} eq "BUS SEND"
		   ? "=> "
		   : "<= ");
    
    $str = sprintf("$str $interfaceName (sessionRef=0x%lx)", 
		   $sessionRef);
    $trace_hash{$HASH_STRING_TAG} = $str;
    
    $str = "\n";
    # Push data
    $trace_hash{$READ_DATA_TAG} += $#binData + 1;
    llog("total data read = $trace_hash{$READ_DATA_TAG} of $trace_hash{$TOT_LENGTH_TAG}", 3);
  } else {
    # not an interface trace, get group and id and print
    llog("trGrp is $trGrp, traceId is $traceId", 4);
    my $trGrpName = $traceGroups_p->{$trGrp};
    my $trObjName = $traceObjIds_p->{$traceId};
    #print Dumper ($traceObjIds_p);
    $str = "$trGrpName trace from $trObjName \n";
    
    llog("Interface trace parse failed, resetting data", 2);
    @binData = @dataCopy; #restore data

  }
 
  $str = formatBusData($str, \@binData);

  $trace_hash{$HASH_STRING_TAG} = $trace_hash{$HASH_STRING_TAG}.$str;
  
  push @$tracearr_ref, dclone(\%trace_hash);
  
  # }
  
  llog("Done parsing BUS data for traceobj $trObj", 1);
  return 1;
}
################################################################################
# Routine readTraceStringsFromFile
##
# @brief Reads trace strings from file, entering them into %
#
################################################################################
sub readTraceStringsFromFile {
  my ($file, $traceStrings_p) = @_;

  return if (! -e $file);

  my $lno = 0;
  open(hBib, "<$file")
    or fatalError("Couldn't open $file");
  ### Parse input files
  $lno = 0;
  llog("Parsing trace string list", 1);
  llog("String list file used for parsing traces:\n  $file", 1);
  while (<hBib>) {
    $lno++;
   #  if (/^\s*\# Auto-generated string list version: (\d+)$/) {
#       $verTraceStringsFile = $1;
#       if (not ($verTraceStringsFile > 0 &&
# 	       $verTraceStringsFile < 65536)) {
# 	fatalError("failed to get trace string list version "
# 		   . "from $file");
#       }
    if (/^\s*#/ or /^\s*$/) {
      next;
    } elsif (/^\s*(\d+),\s*(\d+),\s*(\d+),\s*\"(.*)\"(\s*#.*)?$/) {
      $traceStrings_p->{$1}{$2}{$3} = $4;
      $verTraceStringsFile = $1;
    } else {
      fatalError("failed to parse line no $lno of file $file");
    }
  }
  close(hBib);
 
    
  if ($verTraceStringsFile < 0) {
    llog("no traces found in file $file", 2);
  }
}

################################################################################
# Routine readSignalsFromFile
##
# @brief Reads signal numbers and signal names from file
#
################################################################################
sub readSignalsFromFile {
    my ($file, $signals_p) = @_;
    
    fatalError("$file doesn't exists") if (! -e $file);
    
    my $lno = 0;
    open(hBib, "<$file")
      or fatalError("Couldn't open $file");
    ### Parse input files
    llog("Parsing signal file", 1);
    llog("Signal file used for parsing signals:\n  $file", 1);
    while (<hBib>) {
      if (/^\#define ([\w_]*) (\d*)U$/) {
	if ($1 !~ /MAX|MIN/) {
	  # Add signal
	  $signals_p->{$2} = $1;
	}
      }
    }
    close(hBib);

  }

################################################################################
# Routine translateData
##
# @brief Parses common header, collecting parts of segmented traces and passing 
#        complete traces to the various translation functions.
#
# @param[in]     $gcpuId         name of gcpu that this trace dump came from
# @param[in]     $dataArr_p      reference to U16 bin data
# @param[in]     $traceObjIds_p  reference to traceObjIds hash
# @param[in]     $traceGroups_p  reference to traceGroups hash
#
# @return        @trArr          array containing all traces
#
################################################################################
sub translateData {
  my ($dataArr_p, $trArr_ref, $traceObjIds_p, $traceGroups_p, $pendingData_p, $traceTime,
      #$gcpuId, $traceObj, $traceGrp, 
      $signals_ref) = @_;
  my @binData = @{$dataArr_p};
  my %trHash;
  my $str;

  #$trHash{$HASH_GCPUID_TAG} = $gcpuId;

  ### Main driver loop
  my $offset = 0;
  llog("Reading GCPU header!", 1);
  #readGCPUHeader (\@binData, \$offset, \%trHash);
  readCommonHeader (\@binData, \$offset, \%trHash);


  checkForTraceStringFile($trHash{$HASH_STRVERSION_TAG});

  my $seqId = "prod".$trHash{$HASH_PRODUCER_TAG}."seq".$trHash{$HASH_SEQNO_TAG};

  if ($trHash{$HASH_FRAGTOTAL_TAG} > 1) {
    llog("found fragmented trace", 2);
    #print $trHash{$HASH_FRAGNO_TAG}, "\n";
    if ($trHash{$HASH_FRAGNO_TAG} == 1) {
      # add data to pending hash
      llog("added first part of trace with seqno $trHash{$HASH_SEQNO_TAG}", 2 );
      #print "offset: $offset \n";
      my @data = @binData[$offset..scalar(@binData)-1] ;
      $pendingData_p->{$seqId} = \@data;
      #print Dumper(%$pendingData_p);
    } else {
      # concatenate data to pending hash
      llog("concatenating data to trace with seqno $trHash{$HASH_SEQNO_TAG}", 2 );
      #print "offset: $offset \n";
      #print Dumper(%$pendingData_p);
      if ($pendingData_p->{$seqId} != 0) { 
	$offset += 8; #remove bus header since all info is in first header.
	my @newData =  @binData[$offset..scalar(@binData)-1];
	my @data = (@{$pendingData_p->{$seqId}} , @newData);
	$pendingData_p->{$seqId} = \@data;
      }
      else {
	print "TET discovered an ERROR: Fragment missing in bustrace dumping data\n";
	$str = formatBusData($str, \@binData);
	print  $str, "\n";
	return;
      }
    }

    if ($trHash{$HASH_FRAGNO_TAG} == $trHash{$HASH_FRAGTOTAL_TAG}){
      @binData = @{$pendingData_p->{$seqId}};
    }
  }
  
  if ($trHash{$HASH_FRAGTOTAL_TAG} == 1 || $trHash{$HASH_FRAGNO_TAG} == $trHash{$HASH_FRAGTOTAL_TAG}) {
    
    
    my $prod = $trHash{$HASH_PRODUCER_TAG};
    my $seq = $trHash{$HASH_SEQNO_TAG};

    if ($lastSeq{$prod} == 0) {
      $lastSeq{$prod} = $seq;
    } else {
      if ($seq - 1 != $lastSeq{$prod}) {
	my $missing = $seq -1 -$lastSeq{$prod};
	#warning("Non-consecutive trace numbers, up to $missing traces may be missing");
	$trHash{$HASH_WARNING_TAG} = "Non-consecutive trace numbers, up to $missing traces may be missing"; 
      }
    }

  $lastSeq{$prod} = $seq;

    #print Dumper(@binData);

    if ($trHash{$HASH_TRACETYPE_TAG} == $TRACE_TYPE_NORMAL) {
      llog("translating normal trace", 2);
      translateNormalTrace(\@binData, \$offset, \%trHash,
			 $traceObjIds_p, \%traceStrings, $traceGroups_p, $trArr_ref);
    }else {
      #for bus-traces, remove the parsed commonheader if only segment
      if ($trHash{$HASH_FRAGTOTAL_TAG} == 1 || $trHash{$HASH_FRAGTOTAL_TAG} == 0) {
	#if single fragment trace
	@binData = splice(@binData, $offset); # remove info read from beginning of buffer
      }
    }
    if ($trHash{$HASH_TRACETYPE_TAG} == $TRACE_TYPE_BUS) {
      
      llog("translating trace bus", 2);

      my $ret = translateTraceBus($signals_ref,
				  \%trHash,
				  $trArr_ref,   
				  $traceTime,
				  $traceObjIds_p,
				  $traceGroups_p,
				  \@binData);
    }
    if ($trHash{$HASH_TRACETYPE_TAG} == $TRACE_TYPE_WH) {
      
      llog("translating trace bus with header", 2);
      translateTraceWH(\@binData, #\$offset, 
		       \%trHash,
		       $traceObjIds_p, \%traceStrings, $traceGroups_p, $trArr_ref);
    } 
    
    
  }
}

################################################################################
# Routine translateNormalTrace
##
# @brief Translates a regular trace bus of binary traces.
#
# @param[in]     $binData      reference to the raw data array.
# @param[in]     $offset         offset into databuffer
# @param[in]     $trHash       reference to tracehash
# @param[in]     $traceObjIds_p  reference to traceId hash
# @param[in]     $traceGroups_p  reference to tracegroup hash
# @param[out]    $tracearr_ref   reference to the trace array where the trace data is put 
#
# @return        NONE       
#
################################################################################
sub translateNormalTrace{
  my $binData = shift;
  my $offset = shift;
  my $trHash = shift;
  my $traceObjIds_p = shift;
  my $traceStrings = shift;
  my $traceGroups_p = shift;
  my $trArr_ref = shift;

  my $outer_loop = $$offset + $trHash->{$HASH_SIZE_TAG};
  while ($$offset < $outer_loop) {
    llog("Reading trace header!", 1);
    readTraceHeader ($binData, $offset, $trHash);
    my $inner_loop = $$offset + $trHash->{$HASH_LEN_TAG};
    while ($$offset < $inner_loop) {
      llog("Reading trace!", 2);
      llog("offset $offset", 2);
      if(readTrace($binData, $offset, $trHash,
			$traceObjIds_p, $traceStrings, $traceGroups_p)) {
	push @$trArr_ref, dclone($trHash);
	$trHash->{$HASH_WARNING_TAG} = ""; #only add warning to first trace in buffer
      }
    }
  }
}



################################################################################
# Routine translateTraceBusWH
##
# @brief Translates a "WH" trace bus.
#
# @param[in]     $binData      reference to the raw data array.
# @param[in]     $trHash       reference to tracehash
# @param[in]     $traceObjIds_p  reference to traceId hash
# @param[in]     $traceGroups_p  reference to tracegroup hash
# @param[out]    $tracearr_ref   reference to the trace array where the trace data is put 
#
# @return        NONE       
#
################################################################################

sub translateTraceWH{
  my $data_p = shift;

  my $hash_p = shift;
  my $traceObjIds_p = shift;
  my $traceStrings_p = shift;
  my $traceGroups_p = shift;
  my $trArr_ref = shift;
  
  my $offset = 0;
  my $offset_p = \$offset;
  my ($bufSize, $pid, $trGrp, $traceId, $bfn, $payloadSize) = 
    readBusHeader($data_p, $offset_p, $hash_p);

  my $buffLen = read16($data_p, $offset_p);
  my $argLen = read16($data_p, $offset_p);
  my $traceStringListVersion = read16($data_p, $offset_p);# not used
  my $strid = read32($data_p, $offset_p);
  
  
  if (exists($traceGroups_p->{$trGrp})) {
    $hash_p->{$HASH_TRGRP_TAG} = $traceGroups_p->{$trGrp};
  } else {
    $hash_p->{$HASH_TRGRP_TAG} = $trGrp;
  }
  llog ("$HASH_TRGRP_TAG = $hash_p->{$HASH_TRGRP_TAG}", 3);
  
  $hash_p->{$HASH_STRID_TAG} = $strid;
  llog ("$HASH_STRID_TAG = $hash_p->{$HASH_STRID_TAG}", 3);
  
  $hash_p->{$HASH_TRID_TAG} = $traceId;
  llog ("$HASH_TRID_TAG = $hash_p->{$HASH_TRID_TAG}", 3);
  # FIXME: Temporary fix. LPP always traces on object id 0, and the
  # tmg.pl script allocates other trace ids starting from 1. Remove the
  # special LPP case once LPP gets its own trace system.
  if ($hash_p->{$HASH_TRID_TAG} == 0) {
    $hash_p->{$HASH_TRONAME_TAG} = "LPP";
  }
  else {
    my $name = $traceObjIds_p->{$hash_p->{$HASH_TRID_TAG}};
    $name = $hash_p->{$HASH_TRID_TAG} unless $name;
    $hash_p->{$HASH_TRONAME_TAG} = $name;
  }
  
  
  llog ("$HASH_TRONAME_TAG = $hash_p->{$HASH_TRONAME_TAG}", 3);
  
  $hash_p->{$HASH_BFNREG_TAG} = $bfn;
  llog ("$HASH_BFNREG_TAG = $hash_p->{$HASH_BFNREG_TAG}", 3);
  if ($useUTCtraces && $utcTraceRead) {
    my $utcTime = getUtcTime($hash_p->{$HASH_BFNREG_TAG});
    $hash_p->{$HASH_TIME_TAG} = $utcTime;
    llog("$HASH_TIME_TAG = $hash_p->{$HASH_TIME_TAG}", 3);
  }
  $hash_p->{$HASH_LENGTH_TAG} = $argLen;
  llog ("$HASH_LENGTH_TAG = $hash_p->{$HASH_LENGTH_TAG}", 3);

  #$hash_p->{$HASH_LPID_TAG} = $lpid;
  #llog ("$HASH_LPID_TAG = $hash_p->{$HASH_LPID_TAG}", 3);

  $hash_p->{$HASH_PID_TAG} = $hash_p->{$HASH_NID_TAG} << 8 | $hash_p->{$HASH_LPID_TAG};
  llog ("$HASH_PID_TAG = $hash_p->{$HASH_PID_TAG}", 3);
  
  my $argStringList_p;
  my $s = "";
  if (exists($traceStrings_p->{$hash_p->{$HASH_STRVERSION_TAG}}{$hash_p->{$HASH_PRODUCER_TAG}}{$hash_p->{$HASH_STRID_TAG}})) {
    $s = $traceStrings_p->{$hash_p->{$HASH_STRVERSION_TAG}}{$hash_p->{$HASH_PRODUCER_TAG}}{$hash_p->{$HASH_STRID_TAG}};
    $argStringList_p = $traceStrings_p->{$hash_p->{$HASH_STRVERSION_TAG}}{$hash_p->{$HASH_PRODUCER_TAG}};
  }else {
    
    if (!$forceTraceStrings) {
      #warning("Invalid string ID number $hash_p->{$HASH_STRID_TAG} string version $hash_p->{$HASH_STRVERSION_TAG} in trace from trace object $hash_p->{$HASH_TRONAME_TAG}! Corrupt trace data?");
      $hash_p->{$HASH_WARNING_TAG} = "Invalid string ID number $hash_p->{$HASH_STRID_TAG} string version $hash_p->{$HASH_STRVERSION_TAG} in trace from trace object $hash_p->{$HASH_TRONAME_TAG}! Corrupt trace data?"; 
      return 0;
    }else {
      foreach my $version (keys %$traceStrings_p) {
	if (exists ($traceStrings_p->{$version}{$hash_p->{$HASH_PRODUCER_TAG}}{$hash_p->{$HASH_STRID_TAG}})) {
	  $s = ($traceStrings_p->{$version}{$hash_p->{$HASH_PRODUCER_TAG}}{$hash_p->{$HASH_STRID_TAG}});
	  $argStringList_p = $traceStrings_p->{$version}{$hash_p->{$HASH_PRODUCER_TAG}};
	  last;
	}
      }
      if ($s eq "") {
	#warning("String id does not exist in forced trace string file. Trace output may be unreliable.");
	$hash_p->{$HASH_WARNING_TAG} = "String id does not exist in forced trace string file. Trace output may be unreliable.";
      }
      
    }
    
  }
  
  llog("trace string is : $s", 3);
  my $data;
 
  my ($params_p, $warn) = parseVariableArguments($data_p, $offset_p, $s, $hash_p->{$HASH_LENGTH_TAG}, $argStringList_p);
  if ($warn ne "") {
    llog("adding warning from parseVariableArgs: $warn to hash", 3);
    $hash_p->{$HASH_WARNING_TAG} = $warn;
  }
  llog("found params: @$params_p", 3);

  my $str = sprintf($s, @$params_p);
  $str .= "\n Data is:\n";
  
  my @binData = @{$data_p}[$$offset_p..scalar(@{$data_p})]; 
  
  $str = formatBusData($str, \@binData);
  

  $hash_p->{$HASH_STRING_TAG} = $str;
  
  push @$trArr_ref, dclone($hash_p);
}


################################################################################
# Routine parseVariableArguments
##
# @brief Reads arguments from databuffer accordning to formatstring, and removes 
#        leftover arguments.
#
# @param[in]     $data_p Pointer to binary data
# @param[in]     $offset_p Pointer to where to read data (will be updated to point after read data)
# @param[in]     $formatString  String containing printf-type formatting information for the arguments
# @param[in]     $argLen The amount of arguments in the data stream, may or may not match #args in formatstring.
#
# @return        array of arguments (can be used eg for printf($formatString, @params))
#
################################################################################
sub parseVariableArguments {
  my $data_p = shift;
  my $offset_p = shift;
  my $formatString = shift;
  my $argLen = shift;
  my $argStringList_p = shift;
  my @params;
  my $data;
  my @supportedPrintfIdentifiers = "dxXcuop";
  my $warn="";

  if ($argLen == 0) {
    #read16($data_p, $offset_p); # Needed to handle empty strings
    llog("no args to parse", 2);
    return @params;
  }
  else {
    my $argsRead = 0;
    while ($formatString =~ m/(.)?%(.)/g && $argsRead <= $argLen) {
      if ($1 eq "%" or $1 eq "\\") {
	next;
      } elsif (uc($2) eq "L" && member($3, @supportedPrintfIdentifiers)) {
	if ($argsRead + 2 > $argLen) {
	  #warning("Insufficient arguments for trace $formatString. Data will not be reliable");
	  $warn = "Insufficient arguments for trace \"$formatString\". Data will not be reliable";
	  last;
	}
	$data = read32($data_p, $offset_p);
	$argsRead = $argsRead + 2;
      } elsif ($2 eq "s") {
      
	if ($argsRead + 2 > $argLen) {
	  #warning("Insufficient arguments for trace $formatString. Data will not be reliable");
	  $warn = "Insufficient arguments for trace \"$formatString\". Data will not be reliable";
	  last;
	}
	my $traceStrId = read32($data_p, $offset_p);
	$argsRead = $argsRead + 2;
	# convert traceStrId to a string
	if (exists $argStringList_p->{$traceStrId}) {
	  $data = $argStringList_p->{$traceStrId};
	}else {
	  #warning("Bad string parameter to trace $formatString. $traceStrId is not a valid arg string id.");
	  $warn = "Bad string parameter to trace \"$formatString\". $traceStrId is not a valid arg string id.";
	}
	
      } elsif (member($2, @supportedPrintfIdentifiers)) {
	if ($argsRead + 1 > $argLen) {
	  #warning("Insufficient arguments for trace $formatString. Data will not be reliable");
	  $warn = "Insufficient arguments for trace \"$formatString\". Data will not be reliable";
	  last;
	}
	$data = read16($data_p, $offset_p);
	$argsRead = $argsRead + 1;
	# if signed, the value must be sign extended to 32 bits,
	# otherwise perl prints it as a positive number.
	if (uc($2) eq "D" && ($data & (1<<15))) {
	  $data -= 2**16;
	}
      }
      
      llog("Found parameter $data", 4);
	push(@params, $data);
    }

    if ($argsRead < $argLen) {
      #remove leftover args.
      if ($argLen > 1) { # zero argument traces will always have extra data. Otherwise warn user.
	#warning("Too many arguments for trace $formatString. Data may be unreliable");
	$warn = "Too many arguments for trace \"$formatString\". Data may be unreliable";
      }
      llog("leftover data removed", 2);
      for (my $i = 0; $i < $argLen - $argsRead; $i++) {
	$data = read16($data_p, $offset_p);
	llog("data: $data", 4);
      }
    }
  }
  if ($warn ne "") {
    llog("warning while parsning args: $warn",2);
  }
  return \@params, $warn;
}



################################################################################
# Routine formatBusData
##
# @brief Outputs raw data from a bus trace in a formatted form.
#
# @param[in]     $str Header string to prepend to data
# @param[in]     $binData_p Pointer to array of U16 data
#
# @return        Multiline string of formatted data.
#
################################################################################
sub formatBusData {
  my $str = shift;
  my $binData_p = shift;
## PRINT DATA:

  my $loop = 0;
  my $index = 0;
  my $charStr;
  my $line = "";
  my $char1 = "";
  my $char2 = "";
  my $tmpStr = "";

  #print Dumper(@binData);
  foreach my $currChar (@$binData_p ) {
    $char1 = $currChar>>8 & 0xff;
    $char2 = $currChar & 0xff;
    $line .=  sprintf ("%02x %02x ", $char1, $char2);
    $charStr = ( $char1 >= 32 && $char1 <= 126 ) ?
      sprintf("$charStr%c", $char1) : sprintf("$charStr.");
    $charStr = ( $char2 >= 32 && $char2 <= 126 ) ?
      sprintf("$charStr%c", $char2) : sprintf("$charStr.");
    $index += 2;
    if ($index == 16) {
      $str = sprintf ("$str\t%04x $line '$charStr'\n", $loop);
      $loop += 16;
      $index = 0;
      $line = '';
      $charStr = '';
    }
  }   
  $str = sprintf ("$str\t%04x $line '$charStr'", $loop) unless $line eq "";
  
  return $str;

}

################################################################################
# Routine readcommonHeader
##
# @brief Reads a common header from binary data and enters the data into the hash
#
# @param[in]     $data_p Pointer to binary data
# @param[in]     $offset_p Pointer to where to read data
# @param[in]     $hash_p Pointer to where to store data
#
# @return        NONE
#
################################################################################
sub readCommonHeader {
  my $data_p = shift;
  my $offset_p = shift;
  my $hash_p = shift;
  
  $hash_p->{$HASH_HDRVERSION_TAG} = read16($data_p, $offset_p);
  llog ("$HASH_HDRVERSION_TAG = $hash_p->{$HASH_HDRVERSION_TAG}", 2);

  $hash_p->{$HASH_STRVERSION_TAG} = read32($data_p, $offset_p);
  llog ("$HASH_STRVERSION_TAG = $hash_p->{$HASH_STRVERSION_TAG}", 2);

  $hash_p->{$HASH_SEQNO_TAG} = read16($data_p, $offset_p);
  llog ("$HASH_SEQNO_TAG = $hash_p->{$HASH_SEQNO_TAG}", 2);

  $hash_p->{$HASH_PRODUCER_TAG} = read16($data_p, $offset_p);
  llog ("$HASH_PRODUCER_TAG = $hash_p->{$HASH_PRODUCER_TAG}", 2);
  
  $hash_p->{$HASH_TRACETYPE_TAG} = read16($data_p, $offset_p);
  llog ("$HASH_TRACETYPE_TAG = $hash_p->{$HASH_TRACETYPE_TAG}", 2);
  
  my $frag = read16($data_p, $offset_p);
  $hash_p->{$HASH_FRAGTOTAL_TAG} = $frag >> 8 & 0xff;
  llog ("$HASH_FRAGTOTAL_TAG = $hash_p->{$HASH_FRAGTOTAL_TAG}", 2);
  $hash_p->{$HASH_FRAGNO_TAG} = $frag & 0xff;
  llog ("$HASH_FRAGNO_TAG = $hash_p->{$HASH_FRAGNO_TAG}", 2);

  my $size_and_overwritten = read16($data_p, $offset_p);
  $hash_p->{$HASH_SIZE_TAG} = ($size_and_overwritten & 0x7FFF);
  llog ("$HASH_SIZE_TAG = $hash_p->{$HASH_SIZE_TAG}", 2);
  $hash_p->{$HASH_OVERWRITTEN_TAG} = ($size_and_overwritten >> 15) & 0x1;
  llog ("$HASH_OVERWRITTEN_TAG = $hash_p->{$HASH_OVERWRITTEN_TAG}", 2);

  if ($hash_p->{$HASH_TRACETYPE_TAG} == $TRACE_TYPE_NORMAL &&
      $hash_p->{$HASH_OVERWRITTEN_TAG} != 0) {
    print "*** WARNING: Buffer overwritten bit is set! Data might have been ".
      "corrupted or lost!\n"
    }
}



################################################################################
# Routine readBusHeader
##
# @brief Reads a bus header from binary data and returns it
# @param[in]     $data_p Pointer to binary data
# @param[in]     $offset_p Pointer to where to read data
#
# @return        NONE
#
################################################################################
sub readBusHeader {
  my $data_p = shift;
  my $offset_p = shift;
 
  my $bufSize = read16($data_p, $offset_p);
  my $nid = read16($data_p, $offset_p);
  
  my $trGrpLpid = read16($data_p, $offset_p);
  my $trGrp = $trGrpLpid >> 11;
  my $pid = $nid<<8 | ($trGrpLpid & 0xff);
  my $dummy = read16($data_p, $offset_p); #padding
  my $traceId = read16($data_p, $offset_p);
  my $bfn = read32($data_p, $offset_p);
  my $payloadSize =  read16($data_p, $offset_p);

  llog ("readBusHeader: size: $bufSize, pid: $pid, trGrp: $trGrp, traceId: $traceId, bfn: $bfn, payload: $payloadSize", 4);

  return ($bufSize, $pid, $trGrp, $traceId, $bfn, $payloadSize);
}
 

################################################################################
# Routine readTraceHeader
##
# @brief Reads a trace header from binary data and enters the data into the hash
#
# @param[in]     $data_p Pointer to binary data
# @param[in]     $offset_p Pointer to where to read data
# @param[in]     $hash_p Pointer to where to store data
#
# @return        NONE
#
################################################################################
sub readTraceHeader {
  my $data_p = shift;
  my $offset_p = shift;
  my $hash_p = shift;

  $hash_p->{$HASH_LEN_TAG} = read16($data_p, $offset_p);
  llog ("$HASH_LEN_TAG = $hash_p->{$HASH_LEN_TAG}", 2);
  $hash_p->{$HASH_NID_TAG} = read16($data_p, $offset_p);
  llog ("$HASH_NID_TAG = $hash_p->{$HASH_NID_TAG}", 2);
}

################################################################################
# Routine readTrace
##
# @brief Reads a trace from binary data and enters the data into the hash
#
# @param[in]     $data_p Pointer to binary data
# @param[in]     $offset_p Pointer to where to read data
# @param[in]     $hash_p Pointer to where to store data
#
# @return        NONE
#
################################################################################
sub readTrace {
  my $data_p = shift;
  my $offset_p = shift;
  my $hash_p = shift;
  my $traceObjIds_p = shift;
  my $traceStrings_p = shift;
  my $traceGroups_p = shift;
  my $isRdrTrace = 0; # 1 if trace is a RDR trace, 0 otherwise
  my $isUtcTimingTrace = 0;

  my $trgrp_strid = read32($data_p, $offset_p);
  my $trgrp = (($trgrp_strid >> 27) & 0x1F);
  if (exists($traceGroups_p->{$trgrp})) {
    $hash_p->{$HASH_TRGRP_TAG} = $traceGroups_p->{$trgrp};
  } else {
    $hash_p->{$HASH_TRGRP_TAG} = $trgrp;
  }
  llog ("$HASH_TRGRP_TAG = $hash_p->{$HASH_TRGRP_TAG}", 3);
  $hash_p->{$HASH_STRID_TAG} = ($trgrp_strid & 0x7FFFFFF);
  llog ("$HASH_STRID_TAG = $hash_p->{$HASH_STRID_TAG}", 3);
  $hash_p->{$HASH_TRID_TAG} = read16($data_p, $offset_p);
  llog ("$HASH_TRID_TAG = $hash_p->{$HASH_TRID_TAG}", 3);
  # FIXME: Temporary fix. LPP always traces on object id 0, and the
  # tmg.pl script allocates other trace ids starting from 1. Remove the
  # special LPP case once LPP gets its own trace system.
  if ($hash_p->{$HASH_TRID_TAG} == 0) {
    $hash_p->{$HASH_TRONAME_TAG} = "LPP";
  }
  else {
    my $name = $traceObjIds_p->{$hash_p->{$HASH_TRID_TAG}};
    $name = $hash_p->{$HASH_TRID_TAG} unless $name;
    $hash_p->{$HASH_TRONAME_TAG} = $name;
  }
  # check if trace object matches a RDR trace
  if ($hash_p->{$HASH_TRONAME_TAG} =~ m/\w+_Srdr/) {
    $isRdrTrace = 1;
  } elsif ($hash_p->{$HASH_TRONAME_TAG} eq "BbbaseLuUTC") {
    $isUtcTimingTrace = 1;
  }

  llog ("$HASH_TRONAME_TAG = $hash_p->{$HASH_TRONAME_TAG}", 3);
  $hash_p->{$HASH_BFNREG_TAG} = read32($data_p, $offset_p);
  llog ("$HASH_BFNREG_TAG = $hash_p->{$HASH_BFNREG_TAG}", 3);
  if ($useUTCtraces && $utcTraceRead) {
    my $utcTime = getUtcTime($hash_p->{$HASH_BFNREG_TAG});
    $hash_p->{$HASH_TIME_TAG} = $utcTime;
    llog("$HASH_TIME_TAG = $hash_p->{$HASH_TIME_TAG}", 3);
  }
  my $len_pid = read16($data_p, $offset_p);
  $hash_p->{$HASH_LENGTH_TAG} = $len_pid >> 8;
  llog ("$HASH_LENGTH_TAG = $hash_p->{$HASH_LENGTH_TAG}", 3);
  $hash_p->{$HASH_LPID_TAG} = $len_pid & 0xFF;
  llog ("$HASH_LPID_TAG = $hash_p->{$HASH_LPID_TAG}", 3);
  $hash_p->{$HASH_PID_TAG} = $hash_p->{$HASH_NID_TAG} << 8 | $hash_p->{$HASH_LPID_TAG};
  llog ("$HASH_PID_TAG = $hash_p->{$HASH_PID_TAG}", 3);

  my $argStringList_p;
  my $s = "";

  if (!$isRdrTrace) {

    if (!$forceTraceStrings) {
      if (!exists($traceStrings_p->{$hash_p->{$HASH_STRVERSION_TAG}})) {
	#Bad version, exit script
	my $verInfo = getBuildInfoFromVersion($hash_p->{$HASH_STRVERSION_TAG});
	fatalError("String version in trace ($hash_p->{$HASH_STRVERSION_TAG}) not found in tracestring hash. Supply the correct trace string file for $verInfo");
      }
    }
    
    if (exists($traceStrings_p->{$hash_p->{$HASH_STRVERSION_TAG}}{$hash_p->{$HASH_PRODUCER_TAG}}{$hash_p->{$HASH_STRID_TAG}})) {
      $s = $traceStrings_p->{$hash_p->{$HASH_STRVERSION_TAG}}{$hash_p->{$HASH_PRODUCER_TAG}}{$hash_p->{$HASH_STRID_TAG}};
      $argStringList_p = $traceStrings_p->{$hash_p->{$HASH_STRVERSION_TAG}}{$hash_p->{$HASH_PRODUCER_TAG}};
    }else {
      
      if (!$forceTraceStrings) {
	#warning("Invalid string ID number $hash_p->{$HASH_STRID_TAG} string version $hash_p->{$HASH_STRVERSION_TAG} in trace from trace object $hash_p->{$HASH_TRONAME_TAG}! Corrupt trace data?");
	$hash_p->{$HASH_WARNING_TAG}="Invalid string ID number $hash_p->{$HASH_STRID_TAG} string version $hash_p->{$HASH_STRVERSION_TAG} in trace from trace object $hash_p->{$HASH_TRONAME_TAG}! Corrupt trace data?";
	return 0;
      }else {
	foreach my $version (keys %$traceStrings_p) {
	  if (exists ($traceStrings_p->{$version}{$hash_p->{$HASH_PRODUCER_TAG}}{$hash_p->{$HASH_STRID_TAG}})) {
	    $s = ($traceStrings_p->{$version}{$hash_p->{$HASH_PRODUCER_TAG}}{$hash_p->{$HASH_STRID_TAG}});
	    $argStringList_p = $traceStrings_p->{$version}{$hash_p->{$HASH_PRODUCER_TAG}};
	    last;
	  }
	}
	if ($s eq "") {
	  #warning("String id does not exist in forced trace string file. Trace output may be unreliable.");
	  $hash_p->{$HASH_WARNING_TAG}="String id does not exist in forced trace string file. Trace output may be unreliable.";
	}
	
      }
      
    }
  }
  
  my $data;

  if ($isUtcTimingTrace and $s =~ /BBBASE_LUUTC_PROC: INFO: *bfn=/) {
    my ($params_p, $warn) = parseVariableArguments($data_p, $offset_p, $s, $hash_p->{$HASH_LENGTH_TAG}, $argStringList_p);
    if ($warn ne "") {
      $hash_p->{$HASH_WARNING_TAG} = $warn;
    }
    llog(sprintf("Got utc time trace from producer %d. Old times were: bfn: %x utcSec: %d utcMs: %d" ,$hash_p->{$HASH_PRODUCER_TAG}, $utcBfn, $utcSec, $utcMs ), 2);
    $utcBfn = $params_p->[0];
    $utcSec = $params_p->[1];
    $utcMs = $params_p->[2];
    $utcTraceRead = 1;
    llog(sprintf("Got utc time trace from producer %d. New times are: bfn: %x utcSec: %d utcMs: %d", $hash_p->{$HASH_PRODUCER_TAG}, $utcBfn, $utcSec, $utcMs ), 2);

    # Per default UTC-traces are not displayed. return unless --utc was given as argument.
    if (!$showUTCtraces) {
      return 0; # return 0 to not add hash to trace list
    } else {
      
      $hash_p->{$HASH_STRING_TAG} =
	sprintf($s, @$params_p);
      return 1;
    }
  } 
  if ($isRdrTrace) {
    # RDR trace => no formatting string, just read raw data
    my @rdrTrace;
    for (my $i = 1; $i < $hash_p->{$HASH_LENGTH_TAG} + 1; $i++) {
      push(@rdrTrace, read16($data_p, $offset_p));
    }
    $hash_p->{$HASH_STRING_TAG} = formatRdrTrace(@rdrTrace);
  } else {
    my ($params_p, $warn) = parseVariableArguments($data_p, $offset_p, $s, $hash_p->{$HASH_LENGTH_TAG},  $argStringList_p);
    if ($warn ne "") {
      $hash_p->{$HASH_WARNING_TAG} = $warn;
    }
    if ($params_p) {
    
      llog("found params: @$params_p", 3);
      
      $hash_p->{$HASH_STRING_TAG} =
	sprintf($s, @$params_p);
    }else {
      $hash_p->{$HASH_STRING_TAG} = $s;
    }
  }

  llog ("$HASH_STRING_TAG = $hash_p->{$HASH_STRING_TAG}", 3);
  return 1;
}

################################################################################
# Routine printTraces
##
# @brief Prints the trace hashes in input array nsing formatstring supplied
#
# @param[in]     $trArr_p Pointer to trace array with trace hashes
# @param[in]     $leftOver force tracing of all data in buffer.
#
# @return        NONE
#
################################################################################
sub printTraces {
    my $trArr  = shift;
    my $leftOver = shift;# 1: print all the trArr, 0: print only the value older then 10sec in Log
    #my @trArr    = @{$trArr_p};
    my @tokenArr = split( " ", $tokenString );
    my $treeSecond = 19660800;#one second for BFN: 0x640000
    #my $fourSecond = 26214400;#one second for BFN: 0x640000
    #my $fiveSecond = 32768000;#one second for BFN: 0x640000
    #my $tenSecond = 65536000;#one second for BFN: 0x640000

    return if (!defined $trArr->[0]);#no traces
    
    #take care of BFN wrap: if the difference between the max value and the min value
    # is bigger than the BFN period/2 (0x80000000), bfn have wrapped.
    # Reorder the table in this case.
    my $trArrayFirstIndex = 0;
    if(($trArr->[-1]->{$HASH_BFNREG_TAG} - $trArr->[0]->{$HASH_BFNREG_TAG}) 
       > 2147483648)
    {
      #find the index where the bfn is bigger than BFN period/2
      ($trArrayFirstIndex)= grep { $trArr->[$_]->{$HASH_BFNREG_TAG} > 2147483648 } 0..$#$trArr;
      #Reorder the table in the correct way
      my @trArrTemp = splice(@$trArr, $trArrayFirstIndex-$#$trArr-1, $#$trArr- $trArrayFirstIndex +1);
      @$trArr = (@trArrTemp, @$trArr);
    }
    my $maxBFN = $trArr->[$trArrayFirstIndex-1]->{$HASH_BFNREG_TAG};

    #trace the data only if they are older than 10 second
    #if the left over flag is set, trace all data.
    while ((defined $trArr->[0]) &&
           (($leftOver == 1) || (((($maxBFN - $trArr->[0]->{$HASH_BFNREG_TAG})%4294967295) >= $treeSecond))))
    {
      my @args   = ();
      map { push( @args, "$trArr->[0]->{$_}" ) } @tokenArr;
      if ( $trArr->[0]->{$HASH_WARNING_TAG}) {
	      print $trArr->[0]->{$HASH_WARNING_TAG} . "\n";
      }
      printf $formatString, @args;
      shift  @$trArr; 
    }
}

################################################################################
# Routine read16
##
# @brief Reads a 16-bit word starting from offset.
#
# @param[in]     $data_p Pointer to data
# @param[in]     $offset_p Offset pointer
#
# @return        The data
#
################################################################################
sub read16 {
  my $data_p = shift;
  my $offset_p = shift;
  my $data =  @{$data_p}[$$offset_p++];
  llog("read16: $data", 4);
  return $data;
}

################################################################################
# Routine read32
##
# @brief Reads a 32-bit word starting from offset.
#
# @param[in]     $data_p Pointer to data
# @param[in]     $offset_p Offset pointer
#
# @return        The data
#
################################################################################
sub read32 {
  my $data_p = shift;
  my $offset_p = shift;
  my $data = @{$data_p}[$$offset_p++] << 16 | @{$data_p}[$$offset_p++];
  llog("read32: $data", 4);
  return $data;
}

################################################################################
# Routine convertToU16
##
# @brief Converts an array of U8 to an array of U16
#
# @param[in]     $arr The array of U8
#
# @return        The array of U16
#
################################################################################
sub convertToU16 {
  my @arr = @_;
  my @tmp;

  for (my $i = 0; $i < $#arr; ) {
    my $data = hex($arr[$i++]) << 8 | hex($arr[$i++]);
    push(@tmp, $data);
  }

  return @tmp;
}


################################################################################
# Routine formatRdrTrace
##
# @brief Format RDR trace in the same format as e.g. bus send traces
#
# This function converts the array of decimal numbers to a hexadecimal + ASCII
# dump. On each row, 16 bytes are printed, i.e. 8 numbers from the array.
# The MSB is printed first, then the LSB.
#
# In the ASCII part, only ASCII characters between 32 and 126 are printed,
# all other characters are replaced with a dot '.'.
#
# Todo: This is a "C" implementation, it might be possible to convert it to
#       Perl.
#
# @param[in]     An array of 16-bit decimal numbers
#
# @return        A string with a formatted RDR trace
#
################################################################################
sub formatRdrTrace {
  my @rdrTrace = @_;
  my $msb;
  my $lsb;
  my $wordCntr;
  my $rowCntr;
  my $ascii;
  my $str;

  $wordCntr = 0;
  $rowCntr = 0;
  $ascii="";
  $str = "\n";
  foreach (@rdrTrace) {
    # are we starting a new row?
    if ($wordCntr == 0) {
      $str .= sprintf "%04lx ", 16 * $rowCntr;
    }

    $msb = ($_ >> 8) & 0xff;
    $lsb= ($_ & 0xff);
    $str .= sprintf "%02lx %02lx ", $msb, $lsb;
    # only print visible ASCII characters
    if ($msb < 32 || $msb > 126) {
      $msb = 46;
    }
    if ($lsb < 32 || $lsb > 126) {
      $lsb = 46;
    }
    $ascii .= pack "C2", $msb, $lsb;

    $wordCntr++;
    # check if we have printed 8 words, if yes, finish the row 
    # i.e. print the ASCII part and go to next row
    if ($wordCntr == 8) {
      $str .= "\'$ascii\'\n";
      $ascii="";
      $wordCntr = 0;
      $rowCntr++;
    }
  }
  
  # do we have some non-printed ASCII part left to print?
  if (length($ascii) > 0) {
    $str .= "\'$ascii\'\n";
  }

  chomp($str); # remove trailing \n
  return $str;
}

  


################################################################################
# Routine checkForTraceStringFile
##
# @brief Checks the version number to find the correct string id file to open.
#
#
# @param[in]     TraceStringVersion
#
# @return        Nothing
#
################################################################################
sub checkForTraceStringFile {
  my $traceStringsVersion = shift;
  
  if (!$haveReadTraceStrings) {
    
    llog("Locating correct traces-string file", 2);
    llog("Preselected trace-string file is: $traceStringBib", 3);
    if ($traceStringBib ne "") {
      llog("reading tracestrings from --trace_strings file: $traceStringBib", 2);
      if (!(-e $traceStringBib) ) {
	fatalError("Trace string file: $traceStringBib does not exist");
      }
      readTraceStringsFromFile("$traceStringBib", \%traceStrings);
      if ($verTraceStringsFile == -1) {
	fatalError("Trace string file: $traceStringBib does not contain any trace strings.");
      }
      if (!member($traceStringsVersion, keys(%traceStrings))) {
	if (!$forceTraceStrings) {
	  my $stringInfo = getBuildInfoFromVersion($verTraceStringsFile);
	  my $traceInfo = getBuildInfoFromVersion($traceStringsVersion);
	  fatalError("String list version in file $traceStringBib ". 
		     "($verTraceStringsFile, $stringInfo) is not the ".
		     "same as version ".
		     "in trace ($traceStringsVersion, $traceInfo). ".
		     "Use --force ".
		     "flag to overrride (not recommended).");
	}
	llog("Using forced tracestring file.",1);
      }
      $haveReadTraceStrings = 1;
      #all fileversions should now be correct, read info from them
      readTranslationFiles(); 
      return;
    }
    
    if ($traceStringsVersion & 0x80000000) {
      # white build, check vob for info
      my ($revString, $hwId) = traceStringVersionToRevision($traceStringsVersion);
      llog("found white build revision: $revString", 2);

      # Find a white strid file (erobwen)
      my $vobFileName;
      if ($hwId == 2) { 
          # Dul step 3
	  my $revStringCopy = $revString;
	  $revStringCopy =~ /(\d+)-/;	  
	  my $iteration = $1 + 0; # Add with zero to get a number (removes starting zeroes)
	  if ($iteration >= 14) {
              # From iteration 14, binary directories correspond to iteration. 
	      $vobFileName = $CC_WHITE_STRING_VERSION_BASE_ARR[$hwId] . $revString;
	      $vobFileName =~ s/<binDirNum>/$iteration/;
	  } else {
              # Prior to iteration 14, there were three directories to look in.
	      $vobFileName = $CC_WHITE_STRING_VERSION_BASE_ARR[$hwId] . $revString;
	      $vobFileName =~ s/<binDirNum>/3/;
	      if (! (-e $vobFileName)) {
		  llog("$vobFileName did not exist, trying another directory", 2);
		  $vobFileName = $CC_WHITE_STRING_VERSION_BASE_ARR[$hwId] . $revString;
		  $vobFileName =~ s/<binDirNum>/2/;
	      }
	      if (! (-e $vobFileName)) {
		  llog("$vobFileName did not exist, trying another directory", 2);
		  $vobFileName = $CC_WHITE_STRING_VERSION_BASE_ARR[$hwId] . $revString;
		  $vobFileName =~ s/<binDirNum>/1/;
	      }
	  }
      } else { 
          # Dul step 1 & 2
	  $vobFileName = $CC_WHITE_STRING_VERSION_BASE_ARR[$hwId] . $revString;
      }
      llog("opening trace string file $vobFileName", 2);
      if (! (-e $vobFileName) || $noClearCase) {
	  fatalError("String list version for this revision not found, or ".
		     "clearcase vob not accessible. Please supply the correct ".
		     "trace string file for revision $revString product ".
		     "$HW_VERSION_NAMES[$hwId].");
      }


      readTraceStringsFromFile("$vobFileName", \%traceStrings);
      #if ($verTraceStringsFile != $traceStringsVersion) {
      if (!member($traceStringsVersion, keys(%traceStrings))) {
	fatalError("String list version in file $vobFileName extracted from ".
	     "vob does not match version in trace " .
	     "($verTraceStringsFile != $traceStringsVersion).".
	     "Please use --trace_strings flag to explicitly ".
	     "use correct version of file, and contact FAP ".
	     "to trouble-shoot the problem.");
      }
      llog("found string version file: $vobFileName",2);

      if (!$noClearCase) {
	setFilePathsFromVob($hwId, $revString);
      }

      $haveReadTraceStrings = 1;
    }
    else {
      # black build, try defaults:
      foreach my $filename(@DEFAULT_STRID_FILE_ARR) {
	if ($buildView) {
	  # user set a view to look for files in, start that view and put name in front of path.
	  my $command = $startView.$buildView;
	  system($command);
	  $filename = $viewPath . $buildView . $filename;
	}
	readTraceStringsFromFile("$filename", \%traceStrings);
#	if ($verTraceStringsFile == $traceStringsVersion) {
	if (member($traceStringsVersion, keys(%traceStrings))) {
	  
	  llog("found string version file: $filename",2);
	  $haveReadTraceStrings = 1;
	  last;
	} 
	llog("string version in $filename ($verTraceStringsFile) did not ".
	   "match version from trace($traceStringsVersion).",2);
      }
    
      if (!$haveReadTraceStrings) {
	my $traceInfo = getBuildInfoFromVersion($traceStringsVersion);
	fatalError("No matching string list version for black build found in any of the default locations:\n".
		   "@DEFAULT_STRID_FILE_ARR\nIf you built in a different view, use --build_view to search in the correct view. ".
		   "\nOtherwise you can use --trace_strings ".
		   "option to point to the correct file for this build.\n".
                    "The traces are from $traceInfo");
      }
      
      
    }
    #all fileversions should now be correct, read info from them
    readTranslationFiles(); 
  }
}


################################################################################
# Routine member
##
# @brief Checks if elem is in list (numeric ==, not eq).
#
#
# @param[in]     element to look for
# @param[in]     list to look in
#
# @return        true or false
#
################################################################################
sub member {
  my $elem = shift;
  my @list = @_;
  my $retval = 0;
  #print Dumper(@list);

  map {$retval |= ($elem == $_)} @list;
  
  return $retval;
}

################################################################################
# Routine readTranslationFiles
##
# @brief Reads tracegroups, signals and traceobjects to global variables
#
# @return        none
#
################################################################################
sub readTranslationFiles{

  my $lno = 0;
  if ($buildView) {
    $traceGroupBib = $viewPath . $buildView . $traceGroupBib;
    $sigFileBib = $viewPath . $buildView . $sigFileBib;
    $traceObjList = $viewPath . $buildView . $traceObjList;
  }
  ### Open correct group translation file
  open(hBib, "<$traceGroupBib")
    or fatalError("Couldn't open $traceGroupBib");
  ### Parse input files
  $lno = 0; 
  llog("Parsing trace group list", 1);
  while (<hBib>) {
    $lno++;
    if (/^[\s]*#/ or /^[\s]*$/) {
      next;
    }
    elsif (/^\s*([^\s]+) = (\d+)?([\s]*#.*)?$/) {
      $traceGroups{$2} = $1 unless ($2 eq "");
    }
    else {
      fatalError("failed to parse line no $lno of file $traceGroupBib");
    }
  }
  close(hBib);
  
  # Read signal numbers and names
  readSignalsFromFile("$sigFileBib", \%signals);
  
  ### Optionally read in object ids and names
  if (defined($traceObjList) and -r $traceObjList) {
    open(hObjList, "<$traceObjList")
      or fatalError("failed to open trace object list: $traceObjList");
	### Parse input files
    llog("Parsing trace object list", 1);
    while (<hObjList>) {
	    if (m/^[\s]*#define TRACEID_[A-Z0-9_]+ ([\d]+), (\/\*lint -e\(926\)\*\/ \(CHAR\*\) )?\"([a-zA-Z0-9_]+)\"$/) {
	      $traceObjIds{$1} = $3;
	    }
	  }
    close(hObjList);
  }
  
}
################################################################################
# Routine setFilePathsFromVob
##
# @brief Set traceobj and tracegroup files from vob using the cs pointed to by 
#        revString and hwId
#
#
# @param[in]      hwId for white build
# @param[in]     revString for the white build
#
# @return        none
#
################################################################################



sub setFilePathsFromVob
{
 #(erobwen)
 my $hwId = shift;
 my $revString = shift;

 my $cs;
 if ($hwId == 2) { 
     # Dul step 3
     my $revStringCopy = $revString; 
     $revStringCopy =~ /(\d+)-/;
     my $iteration = $1 + 0;
     if ($iteration >= 14) {
	 # From iteration 14, binary directories correspond to iteration.
	 $cs = $CC_WHITE_CONFIG_SPEC_BASE_ARR[$hwId].$revString;
	 $cs =~ s/<binDirNum>/$iteration/;
     } else {
	 # Prior to iteration 14, there were three directories to look in.
	 $cs = $CC_WHITE_CONFIG_SPEC_BASE_ARR[$hwId].$revString;
	 $cs =~ s/<binDirNum>/3/;
	 if (!open(CS, $cs)) {
	     llog("$cs did not exist, trying another directory", 2);
	     $cs = $CC_WHITE_CONFIG_SPEC_BASE_ARR[$hwId].$revString;
	     $cs =~ s/<binDirNum>/2/;
	 }
	 if (!open(CS, $cs)) {
	     llog("$cs did not exist, trying another directory", 2);
	     $cs = $CC_WHITE_CONFIG_SPEC_BASE_ARR[$hwId].$revString;
	     $cs =~ s/<binDirNum>/1/;
	 }
     }
 } else { 
     # Dul step 1 & 2
     $cs = $CC_WHITE_CONFIG_SPEC_BASE_ARR[$hwId].$revString;
 }

 llog("Opening cs: $cs", 2);
 if (!open(CS, $cs)){
     llog("failed to open config spec for white build with revString: $revString and hwId: $hwId", 1);
     return;
 }

 my $traceStringsLU;
 my $commonLU;
 while (<CS>) {
   if (/.*\/vobs\/erbs\/elib\/bbBaseBl\/traceStringsLU\/\.\.\. *([^ ]*).*/) {
     $traceStringsLU = $1;
   }
    if (/.*\/vobs\/erbs\/elib\/bbBaseBl\/commonLU\/\.\.\. *([^ ]*).*/) {
     $commonLU = $1;
   }

 }
 llog("Found traceStringLU label: $traceStringsLU", 4);
 llog("Found commonLU label: $commonLU", 4);
 

 $traceGroupBib = $traceGroupBib ."@@/" . $traceStringsLU;
 llog("trace group file set to $traceGroupBib", 2);
 $traceObjList = $traceObjList ."@@/" . $traceStringsLU;
 llog("trace obj file set to $traceObjList", 2);
 $sigFileBib =  $sigFileBib ."@@/" . $commonLU;
 llog("signal file set to $sigFileBib", 2);

}

################################################################################
# Routine handleOutFile
##
# @brief Generates strid-file from outfile(s).
#
# @return        none
#
################################################################################
sub handleOutFile {

  if (!$outFile && !$outFileDir) {
    return;
  }
  if (-e $outFile) {
    my $command = $stridGenCommand . " --outfile " . $tempStridFile . " ". $outFile;
    !system($command) or fatalError("failed to execute out-file generation command: $command");
  } elsif ( -d $outFileDir) {
    my @files = <$outFileDir/*.out>;
    my $i = 0;
    foreach my $file (@files) {
      my $noPathName = (split('/', $file))[-1];
      llog("found out file: $noPathName", 3);
      my $lmIdString = "";
      if ($lmIds{$noPathName}) {
	llog("found lmId $lmIds{$noPathName} for $noPathName", 3 );
	$lmIdString = " --lmId " . $lmIds{$noPathName};
      } 
      my $command = $stridGenCommand . " --outfile " . $tempStridFile . "."
	.$i++ . " " . $file . $lmIdString; 
      !system($command) or fatalError("failed to execute out-file generation command: $command");
    }
    my $command = "cat $tempStridFile.* > $tempStridFile";
    !system($command) or fatalError("failed to execute out-file generation command: $command");
      
  } else {
    fatalError("outfile or outFileDir does not exist");
  }
  
  
  
  
  $traceStringBib = $tempStridFile;
  
}

################################################################################
# Routine handleXmlFile
##
# @brief handles logTool-format xml file for all necessary info
#
# @return        none
#
################################################################################
sub handleXmlFile {
  
  if (!$xmlFile) {
    return;
  }
  
  if (-e $xmlFile) {

    eval "use XML::Simple";
    fatalError("Perl module XML::Simple (>= version 2.18) not found, ".
	"this is required to use TET with --xml_file option",$@) if ($@);
    
    # the default (SAX) parser is very slow for large files
    local $ENV{XML_SIMPLE_PREFERRED_PARSER} = 'XML::Parser';
    my $xml = new XML::Simple 
      (#KeepRoot => 1, 
       SearchPath => ".", 
       ForceArray => 1, 
       NormaliseSpace => 2,
      );
    
    
    my $xmlData = eval{$xml->XMLin($xmlFile)};
    if ($@) {
      fatalError("Error reading xml file. Probably xml was not well formed\n"
	   ."Error message was: ". $@ ."\n");
    }
  
    llog("reading data from xml file", 2);

    if (!exists($xmlData->{"translationMap"}) ) {
      fatalError("$xmlFile is not the correct format for a bbTraceTranslation file.");
    }

    foreach my $map (@{$xmlData->{"translationMap"}}) {
      #each xml-file may have several translation maps

      # read tracestrings for each producer id
      my %producers = %{$map->{'stridList'}[0]->{'producerId'}};
   
      foreach my $prodid (keys(%producers) ) {
	
	foreach my $strid (@{$producers{$prodid}->{"stridItem"}}) {

	  $traceStrings{$map->{'version'}}->{$prodid}->{$strid->{"intValue"}} =
	    $strid->{"content"};
	  $verTraceStringsHeader = $map->{'version'};

	  $haveReadTraceStrings = 1;
	  llog("strid: ". $map->{'version'}. " " .$strid->{"intValue"} . " " . $strid->{"content"}. "\n", 4);
	}
      }
     
      # Read signals
      foreach my $signal (@{$map->{"signalList"}[0]->{'signal'}}) {
	llog("signal: " . $signal->{'intValue'} . " " . 
	     $signal->{'content'}. "\n", 4);
	$signals{$signal->{'intValue'}} = $signal->{'content'};
      }
      
      # Read trace Objects
      foreach my $traceObj (@{$map->{'traceObjectList'}[0]->{'traceObjectItem'}}) {
	llog("traceObj: ". $traceObj->{'intValue'}. " " . 
	     $traceObj->{'content'} . "\n", 4);
	$traceObjIds{ $traceObj->{'intValue'}} = $traceObj->{'content'};
	
      }
    
      # Read trace Groups
      foreach my $traceGrp(@{$map->{'traceGroupList'}[0]->{'traceGroupItem'}}) {
	llog("traceGrp: ". $traceGrp->{'intValue'}. " " . 
	     $traceGrp->{'content'} . "\n", 4);
	$traceGroups{ $traceGrp->{'intValue'}} = $traceGrp->{'content'};
	
      }
    }
   
  } else {
    fatalError("xmlFile $xmlFile does not exist");
  }
  
  
}

################################################################################
# Routine getUtcTime
##
# @brief returns utc-time calculated from last received utc trace
#
# @in    bfn timestamp
# @return utc-time
#
################################################################################
sub getUtcTime {
 
  my $actualBfn = shift;
  my $utc;
  my $MICRO_PER_BASIC = 10000; #10*0.001*1000000 
  my $MICRO_PER_SUB = 67; #1000000UL/15000
  my $actualB = $actualBfn>>20 & 0x00000FFF;
  my $actualS = $actualBfn>>12 & 0x000000FF;

  my $utcB = $utcBfn>>20 & 0x00000FFF;
  my $utcS = $utcBfn>>12 & 0x000000FF;

  my $diffB = 0;
  my $diffS = 0;
  my $tempMicrosec;
  my $tempSec;

  my $carryS = 0;

  my $logstring = sprintf("getting utc time for bfn: %x . utcBfn: %x utcSec: %d utcMs: %d", $actualBfn, $utcBfn, $utcSec, $utcMs);

  llog($logstring, 3);

  if ($actualS >= $utcS)
  {
    $diffS = $actualS - $utcS;
  } 
  else 
  {
    $carryS = 1;
    $diffS = 150 - ($utcS - $actualS);
  }

  if (($actualB - $carryS) >= $utcB)
  {
    $diffB = $actualB - $carryS - $utcB;
  }
  else
  {
    $diffB = 4096 - ($utcB + $carryS - $actualB);
  }
   

  my $tempMicrosec = ($diffB) * $MICRO_PER_BASIC + 
    ($diffS * $MICRO_PER_SUB) + $utcMs;
  my $tempSec = $utcSec + int($tempMicrosec / 1000000);
  $tempMicrosec = $tempMicrosec % 1000000;
  my @gmtArray = gmtime($tempSec);
 
  #print "tempsec is: ". $tempSec . " utcS is: " . $utcS . "\n";
  #print Dumper(\@gmtArray);

  $utc = sprintf("[%d-%02d-%02d %02d:%02d:%02d.%06d]", 1900 + $gmtArray[5], $gmtArray[4]+1, $gmtArray[3], $gmtArray[2], 
		$gmtArray[1], $gmtArray[0], $tempMicrosec);

  llog("calculated utc string: ".$utc, 3);

  return $utc;

}


################################################################################
# Routine getBuildInfoFromVersion
##
# @brief returns utc-time calculated from black build version id or Revision string for white build
#
# @in     string list version
# @return utc-time/revision
#
################################################################################
sub getBuildInfoFromVersion{
  my $version = shift;
  my $info;
  
  if ($version &0x80000000) {
    #white build
    my $dummy;
    ($info, $dummy) = traceStringVersionToRevision($version);
    return "revision $info";
  }
  
  my $secs = ($version & 0xffffff);
  if ($secs < 0xe00000) {
    # when I'm writing this 16/4 2010, secs will be approx 0xf20000
    # 0xe00000 is about 2 months in the past, should be enough
    # so if less than this, assume we have wrapped around in the 24 bits
    # if anyone is still using this in 2012 when it wraps again, this needs
    # to be fixed...
    $secs = $secs | 0x13000000;
  } else {
    $secs = $secs | 0x12000000;
  }
  $secs = $secs * 4;
  my @gmtArray = gmtime($secs);
  
  my $utc = sprintf("black build from %d-%02d-%02d %02d:%02d", 1900 + $gmtArray[5], 
		    $gmtArray[4]+1, $gmtArray[3], $gmtArray[2], $gmtArray[1]);
  
  return $utc; 
}

