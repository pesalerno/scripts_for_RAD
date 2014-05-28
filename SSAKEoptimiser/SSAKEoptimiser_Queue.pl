#!/usr/bin/env perl 
#===============================================================================
#
#         FILE: SSAKEoptimiser_thr.pl
#
#        USAGE: ./SSAKEoptimiser_thr.pl  
#
#  DESCRIPTION: This script opimises the SSAKE de novo assembler in parallel
#  				using Perls ithreads and queues.
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Claudius Kerth (CEK), c.kerth[at]sheffield.ac.uk
# ORGANIZATION: 
#      VERSION: 1.0
#      CREATED: 27/05/14 13:27:05
#     REVISION: ---
#===============================================================================

use strict;
use warnings;


use Time::HiRes qw(time sleep);

my $start = time();

#-------------------------------------------------------------------------------
#  get input and sort by size
#-------------------------------------------------------------------------------

## get input file names
my @files = glob("input/*.fa");

## get line count for each file
my %h;
for (@files){
	my $filename = $_;
	my $filesize = -s $filename;
	$h{$filename} = $filesize;
}
## sort files by size descendingly
my @files_sorted = sort {$h{$b} <=> $h{$a}} keys %h;


#-------------------------------------------------------------------------------
#  set up queue and spawn worker threads
#-------------------------------------------------------------------------------

use threads;
use threads::shared;
use Thread::Queue;

# create a queue
my $q = Thread::Queue->new();

# this shared variable needs to be defined before spawning the workers
# threads that try tp lock it
my %gather :shared;

# fill the queue with parameter combinations
for my $file (@files_sorted[30..40]){
	for my $kmer (11..33){
		$q->enqueue([$file, $kmer]);
	}
}

##
## for parallel processing it is necessary to fill the queue BEFORE spawning the worker threads
##

# set the number of worker threads to spawn
my $threads = 22;

# spawn worker threads
threads->create('run_SSAKE') for (1..$threads);

print "Number of running threads: " . scalar threads->list(threads::running) . "\n";

# this is only necessary if 'dequeue' is used instead of dequeue_nb
#$q->enqueue((undef) x $threads); # note the parentheses around undef are necessary

$_->join for threads->list();

printf STDERR "\n## Comnpute time: %0.3f secs\n\n", time() - $start;

#-------------------------------------------------------------------------------
#  subroutines
#-------------------------------------------------------------------------------

sub run_SSAKE {
	while(my $run = $q->dequeue_nb()){
		my ($file, $kmer) = @{$run};
		my $cmd = "SSAKE -f $file -w 1 -o 1 -m $kmer -c 1 > /dev/null";
		system($cmd)==0 or die $!;
		{
			lock %gather;
			gather($file);
		}
	}
}

sub gather {
	my ($file) = @_;	
	$gather{$file}++;
	if($gather{$file} == 33-11+1){
		print("Finding longest contig for $file.\n");
		find_longest_contig($file);
		delete $gather{$file};
	}
}


#===  FUNCTION  ================================================================
#         NAME: Find_Longest_Contig
#      PURPOSE: Finding the output file containing the longest contig among all
#      			output files produced by different SSAKE runs with different
#      			kmer sizes. Removes all other output files (clean-up).
#   PARAMETERS: input file name
#      RETURNS: nothing (I think)
#  DESCRIPTION: ????
#       THROWS: no exceptions
#     COMMENTS: none
#     SEE ALSO: n/a
#===============================================================================
sub find_longest_contig {
	my $file = shift;

	# get all output file names containing the contigs
	my @output = `ls $file*contigs`; 
	chomp @output;

	my $longest_contig_length = 0;
	my %longest_contig_hash;

	# get the length of the longest contig for each SSAKE x kmer run
	for my $output (@output){

		if(-z $output){ # if the contig file is empty
			print("Contig file is empty for $output\n");
			$output =~ s/contigs$/\*/; 
			system("rm -f $output")==0 or die $!;
			next; 
		}

		open my $IN, "<", $output or die $!;
		my $length;
		while(<$IN>){
			next if /^>/;
			chomp;
			$length = length($_);
			$longest_contig_length = $length if ($length > $longest_contig_length);
		}
		close $IN;
		print("$output : $longest_contig_length\n");
		unless ($longest_contig_length){
			print("Found no contig length for $output\n");
			next;
		}; 
		$longest_contig_hash{$output} = $longest_contig_length;
	}

	# exit if no contigs could be assembled
	unless(keys %longest_contig_hash){
		print("No contigs could be assembled for $file.\n");
		map { s/contigs$/\*/ } @output;
		system("rm -f @output")==0 or die $!;
		return;
	}

	my @remove;
	# sort output file names by contig length
	foreach my $output (sort {$longest_contig_hash{$b} <=> $longest_contig_hash{$a}} keys %longest_contig_hash){
		push(@remove, $output);
	}


	# save the name of the output file containing the longest contig from
	# all SSAKE runs
	my $keep = shift(@remove);
	print("File containing longest contig:\n", "$keep : $longest_contig_hash{$keep}\n\n");


	map { s/contigs$/\*/ } @remove;
	system("rm -f @remove")==0 or die $!;

	return;
}
